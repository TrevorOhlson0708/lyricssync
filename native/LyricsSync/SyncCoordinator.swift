import Foundation
import WidgetKit
import Combine

/// Drives the whole "what's playing -> lyrics -> shared timeline -> widget
/// reload" pipeline. Runs while the app is in the foreground; the widget
/// keeps ticking through the pushed timeline on its own afterward.
final class SyncCoordinator: ObservableObject {
    @Published var statusText = "Not synced yet"
    @Published var currentLine = ""
    @Published var trackTitle = ""
    @Published var trackArtist = ""

    private var timer: Timer?
    private var lastTrackId: String?

    func startAutoRefresh() {
        refreshNow()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() {
        NowPlayingService.fetchCurrentTrack { [weak self] track in
            guard let self else { return }
            guard let track, track.isPlaying else {
                DispatchQueue.main.async {
                    self.statusText = "Nothing playing"
                }
                return
            }

            DispatchQueue.main.async {
                self.trackTitle = track.name
                self.trackArtist = track.artist
            }

            // Only refetch lyrics + rebuild the whole timeline when the
            // track actually changes; otherwise just update the on-screen
            // preview from what we already pushed to the widget.
            if track.id != self.lastTrackId {
                self.lastTrackId = track.id
                let now = Date()
                LyricsService.fetchTimeline(for: track, referenceTime: now) { lines in
                    guard let lines, !lines.isEmpty else {
                        DispatchQueue.main.async {
                            self.statusText = "No synced lyrics found for this track"
                        }
                        return
                    }
                    let data = NowPlayingData(trackId: track.id, title: track.name, artist: track.artist, lines: lines)
                    SharedStore.save(data)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.lyrics)
                    DispatchQueue.main.async {
                        self.statusText = "Synced — check your CarPlay widgets page"
                    }
                }
            } else {
                // Same track still playing: just refresh the phone-screen preview.
                if let data = SharedStore.load() {
                    let now = Date()
                    let line = data.lines.last(where: { $0.time <= now })?.text ?? ""
                    DispatchQueue.main.async {
                        self.currentLine = line
                    }
                }
            }
        }
    }
}
