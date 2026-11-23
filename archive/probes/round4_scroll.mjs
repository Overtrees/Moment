import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
// 关键：不用触摸/移动端仿真——之前 wheel 被吞很可能就是 isMobile/hasTouch 造成的
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
await page.waitForTimeout(6000);
await page.mouse.move(210, 500);
for (let i = 0; i < 5; i++) { await page.mouse.wheel(0, 350); await page.waitForTimeout(150); }
await page.waitForTimeout(600);
await page.screenshot({ path: OUT + '/r4-list-wheel.png' });
await page.mouse.click(210, 695);
await page.waitForTimeout(3500);
await page.screenshot({ path: OUT + '/r4-music-top3.png' });
await page.mouse.move(210, 500);
for (let i = 0; i < 5; i++) { await page.mouse.wheel(0, 350); await page.waitForTimeout(150); }
await page.waitForTimeout(900);
await page.screenshot({ path: OUT + '/r4-music-scrolled3.png' });
await browser.close();
console.log('done');
