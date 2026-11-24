// 探针（斜杠定位批 + 键盘删块收口批）：
// 第一部分 斜杠面板锚定——长文档上/中/下三处 + 下半部带 +
// 双栏两栏唤出，断言面板贴调用光标（下置间距 10）、翻转带内
// 不溢出视口、窗滚/栏滚跟随重锚；链接表单继承锚点。
// 第二部分 键盘删块不变量——键盘永不直接删除非文本块：
// 选中卡退格/Del 不删、块首退格邻卡至多选中、音乐胶囊段首
// 退格不删、跨块选区删除原子块存活；文本路径（合并/MD 源
// 段）行为如基线。Chromium 口径。
// 用法：node probe_slash_anchor.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const near = (a, b, tol) => Math.abs(a - b) <= tol;

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
const memo = (id, title, doc) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc });
const longDoc = [];
for (let i = 1; i <= 60; i++) longDoc.push(para('sa-' + i, '第' + i + '段 量测文本 abcdefghij'));
const img = (id) => ({ id, type: 'image', attrs: { fileId: '' }, children: [] });
const gal = (id) => ({ id, type: 'gallery', attrs: { items: [] }, children: [] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('sa-long', '斜杠锚点探针', longDoc),
    memo('kb-merge', '键盘合并基线', [para('km-1', 'foo'), para('km-2', 'bar')]),
    memo('kb-k1', '键盘K1选中删', [para('k1-1', 'aaaa'), img('k1-img'), para('k1-2', 'bbbb')]),
    memo('kb-k2', '键盘K2块首邻卡', [para('k2-1', 'aaaa'), img('k2-img'), para('k2-2', 'bbbb')]),
    memo('kb-k3', '键盘K3空段邻卡', [para('k3-1', 'aaaa'), gal('k3-gal'), para('k3-2', '')]),
    memo('kb-k4', '键盘K4音乐胶囊', [para('k4-1', 'dddd'), { id: 'k4-mus', type: 'musicCard', status: 'input', children: [{ text: '' }] }, para('k4-2', 'eeee')]),
    memo('kb-k5a', '键盘K5跨块选区', [para('k5-1', 'aaaa'), img('k5-img'), para('k5-2', 'bbbb')]),
    memo('kb-k5b', '键盘K5全选', [para('k5b-1', 'aaaa'), img('k5b-img'), para('k5b-2', 'bbbb'), gal('k5b-gal'), para('k5b-3', 'cccc')]),
    memo('kb-k7', '键盘K7MD源段', [para('k7-1', '前文'), para('k7-2', '## 标题行')]),
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
  await page.setInputFiles('#file-import', { name: 'slash_anchor.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
}
async function openMemo(page, id) {
  await page.goto(base + '?open=' + id, { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(800);
}
const readDoc = (page, title) => page.evaluate(async (t) => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const raw = await new Promise((res, rej) => { const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === t);
  if (!m) return null;
  const textOf = (n) => (n.children || []).map((c) => c.text || '').join('');
  return m.doc.map((b) => ({ type: b.type, text: textOf(b) }));
}, title);
async function setCaret(page, bid, off) {
  return page.evaluate(([b, off]) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    if (!el) return false;
    el.focus();
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode(); let acc = 0;
    while (n) { const len = n.textContent.length; if (acc + len >= off) {
      const r = document.createRange(); r.setStart(n, off - acc); r.collapse(true);
      const s = window.getSelection(); s.removeAllRanges(); s.addRange(r); return true;
    } acc += len; n = walker.nextNode(); }
    const r = document.createRange(); r.selectNodeContents(el); r.collapse(false);
    const s = window.getSelection(); s.removeAllRanges(); s.addRange(r); return true;
  }, [bid, off]);
}
async function caretBlockIdx(page) {
  return page.evaluate(() => {
    const els = [...document.querySelectorAll('.editor-body [data-bid]')];
    const s = window.getSelection(); if (!s.rangeCount) return -1;
    const node = s.getRangeAt(0).startContainer;
    const el = node.nodeType === 1 ? node.closest('[data-bid]') : node.parentElement.closest('[data-bid]');
    return els.indexOf(el);
  });
}
const selBid = (page) => page.evaluate(() => {
  const w = document.querySelector('.blk-wrap.sel');
  return w ? (w.getAttribute('data-wrapbid') || '') : null;
});

// ---------- 第一部分：斜杠锚定（393×852） ----------
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
await ctx.addInitScript(() => localStorage.setItem('mynote_hint_editor_v1', '1'));
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 160)));
await importFixture(page);
await openMemo(page, 'sa-long');

async function placeBlock(bid, targetY) {
  await page.evaluate(([b, ty]) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    let sc = null; let n = el.parentElement;
    while (n && n !== document.body) {
      const s = getComputedStyle(n);
      if ((s.overflowY === 'auto' || s.overflowY === 'scroll') && n.scrollHeight > n.clientHeight + 4) { sc = n; break; }
      n = n.parentElement;
    }
    const r0 = el.getBoundingClientRect();
    if (sc) sc.scrollTop += (r0.top - ty); else window.scrollBy(0, r0.top - ty);
  }, [bid, targetY]);
  await page.waitForTimeout(150);
}
async function slashMeasure() {
  return page.evaluate(() => {
    const panel = document.getElementById('slash-panel');
    const sel = window.getSelection();
    let caret = null;
    if (sel && sel.rangeCount) {
      const rg = sel.getRangeAt(0);
      const rects = rg.getClientRects();
      const cr = rects.length ? rects[0] : rg.getBoundingClientRect();
      caret = { top: cr.top, bottom: cr.bottom, left: cr.left };
    }
    const pr = panel ? panel.getBoundingClientRect() : null;
    return { caret, panel: pr ? { top: pr.top, bottom: pr.bottom, left: pr.left, height: pr.height } : null, vh: window.innerHeight, vw: window.innerWidth };
  });
}
async function openSlashAt(bid, targetY) {
  await placeBlock(bid, targetY);
  const pt = await page.evaluate((b) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    const r = el.getBoundingClientRect();
    return { x: r.x + 30, y: r.y + r.height / 2 };
  }, bid);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(200);
  await page.keyboard.type('/');
  await page.waitForTimeout(600);
  return slashMeasure();
}
async function closeSlash() { await page.keyboard.press('Escape'); await page.waitForTimeout(250); }

