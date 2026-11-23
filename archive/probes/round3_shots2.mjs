import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

// 1280：装修笔记 → 菜单 → 打开双栏开关 → 双栏视图
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(190, 560); // 置顶：装修踩坑清单
  await page.waitForTimeout(3000);
  await page.screenshot({ path: OUT + '/fl-wide-editor2.png' });
  await page.touchscreen.tap(1248, 40);
  await page.waitForTimeout(1200);
  // 开关在菜单首行右侧
  await page.touchscreen.tap(1215, 128);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: OUT + '/fl-wide-menu-on.png' });
  // 点空白关菜单看双栏
  await page.touchscreen.tap(400, 600);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/fl-wide-twopane.png' });
  await ctx.close();
}

// 900×420 横屏：新建笔记 → 菜单（不应有双栏行）
{
  const ctx = await browser.newContext({ viewport: { width: 900, height: 420 }, hasTouch: true, isMobile: false, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(180, 240); // 新建卡
  await page.waitForTimeout(3000);
  await page.touchscreen.tap(868, 40);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: OUT + '/fl-land-menu2.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
