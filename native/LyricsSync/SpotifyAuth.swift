import Foundation
import AuthenticationServices
import CryptoKit

/// Spotify login using the Authorization Code + PKCE flow — no client
/// secret needed, safe to ship inside an app binary.
///
/// Set your Spotify Client ID below (same one from developer.spotify.com —
/// you can reuse the Client ID from the web version of this project, just
/// add "lyricssync://callback" as an additional Redirect URI on that same
/// Spotify app).
final class SpotifyAuth: NSObject, ObservableObject {
    static let shared = SpotifyAuth()

    private let clientId = "d75d079123264d1a8edec9491be9d133"
    private let redirectUri = "lyricssync://callback"
    private let scopes = "user-read-currently-playing user-read-playback-state"

    @Published var isLoggedIn: Bool = false

    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?
    // ASWebAuthenticationSession.presentationContextProvider is a *weak*
    // reference — without a strong reference held somewhere else, ARC frees
    // this immediately and the session has nowhere to present into.
    private var contextProvider: ContextProvider?

    private let defaults = UserDefaults.standard
    private let accessTokenKey = "ls_access_token"
    private let refreshTokenKey = "ls_refresh_token"
    private let expiresAtKey = "ls_expires_at"

    override init() {
        super.init()
        isLoggedIn = defaults.string(forKey: refreshTokenKey) != nil
    }

    // MARK: - Login

    func login(presentationAnchor: ASPresentationAnchor, completion: @escaping (Result<Void, Error>) -> Void) {
        let verifier = Self.randomString(length: 64)
        codeVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        let session = ASWebAuthenticationSession(
            url: components.url!,
            callbackURLScheme: "lyricssync"
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            guard
                let callbackURL,
                let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                completion(.failure(NSError(domain: "SpotifyAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "No authorization code returned"])))
                return
            }
            self.exchangeCode(code) { result in
                switch result {
                case .success:
                    DispatchQueue.main.async { self.isLoggedIn = true }
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
        let provider = ContextProvider(anchor: presentationAnchor)
        contextProvider = provider
        session.presentationContextProvider = provider
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        let started = session.start()
        if !started {
            completion(.failure(NSError(domain: "SpotifyAuth", code: 5, userInfo: [NSLocalizedDescriptionKey: "ASWebAuthenticationSession.start() returned false"])))
        }
    }

    func logout() {
        defaults.removeObject(forKey: accessTokenKey)
        defaults.removeObject(forKey: refreshTokenKey)
        defaults.removeObject(forKey: expiresAtKey)
        isLoggedIn = false
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(_ code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let verifier = codeVerifier else {
            completion(.failure(NSError(domain: "SpotifyAuth", code: 2, userInfo: nil)))
            return
        }
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        postToken(body: body.percentEncodedQuery ?? "", completion: completion)
    }

    private func refreshToken(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let refresh = defaults.string(forKey: refreshTokenKey) else {
            completion(.failure(NSError(domain: "SpotifyAuth", code: 3, userInfo: nil)))
            return
        }
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
        ]
        postToken(body: body.percentEncodedQuery ?? "", completion: completion)
    }

    private func postToken(body: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            guard
                let data,
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessToken = json["access_token"] as? String,
                let expiresIn = json["expires_in"] as? Double
            else {
                completion(.failure(NSError(domain: "SpotifyAuth", code: 4, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed"])))
                return
            }
            self.defaults.set(accessToken, forKey: self.accessTokenKey)
            if let refreshToken = json["refresh_token"] as? String {
                self.defaults.set(refreshToken, forKey: self.refreshTokenKey)
            }
            self.defaults.set(Date().addingTimeInterval(expiresIn - 60).timeIntervalSince1970, forKey: self.expiresAtKey)
            completion(.success(()))
        }.resume()
    }

    /// Returns a valid access token, refreshing first if it's expired.
    func validToken(completion: @escaping (String?) -> Void) {
        let expiresAt = defaults.double(forKey: expiresAtKey)
        if let token = defaults.string(forKey: accessTokenKey), Date().timeIntervalSince1970 < expiresAt {
            completion(token)
            return
        }
        refreshToken { [weak self] result in
            switch result {
            case .success:
                completion(self?.defaults.string(forKey: self?.accessTokenKey ?? ""))
            case .failure:
                DispatchQueue.main.async { self?.isLoggedIn = false }
                completion(nil)
            }
        }
    }

    // MARK: - PKCE helpers

    private static func randomString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor
        init(anchor: ASPresentationAnchor) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }
}
