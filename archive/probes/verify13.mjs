import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 200)));
await page.goto('http://localhost:8096/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(5000);
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(2000);
await page.touchscreen.tap(210, 322);
await page.waitForTimeout(2500);
const chooserPromise = page.waitForEvent('filechooser', { timeout: 15000 });
await page.touchscreen.tap(210, 405); // 导入备份
const chooser = await chooserPromise;
await chooser.setFiles(process.env.HOME + '/workspace/mynote-zip-acceptance/flutter_export.zip');
await page.waitForTimeout(2500);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/26-orig-confirm.png' });
await browser.close();