let m = await openSlashAt('sa-2', 150);
ok('S1 顶部块面板贴光标下方 10px', !!m.panel && near(m.panel.top - m.caret.bottom, 10, 2), JSON.stringify(m));
ok('S1 面板完整在视口内', !!m.panel && m.panel.top >= 0 && m.panel.bottom <= m.vh - 14, JSON.stringify(m.panel));
await closeSlash();
m = await openSlashAt('sa-30', 420);
ok('S2 中部块面板贴光标下方 10px', !!m.panel && near(m.panel.top - m.caret.bottom, 10, 2), JSON.stringify(m));
ok('S2 面板完整在视口内', !!m.panel && m.panel.bottom <= m.vh - 14, JSON.stringify(m.panel));
await closeSlash();
m = await openSlashAt('sa-45', 545);
ok('S3 下半部带面板仍贴光标下方 10px', !!m.panel && near(m.panel.top - m.caret.bottom, 10, 2), JSON.stringify(m));
ok('S3 下半部带面板不溢出视口底（动态高上限）', !!m.panel && m.panel.bottom <= m.vh - 14, 'bottom=' + (m.panel && m.panel.bottom) + ' vh=' + m.vh);
await closeSlash();
m = await openSlashAt('sa-59', 780);
ok('S4 底部块面板上翻（顶在光标上方且 ≥76 钳制）', !!m.panel && m.panel.top < m.caret.top && m.panel.top >= 74, JSON.stringify(m));
ok('S4 翻转面板完整在视口内', !!m.panel && m.panel.top >= 0 && m.panel.bottom <= m.vh - 14, JSON.stringify(m.panel));
ok('S4 翻转面板底与光标行间距在原版带内（-10..52）', !!m.panel && (m.panel.bottom - m.caret.top) >= -12 && (m.panel.bottom - m.caret.top) <= 54, 'diff=' + (m.panel && (m.panel.bottom - m.caret.top)));
await closeSlash();
// S5 窗滚跟随
m = await openSlashAt('sa-30', 420);
await page.evaluate(() => window.scrollBy(0, 240));
await page.waitForTimeout(600);
{ const m2 = await slashMeasure();
  ok('S5 窗口滚动后面板跟随重锚（间距仍 10）', !!m2.panel && near(m2.panel.top - m2.caret.bottom, 10, 3), JSON.stringify(m2)); }
