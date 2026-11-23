// 对照实验：同一 CDP 拖动作用于官方原型（朴素 CustomScrollView）
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const url = process.argv[2] || 'http://localhost:8097/';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(12000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/11-proto-top.png' });
const cdp = await ctx.newCDPSession(page);
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 210, y: 720, id: 1 }] });
for (let i = 1; i <= 14; i++) {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 210, y: 720 - 460 * (i / 14), id: 1 }] });
  await page.waitForTimeout(28);
  if (i === 7) await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/12-proto-mid.png' });
}
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await page.waitForTimeout(300);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/13-proto-end.png' });
await page.waitForTimeout(1500);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/14-proto-settled.png' });
console.log('pageerrors:', JSON.stringify(errors.slice(0, 5)));
await browser.close();
