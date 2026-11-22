// 遮罩包含块滚动判别探针（Chromium 口径）：小视口使备份页可滚动，
// 弹窗打开后程序滚动页面——真 viewport-fixed 的 fixed 层 rect
// 不动；被 .page-enter 页面盒包含的 fixed 层 rect 随文档平移。
// 顺带量同页 .editor-fab（同为 fixed、同在 .page-enter 内）。
// 用法：node probe_scrim_scroll.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8221/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 390, height: 560 }, hasTouch: true });
page.on('pageerror', (e) => console.log('pageerror:', String(e)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(() => document.querySelector('h1.page-title').dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForSelector('.set-row', { timeout: 10000 });
await page.evaluate(() => {
  const row = [...document.querySelectorAll('.set-row')].find((r) => r.textContent.includes('备份'));
  row.dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
await page.waitForSelector('.backup-card', { timeout: 10000 });
await page.waitForTimeout(500);

const snap = () => page.evaluate(() => {
  const g = (sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { top: Math.round(r.top * 10) / 10, height: Math.round(r.height * 10) / 10, op: el.offsetParent ? String(el.offsetParent.className || el.offsetParent.tagName) : null };
  };
  return {
    scrollY: window.scrollY, docH: document.scrollingElement.scrollHeight, innerH: window.innerHeight,
    scrim: g('.backup-modal-scrim'), fab: g('.editor-fab.left'),
  };
});

console.log('打开前   ', JSON.stringify(await snap()));
await page.evaluate(() => {
  const row = [...document.querySelectorAll('.backup-row')].find((b) => b.offsetParent !== null && b.textContent.includes('导出'));
  row.dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
await page.waitForSelector('.backup-modal-scrim', { timeout: 10000 });
await page.waitForTimeout(400);
console.log('弹窗@0   ', JSON.stringify(await snap()));
await page.evaluate(() => window.scrollTo(0, 200));
await page.waitForTimeout(300);
const s1 = await snap();
console.log('弹窗@200 ', JSON.stringify(s1));
let fails = 0;
const ok = (cond, name, extra = '') => { console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : '')); if (!cond) fails++; };
ok(s1.scrollY > 0, '页面已滚动', `scrollY=${s1.scrollY}`);
ok(s1.scrim && Math.abs(s1.scrim.top) < 1, '遮罩钉在视口（rect.top≈0）', `top=${s1.scrim && s1.scrim.top}`);
ok(s1.scrim && Math.abs(s1.scrim.height - s1.innerH) < 1, '遮罩高 = 视口高（非页面盒高）', `h=${s1.scrim && s1.scrim.height} innerH=${s1.innerH}`);
ok(s1.scrim && s1.scrim.op === null, '遮罩 offsetParent=null', String(s1.scrim && s1.scrim.op));
ok(s1.fab && Math.abs(s1.fab.top - 7) < 1, '返回钮钉在视口（rect.top≈7）', `top=${s1.fab && s1.fab.top}`);
console.log(fails === 0 ? 'PROBE PASS' : `PROBE FAIL x${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
