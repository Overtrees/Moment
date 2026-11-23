// E组实测三轮：两边编辑器重开时间 + Flutter 列表触摸滚动帧时间
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function instrument(page) {
  await page.evaluate(() => {
    window.__frames = [];
    let last = performance.now();
    const loop = (t) => { window.__frames.push(+(t - last).toFixed(1)); last = t; if (window.__frames.length < 4000) requestAnimationFrame(loop); };
    requestAnimationFrame(loop);
  });
}
async function frameStats(page) {
  return page.evaluate(() => {
    const f = window.__frames.filter((x) => x > 0 && x < 1000);
    const s = [...f].sort((a, b) => a - b);
    return { frames: f.length, mean: +(f.reduce((a, b) => a + b, 0) / f.length).toFixed(1), p95: s[Math.floor(s.length * 0.95)], over50ms: f.filter((x) => x > 50).length };
  });
}
async function tapUntilChange(page, x, y) {
  const before = await page.screenshot();
  const t0 = Date.now();
  await page.touchscreen.tap(x, y);
  while (Date.now() - t0 < 12000) {
    const shot = await page.screenshot();
    if (Buffer.compare(shot, before) !== 0) return Date.now() - t0;
    await page.waitForTimeout(40);
  }
  return null;
}

// Flutter：进编辑器 → 返回 → 重开计时；列表滚动帧
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8096/', { waitUntil: 'load' });
  await page.waitForTimeout(7000);
  await page.touchscreen.tap(210, 320);
  await page.waitForTimeout(3000);
  await page.touchscreen.tap(32, 40); // 返回
  await page.waitForTimeout(1500);
  console.log('FL_EDITOR_REOPEN_MS', await tapUntilChange(page, 210, 320));
  await page.waitForTimeout(1500);
  await page.touchscreen.tap(32, 40);
  await page.waitForTimeout(1500);
  // 列表触摸滚动（CDP touch drag ×6）
  await instrument(page);
  const cdp = await ctx.newCDPSession(page);
  for (let i = 0; i < 6; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 210, y: 700, id: 1 }] });
    for (let s = 1; s <= 5; s++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 210, y: 700 - s * 60, id: 1 }] });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForTimeout(120);
  }
  await page.waitForTimeout(600);
  console.log('FL_LIST_SCROLL', JSON.stringify(await frameStats(page)));
  await ctx.close();
}

// 原版：新建 → 返回 → 重开计时
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8097/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(2000);
  // 返回按钮位置试探：左上角
  await page.touchscreen.tap(32, 40);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: '/tmp/orig_back.png' });
  console.log('ORIG_EDITOR_REOPEN_MS', await tapUntilChange(page, 210, 400));
  await ctx.close();
}
await browser.close();
console.log('done');
