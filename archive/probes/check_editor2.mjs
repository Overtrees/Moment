import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8097/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
const before = await page.evaluate(() => document.documentElement.scrollHeight);
console.log('before scrollH:', before);
let hit = null;
outer:
for (const y of [110, 118, 126, 105]) {
  for (const x of [85, 100, 115, 130, 70]) {
    await page.touchscreen.tap(x, y);
    await page.waitForTimeout(700);
    const h = await page.evaluate(() => document.documentElement.scrollHeight);
    if (h !== before) { hit = { x, y, h }; break outer; }
  }
}
console.log('tap hit:', JSON.stringify(hit));
if (hit) {
  await page.waitForTimeout(1500);
  const ed = await page.evaluate(() => ({ spacer: document.getElementById('spacer')?.style.height, scrollH: document.documentElement.scrollHeight }));
  console.log('editor state:', JSON.stringify(ed));
  await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/63-spike-v3-editor-top.png' });
  await page.evaluate(() => window.scrollTo(0, 1e9));
  await page.waitForTimeout(1200);
  console.log('bottom y:', await page.evaluate(() => window.scrollY));
  await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/64-spike-v3-editor-bottom.png' });
  await page.evaluate(() => window.scrollTo(0, 1500));
  await page.waitForTimeout(1000);
  await page.touchscreen.tap(210, 450);
  await page.waitForTimeout(800);
  await page.screenshot({ path: '/home/hatch/workspace/mynote-shots-round6/65-spike-v3-editor-tap.png' });
}
console.log('pageerrors:', errors.slice(0, 3));
await browser.close();
