import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round6';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 250)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
await page.touchscreen.tap(210, 815); // 最近在听的歌
await page.waitForTimeout(3500);
// 点第一段正文（标题下方 She Her Her Hers…，约 y=235）
await page.touchscreen.tap(200, 235);
await page.waitForTimeout(800);
await page.keyboard.type('ZZ');
await page.waitForTimeout(1000);
await page.screenshot({ path: OUT + '/09-type-para.png' });
const diag = await page.evaluate(() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-500); } catch (e) { return 'ERR'; } });
console.log('DIAG:', diag);
await browser.close();
