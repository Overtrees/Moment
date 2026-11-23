// 导出面板 + 宽屏 flow 双栏（窄屏打开音乐笔记后放大视口触发重建）
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round4';
const BASE = 'http://127.0.0.1:8095/';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(210, 320); // 装修
  await page.waitForTimeout(3000);
  await page.touchscreen.tap(381, 30); // •••
  await page.waitForTimeout(900);
  await page.touchscreen.tap(270, 285); // 导出笔记行
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/25-export.png' });
  await ctx.close();
}

{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(210, 815); // 最近在听的歌
  await page.waitForTimeout(3500);
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.waitForTimeout(2500);
  await page.screenshot({ path: OUT + '/32-wide-flow.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
