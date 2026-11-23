// 探针：列表页新建卡片点击落点——建一条、返回、再点同位置，看打开什么。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(14000);
const diagTail = async () => {
  const d = await page.evaluate(() => localStorage.getItem('mynote_diag_v1'));
  const arr = JSON.parse(d || '[]');
  return arr.slice(-3).join(' | ');
};

await page.touchscreen.tap(210, 233);
await page.waitForTimeout(2500);
console.log('after tap1 diag:', await diagTail());
await page.touchscreen.tap(210, 420);
await page.waitForTimeout(500);
await page.keyboard.insertText('探针一号');
await page.waitForTimeout(900);
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(2500);
console.log('after back diag:', await diagTail());
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/85-prod-v3-probe-list.png' });

await page.touchscreen.tap(210, 233);
await page.waitForTimeout(2500);
console.log('after tap2 diag:', await diagTail());
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/86-prod-v3-probe-after-tap2.png' });
await browser.close();