await closeSlash();
// S6 链接表单锚点保持：过滤出链接行后真实点击，表单须留在
// 菜单原锚点（原版实测：S8 回顶滚动后面板位置不变），且完整
// 落在视口内——选区离开调用块时重锚不得改写锚点。
m = await openSlashAt('sa-30', 420);
{ const topBefore = m.panel ? m.panel.top : -1;
  await page.keyboard.type('链接');
  await page.waitForTimeout(500);
  const rowPt = await page.evaluate(() => {
    const rows = [...document.querySelectorAll('.slash-row')];
    const link = rows.find((r) => r.dataset.act === 'link');
    if (!link) return null;
    const r = link.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  if (rowPt) await page.mouse.click(rowPt.x, rowPt.y);
  await page.waitForTimeout(900);
  const m3 = await slashMeasure();
  const hasForm = await page.evaluate(() => !!document.querySelector('.slash-link-form'));
  ok('S6 链接表单出现', hasForm, 'rowPt=' + JSON.stringify(rowPt));
  ok('S6 表单锚点保持在菜单原位（回顶滚动不改写锚点）', !!m3.panel && near(m3.panel.top, topBefore, 2), 'before=' + topBefore + ' after=' + JSON.stringify(m3.panel));
  ok('S6 表单完整在视口内', !!m3.panel && m3.panel.top >= 0 && m3.panel.bottom <= m3.vh - 14, JSON.stringify(m3.panel)); }
await closeSlash();
await ctx.close();

// ---------- 第一部分：双栏（1440×900 独立滚动） ----------
const ctx2 = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await ctx2.addInitScript(() => { try { localStorage.setItem('sj_editor_independent_scroll', '1'); } catch (e) {} });
await ctx2.addInitScript(() => localStorage.setItem('mynote_hint_editor_v1', '1'));
const page2 = await ctx2.newPage();
page2.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 160)));
await importFixture(page2);
await openMemo(page2, 'sa-long');
async function openSlashAt2(bid, targetY) {
  await page2.evaluate(([b, ty]) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    let sc = null; let n = el.parentElement;
    while (n && n !== document.body) {
      const s = getComputedStyle(n);
      if ((s.overflowY === 'auto' || s.overflowY === 'scroll') && n.scrollHeight > n.clientHeight + 4) { sc = n; break; }
      n = n.parentElement;
    }
    const r0 = el.getBoundingClientRect();
    if (sc) sc.scrollTop += (r0.top - ty); else window.scrollBy(0, r0.top - ty);
  }, [bid, targetY]);
  await page2.waitForTimeout(150);
  const pt = await page2.evaluate((b) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    const r = el.getBoundingClientRect();
    return { x: r.x + 30, y: r.y + r.height / 2 };
  }, bid);
  await page2.mouse.click(pt.x, pt.y);
  await page2.waitForTimeout(200);
  await page2.keyboard.type('/');
  await page2.waitForTimeout(600);
  return page2.evaluate(() => {
    const panel = document.getElementById('slash-panel');
    const sel = window.getSelection();
    let caret = null;
    if (sel && sel.rangeCount) {
      const rg = sel.getRangeAt(0);
      const rects = rg.getClientRects();
      const cr = rects.length ? rects[0] : rg.getBoundingClientRect();
      caret = { top: cr.top, bottom: cr.bottom, left: cr.left };
    }
    const pr = panel ? panel.getBoundingClientRect() : null;
    return { caret, panel: pr ? { top: pr.top, bottom: pr.bottom, left: pr.left } : null, vh: window.innerHeight, vw: window.innerWidth };
  });
}
{ const picks = await page2.evaluate(() => {
    const els = [...document.querySelectorAll('.editor-body [data-bid]')];
    const fr = els[0].getBoundingClientRect();
    const right = els.find((e) => Math.abs(e.getBoundingClientRect().x - fr.x) > 200);
    return { left: els[0].dataset.bid, right: right ? right.dataset.bid : null };
  });
  ok('S7/S8 双栏成形（左右栏块可定位）', !!picks.right, JSON.stringify(picks));
  if (picks.right) {
    let mm = await openSlashAt2(picks.left, 300);
    ok('S7 左栏块面板贴光标下方 10px 且在视口内', !!mm.panel && near(mm.panel.top - mm.caret.bottom, 10, 2) && mm.panel.bottom <= mm.vh - 14, JSON.stringify(mm));
    await page2.keyboard.press('Escape'); await page2.waitForTimeout(250);
    mm = await openSlashAt2(picks.right, 300);
    ok('S8 右栏块面板锚右栏（left 随光标）且贴下方 10px', !!mm.panel && near(mm.panel.top - mm.caret.bottom, 10, 2) && mm.panel.left > mm.vw / 2, JSON.stringify(mm));
    // S9 栏滚跟随：滚动右栏容器 200
    await page2.evaluate(() => {
      const sel = window.getSelection(); const node = sel.getRangeAt(0).startContainer;
      const el = node.nodeType === 1 ? node.closest('[data-bid]') : node.parentElement.closest('[data-bid]');
      let n = el.parentElement;
      while (n && n !== document.body) { const s = getComputedStyle(n); if ((s.overflowY === 'auto' || s.overflowY === 'scroll') && n.scrollHeight > n.clientHeight + 4) { n.scrollTop += 200; return; } n = n.parentElement; }
    });
    await page2.waitForTimeout(700);
    const mm2 = await page2.evaluate(() => {
      const panel = document.getElementById('slash-panel');
      const sel = window.getSelection();
      const rg = sel.getRangeAt(0);
      const rects = rg.getClientRects();
      const cr = rects.length ? rects[0] : rg.getBoundingClientRect();
      const pr = panel ? panel.getBoundingClientRect() : null;
      return { caret: { bottom: cr.bottom }, panel: pr ? { top: pr.top } : null };
    });
    ok('S9 栏内滚动后面板跟随重锚（间距仍 10）', !!mm2.panel && near(mm2.panel.top - mm2.caret.bottom, 10, 3), JSON.stringify(mm2));
    await page2.keyboard.press('Escape');
  }
}
await ctx2.close();

