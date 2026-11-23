// 探针：跨块编辑语义三项对照（合并光标口径 / 跨块选区 /
// 段首退格跨原子块）。用法：node probe_xblock.mjs rust|orig
import { chromium } from 'playwright-core';

const mode = process.argv[2];
if (mode !== 'rust' && mode !== 'orig') { console.error('need rust|orig'); process.exit(2); }
const url = mode === 'rust' ? 'http://localhost:8211/' : 'http://localhost:8212/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);
const J = (o) => JSON.stringify(o);

// ---------- seed ----------
if (mode === 'rust') {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', 'fixtures/xblock.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 }).catch(() => {});
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.waitForTimeout(400);
  L('SEEDED rust via import');
} else {
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
  L('SEEDED orig', seeded);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2000);
}

// ---------- open / back ----------
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
  await page.waitForTimeout(mode === 'orig' ? 1800 : 800);
};
const goBack = async () => {
  await page.click('.editor-fab.left');
  await page.waitForTimeout(mode === 'orig' ? 1500 : 900);
};

// ---------- in-page helpers ----------
await page.evaluate((m) => {
  const roots = () => m === 'rust'
    ? [...document.querySelector('.editor-body').children].filter((el) => el.hasAttribute('data-bid') || el.classList.contains('blk-wrap'))
    : [...document.querySelectorAll('.editor-body [data-blockid]')];
  const editableOf = (root) => {
    if (m !== 'rust') return root;
    return root.hasAttribute('data-bid') ? root : root.querySelector('[data-bid]');
  };
  const kindOf = (root) => {
    if (m === 'rust') {
      if (root.querySelector('[data-type="image"], img')) return 'image';
      return editableOf(root) ? 'text' : 'other';
    }
    const t = root.dataset.type || '';
    if (t === 'image' || root.classList.contains('atomic')) return 'image';
    return 'text';
  };
  const textOf = (root) => {
    const ed = editableOf(root);
    return (ed ? ed.textContent : root.textContent) || '';
  };
  const posIn = (el, off) => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let rem = off, n, last = null;
    while ((n = walker.nextNode())) {
      last = n;
      if (rem <= n.textContent.length) return [n, rem];
      rem -= n.textContent.length;
    }
    return last ? [last, last.textContent.length] : [el, 0];
  };
  window.__xb = {
    blocks() { return roots().map((r) => ({ kind: kindOf(r), text: textOf(r) })); },
    findByText(t) { return roots().findIndex((r) => textOf(r) === t); },
    findTextBlock(t) { return roots().findIndex((r) => kindOf(r) === 'text' && textOf(r) === t); },
    setCaret(idx, off) {
      const el = editableOf(roots()[idx]); if (!el) return false;
      el.focus();
      const [n, o] = posIn(el, off);
      const r = document.createRange(); r.setStart(n, o); r.collapse(true);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
      return true;
    },
    setRange(ai, ao, bi, bo) {
      const [an, aoff] = posIn(editableOf(roots()[ai]), ao);
      const [bn, boff] = posIn(editableOf(roots()[bi]), bo);
      const r = document.createRange(); r.setStart(an, aoff); r.setEnd(bn, boff);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
      return true;
    },
    caret() {
      const s = getSelection();
      if (!s.rangeCount) return null;
      const node = s.anchorNode;
      const rs = roots();
      let idx = -1, el = null;
      for (let i = 0; i < rs.length; i++) { const e = editableOf(rs[i]); if (e && node && e.contains(node)) { idx = i; el = e; break; } }
      if (idx < 0) return { idx: -1, collapsed: s.isCollapsed, sel: s.toString() };
      const r = document.createRange(); r.selectNodeContents(el); r.setEnd(node, s.anchorOffset);
      const before = r.toString();
      return { idx, utf16: before.length, scalar: [...before].length, collapsed: s.isCollapsed, sel: s.toString() };
    },
    selText() { const s = getSelection(); return s.rangeCount ? s.toString() : ''; },
    charPoint(idx, off) {
      const el = editableOf(roots()[idx]);
      const [n, o] = posIn(el, off);
      const r = document.createRange(); r.setStart(n, o); r.collapse(true);
      const rects = r.getClientRects(); const rc = rects && rects[0];
      if (!rc) return null;
      return { x: rc.left + 1, y: rc.top + rc.height / 2 };
    },
  };
}, mode);
const xb = (fn, ...args) => page.evaluate(([f, a]) => window.__xb[f](...a), [fn, args]);
const blocks = () => xb('blocks');
const caret = () => xb('caret');

