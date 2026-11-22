// 双栏级联量测：Rust 双栏开启时 body/spread/column 的计算盒
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = process.argv[2] || 'http://localhost:8197/';
const SENT = '这是一个用于量测分栏分布的均匀段落，文字长度在各段之间保持一致。';
const memo = {
  id: 'tpdist1', title: '分栏量测长文', pinned: false,
  createdAt: '2026-11-22T02:00:00.000Z', updatedAt: '2026-11-22T02:00:00.000Z',
  doc: Array.from({ length: 30 }, (_, i) => ({ id: 'tp' + (i + 1), type: 'paragraph', children: [{ text: `第${String(i + 1).padStart(2, '0')}段 ${SENT}` }] })),
};
const payload = { version: 2, exportedAt: '2026-11-22T02:00:00.000Z', memos: [memo], avatars: {} };
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto(RUST, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(async ({ mj, mf }) => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => { const tx = db.transaction('kv', 'readwrite'); tx.objectStore('kv').put(mj, 'memos_json'); tx.objectStore('kv').put(mf, 'manifest_raw'); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
}, { mj: JSON.stringify(payload), mf: JSON.stringify({ version: 1, attachments: {} }) });
await page.reload({ waitUntil: 'load' });
await page.waitForFunction(() => document.body.innerText.includes('分栏量测长文'), { timeout: 15000 });
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item .item-title-text')].find((e) => e.textContent.includes('分栏量测长文'));
  el.click();
});
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1300);
await page.evaluate(() => document.querySelector('.editor-fab.right')?.click());
await page.waitForTimeout(500);
await page.evaluate(() => document.querySelector('.twopane-row')?.click());
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
    bodyCols: cs.gridTemplateColumns, bodyW: body.clientWidth,
    spreadPad: scs.padding, spreadW: spread.clientWidth, spreadCls: spread.className.slice(0, 44),
    colW: col.clientWidth, colPad: ccs.padding,
    chain,
  };
});
console.log(JSON.stringify(m, null, 1));
await browser.close();
console.log('CASCADE DONE');
