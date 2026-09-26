let captureTabId = null;
let media = null;
let audioContext = null;
let analyser = null;
let timer = null;
let socket = null;
let lastConnectAttempt = 0;

function connectBridge() {
  if (socket || !media || Date.now() - lastConnectAttempt < 1000) return;
  lastConnectAttempt = Date.now();
  const connection = new WebSocket("ws://127.0.0.1:18765/hoshi-voice-v1");
  socket = connection;
  connection.onclose = () => { if (socket === connection) socket = null; };
  connection.onerror = () => { /* The Godot bridge may be started later. */ };
}

function sampleLevel() {
  if (!analyser || !media?.active) return;
  connectBridge();
  if (socket?.readyState !== WebSocket.OPEN) return;
  const samples = new Float32Array(analyser.fftSize);
  analyser.getFloatTimeDomainData(samples);
  let energy = 0;
  for (const value of samples) energy += value * value;
  const rms = Math.sqrt(energy / samples.length);
  const level = Math.max(0, Math.min(1, (rms - 0.012) * 8));
  socket.send(JSON.stringify({level}));
}

async function stopCapture() {
  const oldTabId = captureTabId;
  captureTabId = null;
  if (timer) clearInterval(timer);
  timer = null;
  if (media) for (const track of media.getTracks()) track.stop();
  media = null;
  analyser = null;
  if (audioContext) await audioContext.close();
  audioContext = null;
  if (socket) socket.close();
  socket = null;
  if (oldTabId) chrome.runtime.sendMessage({target: "worker", type: "stopped", tabId: oldTabId});
}

async function startCapture(tabId, streamId) {
  await stopCapture();
  media = await navigator.mediaDevices.getUserMedia({
    audio: {mandatory: {chromeMediaSource: "tab", chromeMediaSourceId: streamId}},
    video: false
  });
  captureTabId = tabId;
  audioContext = new AudioContext();
  const source = audioContext.createMediaStreamSource(media);
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 1024;
  source.connect(analyser);
  // Tab capture mutes normal tab output; route it back to the speakers.
  analyser.connect(audioContext.destination);
  media.getAudioTracks()[0].onended = () => { stopCapture(); };
  timer = setInterval(sampleLevel, 50);
  connectBridge();
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.target !== "offscreen") return;
  if (message.type === "status") {
    sendResponse({tabId: captureTabId});
    return;
  }
  const action = message.type === "start"
    ? startCapture(message.tabId, message.streamId)
    : stopCapture();
  action.then(() => sendResponse({active: Boolean(captureTabId)}))
    .catch((error) => {
      console.error("Hoshi Voice:", error);
      sendResponse({active: false, error: String(error)});
    });
  return true;
});
