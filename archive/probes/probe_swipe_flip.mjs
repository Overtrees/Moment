// 开启态翻转方案：行/按钮节点身份与状态存活检查（Rust）
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

// 合成指针事件滑开第一行（与冒烟同通路）
await page.evaluate(() => {
  const w = [...document.querySelectorAll('.swipe-wrapper')].find((e) => e.querySelector('.swipe-actions'));
  const row = w.querySelector('.list-item, .img-card');
  const opts = (x, y) => ({ bubbles: true, cancelable: true, pointerId: 7, clientX: x, clientY: y, isPrimary: true });
  row.dispatchEvent(new PointerEvent('pointerdown', opts(300, 400)));
  row.dispatchEvent(new PointerEvent('pointermove', opts(200, 400)));
  row.dispatchEvent(new PointerEvent('pointermove', opts(120, 400)));
  row.dispatchEvent(new PointerEvent('pointerup', opts(120, 400)));
  window.__w = w; window.__row = row;
  window.__trig = document.querySelector('.glass-search-trigger');
  if (window.__trig) window.__trig.__mark = 'trig';
  window.__ava = document.querySelector('h1.page-title > *');
  if (window.__ava) window.__ava.__mark = 'ava';
  row.__mark = 'row-alive'; w.__mark = 'wrap-alive';
  w.querySelectorAll('.swipe-action-btn').forEach((b, i) => { b.__mark = 'btn' + i; });
});
await page.waitForTimeout(500);
console.log('before flip:', await page.evaluate(() => ({
  rowTransform: getComputedStyle(window.__row).transform,
  sameRow: document.contains(window.__row),
})));
await page.emulateMedia({ colorScheme: 'dark' });
await page.waitForTimeout(800);
console.log('after flip:', await page.evaluate(() => {
  const w = [...document.querySelectorAll('.swipe-wrapper')].find((e) => e.querySelector('.swipe-actions'));
  const row = w.querySelector('.list-item, .img-card');
  const btns = w.querySelectorAll('.swipe-action-btn');
  return {
    sameWrapper: w === window.__w, sameRow: row === window.__row,
    rowMark: row.__mark || null, btnMarks: [...btns].map((b) => b.__mark || null),
    rowTransform: getComputedStyle(row).transform,
    btnStyles: [...btns].map((b) => b.getAttribute('style')),
    trigSame: document.querySelector('.glass-search-trigger') === window.__trig,
    avaSame: document.querySelector('h1.page-title > *') === window.__ava,
    trigBg: (() => { const t = document.querySelector('.glass-search-trigger'); return t ? getComputedStyle(t).backgroundColor + '|' + getComputedStyle(t).backdropFilter : 'absent'; })(),
    diag: (localStorage.getItem('mynote_diag_v1') || '').slice(-400),
  };
}));
await browser.close();
