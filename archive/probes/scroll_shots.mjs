import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round2';
fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function scrollShot(url, name, openTap) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  if (openTap) {
    await page.touchscreen.tap(openTap[0], openTap[1]);
    await page.waitForTimeout(3000);
  }
  await page.screenshot({ path: `${OUT}/${name}-top.png` });
  // 触摸滚动
  await page.touchscreen.tap(210, 450);
  await page.mouse.move(210, 600);
  await page.mouse.down();
  await page.mouse.move(210, 250, { steps: 12 });
  await page.mouse.up();
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `${OUT}/${name}-scrolled.png` });
  await ctx.close();
}

// 原版列表滚动
await scrollShot('http://127.0.0.1:8096/Moment.html', '40-web-list');
// 新版列表滚动
await scrollShot('http://127.0.0.1:8095/', '41-fl-list');
// 原版编辑器（周末看展记录，列表第三张附近）
await scrollShot('http://127.0.0.1:8096/Moment.html', '42-web-editor', [210, 430]);
// 新版编辑器（同位置）
await scrollShot('http://127.0.0.1:8095/', '43-fl-editor', [210, 430]);
await browser.close();
console.log('done');
