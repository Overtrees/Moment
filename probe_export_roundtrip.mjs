// 导出真实弹窗往返探针（probe_export_flow 的补充）：不桩
// window.open，让应用真的开出弹窗页（仅以 context 级 init
// script 记录 print 调用并派发 beforeprint/afterprint，避免
// 无头打印预览阻塞）；断言弹窗文档完整、关弹窗后 opener 页
// 体检与导出前逐项一致。Chromium 专用（WebKit MiniBrowser
// 缺 libgstreamer 无法在本机启动）。
// 用法：node probe_export_roundtrip.mjs [rustBase] [origBase]
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const RUST = process.argv[2] || 'http://localhost:8120/';
const ORIG = process.argv[3] || 'http://localhost:8119/Moment.html';
const CHROME = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};

const SNAP = () => {
  const blocks = [...document.querySelectorAll('.editor-body [data-bid], .editor-body [data-blockid]')].slice(0, 30).map(el => {
    const r = el.getBoundingClientRect();
    return { bid: el.getAttribute('data-bid') || el.getAttribute('data-blockid'), x: Math.round(r.x * 10) / 10, y: Math.round(r.y * 10) / 10, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10 };
  });
  const hit = document.elementFromPoint(innerWidth / 2, Math.min(innerHeight - 40, 500));
  return {
    blocks,
    overlays: [...document.querySelectorAll('.menu-scrim,.sheet-scrim,.editor-export-panel,.editor-menu-panel,.bg-sheet')].length,
    hitInBody: !!(hit && hit.closest && hit.closest('.editor-body')),
    hitLabel: hit ? hit.tagName + '.' + String(hit.className).slice(0, 30) : 'none',
  };
};

function diffSnaps(s0, s1) {
  const diffs = [];
  if (s1.blocks.length !== s0.blocks.length) diffs.push(`count ${s0.blocks.length}->${s1.blocks.length}`);
  const n = Math.min(s0.blocks.length, s1.blocks.length);
  for (let i = 0; i < n; i++) {
    if (s0.blocks[i].bid !== s1.blocks[i].bid) { diffs.push(`bid[${i}]`); continue; }
    if (Math.abs(s0.blocks[i].y - s1.blocks[i].y) > 1.5) diffs.push(`${s0.blocks[i].bid}.y`);
    if (Math.abs(s0.blocks[i].x - s1.blocks[i].x) > 1.5) diffs.push(`${s0.blocks[i].bid}.x`);
    if (Math.abs(s0.blocks[i].h - s1.blocks[i].h) > 1.5) diffs.push(`${s0.blocks[i].bid}.h`);
    if (Math.abs(s0.blocks[i].w - s1.blocks[i].w) > 1.5) diffs.push(`${s0.blocks[i].bid}.w`);
  }
  return diffs;
}

const browser = await chromium.launch({ executablePath: CHROME, args: ['--no-sandbox'] });

