import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const OUT = process.env.HOME + '/workspace/mynote-shots-round3';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function dragUp(page, x, y, dist = 420) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
  const steps = 12;
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y - (dist * i) / steps, id: 1 }] });
    await page.waitForTimeout(16);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

// Flutter：音乐笔记 未滚动 + 滚动后坞形态
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  // 最近在听的歌 = 过去30天分组卡片，滚动列表一点再点
  await dragUp(page, 210, 600, 300);
  await page.waitForTimeout(800);
  await page.screenshot({ path: OUT + '/r4-list-scrolled.png' });
  await page.touchscreen.tap(210, 700);
  await page.waitForTimeout(3500);
  await page.screenshot({ path: OUT + '/r4-music-top.png' });
  await dragUp(page, 210, 600, 380);
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/r4-music-scrolled.png' });
  await ctx.close();
}

// 原版：同一笔记 未滚动 + 滚动后
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8096/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await dragUp(page, 210, 600, 300);
  await page.waitForTimeout(800);
  await page.touchscreen.tap(210, 700);
  await page.waitForTimeout(3500);
  await page.screenshot({ path: OUT + '/r4-web-music-top.png' });
  await dragUp(page, 210, 600, 380);
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/r4-web-music-scrolled.png' });
  await ctx.close();
}

await browser.close();
console.log('done');
