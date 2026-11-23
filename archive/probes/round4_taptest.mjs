import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
const page = await ctx.newPage();
const navs = [];
page.on('framenavigated', f => { if (f === page.mainFrame()) navs.push(f.url()); });
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
await page.waitForTimeout(6000);
await page.touchscreen.tap(210, 695); // 最近在听的歌
await page.waitForTimeout(3500);
// 点第一张链接卡（c6.y.qq.com 卡身中央）
await page.touchscreen.tap(210, 288);
await page.waitForTimeout(1800);
await page.screenshot({ path: OUT + '/r4-tap-linkcard.png' });
console.log('navs:', JSON.stringify(navs));
await browser.close();
