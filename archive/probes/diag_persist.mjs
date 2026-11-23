import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ctx = await chromium.launchPersistentContext('/tmp/mynote-profile', { executablePath: exe, viewport: { width: 420, height: 900 } });
const page = ctx.pages()[0] ?? await ctx.newPage();
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200); // 打开备忘产生 EDITOR 日志
await page.waitForTimeout(2500);
await page.reload({ waitUntil: 'networkidle' }); // 模拟崩溃后重进
await page.waitForTimeout(5000);
await page.mouse.click(330, 42);
await page.waitForTimeout(1200);
await page.mouse.click(200, 140);
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/diag-persist.png' });
await ctx.close();
