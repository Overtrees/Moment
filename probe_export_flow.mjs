// 导出流程专项探针（2026-11-21 导出二次根治）：
// 与 smoke-rustweb-export（内容口径）分工——本探针只测「流程」：
//  1) PDF 的 window.open 是否落在点击事件分发内（手势任务）执行：
//     capture 阶段置位 __inClick、window 冒泡末端清零，open 桩
//     记录调用瞬间 flag。处理函数内同步开窗 => true；spawn 的
//     future 首轮 poll（微任务，已出分发）开窗 => false。
//  2) 调用序 open→doc.open→write→doc.close→print（等图后）。
//  3) afterprint + visibility hidden→visible + print 媒体切换后，
//     opener 页体检：块几何/无残留遮罩/body 与 root 类样式/
//     正文命中/可打字且桥同步/scrollY 保持——逐项与导出前一致。
//  4) 三格式（pdf/markdown/html）各一轮。
// 用法：node probe_export_flow.mjs [base] [engine]
//   engine = chromium（默认）| webkit
import { chromium, webkit } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8096/';
const engine = process.argv[3] || 'chromium';
const exe = engine === 'webkit'
  ? process.env.HOME + '/.cache/ms-playwright/webkit-2388/pw_run.sh'
  : process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};

// ---------- stored zip 内存夹具（与 smoke-rustweb-export 同构） ----------
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
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'rich1', title: '打印测试', pinned: false, createdAt: ts, updatedAt: ts, doc: richDoc },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { img1: { name: '图一.png', type: 'image/png' } } }) },
  { name: 'attachments/img1', data: png1 },
]);

const SNAP = () => {
  const blocks = [...document.querySelectorAll('.editor-body [data-bid]')].slice(0, 30).map(el => {
    const r = el.getBoundingClientRect();
    return { bid: el.getAttribute('data-bid'), x: Math.round(r.x * 10) / 10, y: Math.round(r.y * 10) / 10, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10 };
  });
  const hit = document.elementFromPoint(innerWidth / 2, Math.min(innerHeight - 40, 500));
  const root = document.querySelector('#editor-root');
  return {
    blocks,
    scrollY: Math.round(window.scrollY),
    bodyClass: document.body.className,
    bodyStyle: document.body.getAttribute('style') || '',
    rootStyle: root ? (root.getAttribute('style') || '') : '?',
    overlays: [...document.querySelectorAll('.menu-scrim,.sheet-scrim,.editor-export-panel,.editor-menu-panel,.bg-sheet')].map(e => e.className),
    hitInBody: !!(hit && hit.closest && hit.closest('.editor-body')),
    hitLabel: hit ? hit.tagName + '.' + String(hit.className).slice(0, 30) : 'none',
  };
};

async function importAndOpen(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'export_rich.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=rich1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(900);
}

const launcher = engine === 'webkit' ? webkit : chromium;
const browser = await launcher.launch({ executablePath: exe, args: ['--no-sandbox'] });

