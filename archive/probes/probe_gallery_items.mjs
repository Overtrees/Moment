// 探针（Rust）：C-08 图库 items 对象形态——原版实写形态
// {fileId}/{url} 对象在 Rust 渲染被丢弃（非空图库成空态）。
// 断言：对象形态渲染出图（fileId→blob、url→直链）、字符串
// 形态不回归、编辑保存后 attrs.items 逐字无损往返。
// Chromium 口径。用法：node probe_gallery_items.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

// ---------- stored zip 内存夹具（与 probe_export_flow 同构） ----------
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
const PNG1_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const png1 = Buffer.from(PNG1_B64, 'base64');
const DATA_PNG = 'data:image/png;base64,' + PNG1_B64;
const OBJ_ITEMS = [
  { fileId: 'att1' },
  { url: DATA_PNG },
  { fileId: 'att2' },
  { url: 'https://example.com/pic.png' },
  { url: 'https://example.com/both.png', fileId: 'att2' },
];
const doc = [
  { id: 'g-obj', type: 'gallery', attrs: { items: OBJ_ITEMS }, children: [] },
  { id: 'g-str', type: 'gallery', attrs: { items: ['att1', 'att2'] }, children: [] },
  { id: 'tail', type: 'paragraph', children: [{ text: '尾段' }] },
];
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'gal1', title: '图库对象形态', pinned: false, createdAt: ts, updatedAt: ts, doc },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { att1: { name: '图一.png', type: 'image/png' }, att2: { name: '图二.png', type: 'image/png' } } }) },
  { name: 'attachments/att1', data: png1 },
  { name: 'attachments/att2', data: png1 },
]);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'gallery_items.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.goto(base + '?open=gal1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(1500);

const render = await page.evaluate(() => {
  const gals = [...document.querySelectorAll('.editor-body .atomic[data-type="gallery"]')];
  return gals.map((g) => ({
    imgs: [...g.querySelectorAll('img')].map((i) => i.getAttribute('src') || ''),
    placeholder: !!g.querySelector('.atomic-placeholder'),
  }));
});
L('RENDER:', JSON.stringify(render, null, 1));
ok('对象形态图库渲染 5 张图', render[0] && render[0].imgs.length === 5, `n=${render[0]?.imgs.length}`);
ok('对象形态图库无空态占位', render[0] && !render[0].placeholder);
ok('item1 {fileId} → blob 图', !!render[0]?.imgs[0]?.startsWith('blob:'), render[0]?.imgs[0]?.slice(0, 30));
ok('item2 {url data:} → 直链图', render[0]?.imgs[1] === DATA_PNG, render[0]?.imgs[1]?.slice(0, 30));
ok('item3 {fileId} → blob 图', !!render[0]?.imgs[2]?.startsWith('blob:'), render[0]?.imgs[2]?.slice(0, 30));
ok('item4 {url https} → 直链图', render[0]?.imgs[3] === 'https://example.com/pic.png', render[0]?.imgs[3]);
ok('item5 {url+fileId} → fileId 优先（blob）', !!render[0]?.imgs[4]?.startsWith('blob:'), render[0]?.imgs[4]?.slice(0, 30));
ok('字符串形态图库渲染 2 张图', render[1] && render[1].imgs.length === 2 && render[1].imgs.every((s) => s.startsWith('blob:')), JSON.stringify(render[1]?.imgs.map((s) => s.slice(0, 10))));

// 编辑保存往返：尾段回车拆块触发 persist，再读 IDB 比对 items
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.editor-body [data-bid]')].pop();
  el.scrollIntoView({ block: 'center' });
  const r = el.getBoundingClientRect();
  window.__tailPt = { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
const pt = await page.evaluate(() => window.__tailPt);
await page.mouse.click(pt.x, pt.y);
await page.waitForTimeout(400);
await page.keyboard.press('Enter');
await page.waitForTimeout(1000);
const stored = await page.evaluate(async () => {
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
  const m = (memos || []).find((x) => x.title === '图库对象形态');
  const g = m && m.doc.find((b) => b.id === 'g-obj');
  return g ? g.attrs.items : null;
});
const canon = (v) => JSON.stringify(v, (k, val) => {
  if (val && typeof val === 'object' && !Array.isArray(val)) {
    return Object.fromEntries(Object.entries(val).sort(([a], [b]) => a.localeCompare(b)));
  }
  return val;
});
ok('保存后 attrs.items 逐字无损（深等值+数组序）', canon(stored) === canon(OBJ_ITEMS), JSON.stringify(stored)?.slice(0, 160));
await browser.close();
L(fails ? `RESULT: ${fails} FAIL` : 'RESULT: ALL PASS');
process.exit(fails ? 1 : 0);
