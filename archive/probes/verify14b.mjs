import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(200);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/34-settings-enter-mid.png' });
await page.waitForTimeout(1500);
// 退场中途：点返回后 150ms
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(150);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/35-settings-exit-mid.png' });
await browser.close();
