// Runs in the page (MAIN world): adds a virtual Xbox 360 controller to navigator.getGamepads().
// Input arrives from relay.js through the '__xpad' event. Pages that never touch the
// Gamepad API never connect to XPad.
(() => {
  if (window.__xpadBridge) return;
  window.__xpadBridge = true;

  const EVT = '__xpad';
  const WANT = '__xpad_want';
  const N_BUTTONS = 17;
  const origGet = Navigator.prototype.getGamepads;
  const nativeList = () => {
    try { return origGet ? Array.from(origGet.call(navigator)) : []; } catch (_) { return []; }
  };

  let wanted = false;
  const want = () => {
    if (wanted) return;
    wanted = true;
    document.dispatchEvent(new CustomEvent(WANT));
  };

  const buttons = Array.from({ length: N_BUTTONS }, () => ({ pressed: false, touched: false, value: 0 }));
  const axes = [0, 0, 0, 0];
  const pad = {
    id: 'Xbox 360 Controller (STANDARD GAMEPAD Vendor: 045e Product: 028e)',
    index: 0,
    mapping: 'standard',
    connected: false,
    timestamp: 0,
    axes,
    buttons,
    vibrationActuator: null,
    hapticActuators: [],
  };
  let slot = -1;

  function list() {
    want();
    const arr = nativeList();
    if (!pad.connected) return arr;
    if (slot < 0 || (arr[slot] && arr[slot] !== pad)) {
      slot = arr.findIndex((g) => !g);
      if (slot < 0) slot = arr.length;
      pad.index = slot;
    }
    while (arr.length <= slot) arr.push(null);
    arr[slot] = pad;
    return arr;
  }

  Object.defineProperty(Navigator.prototype, 'getGamepads', {
    configurable: true,
    writable: true,
    value: function getGamepads() { return list(); },
  });

  // Games that wait for 'gamepadconnected' before polling.
  const origAdd = window.addEventListener;
  window.addEventListener = function (type, ...rest) {
    if (type === 'gamepadconnected') want();
    return origAdd.call(this, type, ...rest);
  };

  function fire(type) {
    const e = new Event(type);
    Object.defineProperty(e, 'gamepad', { value: pad });
    window.dispatchEvent(e);
  }

  document.addEventListener(EVT, (ev) => {
    let s = null;
    try { s = JSON.parse(ev.detail); } catch (_) { return; }
    if (!s) {
      if (pad.connected) {
        pad.connected = false;
        fire('gamepaddisconnected');
        slot = -1;
      }
      return;
    }
    for (let i = 0; i < N_BUTTONS; i++) {
      const on = (s.mask >> i) & 1;
      const b = buttons[i];
      b.pressed = !!on;
      b.touched = !!on;
      b.value = i === 6 ? s.lt : i === 7 ? s.rt : on;
    }
    axes[0] = s.lx; axes[1] = s.ly; axes[2] = s.rx; axes[3] = s.ry;
    pad.timestamp = performance.now();
    if (!pad.connected) {
      pad.connected = true;
      list();
      fire('gamepadconnected');
    }
  });
})();
