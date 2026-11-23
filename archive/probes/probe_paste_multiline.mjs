// 探针（Rust）：粘贴多行纯文本——审计 audit_markdown_slash
// §3.1 双侧实证：原版按行拆块、换行零丢失；Rust 单块且首个
// \n 丢失（黏连）。断言：4 行粘贴 → 存储块数/各行文本逐行
// 一致、任务列表预览成组（2 个 checkbox 勾选态正确）；
// `# 标题行\n正文` → 首块转 heading、次块仍段落（不整块
// 并入）。Chromium 口径。用法：node probe_paste_multiline.mjs [base]
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
  const enc = new TextEncoder();
  const chunks = []; const central = []; let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name); const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const crc = crc32(data); const size = data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true);
    lh.setUint16(26, name.length, true);
    chunks.push(Buffer.from(lh.buffer), Buffer.from(name), Buffer.from(data));
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, size, true); ch.setUint32(24, size, true);
    ch.setUint16(28, name.length, true); ch.setUint32(42, offset, true);
    central.push(Buffer.from(ch.buffer), Buffer.from(name));
    offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const now = new Date();
const ts = now.toISOString();
const emptyPara = (id) => ({ id, type: 'paragraph', children: [{ text: '' }] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'paste1', title: '粘贴任务', pinned: false, createdAt: ts, updatedAt: ts, doc: [emptyPara('p-empty')] },
    { id: 'paste2', title: '粘贴标题', pinned: false, createdAt: ts, updatedAt: ts, doc: [emptyPara('p-empty2')] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const readDoc = (page, title) => page.evaluate(async (t) => {
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('mynote-web', 1);
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const raw = await new Promise((res, rej) => {
    const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error);
  });
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === t);
  if (!m) return null;
  const textOf = (n) => (n.children || []).map((c) => c.text || '').join('');
  return m.doc.map((b) => ({ type: b.type, text: textOf(b) }));
}, title);

async function firePaste(page, text) {
  await page.evaluate((t) => {
    const el = document.querySelector('.editor-body [data-bid]');
    el.focus();
    const sel = window.getSelection();
    const r = document.createRange();
    r.selectNodeContents(el);
    r.collapse(true);
    sel.removeAllRanges();
    sel.addRange(r);
    const ev = new Event('paste', { bubbles: true, cancelable: true });
    Object.defineProperty(ev, 'clipboardData', { value: { getData: (f) => (f === 'text/plain' ? t : ''), items: [], files: [] } });
    el.dispatchEvent(ev);
  }, text);
}

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'paste_multi.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });

// ---------- 案例 1：任务列表 4 行 ----------
await page.goto(base + '?open=paste1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(800);
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  const r = el.getBoundingClientRect();
  window.__pt = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
const pt1 = await page.evaluate(() => window.__pt);
await page.mouse.click(pt1.x, pt1.y);
await page.waitForTimeout(300);
await firePaste(page, '- [] 未完任务\n- [x] 已完任务\n\n第二段 **粗体** 测试');
await page.waitForTimeout(1200);
const doc1 = await readDoc(page, '粘贴任务');
L('DOC1:', JSON.stringify(doc1));
ok('粘贴后拆为 4 块', !!doc1 && doc1.length === 4, `n=${doc1?.length}`);
ok('各行文本逐行一致（首个换行不丢）', eq((doc1 || []).map((b) => b.text), ['- [] 未完任务', '- [x] 已完任务', '', '第二段 **粗体** 测试']), JSON.stringify((doc1 || []).map((b) => b.text)));
// 预览成组：点第三块（空段）移开焦点，前两块应成任务列表预览
const boxes = await page.evaluate(() => {
  const els = [...document.querySelectorAll('.editor-body [data-bid], .editor-body [data-bids]')];
  const target = els[2] || els[els.length - 1];
  if (target) {
    const r = target.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }
  return null;
});
if (boxes) { await page.mouse.click(boxes.x, boxes.y); await page.waitForTimeout(700); }
// 预览口径以原版 vendored marked 实测输出为 oracle：
// `- [] 未完任务` → 普通 li（[] 字面保留、无 checkbox），
// `- [x] 已完任务` → 任务项（checkbox 已勾）；两项成一个 ul。
const prev = await page.evaluate(() => {
  const ul = document.querySelector('.editor-body ul');
  const lis = ul ? [...ul.querySelectorAll('li')].map((li) => li.textContent.trim()) : [];
  const cbs = [...document.querySelectorAll('.editor-body input[type="checkbox"]')].map((c) => c.checked);
  const strong = document.querySelector('.editor-body strong')?.textContent || '';
  return { lis, cbs, strong };
});
L('PREVIEW:', JSON.stringify(prev));
ok('任务列表预览成组：ul 含 2 项', prev.lis.length === 2, JSON.stringify(prev.lis));
ok('已完项 checkbox 已勾（marked 口径共 1 个）', eq(prev.cbs, [true]), JSON.stringify(prev.cbs));
ok('第三段行内预览 strong 正确', prev.strong.includes('粗体'), prev.strong);

// ---------- 案例 2：# 标题行 + 正文 ----------
await page.goto(base + '?open=paste2', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(800);
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  const r = el.getBoundingClientRect();
  window.__pt = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
const pt2 = await page.evaluate(() => window.__pt);
await page.mouse.click(pt2.x, pt2.y);
await page.waitForTimeout(300);
await firePaste(page, '# 标题行\n后面一行正文');
await page.waitForTimeout(1200);
const doc2 = await readDoc(page, '粘贴标题');
L('DOC2:', JSON.stringify(doc2));
ok('标题案例拆为 2 块', !!doc2 && doc2.length === 2, `n=${doc2?.length}`);
ok('首块转 heading 且只含标题行', !!doc2 && doc2[0].type === 'heading' && doc2[0].text === '标题行', JSON.stringify(doc2?.[0]));
ok('次块仍为段落含正文', !!doc2 && doc2[1]?.type === 'paragraph' && doc2[1]?.text === '后面一行正文', JSON.stringify(doc2?.[1]));

await browser.close();
L(fails ? `RESULT: ${fails} FAIL` : 'RESULT: ALL PASS');
process.exit(fails ? 1 : 0);
