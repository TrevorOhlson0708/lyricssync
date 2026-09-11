import Foundation

struct CurrentTrack {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
    let progressMs: Int
    let isPlaying: Bool
}

enum NowPlayingService {
    /// Polls Spotify's "currently playing" endpoint. Returns nil if nothing
    /// is playing or the request fails.
    static func fetchCurrentTrack(completion: @escaping (CurrentTrack?) -> Void) {
        SpotifyAuth.shared.validToken { token in
            guard let token else { completion(nil); return }

            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing?additional_types=track")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, response, error in
                guard
                    let http = response as? HTTPURLResponse,
                    http.statusCode == 200,
                    let data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let item = json["item"] as? [String: Any],
                    let id = item["id"] as? String,
                    let name = item["name"] as? String,
                    let artists = item["artists"] as? [[String: Any]],
                    let durationMs = item["duration_ms"] as? Int
                else {
                    completion(nil)
                    return
                }
                let artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
                let album = (item["album"] as? [String: Any])?["name"] as? String ?? ""
                let progressMs = json["progress_ms"] as? Int ?? 0
                let isPlaying = json["is_playing"] as? Bool ?? false

                completion(CurrentTrack(
                    id: id, name: name, artist: artist, album: album,
                    durationMs: durationMs, progressMs: progressMs, isPlaying: isPlaying
                ))
            }.resume()
        }
    }
}

enum LyricsService {
    /// Fetches synced lyrics from lrclib.net and returns them as absolute
    /// wall-clock Dates, anchored to `track`'s current playback position at
    /// `referenceTime` (normally "now"). Returns nil if no synced lyrics exist.
    static func fetchTimeline(for track: CurrentTrack, referenceTime: Date, completion: @escaping ([LyricLine]?) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(track.durationMs / 1000)),
        ]

        URLSession.shared.dataTask(with: components.url!) { data, response, error in
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let synced = json["syncedLyrics"] as? String
            else {
                completion(nil)
                return
            }
            let offsets = parseLRC(synced) // [(offsetMs, text)]
            let lines = offsets.map { offsetMs, text in
                LyricLine(
                    time: referenceTime.addingTimeInterval(Double(offsetMs - track.progressMs) / 1000.0),
                    text: text
                )
            }
            completion(lines)
        }.resume()
    }

    /// Parses standard `.lrc` timestamps like `[01:23.45]` into
    /// (offsetMs, text) pairs, sorted by time.
    private static func parseLRC(_ text: String) -> [(Int, String)] {
        var results: [(Int, String)] = []
        let pattern = try! NSRegularExpression(pattern: #"\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]"#)

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = pattern.matches(in: line, range: nsrange)
            guard !matches.isEmpty else { continue }

            let content = pattern.stringByReplacingMatches(in: line, range: nsrange, withTemplate: "").trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard
                    let minRange = Range(match.range(at: 1), in: line),
                    let secRange = Range(match.range(at: 2), in: line),
                    let min = Int(line[minRange]),
                    let sec = Int(line[secRange])
                else { continue }

                var fracMs = 0
                if match.range(at: 3).location != NSNotFound, let fracRange = Range(match.range(at: 3), in: line) {
                    let fracStr = String(line[fracRange]).padding(toLength: 3, withPad: "0", startingAt: 0)
                    fracMs = Int(fracStr) ?? 0
                }
                let totalMs = min * 60_000 + sec * 1_000 + fracMs
                results.append((totalMs, content))
            }
        }
        return results.sorted { $0.0 < $1.0 }
    }
}
