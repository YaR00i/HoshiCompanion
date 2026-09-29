const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const listeners = () => {
  const callbacks = [];
  return { addListener: (fn) => callbacks.push(fn), emit: (arg) => callbacks.forEach((fn) => fn(arg)) };
};
const onActivated = listeners();
const onFocusChanged = listeners();
const tabEvents = { onCreated: listeners(), onRemoved: listeners(), onUpdated: listeners(), onActivated };
const pages = [
  { id: 1, windowId: 10, active: true, audible: true, title: "Первый ролик", url: "https://www.youtube.com/watch?v=first", lastAccessed: 30 },
  { id: 2, windowId: 10, active: false, audible: false, title: "Второй ролик", url: "https://www.youtube.com/watch?v=second", lastAccessed: 20 },
  { id: 3, windowId: 10, active: false, audible: false, title: "Другое видео", url: "https://example.org/watch", lastAccessed: 10 },
];
let focused = true;
const opened = [];
const chrome = {
  tabs: {
    ...tabEvents,
    create: async (options) => { opened.push(options); return {id: 4, ...options}; },
    get: async (id) => pages.find((tab) => tab.id === id),
    update: async (id, change) => {
      const tab = pages.find((entry) => entry.id === id);
      assert.ok(tab);
      if (change.active) {
        pages.forEach((entry) => { entry.active = entry.id === id; });
        onActivated.emit({ tabId: id });
      }
      if ("muted" in change) tab.mutedInfo = { muted: change.muted };
      return tab;
    },
    remove: async (id) => { pages.splice(pages.findIndex((entry) => entry.id === id), 1); tabEvents.onRemoved.emit(id); },
  },
  windows: {
    onFocusChanged,
    getAll: async () => [{ id: 10, focused, tabs: pages }],
    update: async (id, change) => { assert.equal(id, 10); focused = change.focused; onFocusChanged.emit(id); },
  },
  scripting: { executeScript: async ({ target }) => [{ frameId: 0, result: {
    playing: target.tabId === 1, time: 12, duration: 90, area: 100,
  } }] },
  runtime: { onConnect: listeners() },
  alarms: { create: () => {}, onAlarm: listeners() },
};
class FakeWebSocket { static OPEN = 1; constructor() { this.readyState = 0; } }
const context = vm.createContext({ chrome, WebSocket: FakeWebSocket, URL, TextEncoder,
  setTimeout, clearTimeout, setInterval, clearInterval, importScripts: () => {}, console });
const extension = path.join(__dirname, "..", "..", "browser_extension", "hoshi_apps");
vm.runInContext(fs.readFileSync(path.join(extension, "tabs.js"), "utf8"), context);
vm.runInContext(fs.readFileSync(path.join(extension, "worker.js"), "utf8"), context);

(async () => {
  vm.runInContext(`
    tabs.set(1, {windowId:10,state:{title:"Первый ролик",playing:true},playingSince:10,touched:10});
    tabs.set(2, {windowId:10,state:{title:"Второй ролик",playing:false,
      lists:[{id:"next",items:[{id:"abc123xyz",title:"Выбранное видео"}]}]},playingSince:0,touched:9});
    focusedTab = 1;
  `, context);
  assert.equal(vm.runInContext("currentTab()", context), 1);
  await vm.runInContext("tabsRun('play_item', {id:2})", context);
  assert.equal(pages.find((tab) => tab.active).id, 2);
  assert.equal(vm.runInContext("currentTab()", context), 2);
  let state = await vm.runInContext("tabsState()", context);
  assert.equal(state.title, "Второй ролик");
  assert.equal(state.tab_id, 2);
  assert.equal(vm.runInContext("currentState().tab_id", context), 2);
  assert.equal(state.lists[0].items.length, 3);
  assert.ok(state.lists[0].items.some((item) => item.title === "Другое видео"));
  assert.equal(vm.runInContext("ADAPTER.commands.some(x => x.name === 'open_new')", context), true);
  assert.equal(await vm.runInContext("openNewVideo({id:'abc123xyz'})", context), true);
  assert.equal(opened[0].url, "https://www.youtube.com/watch?v=abc123xyz");
  assert.equal(opened[0].windowId, 10);
  vm.runInContext(`tabs.get(2).state = {page:"home",title:"Главная YouTube",
    lists:[{id:"home",items:[{id:"homeAAA1111",title:"Предложенный ролик"}]}]};`, context);
  assert.equal(await vm.runInContext("openNewVideo({id:'homeAAA1111'})", context), true);
  assert.equal(opened[1].url, "https://www.youtube.com/watch?v=homeAAA1111");
  assert.equal(await vm.runInContext("openNewVideo({id:'unknown999'})", context), false);
  assert.equal(opened.length, 2);
  assert.equal(vm.runInContext("TABS_ADAPTER.commands.some(x => x.name === 'open_youtube')", context), true);
  await vm.runInContext("tabsRun('open_youtube', {})", context);
  assert.equal(opened[2].url, "https://www.youtube.com/");
  assert.equal(opened[2].windowId, 10);
  onActivated.emit({ tabId: 3 }); // ручное переключение на ПК возвращает обычный выбор
  assert.equal(vm.runInContext("selectedTabId", context), -1);
  state = await vm.runInContext("tabsState()", context);
  assert.equal(state.title, "Первый ролик"); // слышимая вкладка снова первая

  const remote = fs.readFileSync(path.join(extension, "..", "..", "remote", "remote.html"), "utf8");
  const sameTab = remote.match(/function sameBrowserVideo\(tabsState, youtubeState\) \{[^}]*\}/)?.[0];
  assert.ok(sameTab);
  const sameBrowserVideo = vm.runInNewContext(sameTab + ";sameBrowserVideo");
  assert.equal(sameBrowserVideo({tab_id: 2, playing: false}, {tab_id: 2, playing: false}), true);
  assert.equal(sameBrowserVideo({tab_id: 2}, {tab_id: 3}), false);
  assert.equal(sameBrowserVideo({title: "YouTube"}, {tab_id: 2}), false);
  const miniSource = remote.slice(remote.indexOf("const MINI_KEEP_MS"), remote.indexOf("function miniCommand"));
  const remoteContext = vm.createContext({state: {apps: [
    {id: "tabs", state: {title: "Video - YouTube", tab_id: 2, playing: false}, commands: [{command: "app:tabs:toggle"}]},
    {id: "youtube", state: {title: "Video", tab_id: 2, playing: false}, commands: [{command: "app:youtube:toggle"}]},
  ]}, Date});
  vm.runInContext(sameTab + "\n" + miniSource, remoteContext);
  vm.runInContext("miniSeen.tabs={since:0,last:Date.now(),playing:false};miniSeen.youtube={since:0,last:Date.now(),playing:false}", remoteContext);
  assert.equal(vm.runInContext("miniCandidates().length", remoteContext), 1); // пауза не создаёт второй плеер
  vm.runInContext("state.apps[1].state.tab_id=3", remoteContext);
  assert.equal(vm.runInContext("miniCandidates().length", remoteContext), 2); // две разные вкладки
  console.log("HOSHI_BROWSER_TABS_RESULT checks=26 failures=0");
})().catch((error) => { console.error(error); process.exitCode = 1; });
