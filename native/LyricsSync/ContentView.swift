import SwiftUI
import UIKit
import AuthenticationServices

struct ContentView: View {
    @ObservedObject private var auth = SpotifyAuth.shared
    @StateObject private var sync = SyncCoordinator()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if auth.isLoggedIn {
                VStack(spacing: 16) {
                    Text("LyricsSync")
                        .font(.title.bold())
                        .foregroundStyle(.green)

                    VStack(spacing: 4) {
                        Text(sync.trackTitle.isEmpty ? "—" : sync.trackTitle)
                            .font(.headline)
                        Text(sync.trackArtist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)

                    Text(sync.currentLine)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal)

                    Text(sync.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Refresh now") { sync.refreshNow() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                    Text("Add this to CarPlay: Settings → General → CarPlay → [Your Car] → Widgets, then add \"Now Playing Lyrics\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Log out") { auth.logout(); sync.stopAutoRefresh() }
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }
                .padding()
                .onAppear { sync.startAutoRefresh() }
                .onDisappear { sync.stopAutoRefresh() }
            } else {
                VStack(spacing: 20) {
                    Text("LyricsSync")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.green)
                    Text("Synced lyrics on your CarPlay widgets page.")
                        .foregroundStyle(.secondary)
                    Button("Connect Spotify") {
                        guard let anchor = ContentView.currentWindow() else { return }
                        auth.login(presentationAnchor: anchor) { _ in }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }

    private static func currentWindow() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
