// XInput (Xbox 360 USB protokolü) okuyucu — WebUSB API üstünde.
// Aynı dosya Chrome eklentisinde (bridge.html) ve Node testinde (node-usb WebUSB) çalışır.
(function (root) {
  'use strict';

  // Standart Gamepad API düğme sırası (17 düğme)
  const NAMES = ['A', 'B', 'X', 'Y', 'LB', 'RB', 'LT', 'RT', 'Back', 'Start', 'LS', 'RS', 'Up', 'Down', 'Left', 'Right', 'Home'];

  function findXInput(device) {
    for (const cfg of device.configurations || []) {
      for (const itf of cfg.interfaces) {
        for (const alt of itf.alternates) {
          if (alt.interfaceClass === 0xff && alt.interfaceSubclass === 0x5d && alt.interfaceProtocol === 0x01) {
            const epIn = alt.endpoints.find((e) => e.direction === 'in');
            const epOut = alt.endpoints.find((e) => e.direction === 'out');
            if (epIn) {
              return {
                config: cfg.configurationValue,
                iface: itf.interfaceNumber,
                alt: alt.alternateSetting,
                epIn: epIn.endpointNumber,
                epOut: epOut ? epOut.endpointNumber : null,
              };
            }
          }
        }
      }
    }
    return null;
  }

  // 20 baytlık Xbox 360 giriş raporu → normalize durum
  function parse(dv) {
    if (!dv || dv.byteLength < 14 || dv.getUint8(0) !== 0x00 || dv.getUint8(1) < 0x14) return null;
    const lo = dv.getUint8(2);
    const hi = dv.getUint8(3);
    const bit = (b, n) => (b >> n) & 1;
    const lt = dv.getUint8(4) / 255;
    const rt = dv.getUint8(5) / 255;
    const flags = [
      bit(hi, 4), bit(hi, 5), bit(hi, 6), bit(hi, 7), // A B X Y
      bit(hi, 0), bit(hi, 1), // LB RB
      lt > 0.12 ? 1 : 0, rt > 0.12 ? 1 : 0, // LT RT
      bit(lo, 5), bit(lo, 4), // Back Start
      bit(lo, 6), bit(lo, 7), // LS RS
      bit(lo, 0), bit(lo, 1), bit(lo, 2), bit(lo, 3), // D-pad
      bit(hi, 2), // Home
    ];
    let mask = 0;
    flags.forEach((v, i) => { if (v) mask |= 1 << i; });
    const ax = (o) => Math.max(-1, dv.getInt16(o, true) / 32767);
    const r3 = (v) => Math.round(v * 1000) / 1000;
    return {
      mask, lt: r3(lt), rt: r3(rt),
      lx: r3(ax(6)), ly: r3(-ax(8) || 0), rx: r3(ax(10)), ry: r3(-ax(12) || 0),
    };
  }

  // Cihazı aç, arayüzü al, okuma döngüsünü başlat. onState(state) her raporda, onEnd(err) bitince.
  async function start(device, onState, onEnd, log) {
    log = log || (() => {});
    if (!device.opened) await device.open();
    const info = findXInput(device);
    if (!info) throw new Error('XInput arayüzü bulunamadı');
    if (!device.configuration || device.configuration.configurationValue !== info.config) {
      await device.selectConfiguration(info.config);
    }
    await device.claimInterface(info.iface);
    if (info.alt) await device.selectAlternateInterface(info.iface, info.alt);
    // Bazı üçüncü parti 360 kumandaları bu istek gelmeden rapor göndermiyor (Linux xpad ile aynı)
    try {
      await device.controlTransferIn({ requestType: 'vendor', recipient: 'interface', request: 0x01, value: 0x100, index: info.iface }, 20);
    } catch (e) { log('init isteği atlandı: ' + e.message); }
    // Oyuncu 1 LED'i
    if (info.epOut != null) {
      try { await device.transferOut(info.epOut, new Uint8Array([0x01, 0x03, 0x06])); } catch (e) { log('LED atlandı: ' + e.message); }
    }
    let running = true;
    (async () => {
      let err = null;
      while (running) {
        let r;
        try { r = await device.transferIn(info.epIn, 32); } catch (e) { err = e; break; }
        if (r.status !== 'ok' || !r.data) continue;
        const s = parse(r.data);
        if (s) onState(s);
      }
      running = false;
      onEnd && onEnd(err);
    })();
    return {
      info,
      stop: async () => {
        running = false;
        try { await device.releaseInterface(info.iface); } catch (_) {}
        try { await device.close(); } catch (_) {}
      },
    };
  }

  const api = { NAMES, findXInput, parse, start };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.XInputCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
