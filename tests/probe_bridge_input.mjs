// 探针（批 1 bridge.rs）：输入/组字/粘贴/选区九项——
// B-11 组字结束重放、B-5 beforeinput 三指撤销、B-10 全局
// 撤销兜底、B-8 xsel 跨块粘贴（双侧量测口径：按行落块）、
// B-9 音乐胶囊粘贴分流+错位回收、B-13 原子块点击插段区
// 分档、B-12 方向键目标列会话、MD-C5 包裹空白外置、
// D-1 斜杠触发抑制。Chromium 口径。
// 用法：node probe_bridge_input.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

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
const LONG = 'aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd eeeeeeeeee ffffffffff gggggggggg hhhhhhhhhh iiiiiiiiii jjjjjjjjjj';
const memo = (id, title, doc) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('pb-b5', '桥探针B5', [para('pb5-1', 'aaaa')]),
    memo('pb-b11', '桥探针B11', [para('pb11-1', '')]),
    memo('pb-b10', '桥探针B10', [
      { id: 'pb10-itc', type: 'imgTextCard', attrs: { fileId: 'nofile0' }, children: [{ text: '图文卡文字' }] },
      { id: 'pb10-att', type: 'attachment', fileId: 'nofile1', status: 'done', image: false, children: [{ text: '' }] },
      para('pb10-1', 'aaaa'),
    ]),
    memo('pb-b8a', '桥探针B8甲', [para('pb8-1', 'aaaa'), para('pb8-2', 'bbbb'), para('pb8-3', 'cccc')]),
    memo('pb-b8b', '桥探针B8乙', [para('pb8-1', 'aaaa'), para('pb8-2', 'bbbb'), para('pb8-3', 'cccc')]),
    memo('pb-b9a', '桥探针B9甲', [para('pb9-1', 'hello'), { id: 'pb9-m', type: 'musicCard', status: 'input', children: [{ text: '' }] }]),
    memo('pb-b9b', '桥探针B9乙', [para('pb9-1', 'hello'), { id: 'pb9-m', type: 'musicCard', status: 'input', children: [{ text: '' }] }]),
    memo('pb-b12', '桥探针B12', [para('pb12-1', LONG), para('pb12-2', 'short'), para('pb12-3', LONG)]),
    memo('pb-md', '桥探针MD', [para('pbmd-1', 'x ab y')]),
    memo('pb-d1a', '桥探针D1甲', [para('pbd1-1', '')]),
    memo('pb-d1b', '桥探针D1乙', [para('pbd1-1', '')]),
    memo('pb-d1c', '桥探针D1丙', [para('pbd1-1', '')]),
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const readDoc = (page, title) => page.evaluate(async (t) => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('moment-web'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  // 组装读（IDB 分条合流适配，只换读取通道、断言不变）
  const raw = await (async () => {
    const getKv = (k) => new Promise((res) => { const rq = db.transaction('kv', 'readonly').objectStore('kv').get(k); rq.onsuccess = () => res(rq.result); rq.onerror = () => res(undefined); });
    const legacy = await getKv('memos_json');
    if (legacy !== undefined) return legacy;
    const meta = await getKv('backup_meta');
    if (!meta) return undefined;
    const order = JSON.parse((await getKv('memos_order')) || '[]');
    const [vals, ks] = await Promise.all([
      new Promise((res) => { const rq = db.transaction('memos', 'readonly').objectStore('memos').getAll(); rq.onsuccess = () => res(rq.result || []); rq.onerror = () => res([]); }),
      new Promise((res) => { const rq = db.transaction('memos', 'readonly').objectStore('memos').getAllKeys(); rq.onsuccess = () => res(rq.result || []); rq.onerror = () => res([]); }),
    ]);
    const byId = new Map(ks.map((k, i) => [String(k), vals[i]]));
    const root = JSON.parse(meta);
    root.memos = order.map((id) => byId.get(String(id))).filter((v) => v !== undefined).map((v) => JSON.parse(v));
    return JSON.stringify(root);
  })();
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === t);
  if (!m) return null;
  const textOf = (n) => (n.children || []).map((c) => c.text || '').join('');
  return m.doc.map((b) => ({ type: b.type, text: textOf(b), status: b.status || '', url: b.url || '' }));
}, title);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'bridge_input.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });

