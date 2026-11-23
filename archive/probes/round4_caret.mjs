import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, serviceWorkers: 'block' });
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
await page.waitForTimeout(6000);
await page.mouse.click(210, 695);
await page.waitForTimeout(3500);
// 点进正文首段放光标
await page.mouse.click(210, 235);
await page.waitForTimeout(800);
// 光标一路向下：视图应跟随光标滚动，从而触发坞的横排形态
for (let i = 0; i < 45; i++) { await page.keyboard.press('ArrowDown'); await page.waitForTimeout(30); }
await page.waitForTimeout(1000);
await page.screenshot({ path: OUT + '/r4-music-caret-scroll.png' });
await browser.close();
console.log('done');
