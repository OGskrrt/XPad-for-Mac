// XPad tab: reads the controller over WebUSB and sends its state to game tabs (relay.js).
const X = globalThis.XInputCore;
const FILTERS = [
  { vendorId: 0x2dc8 }, // 8BitDo
  { vendorId: 0x045e }, // Microsoft
  { classCode: 0xff, subclassCode: 0x5d, protocolCode: 0x01 }, // Xbox 360-style (XInput)
];

const $ = (id) => document.getElementById(id);
const ui = {
  status: $('status'), dot: $('dot'), connect: $('connect'), tabs: $('tabs'), count: $('count'),
  log: $('log'), ls: $('ls'), rs: $('rs'), lt: $('lt'), rt: $('rt'), buttons: $('buttons'),
};
const btnEls = X.NAMES.map((name) => {
  const li = document.createElement('li');
  li.textContent = name;
  ui.buttons.append(li);
  return li;
});

const ports = new Set();
let handle = null;
let current = null;
let connecting = false;
let lastState = null;
let lastJson = '';
let reports = 0;

function log(msg) {
  const t = new Date().toTimeString().slice(0, 8);
  ui.log.textContent = `${t}  ${msg}\n` + ui.log.textContent.slice(0, 4000);
}

function setStatus(text, ok) {
  ui.status.textContent = text;
  ui.dot.classList.toggle('on', !!ok);
}

function broadcast(s) {
  for (const p of ports) {
    try { p.postMessage({ s }); } catch (_) { ports.delete(p); }
  }
}

function render(s) {
  if (document.visibilityState !== 'visible') return;
  ui.count.textContent = String(reports);
  if (!s) return;
  btnEls.forEach((li, i) => li.classList.toggle('on', !!(s.mask & (1 << i))));
  ui.ls.style.transform = `translate(${s.lx * 31}px, ${s.ly * 31}px)`;
  ui.rs.style.transform = `translate(${s.rx * 31}px, ${s.ry * 31}px)`;
  ui.lt.value = s.lt;
  ui.rt.value = s.rt;
}

function onState(s) {
  reports++;
  const json = JSON.stringify(s);
  if (json === lastJson) return;
  lastJson = json;
  lastState = s;
  broadcast(s);
  render(s);
}

function onEnd(err) {
  handle = null;
  current = null;
  lastState = null;
  lastJson = '';
  broadcast(null);
  setStatus('Controller disconnected', false);
  if (err) log('stopped reading: ' + err.message);
}

async function attach(device) {
  if (handle || connecting) return;
  if (!X.findXInput(device)) { log(`${device.productName || 'device'}: not an XInput controller, skipped`); return; }
  connecting = true;
  setStatus('Connecting…', false);
  try {
    handle = await X.start(device, onState, onEnd, log);
    current = device;
    setStatus(`Connected: ${device.productName || 'controller'}`, true);
    log(`connected (${device.vendorId.toString(16)}:${device.productId.toString(16)})`);
  } catch (e) {
    handle = null;
    const busy = /claim|access|busy/i.test(e.message);
    setStatus(busy ? 'Controller is in use by another app or tab' : 'Could not connect: ' + e.message, false);
    log('error: ' + e.message);
  } finally {
    connecting = false;
  }
}

ui.connect.addEventListener('click', async () => {
  try {
    const device = await navigator.usb.requestDevice({ filters: FILTERS });
    await attach(device);
  } catch (e) {
    if (e.name !== 'NotFoundError') log('picker error: ' + e.message);
  }
});

navigator.usb.addEventListener('connect', (e) => { log('USB plugged in'); attach(e.device); });
navigator.usb.addEventListener('disconnect', (e) => { if (e.device === current) log('USB unplugged'); });

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== 'xpad') return;
  ports.add(port);
  ui.tabs.textContent = String(ports.size);
  port.onDisconnect.addListener(() => {
    ports.delete(port);
    ui.tabs.textContent = String(ports.size);
  });
  if (lastState) port.postMessage({ s: lastState });
});

document.addEventListener('visibilitychange', () => render(lastState));

async function sayHello() {
  try {
    const tabs = await chrome.tabs.query({});
    for (const t of tabs) {
      if (t.id != null) chrome.tabs.sendMessage(t.id, { xpadHello: true }).catch(() => {});
    }
  } catch (_) {}
}

(async () => {
  sayHello();
  if (!navigator.usb) { setStatus('This browser has no WebUSB (use Chrome)', false); return; }
  const devices = await navigator.usb.getDevices();
  const known = devices.find((d) => X.findXInput(d));
  if (known) await attach(known);
  else setStatus('No controller yet — click "Connect controller"', false);
})();