async function openMemo(id) {
  await page.goto(base + '?open=' + id, { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(700);
}
async function clickBlockCenter(bid) {
  const pt = await page.evaluate((b) => {
    const el = document.querySelector('[data-bid="' + b + '"]');
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, bid);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(250);
}
async function setCaret(bid, off) {
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
async function caretState() {
  return page.evaluate(() => {
    const els = [...document.querySelectorAll('.editor-body [data-bid]')];
    const s = window.getSelection(); if (!s.rangeCount) return null;
    const r = s.getRangeAt(0);
    let node = r.startContainer;
    const el = node.nodeType === 1 ? (node.closest ? node.closest('[data-bid]') : null) : (node.parentElement ? node.parentElement.closest('[data-bid]') : null);
    const bi = els.indexOf(el);
    let off = -1;
    if (el) { const pre = document.createRange(); pre.selectNodeContents(el); pre.setEnd(r.startContainer, r.startOffset); off = pre.toString().length; }
    return { bi, off };
  });
}
const MUSIC_URL = 'https://music.163.com/song?id=123456';

// ---------- B-11：组字结束重放（不补发 input） ----------
await openMemo('pb-b11');
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  el.focus();
  el.dispatchEvent(new Event('compositionstart', { bubbles: true }));
  el.textContent = '/加粗';
  const r = document.createRange(); r.selectNodeContents(el); r.collapse(false);
  const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
  el.dispatchEvent(new Event('compositionend', { bubbles: true }));
});
await page.waitForTimeout(900);
const panelAfterComp = await page.evaluate(() => !!document.getElementById('slash-panel'));
ok('B-11 组字提交后斜杠面板即时出现（compositionend 重放）', panelAfterComp);
await page.keyboard.press('Escape');
await page.waitForTimeout(200);
// 智能前缀同路：组字提交 '# 标题词' → 80ms 防抖 pasteSync 转标题
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  el.focus();
  el.dispatchEvent(new Event('compositionstart', { bubbles: true }));
  el.textContent = '# 标题词';
  const r = document.createRange(); r.selectNodeContents(el); r.collapse(false);
  const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
  el.dispatchEvent(new Event('compositionend', { bubbles: true }));
});
await page.waitForTimeout(1000);
const docB11 = await readDoc(page, '桥探针B11');
ok('B-11 组字提交后智能前缀即时生效（转 heading）', !!docB11 && docB11[0] && docB11[0].type === 'heading' && docB11[0].text === '标题词', JSON.stringify(docB11));

// ---------- B-5：beforeinput historyUndo ----------
await openMemo('pb-b5');
await setCaret('pb5-1', 4);
await page.keyboard.press('Enter');
await page.waitForTimeout(400);
let nBlocks = await page.evaluate(() => document.querySelectorAll('.editor-body [data-bid]').length);
ok('B-5 前置：回车拆块为 2', nBlocks === 2, 'n=' + nBlocks);
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  el.dispatchEvent(new InputEvent('beforeinput', { inputType: 'historyUndo', bubbles: true, cancelable: true }));
});
await page.waitForTimeout(500);
nBlocks = await page.evaluate(() => document.querySelectorAll('.editor-body [data-bid]').length);
ok('B-5 beforeinput historyUndo 触发应用撤销（回 1 块）', nBlocks === 1, 'n=' + nBlocks);
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  el.dispatchEvent(new InputEvent('beforeinput', { inputType: 'historyRedo', bubbles: true, cancelable: true }));
});
await page.waitForTimeout(500);
nBlocks = await page.evaluate(() => document.querySelectorAll('.editor-body [data-bid]').length);
ok('B-5 beforeinput historyRedo 触发重做（回 2 块）', nBlocks === 2, 'n=' + nBlocks);

