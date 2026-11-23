// 复现探针 V3：rAF 饥饿（模拟遮挡/隐藏页：requestAnimationFrame 永不触发）
// 下导出面板开启态 export_closing 悬挂 → 点 PDF 后关闭被早退吞掉 → 遮罩残留
// 用法: node probe_pdf_overlay3.mjs <base>
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8200/';
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
  const q = (s) => { const e = document.querySelector(s); if (!e) return null; const cs = getComputedStyle(e); return { opacity: cs.opacity, pe: cs.pointerEvents, style: (e.getAttribute('style') || '').slice(0, 60) }; };
  const cx = innerWidth / 2, cy = Math.min(innerHeight - 40, 500);
  const hit = document.elementFromPoint(cx, cy);
  const fab = document.querySelector('.editor-fab.right');
  const fr = fab ? fab.getBoundingClientRect() : null;
  const hitFab = fr ? document.elementFromPoint(fr.x + fr.width / 2, fr.y + fr.height / 2) : null;
  return {
    scrim: q('.menu-scrim'),
    panel: q('.editor-export-panel'),
    hitCenter: hit ? hit.tagName + '.' + String(hit.className).slice(0, 40) : 'none',
    hitInBody: !!(hit && hit.closest && hit.closest('.editor-body')),
    hitFab: hitFab ? hitFab.tagName + '.' + String(hitFab.className).slice(0, 40) : 'none',
  };
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const popups = [];
ctx.on('page', (p) => { popups.push(p); });
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
// rAF 饥饿：回调永不触发（模拟页面被遮挡/隐藏时合成器停摆）
await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });

await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'export_rich.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
// 注：本探针以 rAF 饥饿为前提，waitForFunction 必须用定时轮询
// （默认 raf 轮询会被自家 init script 堵死，与应用无关）。
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000, polling: 500 });
await page.goto(base + '?open=rich1', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(900);

await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(600);
console.log('state after panel open (rAF starved):', JSON.stringify(await page.evaluate(STATE)));
await page.click('[data-export-format="pdf"]');
console.log('clicked pdf');
await page.waitForFunction(() => (localStorage.getItem('mynote_diag_v1') || '').includes('export pdf doc'), null, { timeout: 25000, polling: 500 }).catch(() => console.log('WARN: no doc line'));
await page.waitForTimeout(2500);
console.log('popups:', popups.length);
await page.bringToFront();
await page.waitForTimeout(1000);
console.log('STATE after export+return:', JSON.stringify(await page.evaluate(STATE)));
// 点正文中心（应命中 scrim → 触发其 onclick 关闭）后复查
await page.mouse.click(393 / 2, 500);
await page.waitForTimeout(1200);
console.log('STATE after scrim click:', JSON.stringify(await page.evaluate(STATE)));
await page.keyboard.press('Escape');
await page.waitForTimeout(700);
console.log('STATE after Esc:', JSON.stringify(await page.evaluate(STATE)));
const diag = await page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || '').slice(-350));
console.log('diag tail:', diag);
await browser.close();
