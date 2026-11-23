import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = 'http://127.0.0.1:8095/';
const OUT = process.env.HOME + '/workspace/mynote-shots-round2';
fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 160)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForTimeout(6000);
await page.touchscreen.tap(210, 130); // 新建笔记
await page.waitForTimeout(2500);
await page.keyboard.type('参考 [[装修踩坑清单]] 这篇，脚注[^1]在此。');
await page.waitForTimeout(800);
await page.keyboard.press('Enter');
await page.keyboard.type('/callout');
await page.waitForTimeout(1200);
await page.touchscreen.tap(150, 838); // Callout 面板行
await page.waitForTimeout(1500);
await page.screenshot({ path: OUT + '/09-callout.png' });
// 返回（触发保存）→ 重开同一条（列表第一条未命名）
await page.touchscreen.tap(40, 40);
await page.waitForTimeout(2500);
await page.screenshot({ path: OUT + '/10-list-after.png' });
await page.touchscreen.tap(210, 190);
await page.waitForTimeout(3000);
await page.screenshot({ path: OUT + '/11-reopened.png' });
// 返回 → 打开装修踩坑清单看反向链接条
await page.touchscreen.tap(40, 40);
await page.waitForTimeout(2000);
await page.touchscreen.tap(210, 300);
await page.waitForTimeout(3000);
await page.screenshot({ path: OUT + '/12-backlinks.png' });
await page.touchscreen.tap(300, 845); // 展开反向链接（条在底部附近）
await page.waitForTimeout(1200);
await page.screenshot({ path: OUT + '/13-backlinks-open.png' });
await browser.close();
console.log('done');