// ---------- B-10 + B-13（同备忘） ----------
await openMemo('pb-b10');
// 先做一次可撤销编辑：段落回车拆块
await setCaret('pb10-1', 4);
await page.keyboard.press('Enter');
await page.waitForTimeout(400);
let docB10 = await readDoc(page, '桥探针B10');
ok('B-10 前置：拆块后共 4 块', !!docB10 && docB10.length === 4, 'n=' + (docB10 || []).length);
// B-13 卡片左侧区（x=10）：不应插段（旧口径会插），只选中
let itcRect = await page.evaluate(() => { const w = document.querySelector('[data-wrapbid="pb10-itc"]'); const r = w.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; });
await page.mouse.click(itcRect.left + 10, itcRect.top + itcRect.height / 2);
await page.waitForTimeout(400);
docB10 = await readDoc(page, '桥探针B10');
ok('B-13 图文卡左侧 10px 点击不插段', !!docB10 && docB10.length === 4, 'n=' + (docB10 || []).length);
// B-13 卡片右 15% 区（距右 40px，宽约 345 时在 28px 口径之外）：应插段后
itcRect = await page.evaluate(() => { const w = document.querySelector('[data-wrapbid="pb10-itc"]'); const r = w.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; });
await page.mouse.click(itcRect.left + itcRect.width - 40, itcRect.top + itcRect.height / 2);
await page.waitForTimeout(500);
docB10 = await readDoc(page, '桥探针B10');
ok('B-13 图文卡右 15% 区点击插段后（+1 块）', !!docB10 && docB10.length === 5, 'n=' + (docB10 || []).length);
// B-13 附件左侧 28px：应插段前
const attRect = await page.evaluate(() => { const w = document.querySelector('[data-wrapbid="pb10-att"]'); const r = w.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; });
await page.mouse.click(attRect.left + 10, attRect.top + attRect.height / 2);
await page.waitForTimeout(500);
docB10 = await readDoc(page, '桥探针B10');
ok('B-13 附件左侧 28px 点击插段前（+1 块）', !!docB10 && docB10.length === 6, 'n=' + (docB10 || []).length);
// B-10 点原子块（焦点落 body）后 Ctrl+Z 应撤销最近一次编辑（附件前插段）
const attRect2 = await page.evaluate(() => { const w = document.querySelector('[data-wrapbid="pb10-att"]'); const r = w.getBoundingClientRect(); return { left: r.left, top: r.top, width: r.width, height: r.height }; });
await page.mouse.click(attRect2.left + attRect2.width / 2, attRect2.top + attRect2.height / 2);
await page.waitForTimeout(300);
await page.keyboard.press('Control+z');
await page.waitForTimeout(600);
docB10 = await readDoc(page, '桥探针B10');
ok('B-10 点过原子块后 Ctrl+Z 生效（撤销插段，-1 块）', !!docB10 && docB10.length === 5, 'n=' + (docB10 || []).length);
// B-10 负例：焦点在标题 input 时 Ctrl+Z 不劫持（文档不变）
await page.locator('#editor-title-text').click();
await page.waitForTimeout(300);
const titleFocused = await page.evaluate(() => document.activeElement && document.activeElement.id === 'editor-title-text');
ok('B-10 负例前置：标题 input 已获焦', titleFocused, String(titleFocused));
await page.keyboard.press('Control+z');
await page.waitForTimeout(500);
docB10 = await readDoc(page, '桥探针B10');
ok('B-10 标题 input 内 Ctrl+Z 不触发应用撤销', !!docB10 && docB10.length === 5, 'n=' + (docB10 || []).length);

