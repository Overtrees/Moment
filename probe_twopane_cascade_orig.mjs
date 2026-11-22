// 双栏级联量测（原版）：双栏开启时 body/spread/column 计算盒
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = 'http://localhost:8199/Moment.html';
const SENT = '这是一个用于量测分栏分布的均匀段落，文字长度在各段之间保持一致。';
const memo = {
  id: 'tpdist1', title: '分栏量测长文', pinned: false,
  createdAt: '2026-11-22T02:00:00.000Z', updatedAt: '2026-11-22T02:00:00.000Z',
  doc: Array.from({ length: 30 }, (_, i) => ({ id: 'tp' + (i + 1), type: 'paragraph', children: [{ text: `第${String(i + 1).padStart(2, '0')}段 ${SENT}` }] })),
};
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
await page.goto(ORIG, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(async (m) => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('MemosDB', 8); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => { const tx = db.transaction('memos', 'readwrite'); tx.objectStore('memos').put(m); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
}, memo);
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(900);
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes('分栏量测长文'));
  if (el) el.click();
});
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1300);
await page.click('.editor-fab.right');
await page.waitForTimeout(600);
await page.evaluate(() => document.querySelector('.editor-column-mode-toggle')?.click());
await page.waitForTimeout(1000);
const m = await page.evaluate(() => {
  const R = (n) => Math.round(n * 100) / 100;
  const body = document.querySelector('.editor-body');
  const spread = body.closest('.editor-spread') || body.parentElement;
  const cs = getComputedStyle(body);
  const scs = getComputedStyle(spread);
  const col = body.querySelector('.editor-column');
  const ccs = getComputedStyle(col);
  const chain = [];
  let el = body;
  while (el && chain.length < 5) {
    const r = el.getBoundingClientRect();
    chain.push({ cls: el.className.slice(0, 44), w: R(r.width), x: R(r.x) });
    el = el.parentElement;
  }
  return {
    bodyPad: cs.padding, bodyGap: cs.columnGap + '/' + cs.gap, bodyDisplay: cs.display,
    bodyCols: cs.gridTemplateColumns, bodyW: body.clientWidth, bodyCls: body.className,
    spreadPad: scs.padding, spreadW: spread.clientWidth, spreadCls: spread.className.slice(0, 44),
    colW: col.clientWidth, colPad: ccs.padding,
    chain,
  };
});
console.log(JSON.stringify(m, null, 1));
await browser.close();
console.log('CASCADE ORIG DONE');
