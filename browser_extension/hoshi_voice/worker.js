async function ensureOffscreen() {
  const contexts = await chrome.runtime.getContexts({contextTypes: ["OFFSCREEN_DOCUMENT"]});
  if (contexts.length === 0) {
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["USER_MEDIA"],
      justification: "Read only the audio level of the selected ChatGPT tab for Hoshi's mouth animation."
    });
  }
}

async function setBadge(tabId, active) {
  await chrome.action.setBadgeText({tabId, text: active ? "ON" : ""});
  if (active) await chrome.action.setBadgeBackgroundColor({tabId, color: "#8d6cb0"});
}

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id || !/^https:\/\/(chatgpt\.com|chat\.openai\.com)(\/|$)/.test(tab.url || "")) {
    console.warn("Open a ChatGPT tab before connecting Hoshi Voice.");
    return;
  }
  try {
    await ensureOffscreen();
    const status = await chrome.runtime.sendMessage({target: "offscreen", type: "status"});
    if (status?.tabId === tab.id) {
      await chrome.runtime.sendMessage({target: "offscreen", type: "stop"});
      await setBadge(tab.id, false);
      return;
    }
    if (status?.tabId) await setBadge(status.tabId, false);
    const streamId = await chrome.tabCapture.getMediaStreamId({targetTabId: tab.id});
    const result = await chrome.runtime.sendMessage({target: "offscreen", type: "start", tabId: tab.id, streamId});
    await setBadge(tab.id, Boolean(result?.active));
  } catch (error) {
    console.error("Hoshi Voice capture failed:", error);
    await setBadge(tab.id, false);
  }
});

chrome.runtime.onMessage.addListener((message) => {
  if (message.target === "worker" && message.type === "stopped" && message.tabId) {
    setBadge(message.tabId, false);
  }
});
