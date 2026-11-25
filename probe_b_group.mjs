// 探针（批 4 B 组余项）：B-14 占位符空判定 / B-3 空块退格越
// 原子块 / B-7 撤销带 layout 快照。各段判据独立，任一红整
// 文件非零退出。Chromium 口径。用法：node probe_b_group.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xFFFFFFFF; for (const b of buf) c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files) {
  const enc = new TextEncoder(); const chunks = []; const central = []; let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name); const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const crc = crc32(data); const size = data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true); lh.setUint16(26, name.length, true);
    chunks.push(Buffer.from(lh.buffer), Buffer.from(name), Buffer.from(data));
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, size, true); ch.setUint32(24, size, true); ch.setUint16(28, name.length, true); ch.setUint32(42, offset, true);
    central.push(Buffer.from(ch.buffer), Buffer.from(name)); offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const ts = new Date().toISOString();
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const memo = (id, title, doc, extra = {}) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc, ...extra });
const img = (id) => ({ id, type: 'image', attrs: { fileId: '' }, children: [] });
const div = (id) => ({ id, type: 'divider', children: [] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('pb-space', 'B14纯空格段', [para('pbs-1', ' ')]),
    memo('pb-empty', 'B14真空段', [para('pbe-1', '')]),
    memo('pb3-skip', 'B3越原子块', [para('pb3-t', '文本甲'), img('pb3-i'), para('pb3-e', '')]),
    memo('pb3-multi', 'B3越连续原子块', [para('pb3m-t', '甲乙'), img('pb3m-i'), div('pb3m-d'), para('pb3m-e', '')]),
    memo('pb3-keep', 'B3只有原子块', [img('pb3k-i'), para('pb3k-e', '')]),
    memo('pb7', 'B7双栏撤销', ['一', '二', '三', '四', '五', '六'].map((t, i) => para('pb7-p' + (i + 1), '段落' + t)),
      { layout: { version: 1, mode: 'independent', left: ['pb7-p1', 'pb7-p2', 'pb7-p3'], right: ['pb7-p4', 'pb7-p5', 'pb7-p6'] } }),
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

async function importFixture(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'b_group.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
}
function openMemoOn(page) {
  return async (id) => {
    await page.goto(base + '?open=' + id, { waitUntil: 'load' });
    await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
    await page.waitForTimeout(700);
  };
}

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
// 批 12 手势提示条预置（非首访口径，同链尾治理）：避免遮挡底部点按目标
await ctx.addInitScript(() => { try { localStorage.setItem('mynote_hint_editor_v1', '1'); } catch (e) {} });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await importFixture(page);
const openMemo = openMemoOn(page);

// ---------- B-14 占位符空判定（原版只看首子节点 text 真值） ----------
{
  await openMemo('pb-space');
  const cls = await page.evaluate(() => document.querySelector('.editor-body')?.className || '');
  ok('B-14 纯空格单段不显占位（首子节点 text 为真值）', !cls.includes('show-placeholder'), cls);
  await openMemo('pb-empty');
  const cls2 = await page.evaluate(() => document.querySelector('.editor-body')?.className || '');
  ok('B-14 真空单段显占位（对照）', cls2.includes('show-placeholder'), cls2);
}

async function readDoc(id) {
  return page.evaluate(async (mid) => {
    // 分条存储形态（IDB v2）：单篇直接读 memos 店条目。
    const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    const raw = await new Promise((res, rej) => { const rq = db.transaction('memos', 'readonly').objectStore('memos').get(mid); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
    if (!raw) return null;
    const m = JSON.parse(raw);
    return m ? m.doc.map((b) => b.type) : null;
  }, id);
}
async function caretIn(bid) {
  return page.evaluate((b) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    const s = window.getSelection();
    if (!el || !s.rangeCount) return -1;
    const r = s.getRangeAt(0);
    if (!el.contains(r.startContainer)) return -1;
    const pre = document.createRange(); pre.selectNodeContents(el); pre.setEnd(r.startContainer, r.startOffset);
    return pre.toString().length;
  }, bid);
}
async function focusBlockEnd(bid) {
  await page.evaluate((b) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    el.focus();
    const r = document.createRange(); r.selectNodeContents(el); r.collapse(false);
    const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
  }, bid);
  await page.waitForTimeout(250);
}

// ---------- B-3 空块退格越原子块（原版一步落更早文本块末尾） ----------
{
  await openMemo('pb3-skip');
  await focusBlockEnd('pb3-e');
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(500);
  ok('B-3 [文本][图][空段] 退格后空段删除、图保留', JSON.stringify(await readDoc('pb3-skip')) === JSON.stringify(['paragraph', 'image']), JSON.stringify(await readDoc('pb3-skip')));
  ok('B-3 光标一步落文本块末尾', (await caretIn('pb3-t')) === 3, String(await caretIn('pb3-t')));
  await openMemo('pb3-multi');
  await focusBlockEnd('pb3m-e');
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(500);
  ok('B-3 连续原子块（图+分割线）一并越过', JSON.stringify(await readDoc('pb3-multi')) === JSON.stringify(['paragraph', 'image', 'divider']), JSON.stringify(await readDoc('pb3-multi')));
  ok('B-3 光标落更早文本块末尾', (await caretIn('pb3m-t')) === 2, String(await caretIn('pb3m-t')));
  await openMemo('pb3-keep');
  await focusBlockEnd('pb3k-e');
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(500);
  ok('B-3 前面只有原子块时保留空段（原版 preventDefault 口径）', JSON.stringify(await readDoc('pb3-keep')) === JSON.stringify(['image', 'paragraph']), JSON.stringify(await readDoc('pb3-keep')));
  ok('B-3 保留时光标仍在空段', (await caretIn('pb3k-e')) === 0, String(await caretIn('pb3k-e')));
}

// ---------- B-7 撤销带 layout 快照（跨栏移动后撤销，栏分布回操作前） ----------
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
async function readMemoById(page, id) {
  return page.evaluate(async (mid) => {
    // 分条存储形态（IDB v2）：单篇直接读 memos 店条目。
    const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    const raw = await new Promise((res, rej) => { const rq = db.transaction('memos', 'readonly').objectStore('memos').get(mid); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
    if (!raw) return null;
    const m = JSON.parse(raw);
    return m ? { ids: m.doc.map((b) => String(b.id)), layout: m.layout || null } : null;
  }, id);
}
async function domUnits(page) {
  return page.evaluate(() => {
    const body = document.querySelector('.editor-body');
    const out = { left: [], right: [], all: [] };
    const bidsOf = (el) => {
      const multi = el.getAttribute('data-bids');
      if (multi) return multi.split(',').filter(Boolean);
      const own = el.getAttribute('data-bid') || el.getAttribute('data-wrapbid');
      if (own) return [own];
      const inner = el.querySelector('[data-bid]');
      return inner ? [inner.getAttribute('data-bid')] : null;
    };
    const collect = (parent, arr) => {
      for (const child of parent.children) {
        if (child.classList?.contains('editor-column')) continue;
        const b = bidsOf(child);
        if (b) { arr.push(...b); out.all.push(...b); }
      }
    };
    const cols = body.querySelectorAll('.editor-column');
    if (cols.length === 2) { collect(cols[0], out.left); collect(cols[1], out.right); }
    else collect(body, out.left);
    return out;
  });
}
async function unitRect(page, bid) {
  return page.evaluate((b) => {
    const body = document.querySelector('.editor-body');
    const units = [];
    const walk = (parent) => {
      for (const child of parent.children) {
        if (child.classList?.contains('editor-column')) { walk(child); continue; }
        units.push(child);
      }
    };
    walk(body);
    const el = units.find((u) => {
      const multi = u.getAttribute('data-bids');
      if (multi) return multi.split(',').includes(b);
      const own = u.getAttribute('data-bid') || u.getAttribute('data-wrapbid');
      if (own) return own === b;
      return u.querySelector('[data-bid]')?.getAttribute('data-bid') === b;
    });
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height, cx: r.x + r.width / 2, cy: r.y + r.height / 2, top: r.top, bottom: r.bottom };
  }, bid);
}
async function mouseDragText(page, fromBid, toBid, toHalf) {
  const from = await unitRect(page, fromBid);
  const to = await unitRect(page, toBid);
  if (!from || !to) return false;
  const targetY = toHalf === 'top' ? to.top + 3 : to.bottom - 3;
  await page.mouse.move(from.cx, from.cy);
  await page.mouse.down();
  await page.waitForTimeout(380); // 文本块桌面拾起 hold 280ms
  const steps = 14;
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(from.cx + (to.cx - from.cx) * (i / steps), from.cy + (targetY - from.cy) * (i / steps));
    await page.waitForTimeout(30);
  }
  await page.mouse.up();
  await page.waitForTimeout(900);
  return true;
}
{
  const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  await ctx2.addInitScript(() => { try { localStorage.setItem('mynote_hint_editor_v1', '1'); } catch (e) {} });
  const p2 = await ctx2.newPage();
  p2.on('pageerror', (e) => L('PAGEERROR(b7)', String(e).slice(0, 200)));
  await importFixture(p2);
  const open7 = openMemoOn(p2);
  await open7('pb7');
  const L0 = ['pb7-p1', 'pb7-p2', 'pb7-p3'];
  const R0 = ['pb7-p4', 'pb7-p5', 'pb7-p6'];
  const dom0 = await domUnits(p2);
  ok('B-7 初始左栏 = 锚 left', eq(dom0.left, L0), dom0.left.join(','));
  ok('B-7 初始右栏 = 锚 right', eq(dom0.right, R0), dom0.right.join(','));
  // 跨栏拖拽：右栏末块 p6 拖到左栏首块 p1 之前（doc 序与锚成员同时变）
  ok('B-7 跨栏拖拽执行', await mouseDragText(p2, 'pb7-p6', 'pb7-p1', 'top'));
  const mMove = await readMemoById(p2, 'pb7');
  ok('B-7 拖后 doc 序', eq(mMove.ids, ['pb7-p6', 'pb7-p1', 'pb7-p2', 'pb7-p3', 'pb7-p4', 'pb7-p5']), mMove.ids.join(','));
  ok('B-7 拖后锚 left 按原分界块数重写', eq(mMove.layout?.left, ['pb7-p6', 'pb7-p1', 'pb7-p2']), (mMove.layout?.left || []).join(','));
  const domMove = await domUnits(p2);
  ok('B-7 拖后 DOM 左栏 == 锚 left', eq(domMove.left, mMove.layout?.left), domMove.left.join(','));
  // 撤销：doc 与 layout 必须一并回到拖前
  const uPt = await unitRect(p2, 'pb7-p1');
  await p2.mouse.click(uPt.cx, uPt.cy);
  await p2.waitForTimeout(300);
  await p2.keyboard.press('Control+z');
  await p2.waitForTimeout(900);
  const mUndo = await readMemoById(p2, 'pb7');
  ok('B-7 撤销后 doc 序回拖前', eq(mUndo.ids, [...L0, ...R0]), mUndo.ids.join(','));
  ok('B-7 撤销后锚 left 回拖前（layout 随历史回退）', eq(mUndo.layout?.left, L0), (mUndo.layout?.left || []).join(','));
  ok('B-7 撤销后锚 right 回拖前', eq(mUndo.layout?.right, R0), (mUndo.layout?.right || []).join(','));
  const domUndo = await domUnits(p2);
  ok('B-7 撤销后 DOM 左栏回拖前', eq(domUndo.left, L0), domUndo.left.join(','));
  ok('B-7 撤销后 DOM 右栏回拖前', eq(domUndo.right, R0), domUndo.right.join(','));
  // 重做：doc 与 layout 一并回到拖后
  await p2.keyboard.press('Control+y');
  await p2.waitForTimeout(900);
  const mRedo = await readMemoById(p2, 'pb7');
  ok('B-7 重做后 doc 序回拖后', eq(mRedo.ids, mMove.ids), mRedo.ids.join(','));
  ok('B-7 重做后锚 left 回拖后', eq(mRedo.layout?.left, mMove.layout?.left), (mRedo.layout?.left || []).join(','));
  const domRedo = await domUnits(p2);
  ok('B-7 重做后 DOM 左栏回拖后', eq(domRedo.left, mMove.layout?.left), domRedo.left.join(','));
  await ctx2.close();
}

L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
