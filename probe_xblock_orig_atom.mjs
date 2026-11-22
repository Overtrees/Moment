// 探针（原版·原子退格复核）：真实鼠标点击落光标（确保焦点与
// React keydown 处理链完整），退格后看 DOM 原始 HTML、落盘
// doc、重载后形态——判定原版段首退格跨原子块的真实规格。
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
const seeded = await page.evaluate(async () => {
  const resp = await fetch('fixtures/xblock.zip');
  const buf = await resp.arrayBuffer();
  const unzipped = await window.MynoteZip.checkedZip(new Uint8Array(buf));
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
  return backup.memos.length;
});
L('SEEDED', seeded);
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

const dump = (label) => page.evaluate((lab) => {
  const body = document.querySelector('.editor-body');
  const s = getSelection();
  let anchorDesc = 'none';
  if (s.rangeCount) {
    const n = s.anchorNode;
    const el = n.nodeType === 1 ? n : n.parentElement;
    const blk = el && el.closest ? el.closest('[data-blockid]') : null;
    anchorDesc = `block=${blk ? (blk.dataset.type || blk.tagName) : '?'} off=${s.anchorOffset} node=${n.nodeType === 3 ? 'text:' + n.textContent.slice(0, 10) : n.nodeName}`;
  }
  return {
    label: lab,
    html: body ? body.innerHTML.replace(/\s+/g, ' ').slice(0, 700) : 'no body',
    anchor: anchorDesc,
    active: document.activeElement ? (document.activeElement.className || document.activeElement.tagName) : '',
  };
}).then((r) => L(J(r)));

const storedDoc = (title) => page.evaluate((t) => {
  try {
    const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
    const m = arr.find((x) => x.title === t);
    return m ? m.doc.map((b) => ({ type: b.type, text: (b.children || []).map((c) => c.text || '').join('') })) : null;
  } catch (e) { return String(e); }
}, title).then((r) => L('STORED', title, J(r)));

// 点击段落最左端落光标到段首
const clickParaStart = (text) => page.evaluate((t) => {
  const blocks = [...document.querySelectorAll('.editor-body [data-blockid]')];
  const el = blocks.find((b) => (b.textContent || '') === t && b.contentEditable !== 'false');
  if (!el) return null;
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  return { x: r.left + 3, y: r.top + r.height / 2 };
}, text).then(async (pt) => {
  if (!pt) { L('clickParaStart MISS', text); return; }
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(300);
});

const cases = [
  ['XB原子甲', '图后段落'],
  ['XB原子乙', '后段文字'],
  ['XB原子丙', ''],
  ['XB原子丁', ''],
];
for (const [title, text] of cases) {
  await openMemo(title);
  await dump(title + ' BEFORE');
  await clickParaStart(text);
  await dump(title + ' CARET-PLACED');
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(600);
  await dump(title + ' AFTER-BS');
  await page.waitForTimeout(1500);
  await storedDoc(title);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(1500);
  // 重载后回到列表（编辑页可能保持），统一处理：若在编辑页先返回
  const inEditor = await page.evaluate(() => !!document.querySelector('.editor-body'));
  if (inEditor) {
    await dump(title + ' AFTER-RELOAD(still editor)');
    await goBack();
  } else {
    await openMemo(title);
    await dump(title + ' AFTER-RELOAD');
    await goBack();
  }
}
await browser.close();
L('DONE');
