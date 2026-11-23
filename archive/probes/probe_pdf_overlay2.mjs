// 复现探针 V2：桌面宽度 + 弹窗驻留 + 关弹窗后返回，采样覆盖层状态时间线
// 用法: node probe_pdf_overlay2.mjs <base> [dwellSec]
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8200/';
const dwell = parseInt(process.argv[3] || '30', 10);
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

const STATE = () => {
  const q = (s) => { const e = document.querySelector(s); if (!e) return null; const cs = getComputedStyle(e); return { opacity: cs.opacity, pe: cs.pointerEvents, style: (e.getAttribute('style') || '').slice(0, 80) }; };
  const cx = innerWidth / 2, cy = Math.min(innerHeight - 40, 500);
  const hit = document.elementFromPoint(cx, cy);
  return {
    vis: document.visibilityState,
    scrim: q('.menu-scrim'),
    panel: q('.editor-export-panel'),
    menuPanel: !!document.querySelector('.editor-menu-panel'),
    sheetScrim: q('.sheet-scrim'),
    hitCenter: hit ? hit.tagName + '.' + String(hit.className).slice(0, 40) : 'none',
    hitInBody: !!(hit && hit.closest && hit.closest('.editor-body')),
  };
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: false, acceptDownloads: true });
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
console.log('pre-click state:', JSON.stringify(await page.evaluate(STATE)));
await page.click('[data-export-format="pdf"]');
console.log('clicked pdf at', new Date().toISOString());

// 隐藏期采样（不切回前台）
for (const wait of [1000, 2000, 4000]) {
  await page.waitForTimeout(wait);
  console.log(`t+~${wait}ms sample:`, JSON.stringify(await page.evaluate(STATE)), 'popups:', popups.length);
}
// 在弹窗里驻留 dwell 秒（模拟判别轮在新页签查看/去做对照）
if (popups.length) {
  await popups[0].bringToFront();
  await popups[0].waitForTimeout(1000);
  const ptxt = await popups[0].evaluate(() => document.title + ' len=' + (document.body ? document.body.innerHTML.length : -1)).catch((e) => 'popup eval fail: ' + e);
  console.log('popup content:', ptxt);
}
await page.waitForTimeout(dwell * 1000);
console.log(`after ${dwell}s dwell (opener still hidden):`, JSON.stringify(await page.evaluate(STATE)));
// 关掉弹窗，回到原页
if (popups.length) { await popups[0].close().catch(() => {}); }
await page.bringToFront();
await page.waitForTimeout(1200);
console.log('after return:', JSON.stringify(await page.evaluate(STATE)));
// 点正文 + 打字
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
await page.keyboard.press('Escape');
await page.waitForTimeout(700);
console.log('after Esc:', JSON.stringify(await page.evaluate(STATE)));
await page.waitForTimeout(8000);
console.log('after +8s:', JSON.stringify(await page.evaluate(STATE)));
const diag = await page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || '').slice(-400));
console.log('diag tail:', diag);
await browser.close();
