import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round6';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 200)));
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(9000);
// 打开「最近在听的歌」
await page.touchscreen.tap(210, 815);
await page.waitForTimeout(3500);
await page.screenshot({ path: OUT + '/03-music.png' });
console.log('music shot done');
// 点第一张卡片右缘区（>85% 宽）：应在卡后插入空段
await page.touchscreen.tap(395, 288);
await page.waitForTimeout(1500);
await page.screenshot({ path: OUT + '/04-rightzone.png' });
const diag = await page.evaluate(() => { try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-800); } catch (e) { return 'ERR'; } });
console.log('DIAG-TAIL:', diag);
await browser.close();
