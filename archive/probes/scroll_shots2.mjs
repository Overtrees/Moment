import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round2';
fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function wheelShot(url, name, openTap) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  if (openTap) {
    await page.touchscreen.tap(openTap[0], openTap[1]);
    await page.waitForTimeout(3000);
  }
  await page.mouse.move(210, 500);
  await page.mouse.wheel(0, 700);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${OUT}/${name}.png` });
  await ctx.close();
}

await wheelShot('http://127.0.0.1:8096/Moment.html', '44-web-list-wheel');
await wheelShot('http://127.0.0.1:8095/', '45-fl-list-wheel');
await wheelShot('http://127.0.0.1:8096/Moment.html', '46-web-editor-wheel', [210, 360]);
await wheelShot('http://127.0.0.1:8095/', '47-fl-editor-wheel', [210, 360]);
await browser.close();
console.log('done');
