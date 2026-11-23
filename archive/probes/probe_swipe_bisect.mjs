// 左滑删除钮 style 被重写的时刻二分：MutationObserver 记录每次 style 变更
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8116/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 25000 });
await page.waitForTimeout(1000);

await page.evaluate(() => {
  window.__log = [];
  const t0 = performance.now();
  const wrappers = [...document.querySelectorAll('.swipe-wrapper')].filter((e) => e.querySelector('.swipe-actions'));
  window.__target = wrappers[0];
  const btns = window.__target.querySelectorAll('.swipe-action-btn');
  const row = window.__target.querySelector('.list-item, .img-card');
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      const el = m.target;
      const who = el === row ? 'ROW' : el === btns[0] ? 'PIN' : el === btns[1] ? 'DEL' : 'OTHER';
      window.__log.push({ t: Math.round(performance.now() - t0), who, style: el.getAttribute('style') });
    }
  });
  [row, btns[0], btns[1]].forEach((el) => obs.observe(el, { attributes: true, attributeFilter: ['style'] }));
  window.__rowEl = row;
});

const box = await page.evaluate(() => {
  const r = window.__rowEl.getBoundingClientRect();
  return { x: r.x, w: r.width, cy: r.y + r.height / 2 };
});
const cdp = await ctx.newCDPSession(page);
const sx = Math.min(box.x + box.w - 40, 340);
const send = (type, x) => cdp.send('Input.dispatchTouchEvent', {
  type, touchPoints: type === 'touchEnd' ? [] : [{ x: Math.round(x), y: Math.round(box.cy), id: 1 }],
});
console.log('--- touchStart');
await send('touchStart', sx);
for (let i = 1; i <= 14; i++) { await send('touchMove', sx - (180 * i) / 14); await page.waitForTimeout(16); }
console.log('--- drag done (still touching), log so far:');
console.log(JSON.stringify(await page.evaluate(() => window.__log), null, 0));
await page.evaluate(() => { window.__log = []; });
await send('touchEnd', 0);
await page.waitForTimeout(80);
console.log('--- 80ms after touchEnd:');
console.log(JSON.stringify(await page.evaluate(() => window.__log), null, 0));
await page.waitForTimeout(600);
console.log('--- later (+680ms):');
console.log(JSON.stringify(await page.evaluate(() => window.__log), null, 0));
console.log('activeElement:', await page.evaluate(() => document.activeElement && (document.activeElement.className || document.activeElement.tagName)));
await browser.close();
