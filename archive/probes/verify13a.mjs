import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 160)));
await page.goto('http://localhost:8096/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(5000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/23-orig-list.png' });
// 点头像进设置
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(2500);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/24-orig-after-avatar.png' });
await browser.close();
