import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR:', String(e).slice(0, 140)));
const shot = (n) => page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round6/' + n });
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(11000);
// —— F2 横滑：装修卡（约 y=320）左滑 ——
await page.mouse.move(210, 330);
await page.mouse.down();
await page.mouse.move(150, 330, { steps: 4 });
await page.waitForTimeout(120);
await shot('36-swipe-mid.png'); // 起手 60px 应已跟手
await page.mouse.move(95, 330, { steps: 4 });
await page.mouse.up();
await page.waitForTimeout(600);
await shot('37-swipe-open.png'); // 过阈值 → 吸附打开
// 点卡身关闭
await page.touchscreen.tap(150, 330);
await page.waitForTimeout(600);
// —— F4 sheet 即时呈现：设置 → 备份 → 导出 ——
await page.touchscreen.tap(52, 84);
await page.waitForTimeout(1500);
await page.touchscreen.tap(210, 322);
await page.waitForTimeout(1500);
// 找「导出到本地」按钮：截图定位用固定坐标试探（备份页中部）
await shot('38-backup-page.png');
await browser.close();
