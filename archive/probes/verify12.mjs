import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 160)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
await page.touchscreen.tap(210, 775); // 最近在听的歌
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/18-music-before.png' });
await page.waitForTimeout(3000);
// 长按第一张卡（c6.y.qq.com，中心约 y=281）
await page.mouse.move(210, 281);
await page.mouse.down();
await page.waitForTimeout(800); // 越过 500ms 武装
await page.mouse.move(210, 500, { steps: 12 });
await page.waitForTimeout(400);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/18-dragging.png' });
await page.mouse.up();
await page.waitForTimeout(1500);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/19-drag-done.png' });
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-8); } catch { return ['?']; } });
console.log('DIAG:', JSON.stringify(diag, null, 0));
await browser.close();
