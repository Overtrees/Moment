// 复现探针：PDF 导出成功（真实 window.open）后原页遮罩残留定罪
// 用法: node probe_pdf_overlay.mjs <base> [pdf|html]
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8200/';
const mode = process.argv[3] || 'pdf';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

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

const ts = new Date().toISOString();
const PNG1_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const png1 = Buffer.from(PNG1_B64, 'base64');
const para = (bid, text) => ({ id: bid, type: 'paragraph', children: [{ text }] });
const richDoc = [
  { id: 'x-head', type: 'heading', attrs: { level: 2 }, children: [{ text: '导出小标题' }] },
  { id: 'x-p1', type: 'paragraph', children: [{ text: '普通段落 ' }, { text: '加粗', bold: true }, { text: ' 结尾文字。' }] },
  { id: 'x-img', type: 'image', attrs: { fileId: 'img1' }, children: [] },
];
for (let i = 0; i < 8; i++) richDoc.push(para('x-fill' + i, '填充段落 ' + i + '：' + '内容文字'.repeat(10)));
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'rich1', title: '打印测试', pinned: false, createdAt: ts, updatedAt: ts, doc: richDoc },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { img1: { name: '图一.png', type: 'image/png' } } }) },
  { name: 'attachments/img1', data: png1 },
]);

const DUMP = () => {
  const cx = innerWidth / 2, cy = Math.min(innerHeight - 40, 500);
  const hit = document.elementFromPoint(cx, cy);
  const fab = document.querySelector('.editor-fab.right');
  const fr = fab ? fab.getBoundingClientRect() : null;
  const hitFab = fr ? document.elementFromPoint(fr.x + fr.width / 2, fr.y + fr.height / 2) : null;
  const covering = [];
  for (const el of document.querySelectorAll('body *')) {
    const cs = getComputedStyle(el);
    if (cs.position !== 'fixed') continue;
    const r = el.getBoundingClientRect();
    if (r.width > innerWidth * 0.8 && r.height > innerHeight * 0.8) {
      covering.push({ cls: String(el.className).slice(0, 60), tag: el.tagName, opacity: cs.opacity, pe: cs.pointerEvents, z: cs.zIndex, display: cs.display, vis: cs.visibility });
    }
  }
  const q = (s) => { const e = document.querySelector(s); if (!e) return null; const cs = getComputedStyle(e); return { opacity: cs.opacity, pe: cs.pointerEvents, display: cs.display, style: e.getAttribute('style') || '' }; };
  return {
    hitCenter: hit ? hit.tagName + '.' + String(hit.className).slice(0, 40) : 'none',
    hitInBody: !!(hit && hit.closest && hit.closest('.editor-body')),
    hitFab: hitFab ? hitFab.tagName + '.' + String(hitFab.className).slice(0, 40) : 'none',
    covering,
    scrim: q('.menu-scrim'),
    panel: q('.editor-export-panel'),
    menuPanel: !!document.querySelector('.editor-menu-panel'),
    diagTail: (localStorage.getItem('mynote_diag_v1') || '').slice(-600),
  };
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const popups = [];
ctx.on('page', (p) => { popups.push(p); });
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'export_rich.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.goto(base + '?open=rich1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(900);

await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(400);
await page.click(`[data-export-format="${mode}"]`);
console.log('clicked export', mode);

// 等 Diag 出现 doc 行（pdf）或 toast（html 下载）
if (mode === 'pdf') {
  await page.waitForFunction(() => (localStorage.getItem('mynote_diag_v1') || '').includes('export pdf doc'), null, { timeout: 25000 }).catch(() => console.log('WARN: no doc line in diag'));
}
await page.waitForTimeout(2500);
console.log('popups:', popups.length);
await page.bringToFront();
await page.waitForTimeout(1000);
let d = await page.evaluate(DUMP);
console.log('DUMP after export:\n' + JSON.stringify(d, null, 1));

// 尝试点正文 + 打字
const pt = await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid="x-p1"]');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
if (pt) {
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(300);
  await page.keyboard.type('Z');
  await page.waitForTimeout(700);
  const alive = await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-bid="x-p1"]');
    return el ? el.innerText.includes('Z') : false;
  });
  console.log('typing lands in body:', alive);
}
// Esc 后再 dump
await page.keyboard.press('Escape');
await page.waitForTimeout(700);
d = await page.evaluate(DUMP);
console.log('DUMP after Esc: scrim=' + JSON.stringify(d.scrim) + ' panel=' + JSON.stringify(d.panel) + ' hitCenter=' + d.hitCenter + ' hitInBody=' + d.hitInBody);
// 前台再等 8 秒看是否自愈
await page.waitForTimeout(8000);
d = await page.evaluate(DUMP);
console.log('DUMP after +8s foreground: scrim=' + JSON.stringify(d.scrim) + ' panel=' + JSON.stringify(d.panel) + ' hitCenter=' + d.hitCenter + ' hitInBody=' + d.hitInBody);

await browser.close();
