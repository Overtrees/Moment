import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 160)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
await page.touchscreen.tap(210, 435); // 周末看展记录
await page.waitForTimeout(3000);
await page.touchscreen.tap(400, 365); // 末段行尾
await page.waitForTimeout(600);
await page.keyboard.press('Enter');
await page.waitForTimeout(400);
await page.keyboard.type('相关：[[装修踩坑清单]]');
await page.waitForTimeout(2600); // 等自动保存落库
await page.touchscreen.tap(39, 30); // 返回
await page.waitForTimeout(1800);
await page.touchscreen.tap(210, 320); // 装修踩坑清单
await page.waitForTimeout(3000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/16-backlinks.png' });
// 点反链行（待办区下方：表头后第一行）
await page.touchscreen.tap(210, 426);
await page.waitForTimeout(2500);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/17-backlink-open.png' });
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-8); } catch { return ['?']; } });
console.log('DIAG:', JSON.stringify(diag, null, 0));
await browser.close();
