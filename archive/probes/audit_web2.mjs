import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 100)));
await page.goto('http://127.0.0.1:8096/Moment.html', { waitUntil: 'networkidle' });
await page.waitForTimeout(3500);
await page.mouse.click(200, 500); // 周末看展记录卡
await page.waitForTimeout(2500);
await page.screenshot({ path: '/tmp/audit-web-editor.png' });
await page.mouse.click(200, 700); // 进入正文末尾
await page.waitForTimeout(600);
await page.keyboard.type('/');
await page.waitForTimeout(900);
await page.screenshot({ path: '/tmp/audit-web-slash.png' });
await browser.close();
