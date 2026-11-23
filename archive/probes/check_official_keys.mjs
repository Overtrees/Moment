// 键盘滚动对照：点列表空白聚焦后 ArrowDown/PageDown 驱动内部 ListView
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const url = process.argv[2] || 'http://localhost:8095/';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(12000);
await page.touchscreen.tap(210, 262); // 卡片间空隙：聚焦列表，不触发打开
await page.waitForTimeout(600);
for (let i = 0; i < 6; i++) { await page.keyboard.press('ArrowDown'); await page.waitForTimeout(120); }
await page.keyboard.press('PageDown');
await page.waitForTimeout(1000);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/15-keys.png' });
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').filter(s => s.includes('compact')); } catch { return ['n/a']; } });
console.log('compact events:', JSON.stringify(diag));
console.log('pageerrors:', JSON.stringify(errors.slice(0, 5)));
await browser.close();
