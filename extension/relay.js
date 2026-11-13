// Isolated world: once the page uses the Gamepad API, connect to the XPad tab and pass
// controller input to page.js.
(() => {
  const EVT = '__xpad';
  const send = (s) => document.dispatchEvent(new CustomEvent(EVT, { detail: JSON.stringify(s) }));
  let wanted = false;
  let port = null;
  let retry = 0;
  let timer = null;

  function connect() {
    if (!wanted || port) return;
    clearTimeout(timer);
    try {
      port = chrome.runtime.connect({ name: 'xpad' });
    } catch (_) {
      return; // extension was reloaded; reload this page
    }
    port.onMessage.addListener((msg) => {
      retry = 0;
      send(msg && msg.s ? msg.s : null);
    });
    port.onDisconnect.addListener(() => {
      void chrome.runtime.lastError; // XPad tab not open
      port = null;
      send(null);
      retry = Math.min(retry + 1, 6);
      timer = setTimeout(connect, 2000 * retry);
    });
  }

  document.addEventListener('__xpad_want', () => {
    wanted = true;
    connect();
  });

  // The XPad tab says hello when it opens, so pages connect right away.
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg && msg.xpadHello) { retry = 0; connect(); }
  });
})();
