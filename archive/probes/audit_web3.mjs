import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8096/Moment.html', { waitUntil: 'networkidle' });
await page.waitForTimeout(3500);
await page.mouse.click(52, 72); // 头像 → 设置
await page.waitForTimeout(1500);
await page.screenshot({ path: '/tmp/audit-web-settings.png' });
await browser.close();
