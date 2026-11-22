// 双栏成员分布差异量测：同篇 30 段均匀长文，1280×800。
// 两边各量：单栏逐块高（渲染层是否同高）→ 双栏开启后
// 左/右列 scrollHeight、成员数、右列首块序号（分栏算法）。
// 用法：node probe_twopane_distribution.mjs [origBase] [rustBase]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = process.argv[2] || 'http://localhost:8199/Moment.html';
const RUST = process.argv[3] || 'http://localhost:8197/';
const R2 = (n) => Math.round(n * 100) / 100;

const SENT = '这是一个用于量测分栏分布的均匀段落，文字长度在各段之间保持一致。';
const memo = {
  id: 'tpdist1', title: '分栏量测长文', pinned: false,
  createdAt: '2026-11-22T02:00:00.000Z', updatedAt: '2026-11-22T02:00:00.000Z',
  doc: Array.from({ length: 30 }, (_, i) => ({
    id: 'tp' + (i + 1), type: 'paragraph',
    children: [{ text: `第${String(i + 1).padStart(2, '0')}段 ${SENT}` }],
  })),
};
const payload = { version: 2, exportedAt: '2026-11-22T02:00:00.000Z', memos: [memo], avatars: {} };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function openEditor(page, title) {
  await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes(t));
    if (el) el.click();
  }, title);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1300);
}

function measureSingle() {
  const body = document.querySelector('.editor-body');
  const hs = [...body.querySelectorAll('[data-bid], .blk-p, p')].slice(0, 60)
    .map((e) => Math.round(e.getBoundingClientRect().height * 100) / 100);
  return { bodyH: Math.round(body.scrollHeight), firstHeights: hs.slice(0, 6) };
}
function measureCols() {
  const cs = document.querySelectorAll('.editor-body.is-independent-scroll .editor-column');
  if (cs.length !== 2) return { n: cs.length, cls: document.querySelector('.editor-body')?.className };
  const info = (c) => ({
    scrollH: c.scrollHeight,
    members: c.querySelectorAll('[data-bid], .blk-p, p').length,
    firstText: (c.querySelector('[data-bid], .blk-p, p')?.textContent || '').slice(0, 8),
    lastText: ([...c.querySelectorAll('[data-bid], .blk-p, p')].pop()?.textContent || '').slice(0, 8),
  });
  return { n: 2, left: info(cs[0]), right: info(cs[1]) };
}

// ---------------- Rust ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('RUST PAGEERROR', String(e).slice(0, 150)));
  await page.goto(RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate(async ({ mj, mf }) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('mynote-web', 1);
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    await new Promise((res, rej) => {
      const tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(mj, 'memos_json');
      tx.objectStore('kv').put(mf, 'manifest_raw');
      tx.oncomplete = res; tx.onerror = () => rej(tx.error);
    });
  }, { mj: JSON.stringify(payload), mf: JSON.stringify({ version: 1, attachments: {} }) });
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(() => document.body.innerText.includes('分栏量测长文'), { timeout: 15000 });
  await openEditor(page, '分栏量测长文');
  console.log('RUST single', JSON.stringify(await page.evaluate(measureSingle)));
  await page.evaluate(() => document.querySelector('.editor-fab.right')?.click());
  await page.waitForTimeout(500);
  await page.evaluate(() => document.querySelector('.twopane-row')?.click());
  await page.waitForTimeout(1000);
  console.log('RUST cols', JSON.stringify(await page.evaluate(measureCols)));
  await ctx.close();
}

// ---------------- 原版 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('ORIG PAGEERROR', String(e).slice(0, 150)));
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate(async (m) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('MemosDB', 8);
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    await new Promise((res, rej) => {
      const tx = db.transaction('memos', 'readwrite');
      tx.objectStore('memos').put(m);
      tx.oncomplete = res; tx.onerror = () => rej(tx.error);
    });
  }, memo);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(900);
  await openEditor(page, '分栏量测长文');
  console.log('ORIG single', JSON.stringify(await page.evaluate(measureSingle)));
  await page.click('.editor-fab.right');
  await page.waitForTimeout(600);
  await page.evaluate(() => document.querySelector('.editor-column-mode-toggle')?.click());
  await page.waitForTimeout(1000);
  console.log('ORIG cols', JSON.stringify(await page.evaluate(measureCols)));
  await ctx.close();
}

await browser.close();
console.log('PROBE-TWOPANE-DISTRIBUTION DONE');
