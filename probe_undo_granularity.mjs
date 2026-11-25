// 探针（批 4 B-4）：撤销粒度与打字落模型四组——
// ① 爆发粒度：爆发 A/爆发 B/退格爆发 C 各成一个撤销步，
//    Ctrl+Z 逐步回退、Ctrl+Y 逐步重做（旧行为：普通打字
//    不落模型，一次 Ctrl+Z 回退整段数分钟输入）；
// ② 块内退格爆发同口径（并入 ① 的 C 步验证）；
// ③ 字数即时更新：打字后 ≤300ms 内标题坞字数刷新（旧
//    行为：doc 信号冻结、纯打字会话内字数不变），且
//    Diag 出现 inputSync 节流行（轮询等落盘，批 10 T-F
//    1s 节流口径）；
// ④ 光标稳定性（确诊报告 §3.3 头号风险坐实）：inputSync
//    落模型后，打字中块的 DOM 节点身份不变、光标偏移不
//    变（编辑态块非受控渲染的实证断言）；
// ⑤ 换篇兜底：打字后立即离开（<80ms 防抖未发火口径），
//    关闭路径全量 sync 兜底落盘，重开文本完整。
// Chromium 口径。用法：node probe_undo_granularity.mjs [base]
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
const memo = (id, title, doc) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('pu-w', '撤销探针字数', [para('puw-1', 'hello world')]),
    memo('pu-g', '撤销探针粒度', [para('pug-1', '')]),
    memo('pu-t', '撤销探针换篇', [para('put-1', 'start-')]),
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const readDoc = (page, title) => page.evaluate(async (t) => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
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
  return m.doc.map((b) => ({ type: b.type, text: textOf(b) }));
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
await page.setInputFiles('#file-import', { name: 'undo_granularity.zip', mimeType: 'application/zip', buffer: fixtureZip });
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
async function caretOffsetIn(bid) {
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
const blockText = (bid) => page.evaluate((b) => {
  const el = document.querySelector('[data-bid="' + b + '"]');
  return el ? el.textContent : null;
}, bid);
const wordsShown = () => page.evaluate(() => {
  const el = document.querySelector('.editor-title-meta');
  if (!el) return -1;
  const m = el.textContent.match(/(\d+)字/);
  return m ? Number(m[1]) : -1;
});
const diagText = () => page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
const count = (s, sub) => s.split(sub).length - 1;
// Diag 落盘 1s 节流（批 10 T-F）：正向断言轮询等落盘（同
// probe_root_dim 治理口径），不放宽判据。
async function waitDiag(pred, timeoutMs = 6000) {
  const t0 = Date.now();
  let txt = await diagText();
  while (!pred(txt) && Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(200);
    txt = await diagText();
  }
  return txt;
}

// ---------- ③+④：字数即时更新 / 光标与节点稳定性 / Diag 节流行 ----------
await openMemo('pu-w');
const w0 = await wordsShown();
ok('③ 前置：初始字数 11', w0 === 11, 'words=' + w0);
const diagBefore = count(await diagText(), 'input sync applied');
await setCaret('puw-1', 5);
await page.evaluate(() => { window.__ugEl = document.querySelector('[data-bid="puw-1"]'); });
await page.keyboard.type('XYZ', { delay: 30 });
const tType1 = Date.now();
// 字数刷新计时：末键后轮询（25ms 步进），≤300ms 判据
let wordsMs = -1;
while (Date.now() - tType1 < 300) {
  if ((await wordsShown()) === 14) { wordsMs = Date.now() - tType1; break; }
  await page.waitForTimeout(25);
}
if (wordsMs < 0 && (await wordsShown()) === 14) wordsMs = Date.now() - tType1;
ok('③ 打字后 ≤300ms 字数刷新 11→14', wordsMs >= 0 && wordsMs <= 300, 'ms=' + wordsMs + ' words=' + (await wordsShown()));
// 等 inputSync 落定（80ms 防抖 + 消息往返）后再验稳定性
await page.waitForTimeout(600);
const sameNode = await page.evaluate(() => document.querySelector('[data-bid="puw-1"]') === window.__ugEl);
ok('④ inputSync 后打字块 DOM 节点身份不变', sameNode === true);
const coff = await caretOffsetIn('puw-1');
ok('④ inputSync 后光标偏移不变（5+3=8）', coff === 8, 'off=' + coff);
const txtW = await blockText('puw-1');
ok('④ 打字块文本完整（helloXYZ world）', txtW === 'helloXYZ world', JSON.stringify(txtW));
const diagAfter = await waitDiag((t) => count(t, 'input sync applied') > diagBefore);
ok('③ Diag 出现 input sync applied 节流行', count(diagAfter, 'input sync applied') > diagBefore,
  'before=' + diagBefore + ' after=' + count(diagAfter, 'input sync applied'));

// ---------- ①+②：爆发粒度（A 打字 / B 打字 / C 退格） ----------
await openMemo('pu-g');
await clickBlockCenter('pug-1');
await page.keyboard.type('abcdef', { delay: 25 });
await page.waitForTimeout(1100); // 与下一爆发拉开 >600ms 合并窗
await page.keyboard.type('XYZ', { delay: 25 });
await page.waitForTimeout(1100);
let txtG = await blockText('pug-1');
ok('① 前置：两爆发落定文本 abcdefXYZ', txtG === 'abcdefXYZ', JSON.stringify(txtG));
await page.keyboard.press('Backspace');
await page.keyboard.press('Backspace');
await page.keyboard.press('Backspace');
await page.waitForTimeout(1100);
txtG = await blockText('pug-1');
ok('② 前置：退格爆发删 XYZ → abcdef', txtG === 'abcdef', JSON.stringify(txtG));
await page.keyboard.press('Control+z');
await page.waitForTimeout(600);
txtG = await blockText('pug-1');
ok('② Ctrl+Z 一步还原整个退格爆发（abcdefXYZ）', txtG === 'abcdefXYZ', JSON.stringify(txtG));
await page.keyboard.press('Control+z');
await page.waitForTimeout(600);
txtG = await blockText('pug-1');
ok('① Ctrl+Z 一步只回退爆发 B（abcdef）', txtG === 'abcdef', JSON.stringify(txtG));
await page.keyboard.press('Control+z');
await page.waitForTimeout(600);
txtG = await blockText('pug-1');
ok('① Ctrl+Z 一步只回退爆发 A（空）', txtG === '', JSON.stringify(txtG));
await page.keyboard.press('Control+y');
await page.waitForTimeout(600);
txtG = await blockText('pug-1');
ok('① Ctrl+Y 逐步重做爆发 A（abcdef）', txtG === 'abcdef', JSON.stringify(txtG));
await page.keyboard.press('Control+y');
await page.waitForTimeout(600);
txtG = await blockText('pug-1');
ok('① Ctrl+Y 逐步重做爆发 B（abcdefXYZ）', txtG === 'abcdefXYZ', JSON.stringify(txtG));
await page.keyboard.press('Control+y');
await page.waitForTimeout(600);
txtG = await blockText('pug-1');
ok('② Ctrl+Y 逐步重做退格爆发（abcdef）', txtG === 'abcdef', JSON.stringify(txtG));
const docG = await readDoc(page, '撤销探针粒度');
ok('① 撤销/重做后持久副本与界面一致（abcdef）', !!docG && docG.map((b) => b.text).join('') === 'abcdef', JSON.stringify(docG));

// ---------- ⑤：换篇兜底 ----------
await openMemo('pu-t');
await clickBlockCenter('put-1');
await setCaret('put-1', 6);
await page.keyboard.type('tail', { delay: 20 });
// 不等防抖（80ms）与落盘：立即离开编辑页，靠关闭路径兜底
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.waitForTimeout(800);
const docT = await readDoc(page, '撤销探针换篇');
ok('⑤ 立即离开后持久副本含尾巴文本（start-tail）', !!docT && docT.map((b) => b.text).join('') === 'start-tail', JSON.stringify(docT));
await openMemo('pu-t');
const txtT = await blockText('put-1');
ok('⑤ 重开文本完整（start-tail）', txtT === 'start-tail', JSON.stringify(txtT));

await browser.close();
L(fails ? `RESULT: ${fails} FAIL` : 'RESULT: ALL PASS');
process.exit(fails ? 1 : 0);
