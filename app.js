// ---- Configuration ----
// Create a free app at https://developer.spotify.com/dashboard, then paste its
// Client ID below. Add this page's exact URL as a Redirect URI in that app's
// settings (Spotify dashboard -> your app -> Edit Settings -> Redirect URIs).
const CLIENT_ID = "YOUR_SPOTIFY_CLIENT_ID";
const REDIRECT_URI = window.location.origin + window.location.pathname;
const SCOPES = "user-read-currently-playing user-read-playback-state";

const POLL_INTERVAL_MS = 2000;

// ---- Small helpers ----
const $ = (id) => document.getElementById(id);
const screens = {
  login: $("login-screen"),
  idle: $("idle-screen"),
  lyrics: $("lyrics-screen"),
};
function showScreen(name) {
  for (const key in screens) screens[key].classList.toggle("hidden", key !== name);
}

function base64url(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function sha256(plain) {
  const data = new TextEncoder().encode(plain);
  return crypto.subtle.digest("SHA-256", data);
}

function randomString(length) {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let out = "";
  const rand = crypto.getRandomValues(new Uint8Array(length));
  for (let i = 0; i < length; i++) out += chars[rand[i] % chars.length];
  return out;
}

// ---- Auth (PKCE, no client secret needed) ----
const Auth = {
  get accessToken() { return localStorage.getItem("ls_access_token"); },
  get refreshToken() { return localStorage.getItem("ls_refresh_token"); },
  get expiresAt() { return Number(localStorage.getItem("ls_expires_at") || 0); },

  save(tokenResponse) {
    localStorage.setItem("ls_access_token", tokenResponse.access_token);
    if (tokenResponse.refresh_token) {
      localStorage.setItem("ls_refresh_token", tokenResponse.refresh_token);
    }
    const expiresAt = Date.now() + (tokenResponse.expires_in - 60) * 1000;
    localStorage.setItem("ls_expires_at", String(expiresAt));
  },

  clear() {
    ["ls_access_token", "ls_refresh_token", "ls_expires_at", "ls_verifier"].forEach((k) =>
      localStorage.removeItem(k)
    );
  },

  isLoggedIn() {
    return Boolean(this.refreshToken);
  },

  async login() {
    const verifier = randomString(64);
    localStorage.setItem("ls_verifier", verifier);
    const challenge = base64url(await sha256(verifier));

    const params = new URLSearchParams({
      client_id: CLIENT_ID,
      response_type: "code",
      redirect_uri: REDIRECT_URI,
      scope: SCOPES,
      code_challenge_method: "S256",
      code_challenge: challenge,
    });
    window.location.href = `https://accounts.spotify.com/authorize?${params.toString()}`;
  },

  async handleRedirect() {
    const params = new URLSearchParams(window.location.search);
    const code = params.get("code");
    const error = params.get("error");
    if (error) {
      $("login-error").textContent = `Spotify said: ${error}`;
      return;
    }
    if (!code) return;

    const verifier = localStorage.getItem("ls_verifier");
    const body = new URLSearchParams({
      client_id: CLIENT_ID,
      grant_type: "authorization_code",
      code,
      redirect_uri: REDIRECT_URI,
      code_verifier: verifier,
    });

    const res = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });

    window.history.replaceState({}, document.title, window.location.pathname);

    if (!res.ok) {
      $("login-error").textContent = "Login failed. Check your Client ID / Redirect URI.";
      return;
    }
    this.save(await res.json());
  },

  async refresh() {
    const body = new URLSearchParams({
      client_id: CLIENT_ID,
      grant_type: "refresh_token",
      refresh_token: this.refreshToken,
    });
    const res = await fetch("https://accounts.spotify.com/api/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
    if (!res.ok) {
      this.clear();
      return false;
    }
    this.save(await res.json());
    return true;
  },

  async getValidToken() {
    if (!this.isLoggedIn()) return null;
    if (Date.now() >= this.expiresAt) {
      const ok = await this.refresh();
      if (!ok) return null;
    }
    return this.accessToken;
  },
};

