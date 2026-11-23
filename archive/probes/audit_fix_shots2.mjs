import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = 'http://127.0.0.1:8095/';
const OUT = '/tmp/shots_audit_fix';
fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForTimeout(6000);
// 打开「最近在听的歌」（过去30天组）
await page.touchscreen.tap(210, 695);
await page.waitForTimeout(5000);
await page.screenshot({ path: OUT + '/05-music.png' });
// 返回，再开「装修踩坑清单」看待办圆环
await page.touchscreen.tap(24, 40);
await page.waitForTimeout(1500);
await page.touchscreen.tap(210, 245);
await page.waitForTimeout(3000);
await page.screenshot({ path: OUT + '/06-todo.png' });
await browser.close();
console.log('done');
