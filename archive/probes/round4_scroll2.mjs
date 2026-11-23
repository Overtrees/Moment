import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

// A: 非触摸上下文 + 长文档（装修）+ 滚轮
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.mouse.click(210, 245);
  await page.waitForTimeout(3500);
  await page.screenshot({ path: OUT + '/r4-zx-top.png' });
  await page.mouse.move(210, 500);
  for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 350); await page.waitForTimeout(150); }
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/r4-zx-wheel.png' });
  await ctx.close();
}

// B: 触摸上下文 + 长文档 + CDP 触摸拖动（起点落在待办行间隙）
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(3500);
  const cdp = await ctx.newCDPSession(page);
  const drag = async (x, y, dist) => {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
    for (let i = 1; i <= 14; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y - (dist * i) / 14, id: 1 }] });
      await page.waitForTimeout(16);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  };
  await drag(210, 620, 430);
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/r4-zx-drag.png' });
  await ctx.close();
}
await browser.close();
console.log('done');
