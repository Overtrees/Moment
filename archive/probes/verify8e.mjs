import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round6';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
await page.touchscreen.tap(210, 320);
await page.waitForTimeout(3500);
// 点第三个待办的勾选框（约 x=45, y=290）
await page.touchscreen.tap(45, 290);
await page.waitForTimeout(1000);
await page.screenshot({ path: OUT + '/10-checkbox.png' });
const diag = await page.evaluate(() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-300); } catch (e) { return 'ERR'; } });
console.log('DIAG:', diag);
await browser.close();