for (const format of ['pdf', 'markdown', 'html']) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(() => {
    window.__seq = [];
    window.__openInClick = null;
    window.__exportHtml = null;
    window.__inClick = false;
    // capture 阶段（分发最先）置位；window 冒泡末端（分发最后、
    // 微任务之前）清零——以此区分「处理函数内同步开窗」与
    // 「spawn future 微任务里开窗」
    window.addEventListener('click', () => { window.__inClick = true; }, true);
    window.addEventListener('click', () => { window.__inClick = false; }, false);
    window.open = () => {
      window.__seq.push('open');
      if (window.__openInClick === null) window.__openInClick = window.__inClick;
      return {
        closed: false,
        focus() {},
        print() { window.__seq.push('print'); },
        document: {
          open() { window.__seq.push('doc.open'); },
          write(s) { window.__seq.push('write'); window.__exportHtml = s; },
          close() { window.__seq.push('doc.close'); },
          images: [],
        },
      };
    };
  });
  await importAndOpen(page);
  // 导出前先滚动一段，scrollY 保持也纳入体检
  await page.evaluate(() => window.scrollTo(0, 120));
  await page.waitForTimeout(300);
  const s0 = await page.evaluate(SNAP);
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  await page.click(`[data-export-format="${format}"]`);
  await page.waitForTimeout(2200);
  if (format === 'pdf') {
    const cap = await page.evaluate(() => ({ seq: window.__seq, inClick: window.__openInClick, html: window.__exportHtml }));
    ok('pdf window.open 落在点击分发内（手势任务）', cap.inClick === true, 'inClick=' + cap.inClick);
    ok('pdf 调用序 open→doc.open→write→doc.close→print', JSON.stringify(cap.seq) === JSON.stringify(['open', 'doc.open', 'write', 'doc.close', 'print']), cap.seq.join('>'));
    ok('pdf 导出文档已生成', !!cap.html && cap.html.length > 20000, cap.html ? cap.html.length : 0);
    // 模拟真机打印返回的页面级事件序列：afterprint、标签页
    // 隐藏→可见、print 媒体进出
    await page.evaluate(() => {
      window.dispatchEvent(new Event('afterprint'));
      Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
      Object.defineProperty(document, 'visibilityState', { value: 'visible', configurable: true });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await page.emulateMedia({ media: 'print' });
    await page.waitForTimeout(250);
    await page.emulateMedia({ media: 'screen' });
    await page.waitForTimeout(500);
  }
  // 返回后体检（几何按相对量比较：scrollY 复位会整体移位，
  // 故先滚回导出前位置再量，与 smoke 的口径一致）
  await page.evaluate((y) => window.scrollTo(0, y), s0.scrollY);
  await page.waitForTimeout(300);
  const s1 = await page.evaluate(SNAP);
  const diffs = [];
  if (s1.blocks.length !== s0.blocks.length) diffs.push(`count ${s0.blocks.length}->${s1.blocks.length}`);
  const n = Math.min(s0.blocks.length, s1.blocks.length);
  for (let i = 0; i < n; i++) {
    if (s0.blocks[i].bid !== s1.blocks[i].bid) { diffs.push(`bid[${i}]`); continue; }
    if (Math.abs(s0.blocks[i].y - s1.blocks[i].y) > 1.5) diffs.push(`${s0.blocks[i].bid}.y ${s0.blocks[i].y}->${s1.blocks[i].y}`);
    if (Math.abs(s0.blocks[i].x - s1.blocks[i].x) > 1.5) diffs.push(`${s0.blocks[i].bid}.x`);
    if (Math.abs(s0.blocks[i].h - s1.blocks[i].h) > 1.5) diffs.push(`${s0.blocks[i].bid}.h`);
    if (Math.abs(s0.blocks[i].w - s1.blocks[i].w) > 1.5) diffs.push(`${s0.blocks[i].bid}.w`);
  }
  ok(`${format} 返回后块几何与导出前一致`, diffs.length === 0, diffs.join(';') || 'identical');
  ok(`${format} 返回后无残留遮罩/面板`, s1.overlays.length === 0, JSON.stringify(s1.overlays));
  ok(`${format} 返回后 body/root 类与样式未变`, s1.bodyClass === s0.bodyClass && s1.bodyStyle === s0.bodyStyle && s1.rootStyle === s0.rootStyle);
  ok(`${format} 返回后正文中心命中正文`, s1.hitInBody, s1.hitLabel);
  const pt = await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-bid="x-p1"]');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  let alive = false;
  if (pt) {
    await page.mouse.click(pt.x, pt.y);
    await page.waitForTimeout(300);
    await page.keyboard.type('Z');
    await page.waitForTimeout(700);
    alive = await page.evaluate(() => {
      const el = document.querySelector('.editor-body [data-bid="x-p1"]');
      const dom = el ? el.innerText.includes('Z') : false;
      const sync = window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()).includes('Z') : false;
      return dom && sync;
    });
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(300);
  }
  ok(`${format} 返回后可打字且桥同步`, alive);
  ok(`${format} 全程无 pageerror`, errors.length === 0, errors.join(' | ').slice(0, 200));
  await ctx.close();
}

await browser.close();
console.log(failures ? `PROBE FAILURES: ${failures}` : 'PROBE ALL PASS');
process.exit(failures ? 1 : 0);
