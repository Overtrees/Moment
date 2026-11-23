import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function ctxDark(w = 420, h = 900) {
  return browser.newContext({ viewport: { width: w, height: h }, hasTouch: true, isMobile: w < 768, colorScheme: 'dark' });
}

// Flutter 深色全表面
{
  const ctx = await ctxDark();
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[fl pageerror]', String(e).slice(0, 140)));
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/fl-dark-list.png' });
  // 搜索展开态
  await page.touchscreen.tap(770 / 2.057, 105 / 2.057 * 1); // 占位，下面用固定坐标
  await page.screenshot({ path: OUT + '/fl-dark-list2.png' });
  // 编辑器
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/fl-dark-editor.png' });
  // 菜单面板
  await page.touchscreen.tap(388, 40);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/fl-dark-menu.png' });
  await page.touchscreen.tap(60, 500);
  await page.waitForTimeout(800);
  // 返回 → 设置
  await page.touchscreen.tap(40, 40);
  await page.waitForTimeout(2000);
  await page.touchscreen.tap(80, 55);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: OUT + '/fl-dark-settings.png' });
  // 备份页
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: OUT + '/fl-dark-backup.png' });
  await ctx.close();
}

// Flutter 深色：斜杠面板（新建笔记）
{
  const ctx = await ctxDark();
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(210, 130);
  await page.waitForTimeout(2500);
  await page.keyboard.type('/todo');
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/fl-dark-slash.png' });
  await ctx.close();
}

// Flutter 深色宽屏
{
  const ctx = await ctxDark(1280, 800);
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/fl-dark-wide.png' });
  await ctx.close();
}

// 原版深色：列表 + 编辑器 + 菜单
{
  const ctx = await ctxDark();
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8096/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/web-dark-list.png' });
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/web-dark-editor.png' });
  await page.touchscreen.tap(388, 40);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/web-dark-menu.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
