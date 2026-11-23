// 拖动被吃定位：监听 pointercancel/touchcancel + 中途采样 + 鼠标拖动对照
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
await page.evaluate(() => {
  window.__cancels = 0;
  window.__downs = 0;
  addEventListener('pointercancel', () => window.__cancels++, true);
  addEventListener('touchcancel', () => window.__cancels++, true);
  addEventListener('pointerdown', () => window.__downs++, true);
  const fv = document.querySelector('flutter-view');
  window.__touchAction = fv ? getComputedStyle(fv).touchAction : '(none el)';
});
const cdp = await ctx.newCDPSession(page);
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 210, y: 720, id: 1 }] });
for (let i = 1; i <= 14; i++) {
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 210, y: 720 - 460 * (i / 14), id: 1 }] });
  await page.waitForTimeout(28);
  if (i === 7) {
    await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/08-middrag.png' });
    console.log('mid-drag state:', JSON.stringify(await page.evaluate(() => ({ cancels: window.__cancels, downs: window.__downs, ta: window.__touchAction }))));
  }
}
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await page.waitForTimeout(600);
console.log('after touch drag:', JSON.stringify(await page.evaluate(() => ({ cancels: window.__cancels }))));
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/09-after-touchdrag.png' });
// 鼠标拖动对照
await page.mouse.move(210, 720);
await page.mouse.down();
await page.mouse.move(210, 260, { steps: 14 });
await page.waitForTimeout(200);
await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-official/10-mousedrag.png' });
await page.mouse.up();
const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').filter(s => s.includes('compact')); } catch { return ['n/a']; } });
console.log('compact events:', JSON.stringify(diag));
console.log('pageerrors:', JSON.stringify(errors.slice(0, 5)));
await browser.close();
