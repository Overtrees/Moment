// 断言探针：跨块编辑语义三项（合并光标 UTF-16 口径 / 跨块
// 选区 / 段首退格跨原子块）修复验收。仅 Rust 侧（8211）。
// 跨块选区为桥内虚拟选区，经 window.__mnXSel() 读回核对。
import { chromium } from 'playwright-core';

const url = 'http://localhost:8211/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
let fails = 0;
page.on('pageerror', (e) => { console.log('PAGEERROR', String(e).slice(0, 150)); fails++; });
const L = (...a) => console.log(...a);
const J = (o) => JSON.stringify(o);
const ok = (cond, label, extra) => { L((cond ? '✓' : '✗ FAIL') + ' ' + label, extra === undefined ? '' : J(extra)); if (!cond) fails++; };

// ---------- seed ----------
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
  await page.waitForTimeout(800);
};
const goBack = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(900); };

await page.evaluate(() => {
  const roots = () => [...document.querySelector('.editor-body').children]
    .filter((el) => el.hasAttribute('data-bid') || el.classList.contains('blk-wrap'));
  const editableOf = (root) => root.hasAttribute('data-bid') ? root : root.querySelector('[data-bid]');
  const kindOf = (root) => (root.querySelector('[data-type="image"], img') ? 'image' : (editableOf(root) ? 'text' : 'other'));
  const textOf = (root) => { const ed = editableOf(root); return (ed ? ed.textContent : root.textContent) || ''; };
  const posIn = (el, off) => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let rem = off, n, last = null;
    while ((n = walker.nextNode())) { last = n; if (rem <= n.textContent.length) return [n, rem]; rem -= n.textContent.length; }
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
    caret() {
      const s = getSelection();
      if (!s.rangeCount) return null;
      const node = s.anchorNode;
      const rs = roots();
      let idx = -1, el = null;
      for (let i = 0; i < rs.length; i++) { const e = editableOf(rs[i]); if (e && node && e.contains(node)) { idx = i; el = e; break; } }
      if (idx < 0) return { idx: -1, collapsed: s.isCollapsed };
      const r = document.createRange(); r.selectNodeContents(el); r.setEnd(node, s.anchorOffset);
      return { idx, utf16: r.toString().length, collapsed: s.isCollapsed };
    },
    charPoint(idx, off) {
      const el = editableOf(roots()[idx]);
      const [n, o] = posIn(el, off);
      const r = document.createRange(); r.setStart(n, o); r.collapse(true);
      const rects = r.getClientRects(); const rc = rects && rects[0];
      return rc ? { x: rc.left + 1, y: rc.top + rc.height / 2 } : null;
    },
    selWrap() { const w = document.querySelector('.blk-wrap.sel'); return w ? (w.querySelector('[data-type]')?.dataset.type || 'sel') : null; },
    xsel() { return window.__mnXSel ? window.__mnXSel() : 'NO-ACCESSOR'; },
    diagHas(sub) {
      try {
        const lines = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
        return lines.some((l) => (l.line || l.text || JSON.stringify(l)).includes(sub));
      } catch (e) { return false; }
    },
  };
});
const xb = (fn, ...args) => page.evaluate(([f, a]) => window.__xb[f](...a), [fn, args]);
const blocks = () => xb('blocks');
const caret = () => xb('caret');
const texts = async () => (await blocks()).map((b) => b.text);

// ---------- 1. MERGE（UTF-16 口径） ----------
await openMemo('XB合并');
let idx = await xb('findByText', '丙丁');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
let c = await caret();
ok((await texts())[0] === '甲乙😀丙丁' && c.utf16 === 4, 'MERGE1 emoji junction utf16=4', { t: (await texts())[0], c });
idx = await xb('findByText', '后续');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
c = await caret();
ok((await texts()).includes('cafe' + '\u0301' + '连后续') && c.utf16 === 6, 'MERGE2 combining junction utf16=6', { c });
idx = await xb('findByText', '合体');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
c = await caret();
ok((await texts()).includes('末𠮷合体') && c.utf16 === 3, 'MERGE3 astral junction utf16=3', { c });
await goBack();

// ---------- 2. ATOMIC BACKSPACE ----------
await openMemo('XB原子甲');
idx = await xb('findTextBlock', '图后段落');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
let bs = await blocks();
c = await caret();
ok(bs.length === 1 && bs[0].text === '图后段落' && c.idx === 0 && c.utf16 === 0, 'ATOM-A atomic deleted, caret at para start', { bs, c });
await goBack();

