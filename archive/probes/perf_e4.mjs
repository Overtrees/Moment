import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8097/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(3000);
const before = await page.screenshot();
const t0 = Date.now();
await page.touchscreen.tap(210, 320);
let dt = null;
while (Date.now() - t0 < 10000) {
  const shot = await page.screenshot();
  if (Buffer.compare(shot, before) !== 0) { dt = Date.now() - t0; break; }
  await page.waitForTimeout(40);
}
console.log('ORIG_EDITOR_OPEN_MS', dt);
await browser.close();
