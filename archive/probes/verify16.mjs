import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 140)));
const shot = (n) => page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/' + n });
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
// —— F7 设置行按压：按住备份与恢复行 ——
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(1500);
await page.mouse.move(210, 322);
await page.mouse.down();
await page.waitForTimeout(280);
await shot('39-settings-press.png'); // 高亮应为内缩圆角矩形
await page.mouse.up();
await page.waitForTimeout(1500);
// —— F4 备份 sheet 即时呈现 ——
await page.touchscreen.tap(210, 322); // 导出备份
await page.waitForTimeout(140);
await shot('40-sheet-instant.png'); // 140ms 时应已完整呈现（无滑入中途态）
await page.touchscreen.tap(210, 150); // 点外关闭
await page.waitForTimeout(500);
await shot('41-sheet-gone.png');
// —— 回列表进编辑器，调 slash 面板 ——
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(1200);
await page.touchscreen.tap(39, 30);
await page.waitForTimeout(1200);
await page.touchscreen.tap(210, 479); // 周末看展记录（新间距后约位）
await page.waitForTimeout(2500);
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').slice(-4); } catch (e) { return ['ERR']; } });
console.log('DIAG:', JSON.stringify(diag).slice(0, 300));
await page.touchscreen.tap(150, 700);
await page.waitForTimeout(600);
await page.keyboard.press('End');
await page.keyboard.press('Enter');
await page.keyboard.type('/');
await page.waitForTimeout(900);
await shot('42-slash.png');
await browser.close();
