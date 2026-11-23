import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round6';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 200)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
await page.touchscreen.tap(210, 320); // 装修踩坑清单
await page.waitForTimeout(3500);
// 点第一个待办中间（厨房插座至少留6个…，约 y=176）
await page.touchscreen.tap(220, 176);
await page.waitForTimeout(800);
await page.keyboard.press('Enter');
await page.waitForTimeout(600);
await page.keyboard.type('XYZ新段落');
await page.waitForTimeout(1200);
await page.screenshot({ path: OUT + '/08-enter-todo.png' });
const diag = await page.evaluate(() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-400); } catch (e) { return 'ERR'; } });
console.log('DIAG:', diag);
await browser.close();
