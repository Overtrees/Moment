import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 160)));
const shot = (n) => page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/' + n });
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
await page.touchscreen.tap(52, 84); // 头像 → 设置
await page.waitForTimeout(120); // 转场中途
await shot('28-settings-mid.png');
await page.waitForTimeout(1200);
await shot('29-settings.png');
// 设置 → 备份
await page.touchscreen.tap(210, 322);
await page.waitForTimeout(1500);
await shot('30-backup.png');
// 备份返回（按下即触发）
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(1500);
await shot('31-settings-again.png');
// 设置返回 → 列表（重播入场后应静止正常）
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(1500);
await shot('32-list-again.png');
// 列表 → 编辑 → 返回
await page.touchscreen.tap(210, 320);
await page.waitForTimeout(2500);
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(1500);
await shot('33-list-after-editor.png');
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').map(e => String(e)).slice(-6); } catch { return ['?']; } });
console.log('DIAG:', JSON.stringify(diag, null, 0));
await browser.close();
