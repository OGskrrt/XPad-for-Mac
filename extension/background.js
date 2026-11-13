// Clicking the toolbar icon opens the XPad tab (or brings it forward). It also opens on install.
const BRIDGE_URL = chrome.runtime.getURL('bridge.html');

async function openBridge() {
  try {
    const ctx = await chrome.runtime.getContexts({ contextTypes: ['TAB'], documentUrls: [BRIDGE_URL] });
    if (ctx.length && ctx[0].tabId >= 0) {
      const tab = await chrome.tabs.update(ctx[0].tabId, { active: true });
      await chrome.windows.update(tab.windowId, { focused: true });
      return;
    }
    await chrome.tabs.create({ url: BRIDGE_URL, pinned: true });
  } catch (e) {
    console.error('XPad: could not open the bridge tab', e);
  }
}

chrome.action.onClicked.addListener(() => { openBridge(); });

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') openBridge();
});
