/* CaptureFox background toolbar action
   FILE: capturefox/extension/background.js */
browser.action.onClicked.addListener(async () => {
  const url = browser.runtime.getURL('index.html');
  const tabs = await browser.tabs.query({});
  const existing = tabs.find(tab => tab.url?.split('#')[0] === url);
  if (existing) {
    await browser.tabs.update(existing.id, { active: true });
    await browser.windows.update(existing.windowId, { focused: true });
    return;
  }
  await browser.tabs.create({ url });
});