// ---------- 1. MERGE ----------
await openMemo('XB合并');
L('MERGE init', J(await blocks()));
let idx = await xb('findByText', '丙丁');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
L('MERGE1 (emoji, expect block 甲乙😀丙丁 caret utf16=4 scalar=3)', J(await blocks()), J(await caret()));
idx = await xb('findByText', '后续');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
L('MERGE2 (combining, expect café连后续 caret utf16=6 scalar=6)', J(await blocks()), J(await caret()));
idx = await xb('findByText', '合体');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
L('MERGE3 (astral CJK, expect 末𐮷合体 caret utf16=3 scalar=2)', J(await blocks()), J(await caret()));
await goBack();

// ---------- 2. SELECTION ----------
await openMemo('XB选区');
L('SEL init', J(await blocks()));
const pA = await xb('charPoint', 0, 2);
const pB = await xb('charPoint', 2, 2);
if (pA && pB) {
  await page.mouse.move(pA.x, pA.y);
  await page.mouse.down();
  await page.mouse.move(pB.x, pB.y, { steps: 12 });
  await page.mouse.up();
  await page.waitForTimeout(300);
  L('SEL drag selText=', J(await xb('selText')), 'caret=', J(await caret()));
}
await xb('setCaret', 0, 0);
await page.keyboard.down('Shift');
await page.keyboard.press('ArrowDown');
await page.keyboard.press('ArrowDown');
await page.keyboard.press('ArrowRight');
await page.keyboard.press('ArrowRight');
await page.keyboard.press('ArrowRight');
await page.keyboard.up('Shift');
await page.waitForTimeout(300);
L('SEL shift selText=', J(await xb('selText')));
await xb('setCaret', 1, 1);
await page.keyboard.press('Control+A');
await page.waitForTimeout(300);
L('SEL ctrlA selText=', J(await xb('selText')));
await xb('setRange', 0, 1, 2, 1);
await page.waitForTimeout(200);
L('SEL prog selText=', J(await xb('selText')));
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
L('SEL prog+backspace blocks=', J(await blocks()), 'caret=', J(await caret()));
await goBack();

await openMemo('XB选区二');
await xb('setRange', 0, 1, 2, 1);
await page.waitForTimeout(200);
L('SEL2 prog selText=', J(await xb('selText')));
await page.keyboard.type('X');
await page.waitForTimeout(700);
L('SEL2 prog+type blocks=', J(await blocks()), 'caret=', J(await caret()));
await goBack();

// ---------- 3. ATOMIC BACKSPACE ----------
const atomicCase = async (title, targetText, label) => {
  await openMemo(title);
  const before = await blocks();
  const idx = await xb('findTextBlock', targetText);
  await xb('setCaret', idx, 0);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(700);
  L(label, 'before=', J(before), 'after=', J(await blocks()), 'caret=', J(await caret()));
  await goBack();
};
await atomicCase('XB原子甲', '图后段落', 'ATOM-A [img][para]');
await atomicCase('XB原子乙', '后段文字', 'ATOM-B [para][img][para]');
await atomicCase('XB原子丙', '', 'ATOM-C [img][empty]');
await atomicCase('XB原子丁', '', 'ATOM-D [para][img][empty]');

await browser.close();
L('DONE', mode);
