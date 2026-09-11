# LyricsSync

A free, local "now playing" lyrics screen for your iPhone — full-screen synced
lyrics for whatever's playing on your Spotify, meant to be propped up in the
car next to (or instead of) CarPlay. It's a **PWA** (a website you add to your
home screen), not a native app, because native iOS apps require a Mac +
Xcode to build, and CarPlay itself doesn't support custom lyrics overlays
anyway — see the notes at the bottom.

Everything runs client-side in the browser. No backend, no server code of
yours, no paid services. Two free third-party pieces make it work:

- **Spotify Web API** — tells the app what's currently playing.
- **lrclib.net** — a free, keyless, community database of synced (`.lrc`)
  lyrics.

## 1. Create a free Spotify app (for your own API access)

1. Go to https://developer.spotify.com/dashboard and log in with your normal
   Spotify account.
2. Click **Create app**. Name/description can be anything.
3. For **Redirect URI**, you'll fill this in after step 2 below (it must
   exactly match the URL you host this app at). You can come back and edit it.
4. Save. Copy the **Client ID** shown on the app's page — you don't need the
   Client Secret for this (the app uses the PKCE flow, which is secret-free
   and safe to run entirely in a browser).

## 2. Host it somewhere with HTTPS (free)

Spotify's login and iOS's PWA install both require HTTPS, so `file://`
won't work. The easiest free option is **GitHub Pages**:

1. Create a new **public** GitHub repo (e.g. `lyricssync`).
2. Push this `LyricsSync` folder's contents to it.
3. In the repo's Settings → Pages, set the source to the `main` branch, root
   folder. GitHub gives you a URL like
   `https://yourusername.github.io/lyricssync/`.
4. Go back to your Spotify app's settings (step 1) and add that exact URL
   as a **Redirect URI**, then Save.

(Netlify Drop or Cloudflare Pages work the same way if you'd rather not use
GitHub — any free static host with HTTPS is fine.)

## 3. Set your Client ID

Open [app.js](app.js) and replace:

```js
const CLIENT_ID = "YOUR_SPOTIFY_CLIENT_ID";
```

with the Client ID you copied in step 1. Push/redeploy.

## 4. Install it on your iPhone

1. Open your hosted URL in **Safari** on the iPhone.
2. Tap the Share icon → **Add to Home Screen**.
3. Launch it from the home screen icon — it opens full-screen, no Safari
   address bar.
4. Tap **Connect Spotify**, log in, approve access. Play a song anywhere
   (phone, speaker, another device on your account) and lyrics should appear
   within a couple seconds.

## Notes & limitations

- **Reading currently-playing** works on free and Premium Spotify accounts
  alike — this app never needs to control playback, only read what's playing.
- **Not every song has synced lyrics** on lrclib.net. When none are found,
  the screen says so instead of showing anything.
- **CarPlay's actual screen** can't be customized like this — Apple only
  exposes fixed templates (basically title/artist/artwork) to third-party
  CarPlay apps, and getting even that requires an Apple-approved CarPlay
  entitlement. This app is meant to run on the iPhone's own screen, mounted
  in the car — the same trick apps like it actually use.
- Spotify apps start in **Development Mode**, which works fine for your own
  account without any extra approval. It only matters if you ever want other
  people's Spotify accounts to log into your instance — then you'd add them
  under "Users" in the app dashboard (25 max) or apply for extended quota.
- Lyrics timing sync is fetched from Spotify every 2 seconds and
  interpolated in between for a smooth highlight — if you seek/skip, it
  catches up within a couple seconds.