// ---------- B-8：xsel 跨块粘贴（量测口径：按行落块） ----------
async function xselPaste(memoId, text) {
  await openMemo(memoId);
  const pt = async (bi, off) => page.evaluate(([bi, off]) => {
    const els = [...document.querySelectorAll('.editor-body [data-bid]')];
    const el = els[bi];
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode(); let acc = 0;
    while (n) { const len = n.textContent.length; if (acc + len >= off) {
      const r = document.createRange(); r.setStart(n, off - acc); r.collapse(true);
      const rect = r.getBoundingClientRect(); return { x: rect.left + 1, y: rect.top + rect.height / 2 };
    } acc += len; n = walker.nextNode(); }
    return null;
  }, [bi, off]);
  const p0 = await pt(0, 2); const p1 = await pt(2, 2);
  await page.mouse.move(p0.x, p0.y); await page.mouse.down();
  await page.mouse.move(p1.x, p1.y, { steps: 12 }); await page.waitForTimeout(150); await page.mouse.up();
  await page.waitForTimeout(300);
  await page.evaluate((t) => {
    const el = document.activeElement && document.activeElement.closest && document.activeElement.closest('[data-bid]') ? document.activeElement : document.querySelector('.editor-body [data-bid]');
    const ev = new Event('paste', { bubbles: true, cancelable: true });
    Object.defineProperty(ev, 'clipboardData', { value: { getData: (f) => (f === 'text/plain' ? t : ''), items: [], files: [] } });
    el.dispatchEvent(ev);
  }, text);
  await page.waitForTimeout(1200);
}
await xselPaste('pb-b8a', 'x\ny\n\nz');
const docB8a = await readDoc(page, '桥探针B8甲');
ok('B-8 xsel 粘贴 x\\ny\\n\\nz 按行落块（与原版量测一致）', eq((docB8a || []).map((b) => b.text), ['aax', 'y', '', 'zcc']), JSON.stringify((docB8a || []).map((b) => b.text)));
await xselPaste('pb-b8b', 'XX');
const docB8b = await readDoc(page, '桥探针B8乙');
ok('B-8 xsel 粘贴单行整段替换为一块', eq((docB8b || []).map((b) => b.text), ['aaXXcc']), JSON.stringify((docB8b || []).map((b) => b.text)));

// ---------- B-9：音乐胶囊粘贴事务 ----------
async function musicStatus(title) {
  const d = await readDoc(page, title);
  const m = (d || []).find((b) => b.type === 'musicCard');
  return m ? m.status : '(missing)';
}
// 甲：paste 阶段分流（胶囊 engaged、粘贴目标是邻块、剪贴板含 URL）
await openMemo('pb-b9a');
await page.locator('[data-btype="musicInput"]').click();
await page.waitForTimeout(300);
await page.evaluate((t) => {
  const el = document.querySelector('[data-bid="pb9-1"]');
  const ev = new Event('paste', { bubbles: true, cancelable: true });
  Object.defineProperty(ev, 'clipboardData', { value: { getData: (f) => (f === 'text/plain' ? t : ''), items: [], files: [] } });
  el.dispatchEvent(ev);
}, '看看这个 ' + MUSIC_URL);
await page.waitForTimeout(2500);
let st = await musicStatus('桥探针B9甲');
const docB9a = await readDoc(page, '桥探针B9甲');
ok('B-9 错位粘贴在 paste 阶段分流进胶囊（状态离 input）', st !== 'input' && st !== '(missing)', 'status=' + st);
ok('B-9 分流后邻块文本未被污染', !!docB9a && docB9a[0] && docB9a[0].text === 'hello', JSON.stringify(docB9a && docB9a[0]));
// 乙：原生落地后 input 阶段 diff 回收
await openMemo('pb-b9b');
await page.locator('[data-btype="musicInput"]').click();
await page.waitForTimeout(300);
await page.evaluate((url) => {
  const el = document.querySelector('[data-bid="pb9-1"]');
  el.dispatchEvent(new InputEvent('beforeinput', { inputType: 'insertFromPaste', bubbles: true, cancelable: true }));
  el.textContent = 'hello ' + url;
  el.dispatchEvent(new Event('input', { bubbles: true }));
}, MUSIC_URL);
await page.waitForTimeout(2500);
st = await musicStatus('桥探针B9乙');
const paraTextB9b = await page.evaluate(() => document.querySelector('[data-bid="pb9-1"]').textContent);
ok('B-9 原生落地后 input 阶段回收进胶囊（状态离 input）', st !== 'input' && st !== '(missing)', 'status=' + st);
ok('B-9 回收后邻块还原为粘贴前文本', paraTextB9b === 'hello', JSON.stringify(paraTextB9b));