await openMemo('XB原子乙');
idx = await xb('findTextBlock', '后段文字');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
bs = await blocks();
c = await caret();
ok(JSON.stringify(await texts()) === JSON.stringify(['前段文字', '后段文字']) && c.utf16 === 0, 'ATOM-B atomic deleted, no text teleport', { bs, c });
await goBack();

await openMemo('XB原子丙');
idx = await xb('findTextBlock', '');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
const selType = await xb('selWrap');
ok(selType === 'image', 'ATOM-C empty para removed, atomic selected', { selType, bs: await blocks() });
ok(await xb('diagHas', 'atomic selected'), 'ATOM-C diag line present');
// 选中态下再按退格 → 删原子块（两步流）
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
bs = await blocks();
ok(!bs.some((b) => b.kind === 'image'), 'ATOM-C second backspace deletes selected atomic', { bs });
await goBack();

await openMemo('XB原子丁');
idx = await xb('findTextBlock', '');
await xb('setCaret', idx, 0);
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
const selTypeD = await xb('selWrap');
const bsD = await blocks();
ok(selTypeD === 'image' && bsD[0].text === '前段文字', 'ATOM-D empty para removed, atomic selected, head intact', { selTypeD, bsD });
await goBack();

// ---------- 3. SELECTION ----------
await openMemo('XB选区');
const pA = await xb('charPoint', 0, 2);
const pB = await xb('charPoint', 2, 2);
await page.mouse.move(pA.x, pA.y);
await page.mouse.down();
await page.mouse.move(pB.x, pB.y, { steps: 12 });
await page.mouse.up();
await page.waitForTimeout(300);
let xs = await xb('xsel');
ok(xs && xs.text === '段文字\n\n第二段文字\n\n第三', 'SEL drag spans blocks', { xs });

await xb('setCaret', 0, 0);
await page.keyboard.down('Shift');
await page.keyboard.press('ArrowDown');
await page.keyboard.press('ArrowDown');
await page.keyboard.press('ArrowRight');
await page.keyboard.press('ArrowRight');
await page.keyboard.press('ArrowRight');
await page.keyboard.up('Shift');
await page.waitForTimeout(300);
xs = await xb('xsel');
ok(xs && xs.text === '第一段文字\n\n第二段文字\n\n第三段', 'SEL shift+arrows spans blocks', { xs });

await xb('setCaret', 1, 1);
await page.keyboard.press('Control+A');
await page.waitForTimeout(300);
xs = await xb('xsel');
ok(xs && xs.text === '第一段文字\n\n第二段文字\n\n第三段文字', 'SEL ctrl+A whole doc', { xs });

// 拖拽建选区 (0,1)->(2,1) 后退格
const qA = await xb('charPoint', 0, 1);
const qB = await xb('charPoint', 2, 1);
await page.mouse.move(qA.x, qA.y);
await page.mouse.down();
await page.mouse.move(qB.x, qB.y, { steps: 12 });
await page.mouse.up();
await page.waitForTimeout(300);
xs = await xb('xsel');
ok(xs && xs.text === '一段文字\n\n第二段文字\n\n第', 'SEL drag (0,1)->(2,1)', { xs });
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
bs = await blocks();
c = await caret();
ok(bs.length === 1 && bs[0].text === '第三段文字' && c.utf16 === 1, 'SEL backspace merges remainders, caret at junction', { bs, c });
await goBack();

await openMemo('XB选区二');
const rA = await xb('charPoint', 0, 1);
const rB = await xb('charPoint', 2, 1);
await page.mouse.move(rA.x, rA.y);
await page.mouse.down();
await page.mouse.move(rB.x, rB.y, { steps: 12 });
await page.mouse.up();
await page.waitForTimeout(300);
await page.keyboard.type('X');
await page.waitForTimeout(700);
bs = await blocks();
c = await caret();
ok(bs.length === 1 && bs[0].text === '第X三段文字' && c.utf16 === 2, 'SEL type replaces span, caret after char', { bs, c });
await goBack();

await browser.close();
L(fails === 0 ? 'XBLOCK ASSERT ALL PASS' : `XBLOCK ASSERT ${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