// ---- Spotify "currently playing" polling ----
async function fetchCurrentlyPlaying() {
  const token = await Auth.getValidToken();
  if (!token) return { loggedOut: true };

  const res = await fetch("https://api.spotify.com/v1/me/player/currently-playing?additional_types=track", {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (res.status === 204) return { playing: false };
  if (res.status === 401) {
    Auth.clear();
    return { loggedOut: true };
  }
  if (!res.ok) return { playing: false };

  const data = await res.json();
  if (!data || !data.item || data.currently_playing_type !== "track") {
    return { playing: false };
  }
  return {
    playing: Boolean(data.is_playing),
    progressMs: data.progress_ms || 0,
    fetchedAt: Date.now(),
    track: {
      id: data.item.id,
      name: data.item.name,
      artist: data.item.artists.map((a) => a.name).join(", "),
      album: data.item.album ? data.item.album.name : "",
      durationMs: data.item.duration_ms,
      art: data.item.album && data.item.album.images && data.item.album.images[0]
        ? data.item.album.images[0].url
        : "",
    },
  };
}

// ---- Lyrics (lrclib.net, free & keyless) ----
const lyricsCache = new Map(); // trackId -> parsed lines (or null if none found)

function parseLRC(lrcText) {
  const lines = [];
  const timeTag = /\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]/g;
  for (const rawLine of lrcText.split("\n")) {
    const tags = [...rawLine.matchAll(timeTag)];
    if (tags.length === 0) continue;
    const text = rawLine.replace(timeTag, "").trim();
    for (const tag of tags) {
      const min = Number(tag[1]);
      const sec = Number(tag[2]);
      const frac = tag[3] ? Number(tag[3].padEnd(3, "0")) : 0;
      const timeMs = min * 60000 + sec * 1000 + frac;
      lines.push({ timeMs, text });
    }
  }
  lines.sort((a, b) => a.timeMs - b.timeMs);
  return lines;
}

async function fetchLyrics(track) {
  if (lyricsCache.has(track.id)) return lyricsCache.get(track.id);

  const storageKey = `ls_lyrics_${track.id}`;
  const cached = localStorage.getItem(storageKey);
  if (cached !== null) {
    const parsed = cached === "" ? null : JSON.parse(cached);
    lyricsCache.set(track.id, parsed);
    return parsed;
  }

  let result = null;
  try {
    const params = new URLSearchParams({
      track_name: track.name,
      artist_name: track.artist,
      album_name: track.album,
      duration: String(Math.round(track.durationMs / 1000)),
    });
    const res = await fetch(`https://lrclib.net/api/get?${params.toString()}`);
    if (res.ok) {
      const data = await res.json();
      if (data.syncedLyrics) result = parseLRC(data.syncedLyrics);
    }
  } catch (e) {
    // network hiccup — fall through, try again next time (not cached)
  }

  if (result) {
    localStorage.setItem(storageKey, JSON.stringify(result));
  } else {
    // remember "no lyrics found" too, so we don't hammer the API every poll
    localStorage.setItem(storageKey, "");
  }
  lyricsCache.set(track.id, result);
  return result;
}

// ---- Rendering ----
const state = {
  currentTrackId: null,
  lines: null,
  activeIndex: -1,
  progressMs: 0,
  fetchedAt: 0,
  durationMs: 0,
  isPlaying: false,
};

function renderTrackInfo(track) {
  $("art").src = track.art || "";
  $("track-title").textContent = track.name;
  $("track-artist").textContent = track.artist;
}

function renderLyricsList(lines) {
  const list = $("lyrics-list");
  list.innerHTML = "";
  if (!lines || lines.length === 0) {
    list.innerHTML = '<div class="center-message">No synced lyrics found for this track.</div>';
    return;
  }
  lines.forEach((line) => {
    const div = document.createElement("div");
    div.className = "lyric-line" + (line.text ? "" : " empty");
    div.textContent = line.text || "";
    list.appendChild(div);
  });
}

function updateActiveLine(progressMs) {
  if (!state.lines || state.lines.length === 0) return;
  let idx = -1;
  for (let i = 0; i < state.lines.length; i++) {
    if (state.lines[i].timeMs <= progressMs) idx = i;
    else break;
  }
  if (idx === state.activeIndex) return;
  state.activeIndex = idx;

  const children = $("lyrics-list").children;
  for (let i = 0; i < children.length; i++) {
    children[i].classList.toggle("active", i === idx);
    children[i].classList.toggle("past", i < idx);
  }

  const container = $("lyrics-container");
  const target = children[idx];
  if (target) {
    const offset = target.offsetTop - container.clientHeight / 2 + target.clientHeight / 2;
    $("lyrics-list").style.transform = `translateY(${-offset}px)`;
  }
}

function updateProgressBar(progressMs, durationMs) {
  const pct = durationMs ? Math.min(100, (progressMs / durationMs) * 100) : 0;
  $("progress-fill").style.width = `${pct}%`;
}

// smooth 60fps interpolation between the ~2s Spotify polls
function tick() {
  if (state.isPlaying && state.fetchedAt) {
    const elapsed = Date.now() - state.fetchedAt;
    const estimated = Math.min(state.progressMs + elapsed, state.durationMs || Infinity);
    updateActiveLine(estimated);
    updateProgressBar(estimated, state.durationMs);
  }
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);

// ---- Main poll loop ----
async function pollLoop() {
  try {
    const result = await fetchCurrentlyPlaying();

    if (result.loggedOut) {
      showScreen("login");
      return;
    }
    if (!result.playing) {
      showScreen("idle");
      $("idle-message").textContent = "Waiting for playback…";
      state.currentTrackId = null;
      return;
    }

    state.isPlaying = result.playing;
    state.progressMs = result.progressMs;
    state.fetchedAt = result.fetchedAt;
    state.durationMs = result.track.durationMs;

    if (result.track.id !== state.currentTrackId) {
      state.currentTrackId = result.track.id;
      state.activeIndex = -1;
      renderTrackInfo(result.track);
      showScreen("lyrics");
      renderLyricsList(null); // clear while loading
      $("lyrics-list").innerHTML = '<div class="center-message">Loading lyrics…</div>';
      const lines = await fetchLyrics(result.track);
      // bail if the track changed again while we were fetching
      if (state.currentTrackId !== result.track.id) return;
      state.lines = lines;
      renderLyricsList(lines);
    } else {
      showScreen("lyrics");
    }
  } catch (e) {
    console.error("poll error", e);
  } finally {
    setTimeout(pollLoop, POLL_INTERVAL_MS);
  }
}

// ---- Boot ----
async function boot() {
  if (CLIENT_ID === "YOUR_SPOTIFY_CLIENT_ID") {
    $("login-error").textContent = "Set your Spotify CLIENT_ID in app.js first.";
  }

  await Auth.handleRedirect();

  $("login-btn").addEventListener("click", () => Auth.login());

  if (Auth.isLoggedIn()) {
    pollLoop();
  } else {
    showScreen("login");
  }

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }
}

boot();
