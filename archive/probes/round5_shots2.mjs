// 第二轮截图：备份页 / 编辑器块（装修） / 菜单 / 导出面板 / 斜杠面板 / 宽屏
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round4';
const BASE = 'http://127.0.0.1:8095/';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

// ---------- 备份页 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(52, 84);
  await page.waitForTimeout(1500);
  await page.touchscreen.tap(210, 328);
  await page.waitForTimeout(2000);
  await page.screenshot({ path: OUT + '/20-backup.png' });
  await ctx.close();
}

// ---------- 编辑器块 + 菜单 + 导出 + 斜杠 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  // 装修踩坑清单（列表约 y=320）
  await page.touchscreen.tap(210, 320);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/21-editor-blocks.png' });
  // ••• 菜单
  await page.touchscreen.tap(381, 30);
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/22-menu.png' });
  // 导出行（菜单内，估算 y≈ 30+59+7+ 4*54 ≈ 330；先截图校准，点导出行中心）
  await page.touchscreen.tap(270, 337);
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/23-export.png' });
  await page.keyboard.press('Escape');
  await page.touchscreen.tap(60, 500);
  await page.waitForTimeout(600);
  // 回到正文末尾输入斜杠：点正文区聚焦后键入 /
  await page.touchscreen.tap(210, 500);
  await page.waitForTimeout(600);
  await page.keyboard.type('/');
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/24-slash.png' });
  const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1'));
  fs.writeFileSync(OUT + '/editor-diag.txt', diag || '');
  await ctx.close();
}

// ---------- 宽屏：列表 + flow 双栏 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: false, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/30-wide-list.png' });
  await page.mouse.click(300, 320);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/31-wide-editor.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
