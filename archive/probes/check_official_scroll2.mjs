// 滚动回顶疑点定位：单次拖动后立即/延迟双采样 Diag compact 事件与画面
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const url = process.argv[2] || 'http://localhost:8095/';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(12000);
const cdp = await ctx.newCDPSession(page);
async function dragUp(x, y1, y2, steps = 14) {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: y1, id: 1 }] });
  for (let i = 1; i <= steps; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y1 + (y2 - y1) * (i / steps), id: 1 }] });
    await page.waitForTimeout(28);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}
const compactEvents = async () => await page.evaluate(() => {
  try {
    const d = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
    return d.filter(s => s.includes('compact'));
  } catch { return ['n/a']; }
});
await dragUp(210, 720, 260);
await page.waitForTimeout(200);
console.log('t+200ms compact events:', JSON.stringify(await compactEvents()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/06-scroll-a.png' });
await page.waitForTimeout(1800);
console.log('t+2000ms compact events:', JSON.stringify(await compactEvents()));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/07-scroll-b.png' });
console.log('pageerrors:', JSON.stringify(errors.slice(0, 5)));
await browser.close();
