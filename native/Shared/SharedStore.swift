import Foundation

/// Reads/writes the currently-playing + lyric timeline through the App
/// Group container, which is the only way a widget extension process and
/// the main app process can share data — they don't share memory.
///
/// IMPORTANT: `appGroupId` below must exactly match the App Group configured
/// in both targets' entitlements files, and must be unique to your Apple ID.
/// See the top-level README for how to change this.
enum SharedStore {
    static let appGroupId = "group.com.trevorohlson0708.lyricssync"
    private static let fileName = "nowplaying.json"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    static func save(_ data: NowPlayingData) {
        guard let dir = containerURL else {
            print("SharedStore: no App Group container — check the App Group entitlement/id")
            return
        }
        let url = dir.appendingPathComponent(fileName)
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url, options: .atomic)
        } catch {
            print("SharedStore save error: \(error)")
        }
    }

    static func load() -> NowPlayingData? {
        guard let dir = containerURL else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NowPlayingData.self, from: raw)
    }

    static func clear() {
        guard let dir = containerURL else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
    }
}