async function roundTrip(label, base, openEditor, clickPdf) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  await ctx.addInitScript(() => {
    window.__prints = [];
    const origPrint = window.print.bind(window);
    window.print = () => {
      window.__prints.push(location.href.slice(0, 30));
      window.dispatchEvent(new Event('beforeprint'));
      window.dispatchEvent(new Event('afterprint'));
    };
    window.__origPrint = origPrint;
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  const popupPromise = ctx.waitForEvent('page', { timeout: 20000 }).catch(() => null);
  await openEditor(page);
  const s0 = await page.evaluate(SNAP);
  const popup = await clickPdf(page, popupPromise);
  ok(`${label} 真实弹窗已打开`, !!popup);
  if (popup) {
    await popup.waitForLoadState('load').catch(() => {});
    await popup.waitForTimeout(800);
    const pinfo = await popup.evaluate(() => ({
      title: document.title,
      hasShell: !!document.querySelector('.mynote-export-shell'),
      hasHeader: !!document.querySelector('.mynote-export-header'),
      imgs: document.querySelectorAll('.editor-body img').length,
      prints: window.__prints || [],
      textStart: (document.querySelector('.editor-body')?.innerText || '').slice(0, 30),
    })).catch((e) => ({ err: String(e) }));
    ok(`${label} 弹窗文档为导出文档（shell+页眉）`, !!pinfo.hasShell && !!pinfo.hasHeader, JSON.stringify(pinfo).slice(0, 160));
    ok(`${label} 弹窗 print() 已调用`, (pinfo.prints || []).length >= 1, JSON.stringify(pinfo.prints));
    // 模拟用户：取消打印（afterprint 已由桩派发）→ 关弹窗页签
    await popup.close().catch(() => {});
    await page.waitForTimeout(600);
    await page.bringToFront().catch(() => {});
    await page.waitForTimeout(400);
  }
  const s1 = await page.evaluate(SNAP);
  const diffs = diffSnaps(s0, s1);
  ok(`${label} 关弹窗后块几何与导出前一致`, diffs.length === 0, diffs.join(';') || 'identical');
  ok(`${label} 关弹窗后无残留遮罩/面板`, s1.overlays === 0, String(s1.overlays));
  ok(`${label} 关弹窗后正文中心命中正文`, s1.hitInBody, s1.hitLabel);
  ok(`${label} 全程无 pageerror`, errors.length === 0, errors.join(' | ').slice(0, 200));
  await ctx.close();
  return page;
}

// ---------- Rust：导入夹具 → 打开 → 真实往返 ----------
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
  { id: 'x-todo1', type: 'todo', attrs: { checked: true }, children: [{ text: '已完成待办' }] },
  { id: 'x-img', type: 'image', attrs: { fileId: 'img1' }, children: [] },
  para('x-code', '```js\nconst a = 1;\n```'),
];
for (let i = 0; i < 10; i++) richDoc.push(para('x-fill' + i, '填充段落 ' + i + '：' + '内容文字'.repeat(10)));
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [{ id: 'rich1', title: '打印测试', pinned: false, createdAt: ts, updatedAt: ts, doc: richDoc }], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { img1: { name: '图一.png', type: 'image/png' } } }) },
  { name: 'attachments/img1', data: png1 },
]);

await roundTrip('RUST', RUST,
  async (page) => {
    await page.goto(RUST, { waitUntil: 'load' });
    await page.waitForSelector('.list-item', { timeout: 20000 });
    await page.$eval('h1.page-title', (e) => e.click());
    await page.waitForSelector('.page-content', { timeout: 8000 });
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
    await page.setInputFiles('#file-import', { name: 'export_rich.zip', mimeType: 'application/zip', buffer: fixtureZip });
    await page.waitForSelector('.backup-modal', { timeout: 8000 });
    await page.click('.backup-modal .backup-btn.primary');
    await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
    await page.goto(RUST + '?open=rich1', { waitUntil: 'load' });
    await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
    await page.waitForTimeout(900);
  },
  async (page, popupPromise) => {
    await page.click('.editor-fab.right');
    await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
    await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
    await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
    await page.waitForTimeout(400);
    await page.click('[data-export-format="pdf"]');
    return popupPromise;
  });

// ---------- 导出文档屏幕渲染量测（两份已抓文档，Chromium） ----------
for (const [label, file] of [['RUST文档', '/tmp/export_rust.html'], ['原版文档', '/tmp/export_orig.html']]) {
  if (!fs.existsSync(file)) { console.log(label, '无文件，跳过'); continue; }
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
  const page = await ctx.newPage();
  await page.goto('file://' + file, { waitUntil: 'load' });
  await page.waitForTimeout(600);
  const m = await page.evaluate(() => {
    const q = (s) => document.querySelector(s);
    const shell = q('.mynote-export-shell');
    const header = q('.mynote-export-header');
    const body = q('.editor-body');
    const first = body ? body.firstElementChild : null;
    const cs = (el, p) => el ? getComputedStyle(el).getPropertyValue(p) : null;
    return {
      横向溢出: document.documentElement.scrollWidth - window.innerWidth,
      shellPadding: shell ? cs(shell, 'padding') : null,
      页眉高: header ? Math.round(header.getBoundingClientRect().height) : null,
      正文字号: cs(body, 'font-size'),
      首块: first ? first.tagName + '.' + String(first.className).slice(0, 36) : null,
      首块Y: first ? Math.round(first.getBoundingClientRect().y) : null,
    };
  });
  console.log(label, JSON.stringify(m));
  await ctx.close();
}

await browser.close();
console.log(failures ? `PROBE FAILURES: ${failures}` : 'PROBE ALL PASS');
process.exit(failures ? 1 : 0);
