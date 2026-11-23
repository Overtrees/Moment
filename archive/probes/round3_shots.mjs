import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function ctxLight(w = 420, h = 900) {
  return browser.newContext({ viewport: { width: w, height: h }, hasTouch: true, isMobile: w < 768, serviceWorkers: 'block' });
}

// 浅色：列表 + 编辑器（新顶栏结构）
{
  const ctx = await ctxLight();
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[fl pageerror]', String(e).slice(0, 140)));
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/fl-light-list.png' });
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/fl-light-editor.png' });
  await ctx.close();
}

// 宽屏 1280：开菜单应出现双栏开关 → 开启 → 双栏（按块高均衡 2/2）
{
  const ctx = await ctxLight(1280, 800);
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(200, 300); // 置顶装修卡（宽屏第一张）
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/fl-wide-editor.png' });
  // ••• 菜单（右上角 fab 约 1248,40）
  await page.touchscreen.tap(1248, 40);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/fl-wide-menu.png' });
  await ctx.close();
}

// 窄屏横屏 900×420：菜单不应出现双栏开关
{
  const ctx = await ctxLight(900, 420);
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(300, 210);
  await page.waitForTimeout(3000);
  await page.touchscreen.tap(868, 40);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/fl-land-menu.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
