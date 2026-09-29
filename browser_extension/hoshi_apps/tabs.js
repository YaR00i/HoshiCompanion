// Hoshi Apps — вкладки Chrome для пульта Хоши (решение 28.09.2026, на ПК).
// Раздел «Вкладки Chrome»: вкладка с видео/звуком (название, сайт, время) и
// кнопки ⏪ ⏯ ⏩ — для видео на любом сайте (управляем только элементом <video>).
// Список вкладок (сайт + заголовок) уходит только после нажатия «Показать
// вкладки» на пульте и живёт 3 минуты; переключить, закрыть, приглушить —
// только по нажатию. Адреса страниц, история, тексты страниц — не читаются
// и не отправляются. Связь — только с Хоши на 127.0.0.1.
"use strict";

const TABS_URL = "ws://127.0.0.1:18771/hoshi-adapter-v1";
const TABS_LIST_MS = 3 * 60 * 1000;
const TABS_MAX = 200;
const TABS_BUDGET = 40000; // байт: Хоши принимает пакет до 64 КБ и состояние до 48 000 знаков
const TABS_ADAPTER = {
  op: "adapter",
  id: "tabs",
  title: "Вкладки Chrome",
  commands: [
    { name: "back", title: "−10 секунд", icon: "⏪", row: "main", args: { seconds: 10 } },
    { name: "toggle", title: "Пауза / играть", icon: "⏯", row: "main" },
    { name: "forward", title: "+10 секунд", icon: "⏩", row: "main", args: { seconds: 10 } },
    { name: "mute", title: "Звук вкладки", icon: "🔈" },
    { name: "show_tab", title: "Показать эту вкладку на ПК", icon: "🗔" },
    { name: "seek_to", title: "Перейти к моменту", icon: "", row: "hidden", args: { time: 0 } },
    { name: "play_item", title: "Переключиться на вкладку", icon: "", row: "hidden", args: { id: "" } },
    { name: "close", title: "Закрыть вкладку", icon: "", row: "hidden", args: { id: "" } },
    { name: "list", title: "Показать вкладки", icon: "", row: "hidden" },
    { name: "open_youtube", title: "Новая вкладка YouTube", icon: "", row: "hidden" },
  ],
};

let tabsSocket = null;
let tabsRetryMs = 2000;
let tabsRetryTimer = null;
let tabsBeat = null;
let tabsPoll = null;
let tabsPushTimer = null;
let listUntil = 0;
let lastSent = "";
let media = { tabId: -1, frameId: 0 }; // где видео, которым управляют ⏪ ⏯ ⏩
let selectedTabId = -1; // вкладка, которую человек явно выбрал на телефоне

const hostOf = (url) => {
  try {
    const u = new URL(url);
    return u.protocol === "http:" || u.protocol === "https:" ? u.hostname.replace(/^www\./, "") : "";
  } catch (e) { return ""; }
};
// Значок сайта: только короткий https-адрес (data: бывают огромными, chrome:// телефон не откроет).
const favOf = (tab) => (tab.favIconUrl && tab.favIconUrl.startsWith("https://") && tab.favIconUrl.length <= 160 ? tab.favIconUrl : "");

// Выполняется внутри страницы: состояние самого подходящего <video> в этом кадре.
function pageVideo(command, args) {
  const videos = [...document.querySelectorAll("video")].filter((v) => v.duration > 0 || v.currentTime > 0);
  if (!videos.length) return null;
  const area = (v) => { const r = v.getBoundingClientRect(); return r.width * r.height; };
  videos.sort((a, b) => ((!b.paused) - (!a.paused)) || area(b) - area(a));
  const v = videos[0];
  if (command === "toggle") { if (v.paused || v.ended) v.play(); else v.pause(); }
  else if (command === "back" || command === "forward") {
    const step = Number(args && args.seconds) || 10;
    v.currentTime = Math.max(0, v.currentTime + (command === "back" ? -step : step));
  } else if (command === "seek_to" && isFinite(Number(args && args.time))) {
    v.currentTime = Math.max(0, Math.min(Number(args.time), v.duration || Number(args.time)));
  }
  return { playing: !v.paused && !v.ended, time: Math.floor(v.currentTime || 0),
    duration: isFinite(v.duration) ? Math.floor(v.duration) : 0, area: area(v) };
}

