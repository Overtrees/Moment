// 探针：无拖柄回归——iOS 桌面式长按拾起重构后，DOM 中
// 不得再生成 .blk-drag-handle（挂载后、点按聚焦后、桌面
// 悬停后各查），Diag 不得再有 drag handle 行（op 已改名
// drag）。前身为拖柄遮字量测探针，契约随重构更新。
import { chromium } from 'playwright-core';
const url = process.argv[2] || 'http://localhost:8411/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const handleCount = (page) => page.evaluate(() => document.querySelectorAll('.blk-drag-handle').length);

// ---------- 触屏：新建空备忘 ----------
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(() => {
  const card = [...document.querySelectorAll('.list-item')].find((e) => (e.querySelector('.item-title-text')?.textContent || '').includes('新建笔记'));
  (card || document.querySelector('.list-item'))?.click();
});
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1800);
ok('触屏新建备忘挂载后无拖柄元素', (await handleCount(page)) === 0);
// 点按首段（聚焦）后仍不得有拖柄元素
const pt = await page.evaluate(() => {
  const u = document.querySelector('.editor-body [data-bid]');
  const r = u.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
});
const cdp = await ctx.newCDPSession(page);
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: pt.x, y: pt.y, id: 1 }] });
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await page.waitForTimeout(800);
ok('触屏点按聚焦后无拖柄元素', (await handleCount(page)) === 0);
const diag = await page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || ''));
ok('Diag 无 drag handle 行', !diag.includes('drag handle'));
await ctx.close();

// ---------- 桌面：hover ----------
const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const p2 = await ctx2.newPage();
p2.on('pageerror', (e) => L('PAGEERROR(d)', String(e).slice(0, 200)));
await p2.goto(url, { waitUntil: 'load' });
await p2.waitForSelector('.list-item', { timeout: 20000 });
await p2.evaluate(() => {
  const card = [...document.querySelectorAll('.list-item')].find((e) => (e.querySelector('.item-title-text')?.textContent || '').trim() === '周末看展记录');
  card?.click();
});
await p2.waitForSelector('.editor-body', { timeout: 10000 });
await p2.waitForFunction(() => document.querySelectorAll('.editor-body [data-bid]').length > 0, null, { timeout: 10000 });
await p2.waitForTimeout(1200);
ok('桌面挂载后无拖柄元素', (await handleCount(p2)) === 0);
const um = await p2.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const firstUnit = (parent) => {
    for (const c of parent.children) {
      if (c.classList.contains('editor-column')) { const r = firstUnit(c); if (r) return r; continue; }
      return c;
    }
    return null;
  };
  const u = firstUnit(body);
  const r = u.getBoundingClientRect();
  return { cx: r.left + r.width / 2, cy: r.top + r.height / 2 };
});
await p2.mouse.move(um.cx, um.cy);
await p2.waitForTimeout(500);
ok('桌面悬停后无拖柄元素', (await handleCount(p2)) === 0);
await ctx2.close();
await browser.close();
L(fails === 0 ? 'NO-HANDLE ALL PASS' : `NO-HANDLE ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
