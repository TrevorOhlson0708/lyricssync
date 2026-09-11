import WidgetKit
import SwiftUI

struct LyricEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let line: String
}

struct LyricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricEntry {
        LyricEntry(date: Date(), title: "LyricsSync", artist: "", line: "Open the app and press Refresh")
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricEntry>) -> Void) {
        guard let data = SharedStore.load(), !data.lines.isEmpty else {
            let entry = LyricEntry(date: Date(), title: "LyricsSync", artist: "", line: "Open the app and press Refresh")
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
            return
        }

        let now = Date()
        var entries: [LyricEntry] = []

        // Seed with whatever line is "current" right now so the widget
        // doesn't render blank until the next scheduled line arrives.
        if let prior = data.lines.last(where: { $0.time <= now }) {
            entries.append(LyricEntry(date: now, title: data.title, artist: data.artist, line: prior.text))
        }

        for line in data.lines where line.time > now {
            entries.append(LyricEntry(date: line.time, title: data.title, artist: data.artist, line: line.text))
        }

        if entries.isEmpty {
            entries = [LyricEntry(date: now, title: data.title, artist: data.artist, line: data.lines[0].text)]
        }

        // Nothing left to show after the last scheduled line — ask again
        // shortly after (covers songs ending / the app not having refreshed
        // for the next track yet).
        let refreshAfter = entries.last!.date.addingTimeInterval(2)
        completion(Timeline(entries: entries, policy: .after(refreshAfter)))
    }

    private func currentEntry() -> LyricEntry {
        guard let data = SharedStore.load() else {
            return LyricEntry(date: Date(), title: "LyricsSync", artist: "", line: "Open the app and press Refresh")
        }
        let now = Date()
        let line = data.lines.last(where: { $0.time <= now })?.text ?? data.lines.first?.text ?? ""
        return LyricEntry(date: now, title: data.title, artist: data.artist, line: line)
    }
}

struct LyricsWidgetView: View {
    var entry: LyricEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.line)
                .font(.system(size: 15, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if !entry.artist.isEmpty {
                Text("\(entry.title) — \(entry.artist)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.black, for: .widget)
    }
}

struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lyrics, provider: LyricsProvider()) { entry in
            LyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing Lyrics")
        .description("Shows the current synced lyric line from LyricsSync.")
        .supportedFamilies([.systemSmall])
    }
}