async function videoIn(tabId, command, args) {
  try {
    const frames = await chrome.scripting.executeScript({ target: { tabId, allFrames: true }, func: pageVideo, args: [command || "", args || {}] });
    let best = null;
    for (const frame of frames) {
      const r = frame.result;
      if (r && (!best || (r.playing && !best.playing) || (r.playing === best.playing && r.area > best.area))) best = { ...r, frameId: frame.frameId };
    }
    return best;
  } catch (e) {
    return null; // chrome://, магазин расширений, закрытая вкладка — туда нельзя
  }
}

async function allTabs() {
  const windows = await chrome.windows.getAll({ populate: true, windowTypes: ["normal", "app", "popup"] });
  const focused = windows.find((w) => w.focused);
  return { windows, focused, tabs: windows.flatMap((w) => w.tabs || []) };
}

// Чем управляют кнопки: вкладка со звуком (последняя открытая), иначе активная.
function pickMedia(info) {
  const selected = info.tabs.find((t) => t.id === selectedTabId);
  if (selected) return selected;
  selectedTabId = -1;
  const sounding = info.tabs.filter((t) => t.audible).sort((a, b) => (b.lastAccessed || 0) - (a.lastAccessed || 0));
  if (sounding.length) return sounding[0];
  const window = info.focused || info.windows[0];
  return window ? (window.tabs || []).find((t) => t.active) : null;
}

async function tabsState() {
  const info = await allTabs();
  const tab = pickMedia(info);
  const state = {};
  if (tab) {
    media.tabId = tab.id;
    state.tab_id = tab.id; // точное совпадение с карточкой YouTube, даже на паузе
    const muted = !!(tab.mutedInfo && tab.mutedInfo.muted);
    state.title = (tab.title || hostOf(tab.url) || "Вкладка").slice(0, 200);
    state.subtitle = (hostOf(tab.url) || "страница Chrome") + (tab.audible ? " · 🔊" : "");
    const video = await videoIn(tab.id);
    if (video) {
      media.frameId = video.frameId;
      Object.assign(state, { time: video.time, duration: video.duration, playing: video.playing });
    } else {
      state.hint = "На этой вкладке нет видео — выбери другую в списке";
    }
    state.icons = { toggle: video && video.playing ? "⏸" : "▶", mute: muted ? "🔇" : "🔈" };
    state.active = muted ? ["mute"] : [];
  } else {
    media.tabId = -1;
    state.hint = "Chrome без вкладок";
  }
  const list = { id: "tabs", title: "Вкладки", request: "list", request_title: "📑 Показать вкладки", small_icons: true,
    open_text: "Переключаю…", position: String(info.tabs.length), items: [],
    actions: [{ name: "mute", icon: "🔈", title: "Приглушить" }, { name: "close", icon: "✕", title: "Закрыть", confirm: "Закрыть вкладку?" }] };
  let size = 0;
  if (Date.now() < listUntil) {
    // Звучащие — первыми (музыку легко найти), дальше по окнам и порядку вкладок.
    const ordered = [...info.tabs].sort((a, b) => (b.audible ? 1 : 0) - (a.audible ? 1 : 0));
    for (const t of ordered.slice(0, TABS_MAX)) {
      const muted = !!(t.mutedInfo && t.mutedInfo.muted);
      const item = {
        id: String(t.id),
        title: (t.title || hostOf(t.url) || "Вкладка").slice(0, 100),
        subtitle: (hostOf(t.url) || "страница Chrome") + (t.audible ? " · 🔊" : "") + (muted ? " · 🔇" : ""),
        thumbnail: favOf(t),
        current: !!(t.active && info.focused && t.windowId === info.focused.id),
      };
      // Кнопки строки общие (list.actions); свои — только у приглушённых (другой значок).
      if (muted) item.actions = [{ name: "mute", icon: "🔇", title: "Включить звук" }, list.actions[1]];
      size += new TextEncoder().encode(JSON.stringify(item)).length; // кириллица — 2 байта
      if (size > TABS_BUDGET) break; // очень много вкладок — остальные не влезут
      list.items.push(item);
    }
  }
  if (list.items.length && list.items.length < info.tabs.length) list.position = list.items.length + " из " + info.tabs.length;
  state.lists = [list];
  return state;
}

function tabsSend(message) {
  if (tabsSocket && tabsSocket.readyState === WebSocket.OPEN) tabsSocket.send(JSON.stringify(message));
}

