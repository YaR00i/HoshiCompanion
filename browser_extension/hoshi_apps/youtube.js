// Hoshi Apps — YouTube side. Runs only on www.youtube.com (see manifest.json).
// Reads what is playing (title, channel, time, like state) and presses the
// player's own controls when Hoshi's phone remote asks. Sends nothing anywhere
// except to this extension's worker, which talks only to Hoshi on 127.0.0.1.
// No history, comments, account data or other sites.
(() => {
  "use strict";
  if (globalThis.__hoshiYouTube) return;
  const api = (globalThis.__hoshiYouTube = {});

  const pick = (selectors, root = document) => {
    for (const selector of selectors) {
      const node = root.querySelector(selector);
      if (node) return node;
    }
    return null;
  };
  const text = (node) => (node && node.textContent ? node.textContent.trim().replace(/\s+/g, " ") : "");

  function video() {
    return pick([
      "ytd-reel-video-renderer[is-active] video",
      "#movie_player video.html5-main-video",
      "#movie_player video",
      "video.html5-main-video",
    ]);
  }

  function videoId() {
    const url = new URL(location.href);
    if (url.pathname === "/watch") return url.searchParams.get("v") || "";
    const shorts = url.pathname.match(/^\/shorts\/([\w-]{6,})/);
    return shorts ? shorts[1] : "";
  }

  function likeButton() {
    return pick([
      "ytd-reel-video-renderer[is-active] #like-button button",
      "ytd-watch-metadata like-button-view-model button",
      "#top-level-buttons-computed like-button-view-model button",
      "#segmented-like-button button",
      "ytd-watch-metadata #like-button button",
    ]);
  }

  function liked() {
    const button = likeButton();
    return !!button && button.getAttribute("aria-pressed") === "true";
  }

  api.collect = function collect() {
    const id = videoId();
    const v = video();
    if (!id || !v) return { hint: "Открой видео на YouTube" };
    const title =
      text(pick(["ytd-watch-metadata h1 yt-formatted-string", "h1.ytd-watch-metadata", "ytd-reel-video-renderer[is-active] h2"])) ||
      document.title.replace(/ - YouTube$/, "");
    const channel = text(pick([
      "ytd-watch-metadata ytd-channel-name a",
      "#owner #channel-name a",
      "ytd-reel-video-renderer[is-active] ytd-channel-name a",
    ]));
    const playing = !v.paused && !v.ended;
    const muted = !!v.muted || v.volume === 0;
    const active = [];
    if (liked()) active.push("like");
    if (muted) active.push("mute");
    return {
      title: title.slice(0, 200),
      subtitle: channel.slice(0, 120),
      thumbnail: `https://i.ytimg.com/vi/${encodeURIComponent(id)}/mqdefault.jpg`,
      time: Math.floor(v.currentTime || 0),
      duration: isFinite(v.duration) ? Math.floor(v.duration) : 0,
      playing,
      volume: Math.round((v.volume || 0) * 100),
      active,
      icons: { toggle: playing ? "⏸" : "▶", mute: muted ? "🔇" : "🔈" },
    };
  };

  const click = (selectors) => {
    const button = pick(selectors);
    if (!button) return false;
    button.click();
    return true;
  };

  api.run = function run(command, args) {
    const v = video();
    args = args || {};
    switch (command) {
      case "toggle":
        if (!v) return false;
        if (v.paused || v.ended) v.play(); else v.pause();
        return true;
      case "back":
      case "forward": {
        if (!v) return false;
        const step = Number(args.seconds) || 10;
        v.currentTime = Math.max(0, (v.currentTime || 0) + (command === "back" ? -step : step));
        return true;
      }
      case "seek_to":
        if (!v || !isFinite(Number(args.time))) return false;
        v.currentTime = Math.max(0, Math.min(Number(args.time), v.duration || Number(args.time)));
        return true;
      case "vol_up":
      case "vol_down":
        if (!v) return false;
        v.muted = false;
        v.volume = Math.max(0, Math.min(1, Math.round(((v.volume || 0) + (command === "vol_up" ? 0.1 : -0.1)) * 10) / 10));
        return true;
      case "mute":
        if (click([".ytp-mute-button"])) return true;
        if (v) { v.muted = !v.muted; return true; }
        return false;
      case "next":
        return click([".ytp-next-button"]) || (videoId() && location.pathname.startsWith("/shorts/") && click(["#navigation-button-down button"]));
      case "like": {
        const button = likeButton();
        if (!button) return false;
        const before = liked();
        button.click();
        if (!before) setTimeout(() => { if (liked()) api.emit("liked"); }, 600);
        return true;
      }
    }
    return false;
  };

  // --- связь с фоновой частью расширения -----------------------------------
  let port = null;
  let last = "";
  api.emit = (event) => { if (port) port.postMessage({ op: "event", event }); };

  function push(force) {
    if (!port) return;
    const state = api.collect();
    const serial = JSON.stringify(state);
    if (force || serial !== last) {
      last = serial;
      port.postMessage({ op: "state", state });
    }
  }

  function connect() {
    try {
      port = chrome.runtime.connect({ name: "hoshi-youtube" });
    } catch (e) {
      port = null; // расширение перезагрузили — страница живёт без Хоши
      return;
    }
    port.onMessage.addListener((message) => {
      if (message && message.op === "run") {
        api.run(String(message.command || ""), message.args || {});
        setTimeout(() => push(true), 150);
      } else if (message && message.op === "refresh") {
        push(true);
      }
    });
    port.onDisconnect.addListener(() => { port = null; setTimeout(connect, 2000); });
    push(true);
  }

  document.addEventListener("ended", (event) => { if (event.target === video()) api.emit("ended"); }, true);
  for (const name of ["play", "pause", "volumechange", "seeked", "loadedmetadata"]) {
    document.addEventListener(name, () => push(false), true);
  }
  setInterval(() => push(false), 1000);
  connect();
})();
