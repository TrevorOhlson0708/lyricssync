import Foundation

/// One timed lyric line. `time` is an absolute wall-clock Date computed from
/// the current playback position at the moment we last synced with Spotify —
/// NOT a relative offset. This is what lets WidgetKit "tick" through lines on
/// its own schedule without the app needing to run continuously.
struct LyricLine: Codable {
    let time: Date
    let text: String
}

/// Everything the widget extension needs to know about what's playing right
/// now, written by the main app and read by the widget through the shared
/// App Group container.
struct NowPlayingData: Codable {
    let trackId: String
    let title: String
    let artist: String
    let lines: [LyricLine]
}

/// Shared constant so the app and widget extension agree on the widget kind.
enum WidgetKind {
    static let lyrics = "LyricsWidget"
}
