// 探针 2：建 3 条不同文字，dump 全部 create/load/save 日志 + 列表截图，
// 定位"多条变一条"发生在哪一层。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(14000);

for (const t of ['甲一', '乙二', '丙三']) {
  await page.touchscreen.tap(210, 233);
  await page.waitForTimeout(2500);
  await page.touchscreen.tap(210, 420);
  await page.waitForTimeout(600);
  await page.keyboard.insertText(t);
  await page.waitForTimeout(1000);
  await page.touchscreen.tap(39, 30);
  await page.waitForTimeout(2500);
}
const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1'));
const arr = JSON.parse(diag || '[]');
console.log(arr.filter((x) => /create|load memo|save memo/.test(x)).join('\n'));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/90-prod-v3-probe2-list.png' });
await browser.close();
