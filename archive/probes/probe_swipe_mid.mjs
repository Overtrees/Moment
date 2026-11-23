// 半开中间态（拖至 -84 保持）：两按钮底色/几何量测 + 截图（Rust 新构建）
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8118/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
for (const scheme of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: scheme });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR:', String(e)));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 25000 });
  await page.waitForTimeout(900);
  const box = await page.evaluate(() => {
    const w = [...document.querySelectorAll('.swipe-wrapper')].find((e) => e.querySelector('.swipe-actions'));
    const row = w.querySelector('.list-item, .img-card');
    const r = row.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height, cy: r.y + r.height / 2 };
  });
  const cdp = await ctx.newCDPSession(page);
  const sx = 330;
  const send = (type, x) => cdp.send('Input.dispatchTouchEvent', {
    type, touchPoints: type === 'touchEnd' ? [] : [{ x: Math.round(x), y: Math.round(box.cy), id: 1 }],
  });
  await send('touchStart', sx);
  for (let i = 1; i <= 10; i++) { await send('touchMove', sx - (84 * i) / 10); await page.waitForTimeout(20); }
  await page.waitForTimeout(350); // 等按钮 CSS 弹簧过渡收敛到目标值附近
  const mid = await page.evaluate(() => {
    const w = [...document.querySelectorAll('.swipe-wrapper')].find((e) => e.querySelector('.swipe-actions'));
    const row = w.querySelector('.list-item, .img-card');
    return {
      rowTransform: getComputedStyle(row).transform,
      btns: [...w.querySelectorAll('.swipe-action-btn')].map((b) => {
        const cs = getComputedStyle(b);
        const r = b.getBoundingClientRect();
        return { bg: cs.backgroundColor, opacity: cs.opacity, transform: cs.transform, rect: { x: +r.x.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }, inline: b.getAttribute('style'), cls: b.className };
      }),
    };
  });
  console.log(scheme, JSON.stringify(mid, null, 1));
  await page.screenshot({ path: `/tmp/swipe-mid-${scheme}.png`, clip: { x: Math.max(0, box.x - 4), y: Math.max(0, box.y - 6), width: Math.min(393, box.w + 8), height: box.h + 12 } });
  await send('touchEnd', 0);
  await ctx.close();
}
await browser.close();
