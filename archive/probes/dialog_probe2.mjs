import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.touchscreen.tap(52, 52);
await page.waitForTimeout(1000);
await page.touchscreen.tap(210, 245);
await page.waitForTimeout(1000);
await page.touchscreen.tap(210, 398);
await page.waitForTimeout(1000);
// 逐点试探继续恢复按钮区域
for (const [x, y] of [[266, 454], [280, 470], [250, 440], [290, 490], [266, 505]]) {
  await page.mouse.click(x, y);
  await page.waitForTimeout(700);
  await page.screenshot({ path: `/tmp/probe2-${x}-${y}.png` });
  console.log('clicked', x, y);
}
await browser.close();
