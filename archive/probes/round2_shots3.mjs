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
await page.waitForTimeout(1000);
await page.touchscreen.tap(40, 40); // 返回保存
await page.waitForTimeout(2500);
await page.screenshot({ path: OUT + '/20-list.png' });
// 无标题卡片在「今天」组第一张（按上轮截图约 y=330）
await page.touchscreen.tap(210, 360);
await page.waitForTimeout(3000);
await page.screenshot({ path: OUT + '/21-reopened-wiki.png' });
await page.touchscreen.tap(40, 40);
await page.waitForTimeout(2000);
// 置顶的装修踩坑清单（约 y=245）
await page.touchscreen.tap(210, 245);
await page.waitForTimeout(3000);
await page.screenshot({ path: OUT + '/22-backlinks.png' });
await page.touchscreen.tap(200, 855); // 展开反向链接条
await page.waitForTimeout(1200);
await page.screenshot({ path: OUT + '/23-backlinks-open.png' });
await browser.close();
console.log('done');
