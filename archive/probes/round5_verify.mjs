// 本轮验证：列表几何 / 设置 / 备份 / 编辑器块与坞 / 卡片按压 / 宽屏 flow 双栏
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round4';
fs.mkdirSync(OUT, { recursive: true });
const BASE = 'http://127.0.0.1:8095/';

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

// ---------- 窄屏主线 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/01-list.png' });

  // 设置页（头像约 52,84）
  await page.touchscreen.tap(52, 84);
  await page.waitForTimeout(1800);
  await page.screenshot({ path: OUT + '/02-settings.png' });

  // 备份页（行位置先截图后按 02 校准；暂用 245）
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(1800);
  await page.screenshot({ path: OUT + '/03-backup.png' });

  // 回列表
  await page.touchscreen.tap(32, 40);
  await page.waitForTimeout(1200);
  await page.touchscreen.tap(32, 40);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: OUT + '/04-list2.png' });
  fs.writeFileSync(OUT + '/list-diag.txt', await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || ''));
  await ctx.close();
}

// ---------- 编辑器 + 按压 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/05-list-for-editor.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
