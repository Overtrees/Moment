// 双栏列内细节：列宽、列内首块高/行数、块宽对照（承接分布量测）
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = 'http://localhost:8199/Moment.html';
const RUST = 'http://localhost:8197/';
const SENT = '这是一个用于量测分栏分布的均匀段落，文字长度在各段之间保持一致。';
const memo = {
  id: 'tpdist1', title: '分栏量测长文', pinned: false,
  createdAt: '2026-11-22T02:00:00.000Z', updatedAt: '2026-11-22T02:00:00.000Z',
  doc: Array.from({ length: 30 }, (_, i) => ({ id: 'tp' + (i + 1), type: 'paragraph', children: [{ text: `第${String(i + 1).padStart(2, '0')}段 ${SENT}` }] })),
};
const payload = { version: 2, exportedAt: '2026-11-22T02:00:00.000Z', memos: [memo], avatars: {} };
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
function colDetail() {
  const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
  if (cs.length !== 2) return { n: cs.length };
  const det = (c) => {
    const blk = c.querySelector('[data-bid], .blk-p, p');
    const bcs = getComputedStyle(c);
    return {
      clientW: c.clientWidth, clientH: c.clientHeight, scrollH: c.scrollHeight,
      pad: bcs.padding, gap: bcs.gap, display: bcs.display, flexDir: bcs.flexDirection,
      blkW: blk ? Math.round(blk.getBoundingClientRect().width) : null,
      blkH: blk ? Math.round(blk.getBoundingClientRect().height * 100) / 100 : null,
      blkCls: blk ? blk.className.slice(0, 40) : null,
    };
  };
  const body = document.querySelector('.editor-body');
  return { n: 2, bodyW: body.clientWidth, left: det(cs[0]), right: det(cs[1]) };
}
async function openT(page, title) {
  await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes(t));
    if (el) el.click();
  }, title);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1300);
}
{
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
  await openT(page, '分栏量测长文');
  await page.evaluate(() => document.querySelector('.editor-fab.right')?.click());
  await page.waitForTimeout(500);
  await page.evaluate(() => document.querySelector('.twopane-row')?.click());
  await page.waitForTimeout(1000);
  console.log('RUST cols detail', JSON.stringify(await page.evaluate(colDetail), null, 1));
  await ctx.close();
}
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate(async (m) => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open('MemosDB', 8); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    await new Promise((res, rej) => { const tx = db.transaction('memos', 'readwrite'); tx.objectStore('memos').put(m); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
  }, memo);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(900);
  await openT(page, '分栏量测长文');
  await page.click('.editor-fab.right');
  await page.waitForTimeout(600);
  await page.evaluate(() => document.querySelector('.editor-column-mode-toggle')?.click());
  await page.waitForTimeout(1000);
  console.log('ORIG cols detail', JSON.stringify(await page.evaluate(colDetail), null, 1));
  await ctx.close();
}
await browser.close();
console.log('COLS DETAIL DONE');
