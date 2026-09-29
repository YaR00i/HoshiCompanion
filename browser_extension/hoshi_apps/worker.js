// Hoshi Apps — background part. Keeps ONE local connection to Hoshi on this PC
// (ws://127.0.0.1:18771/hoshi-adapter-v1) while at least one YouTube tab is
// open, announces the YouTube buttons, forwards state and presses.
// Nothing leaves this computer.
"use strict";

importScripts("tabs.js"); // раздел «Вкладки Chrome» — своё соединение с Хоши

const HOSHI_URL = "ws://127.0.0.1:18771/hoshi-adapter-v1";
const ADAPTER = {
  op: "adapter",
  id: "youtube",
  title: "YouTube",
  commands: [
    { name: "back", title: "−10 секунд", icon: "⏪", row: "main", args: { seconds: 10 } },
    { name: "toggle", title: "Пауза / играть", icon: "⏯", row: "main" },
    { name: "forward", title: "+10 секунд", icon: "⏩", row: "main", args: { seconds: 10 } },
    { name: "next", title: "Следующее видео", icon: "⏭", row: "main" },
    { name: "vol_down", title: "Тише", icon: "🔉" },
    { name: "vol_up", title: "Громче", icon: "🔊" },
    { name: "mute", title: "Без звука", icon: "🔈" },
    { name: "like", title: "Нравится", icon: "♥" },
    { name: "seek_to", title: "Перейти к моменту", icon: "", row: "hidden", args: { time: 0 } },
    { name: "play_item", title: "Включить видео из списка", icon: "", row: "hidden", args: { id: "" } },
    { name: "open_new", title: "Открыть видео в новой вкладке", icon: "", row: "hidden", args: { id: "" } },
  ],
};

const tabs = new Map(); // tabId -> { port, state, playingSince, touched }
let focusedTab = -1;
let socket = null;
let retryMs = 1000;
let retryTimer = null;
let heartbeat = null;

function now() { return Date.now(); }

// Явно открытая вкладка YouTube получает управление, даже если в фоне ещё
// играет другое видео. Пока выбор не сделан, берём последнее играющее.
function currentTab() {
  if (tabs.has(focusedTab)) return focusedTab;
  let best = -1;
  let bestScore = -Infinity;
  for (const [id, info] of tabs) {
    const s = info.state || {};
    let score = info.touched / 1e13;
    if (s.playing) score += 3 + info.playingSince / 1e13;
    else if (s.title) score += 1;
    if (score > bestScore) { bestScore = score; best = id; }
  }
  return best;
}

function currentState() {
  const id = currentTab();
  return id >= 0 ? { ...(tabs.get(id).state || {}), tab_id: id } : { hint: "Открой YouTube в Chrome" };
}

function send(message) {
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
}

function pushState() { send({ op: "adapter_state", state: currentState() }); }

async function openNewVideo(args) {
  const id = String(args && args.id || "");
  if (!/^[A-Za-z0-9_-]{6,20}$/.test(id)) return false;
  const source = currentTab();
  if (source < 0) return false;
  const sourceInfo = tabs.get(source);
  const lists = Array.isArray(sourceInfo.state?.lists) ? sourceInfo.state.lists : [];
  const item = lists.flatMap((list) => Array.isArray(list.items) ? list.items : []).find((entry) => entry.id === id);
  if (!item) return false; // только видео, уже показанное открытым YouTube
  const list = /^[A-Za-z0-9_-]{2,64}$/.test(String(item.list || "")) ? String(item.list) : "";
  const windowId = sourceInfo.windowId;
  if (!Number.isInteger(windowId)) return false;
  const url = "https://www.youtube.com/watch?v=" + encodeURIComponent(id) + (list ? "&list=" + encodeURIComponent(list) : "");
  try {
    await chrome.tabs.create({ url, active: true, windowId });
    await chrome.windows.update(windowId, { focused: true });
    return true;
  } catch (e) { return false; }
}

function connectHoshi() {
  if (socket || tabs.size === 0) return;
  clearTimeout(retryTimer);
  try {
    socket = new WebSocket(HOSHI_URL);
  } catch (e) {
    socket = null;
    scheduleRetry();
    return;
  }
  socket.onopen = () => {
    retryMs = 1000;
    send({ ...ADAPTER, state: currentState() });
    clearInterval(heartbeat);
    heartbeat = setInterval(pushState, 20000); // держит связь (и воркер) живой
  };
  socket.onmessage = (event) => {
    let message;
    try { message = JSON.parse(event.data); } catch (e) { return; }
    if (message.op === "run") {
      if (message.command === "open_new") { openNewVideo(message.args || {}); return; }
      const id = currentTab();
      if (id >= 0) tabs.get(id).port.postMessage({ op: "run", command: message.command, args: message.args || {} });
    }
  };
  socket.onclose = () => {
    socket = null;
    clearInterval(heartbeat);
    scheduleRetry();
  };
  socket.onerror = () => {};
}

function scheduleRetry() {
  if (tabs.size === 0) return;
  clearTimeout(retryTimer);
  retryTimer = setTimeout(connectHoshi, retryMs);
  retryMs = Math.min(retryMs * 2, 15000); // Хоши может быть выключена — не спамим
}

function disconnectHoshi() {
  clearTimeout(retryTimer);
  clearInterval(heartbeat);
  if (socket) { socket.onclose = null; socket.close(); socket = null; }
}

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "hoshi-youtube" || !port.sender || !port.sender.tab) return;
  const tabId = port.sender.tab.id;
  tabs.set(tabId, { port, windowId: port.sender.tab.windowId, state: {}, playingSince: 0, touched: now() });
  port.onMessage.addListener((message) => {
    const info = tabs.get(tabId);
    if (!info || !message) return;
    if (message.op === "state" && message.state && typeof message.state === "object") {
      if (message.state.playing && !(info.state && info.state.playing)) info.playingSince = now();
      info.state = message.state;
      info.touched = now();
      pushState();
    } else if (message.op === "event") {
      send({ op: "event", id: "youtube", event: String(message.event || "").slice(0, 24) });
    }
  });
  port.onDisconnect.addListener(() => {
    tabs.delete(tabId);
    if (tabs.size === 0) disconnectHoshi(); else pushState();
  });
  connectHoshi();
});

chrome.tabs.onActivated.addListener(({ tabId }) => {
  focusedTab = tabId;
  if (tabs.has(tabId)) { tabs.get(tabId).touched = now(); pushState(); }
});