async function tabsPush(force) {
  if (!tabsSocket || tabsSocket.readyState !== WebSocket.OPEN) return;
  const state = await tabsState();
  const serial = JSON.stringify(state);
  if (force || serial !== lastSent) {
    lastSent = serial;
    tabsSend({ op: "adapter_state", state });
  }
}

function tabsSoon() {
  clearTimeout(tabsPushTimer);
  tabsPushTimer = setTimeout(() => tabsPush(false), 300);
}

async function tabsRun(command, args) {
  const id = Number(args && args.id);
  const tabId = Number.isInteger(id) && id > 0 ? id : media.tabId;
  if (command === "list") {
    listUntil = Date.now() + TABS_LIST_MS;
  } else if (command === "open_youtube") {
    const info = await allTabs();
    const windowId = (info.focused || info.windows[0] || {}).id;
    const options = { url: "https://www.youtube.com/", active: true };
    if (Number.isInteger(windowId)) options.windowId = windowId;
    try {
      const created = await chrome.tabs.create(options);
      selectedTabId = created.id;
      if (Number.isInteger(created.windowId)) await chrome.windows.update(created.windowId, { focused: true });
    } catch (e) { /* окно Chrome могло закрыться между выбором и открытием */ }
  } else if (["toggle", "back", "forward", "seek_to"].includes(command)) {
    if (media.tabId >= 0) {
      try {
        await chrome.scripting.executeScript({ target: { tabId: media.tabId, frameIds: [media.frameId] }, func: pageVideo, args: [command, args || {}] });
      } catch (e) { /* вкладку закрыли */ }
    }
  } else if (tabId >= 0) {
    listUntil = Math.max(listUntil, Date.now() + TABS_LIST_MS); // пользуется списком — не прятать
    try {
      const tab = await chrome.tabs.get(tabId);
      if (command === "mute") await chrome.tabs.update(tabId, { muted: !(tab.mutedInfo && tab.mutedInfo.muted) });
      else if (command === "close") await chrome.tabs.remove(tabId);
      else if (command === "play_item" || command === "show_tab") {
        selectedTabId = tabId;
        await chrome.tabs.update(tabId, { active: true });
        await chrome.windows.update(tab.windowId, { focused: true });
      }
    } catch (e) { /* вкладки уже нет */ }
  }
  setTimeout(() => tabsPush(true), 250);
}

function tabsConnect() {
  if (tabsSocket) return;
  clearTimeout(tabsRetryTimer);
  try {
    tabsSocket = new WebSocket(TABS_URL);
  } catch (e) {
    tabsSocket = null;
    tabsRetry();
    return;
  }
  tabsSocket.onopen = async () => {
    tabsRetryMs = 2000;
    lastSent = "";
    tabsSend({ ...TABS_ADAPTER, state: await tabsState() });
    clearInterval(tabsBeat);
    tabsBeat = setInterval(() => tabsPush(true), 20000); // держит связь (и воркер) живой
    clearInterval(tabsPoll);
    tabsPoll = setInterval(() => tabsPush(false), 2000); // время видео
  };
  tabsSocket.onmessage = (event) => {
    let message;
    try { message = JSON.parse(event.data); } catch (e) { return; }
    if (message.op === "run") tabsRun(String(message.command || ""), message.args || {});
  };
  tabsSocket.onclose = () => {
    tabsSocket = null;
    clearInterval(tabsBeat);
    clearInterval(tabsPoll);
    tabsRetry();
  };
  tabsSocket.onerror = () => {};
}

function tabsRetry() {
  clearTimeout(tabsRetryTimer);
  tabsRetryTimer = setTimeout(tabsConnect, tabsRetryMs);
  tabsRetryMs = Math.min(tabsRetryMs * 2, 30000); // Хоши может быть выключена — не спамим
}

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if ("title" in change || "audible" in change || "mutedInfo" in change || "favIconUrl" in change) tabsSoon();
});
for (const event of [chrome.tabs.onCreated, chrome.tabs.onRemoved, chrome.tabs.onActivated, chrome.windows.onFocusChanged]) {
  event.addListener(() => { tabsConnect(); tabsSoon(); });
}
chrome.tabs.onActivated.addListener(({tabId}) => {
  if (tabId !== selectedTabId) selectedTabId = -1; // ручной выбор на ПК возвращает обычный поиск плеера
});
// Воркер Chrome засыпает, если Хоши выключена: будильник раз в минуту пробует снова.
chrome.alarms.create("hoshi-tabs", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => { if (alarm.name === "hoshi-tabs") tabsConnect(); });
tabsConnect();
