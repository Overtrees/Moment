// 探针（原版·空段退格复核）：把光标确切放进空段（JS range +
// 宿主聚焦，验 anchor 落在空段内）后退格，看原版 handler 对
// [图][空段] 与 [段][图][空段] 的裁决。
import { chromium } from 'playwright-core';

const url = 'http://localhost:8212/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);
const J = (o) => JSON.stringify(o);

await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(2500);
await page.evaluate(async () => {
  const resp = await fetch('fixtures/xblock.zip');
  const buf = await resp.arrayBuffer();
  const unzipped = await window.MynoteZip.checkedZip(new Uint8Array(buf));
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
});
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2000);

const openMemo = async (title) => {
  const titlePt = (t) => page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt
        && !e.querySelector('.expand-btn'));
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, t);
  let pt = null;
  for (let attempt = 0; attempt < 4 && !pt; attempt++) {
    pt = await titlePt(title);
    if (pt) break;
    const ex = await page.evaluate(() => {
      const b = document.querySelector('.expand-btn');
      if (!b) return null;
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (ex) { await page.mouse.click(ex.x, ex.y); await page.waitForTimeout(900); }
    else await page.waitForTimeout(500);
  }
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1800);
};
const goBack = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(1500); };

const state = (label) => page.evaluate((lab) => {
  const body = document.querySelector('.editor-body');
  const blocks = [...body.querySelectorAll('[data-blockid]')].map((b) => ({
    type: b.dataset.type || b.tagName, text: (b.textContent || '').slice(0, 12),
  }));
  const s = getSelection();
  let anchor = 'none';
  if (s.rangeCount) {
    const n = s.anchorNode;
    const el = n.nodeType === 1 ? n : n.parentElement;
    const blk = el && el.closest ? el.closest('[data-blockid]') : null;
    anchor = `block=${blk ? (blk.dataset.type || blk.tagName) + ':' + (blk.textContent || '').slice(0, 8) : '?'} off=${s.anchorOffset} node=${n.nodeName}`;
  }
  return { label: lab, blocks, anchor, active: document.activeElement ? (document.activeElement.className || document.activeElement.tagName) : '' };
}).then((r) => L(J(r)));

const caretIntoEmptyPara = () => page.evaluate(() => {
  const host = document.querySelector('.editor-body');
  host.focus();
  const blocks = [...host.querySelectorAll('[data-blockid]')];
  const p = blocks.find((b) => b.tagName === 'P' && (b.textContent || '') === '');
  if (!p) return false;
  const r = document.createRange();
  r.setStart(p, 0); r.collapse(true);
  const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  return true;
});

for (const title of ['XB原子丙', 'XB原子丁']) {
  await openMemo(title);
  await caretIntoEmptyPara();
  await state(title + ' CARET-IN-EMPTY');
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(700);
  await state(title + ' AFTER-BS');
  await page.waitForTimeout(1200);
  const stored = await page.evaluate((t) => {
    const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
    const m = arr.find((x) => x.title === t);
    return m ? m.doc.map((b) => b.type) : null;
  }, title);
  L('STORED', title, J(stored));
  await goBack();
}
await browser.close();
L('DONE');