// ---------- 第二部分：键盘删块不变量（393×852） ----------
const ctx3 = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
await ctx3.addInitScript(() => localStorage.setItem('mynote_hint_editor_v1', '1'));
const p3 = await ctx3.newPage();
p3.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 160)));
await importFixture(p3);

// K6 文本合并基线
await openMemo(p3, 'kb-merge');
await setCaret(p3, 'km-2', 0);
await p3.keyboard.press('Backspace');
await p3.waitForTimeout(700);
{ const d = await readDoc(p3, '键盘合并基线');
  ok('K6 文本块首退格与前块合并（基线）', !!d && d.length === 1 && d[0].text === 'foobar', JSON.stringify(d));
  const bi = await caretBlockIdx(p3);
  ok('K6 合并后光标在存活块', bi === 0, 'bi=' + bi); }

// K1 选中卡 + BS/Del 不删
await openMemo(p3, 'kb-k1');
{ const pt = await p3.evaluate(() => {
    const el = document.querySelector('[data-bid="k1-img"]') || document.querySelector('[data-wrapbid="k1-img"]');
    const t = el.closest('.blk-wrap') || el;
    const r = t.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  await p3.mouse.click(pt.x, pt.y);
  await p3.waitForTimeout(400);
  const sb = await selBid(p3);
  ok('K1 点选图片块进入选中态', sb === 'k1-img', 'sel=' + sb);
  await p3.keyboard.press('Backspace');
  await p3.waitForTimeout(500);
  let d = await readDoc(p3, '键盘K1选中删');
  ok('K1 选中卡 Backspace 不删块（落盘不变）', !!d && d.map((b) => b.type).join(',') === 'paragraph,image,paragraph' && d[0].text === 'aaaa' && d[2].text === 'bbbb', JSON.stringify(d));
  await p3.keyboard.press('Delete');
  await p3.waitForTimeout(500);
  d = await readDoc(p3, '键盘K1选中删');
  ok('K1 选中卡 Delete 不删块（落盘不变）', !!d && d.map((b) => b.type).join(',') === 'paragraph,image,paragraph', JSON.stringify(d)); }

// K2 块首退格邻卡（非空）→ 至多选中
await openMemo(p3, 'kb-k2');
await setCaret(p3, 'k2-2', 0);
await p3.keyboard.press('Backspace');
await p3.waitForTimeout(700);
{ const d = await readDoc(p3, '键盘K2块首邻卡');
  ok('K2 块首退格邻卡：卡与文本都保留', !!d && d.map((b) => b.type).join(',') === 'paragraph,image,paragraph' && d[2].text === 'bbbb', JSON.stringify(d));
  const sb = await selBid(p3);
  ok('K2 退格至多选中该卡', sb === 'k2-img', 'sel=' + sb); }

// K3 空段退格邻卡 → 删空段 + 选中卡（留）
await openMemo(p3, 'kb-k3');
await setCaret(p3, 'k3-2', 0);
await p3.keyboard.press('Backspace');
await p3.waitForTimeout(700);
{ const d = await readDoc(p3, '键盘K3空段邻卡');
  ok('K3 空段退格：空段删除、画廊保留', !!d && d.map((b) => b.type).join(',') === 'paragraph,gallery', JSON.stringify(d));
  const sb = await selBid(p3);
  ok('K3 退格后选中画廊', sb === 'k3-gal', 'sel=' + sb); }

// K4 音乐胶囊段首退格不删
await openMemo(p3, 'kb-k4');
{ const pt = await p3.evaluate(() => {
    const el = document.querySelector('[data-bid="k4-mus"]');
    const r = el.getBoundingClientRect();
    return { x: r.x + 12, y: r.y + r.height / 2 };
  });
  await p3.mouse.click(pt.x, pt.y);
  await p3.waitForTimeout(300);
  await p3.keyboard.press('Home');
  await p3.waitForTimeout(150);
  await p3.keyboard.press('Backspace');
  await p3.waitForTimeout(700);
  const d = await readDoc(p3, '键盘K4音乐胶囊');
  ok('K4 音乐胶囊段首退格不删音乐块', !!d && d.map((b) => b.type).join(',') === 'paragraph,musicCard,paragraph', JSON.stringify(d));
  const bi = await caretBlockIdx(p3);
  ok('K4 退格后焦点回上一文本块', bi === 0, 'bi=' + bi); }

// K5a 跨块选区（跨卡）删除 → 卡存活、头尾分段保留
await openMemo(p3, 'kb-k5a');
{ const pt = async (bid, off) => p3.evaluate(([b, off]) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode(); let acc = 0;
    while (n) { const len = n.textContent.length; if (acc + len >= off) {
      const r = document.createRange(); r.setStart(n, off - acc); r.collapse(true);
      const rect = r.getBoundingClientRect(); return { x: rect.left + 1, y: rect.top + rect.height / 2 };
    } acc += len; n = walker.nextNode(); }
    return null;
  }, [bid, off]);
  const p0 = await pt('k5-1', 2); const p1 = await pt('k5-2', 2);
  await p3.mouse.move(p0.x, p0.y); await p3.mouse.down();
  await p3.mouse.move(p1.x, p1.y, { steps: 12 }); await p3.waitForTimeout(150); await p3.mouse.up();
  await p3.waitForTimeout(300);
  await p3.keyboard.press('Backspace');
  await p3.waitForTimeout(800);
  const d = await readDoc(p3, '键盘K5跨块选区');
  ok('K5a 跨卡选区删除：图片存活、头尾文本分段保留', !!d && d.map((b) => b.type).join(',') === 'paragraph,image,paragraph' && d[0].text === 'aa' && d[2].text === 'bb', JSON.stringify(d)); }

// K5b Ctrl+A 全选删除 → 原子块全存活
await openMemo(p3, 'kb-k5b');
await setCaret(p3, 'k5b-1', 1);
await p3.keyboard.press('Control+a');
await p3.waitForTimeout(300);
await p3.keyboard.press('Backspace');
await p3.waitForTimeout(800);
{ const d = await readDoc(p3, '键盘K5全选');
  const types = d ? d.map((b) => b.type) : [];
  const atoms = types.filter((t) => t === 'image' || t === 'gallery');
  const paras = d ? d.filter((b) => b.type === 'paragraph') : [];
  ok('K5b 全选删除：图片与画廊按序存活', !!d && atoms.join(',') === 'image,gallery', JSON.stringify(d));
  ok('K5b 全选删除：文本清空、仅留一个空段承载光标', !!d && paras.length === 1 && paras[0].text === '' && d.every((b) => b.text === ''), JSON.stringify(d)); }

// K7 MD 源段段首退格同文本合并：MD 块非编辑态是 .md-hit
// 预览，点击进入 mdsrc 源码态后段首退格走文本合并。
await openMemo(p3, 'kb-k7');
{ const pt = await p3.evaluate(() => {
    const el = document.querySelector('.md-hit');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + 16, y: r.y + r.height / 2 };
  });
  await p3.mouse.click(pt.x, pt.y);
  await p3.waitForTimeout(600);
  const srcBid = await p3.evaluate(() => {
    const el = document.querySelector('[data-btype="mdsrc"]');
    return el ? el.dataset.bid : null;
  });
  ok('K7 点击 MD 块进入源码编辑态', !!srcBid, 'srcBid=' + srcBid);
  await setCaret(p3, srcBid, 0);
  await p3.waitForTimeout(200);
  await p3.keyboard.press('Backspace');
  await p3.waitForTimeout(700);
  const d = await readDoc(p3, '键盘K7MD源段');
  const nonEmpty = d ? d.filter((b) => b.text !== '') : [];
  ok('K7 MD 源段段首退格与前块合并（文本同规）', !!d && nonEmpty.length === 1 && nonEmpty[0].text === '前文## 标题行', JSON.stringify(d)); }

await ctx3.close();
await browser.close();
L(fails === 0 ? 'ALL PASS' : ('FAILURES: ' + fails));
process.exit(fails === 0 ? 0 : 1);
