# LyricsSync — native CarPlay widget

This is the real-deal version: a native iOS app + a WidgetKit widget
extension that shows the current synced lyric line on **CarPlay's Widgets
page** (iOS 26+). Unlike the web app in the parent folder, this one can
actually appear on the car screen — but it needs to be compiled and
installed as a real iOS app, which means a few more one-time setup steps.
None of them need a Mac or cost anything.

## How this avoids needing a Mac or a paid Apple account

- **Compiling**: a GitHub Actions workflow (already set up at
  `.github/workflows/build-ipa.yml` in the repo root) builds the app on
  GitHub's free macOS runners and hands you back an unsigned `.ipa` file.
- **Installing on your iPhone**: [Sideloadly](https://sideloadly.io/) (free,
  runs on Windows) signs and installs that `.ipa` using just your normal,
  free Apple ID — no Xcode, no $99/year developer account. The only
  downside: a free Apple ID's signature expires every 7 days, so you'll
  need to reconnect your phone to Sideloadly and reinstall weekly. ([AltStore](https://altstore.io/)
  can automate that reinstall wirelessly if you get tired of the cable —
  optional, do that later if you want.)
- **Getting lyrics onto CarPlay**: this app doesn't try to keep itself
  running in the background. Instead, when you open the app before driving
  and it syncs, it hands the *entire* song's lyric timeline (each line with
  the exact clock time it should appear) to the widget in one shot.
  WidgetKit then advances through that schedule on its own, even though the
  app isn't running — the same trick countdown-timer widgets use. No push
  notifications, no paid Apple Developer Program membership needed.

## 1. Identifiers and Client ID — already done

`project.yml`, `SharedStore.swift`, and `SpotifyAuth.swift` are already set
up with `com.trevorohlson0708.lyricssync` as the bundle ID / App Group
prefix and your real Spotify Client ID. One manual step remains:

- Go back to your Spotify app's **Settings** page (developer.spotify.com/dashboard)
  and **add** `lyricssync://callback` as an additional Redirect URI —
  don't remove the existing `https://trevorohlson0708.github.io/lyricssync/`
  one, Spotify allows multiple on the same app. Click **Save**.

## 2. Run the build

Commit and push these files to your `lyricssync` GitHub repo (same repo the
web app lives in — this all sits under a `native/` subfolder so it won't
interfere with GitHub Pages). Pushing to `main` with changes under `native/`
auto-triggers the build; or trigger it manually:

1. Go to your repo → **Actions** tab.
2. Click **"Build unsigned IPA"** in the left list → **Run workflow**.
3. Wait a few minutes. Click into the finished run → under **Artifacts**,
   download **LyricsSync-ipa** (a zip containing `LyricsSync.ipa`).

If the build fails, open the failed step's log and send me what it says —
since I can't compile this myself without a Mac, the first run may need a
round of fixes.

## 3. Install it with Sideloadly

1. Download and install [Sideloadly](https://sideloadly.io/) on your PC.
2. Plug your iPhone into your PC with a cable, trust the computer if asked.
3. Open Sideloadly, drag `LyricsSync.ipa` into it.
4. Enter your Apple ID email in the field it asks for (this is your normal
   Apple ID login — Sideloadly uses it directly with Apple's servers to
   sign the app; it isn't sent anywhere else).
5. Click **Start**. First time, you'll also need to trust the developer
   profile on the phone: **Settings → General → VPN & Device Management →
   [your Apple ID] → Trust**.

## 4. Add the widget to CarPlay

1. On your iPhone: **Settings → General → CarPlay → [your car] → Widgets**.
2. Add **"Now Playing Lyrics"** to one of the widget stacks near the top.
3. Open the **LyricsSync** app on your phone, tap **Connect Spotify**, log
   in, then play a song. Tap **Refresh now** if it doesn't sync
   automatically.
4. Connect to CarPlay — the widget should show the current lyric line,
   advancing on its own as the song plays.

## Known rough edges

- If you **pause, seek, or skip**, the widget will drift out of sync until
  you next open the app and it re-syncs (it doesn't watch playback
  continuously in the background, by design — that's what keeps this free
  and simple).
- Every 7 days the app's signature expires and it'll refuse to open until
  you reinstall via Sideloadly again.
- Only songs lrclib.net has synced lyrics for will work — same limitation
  as the web version.
