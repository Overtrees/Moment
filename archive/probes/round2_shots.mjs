import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = 'http://127.0.0.1:8095/';
const OUT = '/home/hatch/workspace/mynote-shots-round2';
fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

// 1) 深色模式：列表 + 编辑器
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, colorScheme: 'dark' });
  const page = await ctx.newPage();
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/01-dark-list.png' });
  await page.touchscreen.tap(210, 245); // 装修踩坑清单
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/02-dark-editor.png' });
  await ctx.close();
}

// 2) 宽屏网格
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/03-wide-list.png' });
  await ctx.close();
}

// 3) ••• 下拉菜单 + 双栏开关 + 双栏编辑
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 160)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(210, 245); // 装修踩坑清单（4 个待办）
  await page.waitForTimeout(3000);
  await page.touchscreen.tap(388, 40); // •••
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/04-menu.png' });
  // 点双栏开关行（菜单首行，约 y=面板顶+30；面板 top≈59，行中心≈100）
  await page.touchscreen.tap(300, 100);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: OUT + '/05-menu-on.png' });
  await page.touchscreen.tap(60, 500); // 点 backdrop 关菜单
  await page.waitForTimeout(1500);
  await page.screenshot({ path: OUT + '/06-twopane.png' });
  await ctx.close();
}

// 4) Wiki 链接 + 脚注 + Callout 渲染
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 160)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(210, 130); // 新建笔记卡
  await page.waitForTimeout(2500);
  await page.keyboard.type('参考 [[装修踩坑清单]] 这篇，脚注[^1]在此。');
  await page.waitForTimeout(1200);
  await page.keyboard.press('Enter');
  await page.keyboard.type('/callout');
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/07-slash.png' });
  await page.touchscreen.tap(120, 700); // 面板首行附近（截图后校准）
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/08-wiki-callout.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
