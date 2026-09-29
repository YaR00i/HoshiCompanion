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

  // --- списки: главная лента, рекомендации у видео и плейлист --------------
  const idFromHref = (href) => {
    try {
      const url = new URL(href, location.origin);
      if (url.pathname === "/watch") return url.searchParams.get("v") || "";
      const shorts = url.pathname.match(/^\/shorts\/([\w-]{6,})/);
      return shorts ? shorts[1] : "";
    } catch (e) { return ""; }
  };
  const thumb = (id) => `https://i.ytimg.com/vi/${encodeURIComponent(id)}/mqdefault.jpg`;
  const firstText = (root, selectors) => {
    for (const selector of selectors) {
      const value = text(root.querySelector(selector));
      if (value) return value;
    }
    return "";
  };

  // Читаем только уже загруженные YouTube-ссылки внутри блока рекомендаций.
  // Бесконечную ленту не прокручиваем сами: новые карточки приходят, когда
  // человек прокручивает открытую вкладку на ПК.
  function suggestedVideos(root, currentId) {
    if (!root) return { items: [], total: 0, start: 0, anchor: 0 };
    const found = new Map();
    for (const link of root.querySelectorAll('a[href*="/watch?v="]')) {
      if (link.closest("ytd-playlist-panel-renderer")) continue;
      const id = idFromHref(link.getAttribute("href"));
      if (!id || id === currentId) continue;
      const card = link.closest("ytd-compact-video-renderer, ytd-rich-grid-media, ytd-rich-item-renderer, yt-lockup-view-model, ytd-video-renderer, ytd-grid-video-renderer") || link.parentElement;
      const title = (link.getAttribute("title") || "").trim() ||
        firstText(card, ["#video-title", "h3", ".yt-lockup-metadata-view-model-wiz__title", "[title]"]) || text(link);
      const channel = firstText(card, ["ytd-channel-name", "#channel-name", ".yt-content-metadata-view-model-wiz__metadata-text"]);
      const known = found.get(id);
      if (!known || (title.length > known.title.length)) {
        found.set(id, { id, title: title.slice(0, 160), subtitle: channel.slice(0, 80), thumbnail: thumb(id), card });
      }
    }
    const loaded = [...found.values()].filter((item) => item.title);
    let visible = 0;
    for (let i = 0; i < loaded.length; i++) {
      const rect = loaded[i].card.getBoundingClientRect();
      if (rect.bottom > 0 && rect.top < innerHeight) { visible = i; break; }
      if (rect.top < 0) visible = i;
    }
    const count = Math.min(180, loaded.length);
    const start = Math.max(0, Math.min(visible - 12, loaded.length - count));
    return { items: loaded.slice(start, start + count).map(({card, ...item}) => item), total: loaded.length, start, anchor: visible };
  }

  function suggestedList(id, title, source) {
    if (!source.total) return null;
    return { id, title, actions: [{ name: "open_new", title: "Открыть в новой вкладке" }],
      items: source.items, total: source.total, start: source.start, anchor: source.anchor };
  }

  function fitLists(result) {
    const bytes = () => new TextEncoder().encode(JSON.stringify(result)).length;
    const positions = () => {
      for (const list of result) {
        if (!list.total) continue;
        const end = list.start + list.items.length;
        list.position = end < list.total || list.start ? `${list.start + 1}–${end} из ${list.total}` : String(list.total);
      }
    };
    positions();
    while (bytes() > 30000) {
      const expandable = result.filter((list) => list.items.length);
      if (!expandable.length) break;
      expandable.sort((a, b) => b.items.length - a.items.length);
      const list = expandable[0];
      if (list.total && list.anchor - list.start > list.start + list.items.length - 1 - list.anchor) {
        list.items.shift();
        list.start++;
      } else list.items.pop();
      positions();
    }
    for (const list of result) delete list.anchor;
    return result;
  }

  // Плейлист справа от видео: все видео, текущее отмечено. До 60 вокруг текущего.
  function playlist(currentId) {
    const panel = pick(["ytd-playlist-panel-renderer#playlist", "ytd-playlist-panel-renderer"]);
    const listId = new URL(location.href).searchParams.get("list") || "";
    if (!panel || !listId) return null;
    const items = [];
    for (const row of panel.querySelectorAll("ytd-playlist-panel-video-renderer")) {
      const link = row.querySelector('a[href*="/watch?v="]');
      const id = link ? idFromHref(link.getAttribute("href")) : "";
      if (!id) continue;
      items.push({
        id, list: listId,
        title: firstText(row, ["#video-title", "h4"]).slice(0, 160),
        subtitle: firstText(row, ["#byline", "#channel-name"]).slice(0, 80),
        thumbnail: thumb(id),
        current: row.hasAttribute("selected") || id === currentId,
      });
    }
    if (!items.length) return null;
    const at = Math.max(0, items.findIndex((item) => item.current));
    const start = Math.max(0, Math.min(at - 20, items.length - 60));
    const title = firstText(panel, ["#header-description h3", ".title", "h3"]) || "Плейлист";
    return { id: "playlist", title: "Плейлист · " + title.slice(0, 60), position: `${at + 1} / ${items.length}`,
      actions: [{ name: "open_new", title: "Открыть в новой вкладке" }], items: items.slice(start, start + 60) };
  }

  let listsCache = [];
  let listsAt = 0;
  let listsContext = "";
  function lists(currentId) {
    const context = location.pathname + "|" + currentId + "|" + (new URL(location.href).searchParams.get("list") || "");
    if (context !== listsContext) { listsAt = 0; listsContext = context; }
    if (Date.now() - listsAt < 3000) return listsCache;
    listsAt = Date.now();
    const result = [];
    if (location.pathname === "/") {
      const home = pick(["ytd-browse[page-subtype='home'] ytd-rich-grid-renderer", "ytd-rich-grid-renderer"]);
      const feed = suggestedList("home", "Рекомендации на главной", suggestedVideos(home, ""));
      if (feed) result.push(feed);
    } else if (currentId) {
      const pl = playlist(currentId);
      if (pl) result.push(pl);
      const related = pick(["ytd-watch-flexy #related", "#related", "#secondary"]);
      const next = suggestedList("next", "Рекомендации к видео", suggestedVideos(related, currentId));
      if (next) result.push(next);
    }
    listsCache = fitLists(result);
    return result;
  }

  api.collect = function collect() {
    const id = videoId();
    const v = video();
    if (location.pathname === "/") {
      const offered = lists("");
      return { page: "home", title: "Главная YouTube", subtitle: "Лента открытой вкладки",
        badge: "рекомендации", hint: offered.length ? "" : "Лента загружается — прокрути YouTube на ПК",
        lists: offered };
    }
    if (!id || !v) { listsAt = 0; listsContext = ""; return { hint: "Открой видео на YouTube" }; }
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
      lists: lists(id),
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
      case "play_item": {
        // Нажимаем ссылку на странице (быстрый переход YouTube без перезагрузки);
        // если её уже нет — открываем видео обычным адресом.
        const id = String(args.id || "");
        if (!/^[\w-]{6,20}$/.test(id)) return false;
        const list = /^[\w-]{2,64}$/.test(String(args.list || "")) ? String(args.list) : "";
        const link = [...document.querySelectorAll('a[href*="/watch?v="]')].find((a) => idFromHref(a.getAttribute("href")) === id &&
          (!list || (a.getAttribute("href") || "").includes("list=" + list)));
        listsAt = 0;
        if (link) { link.click(); return true; }
        location.href = `/watch?v=${encodeURIComponent(id)}` + (list ? `&list=${encodeURIComponent(list)}` : "");
        return true;
      }
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
  window.addEventListener("scroll", () => { listsAt = 0; push(false); }, { passive: true });
  setInterval(() => push(false), 1000);
  connect();
})();
