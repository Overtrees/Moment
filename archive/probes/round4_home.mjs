import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

// Flutter 首页：顶部 + 拖动滚动到紧凑态（420x700 保证有滚动余量）
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 700 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/r4-home-top.png' });
  const cdp = await ctx.newCDPSession(page);
  const drag = async (dist) => {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 210, y: 560, id: 1 }] });
    for (let i = 1; i <= 14; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 210, y: 560 - (dist * i) / 14, id: 1 }] });
      await page.waitForTimeout(16);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  };
  await drag(300);
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/r4-home-scrolled.png' });
  await ctx.close();
}

// 原版首页：顶部 + 滚轮滚动到紧凑态
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 700 }, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8096/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/r4-webhome-top.png' });
  await page.mouse.move(210, 400);
  for (let i = 0; i < 4; i++) { await page.mouse.wheel(0, 200); await page.waitForTimeout(150); }
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/r4-webhome-scrolled.png' });
  await ctx.close();
}
await browser.close();
console.log('done');