// ---------- B-12：方向键目标列会话 ----------
await openMemo('pb-b12');
await setCaret('pb12-3', 40);
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(150);
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(200);
let cs = await caretState();
ok('B-12 长-短-长连按 Up 两次落首块末行行尾（目标列保持）', !!cs && cs.bi === 0 && cs.off === 109, JSON.stringify(cs));
await setCaret('pb12-2', 2);
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(200);
cs = await caretState();
ok('B-12 短块首行 Up 跨入长块末行', !!cs && cs.bi === 0, JSON.stringify(cs));
await setCaret('pb12-1', 98);
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(200);
cs = await caretState();
ok('B-12 长块末行 Down 跨入短块', !!cs && cs.bi === 1 && cs.off <= 5, JSON.stringify(cs));

// ---------- MD-C5：包裹选区首尾空白外置 ----------
await openMemo('pb-md');
await page.evaluate(() => {
  const el = document.querySelector('[data-bid="pbmd-1"]');
  el.focus();
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  const n = walker.nextNode();
  const r = document.createRange(); r.setStart(n, 1); r.setEnd(n, 5);
  const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
});
const htmlBold = await page.evaluate(() => window.__mnInline('bold', 'pbmd-1'));
ok('MD-C5 加粗：空白外置存出 <b>ab</b>', htmlBold.includes('<b>ab</b>') && !htmlBold.includes('<b> ab') && !htmlBold.includes('ab </b>'), htmlBold);
await page.evaluate(() => {
  const el = document.querySelector('[data-bid="pbmd-1"]');
  // 复原为纯文本再测行内代码
  el.innerHTML = 'x ab y';
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  const n = walker.nextNode();
  const r = document.createRange(); r.setStart(n, 1); r.setEnd(n, 5);
  const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
});
const htmlCode = await page.evaluate(() => window.__mnInline('code', 'pbmd-1'));
ok('MD-C5 行内代码：空白外置存出 <code>ab</code>', htmlCode.includes('<code>ab</code>') && !htmlCode.includes('<code> ab'), htmlCode);

// ---------- D-1：斜杠触发抑制 ----------
await openMemo('pb-d1a');
await clickBlockCenter('pbd1-1');
await page.keyboard.type('https://abc.com/x', { delay: 12 });
await page.waitForTimeout(400);
let panel = await page.evaluate(() => !!document.getElementById('slash-panel'));
ok('D-1 手打 URL 全程不弹斜杠面板', !panel);
await openMemo('pb-d1b');
await clickBlockCenter('pbd1-1');
await page.keyboard.type('/' + 'a'.repeat(31), { delay: 5 });
await page.waitForTimeout(400);
panel = await page.evaluate(() => !!document.getElementById('slash-panel'));
ok('D-1 查询超 30 字后面板关闭', !panel);
await openMemo('pb-d1c');
await clickBlockCenter('pbd1-1');
await page.keyboard.type('/加', { delay: 12 });
await page.waitForTimeout(500);
panel = await page.evaluate(() => !!document.getElementById('slash-panel'));
ok('D-1 对照：正常斜杠查询仍弹面板', panel);

await browser.close();
L(fails ? `RESULT: ${fails} FAIL` : 'RESULT: ALL PASS');
process.exit(fails ? 1 : 0);
