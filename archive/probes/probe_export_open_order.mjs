// PDF 导出开窗顺序探针（2026-11-21 真机弹窗拦截根治批）：
// 真机证据：WebKit 在 collect 异步收集之后才 window.open →
// 用户激活失效被拦（Diag 只有 memo=/blocked 两行）。
// 本探针断言重构后的严格同构顺序：
//   点击 → 同步 open（< 550ms）→ collect（人为延迟 blob fetch
//   600ms，使收集必然慢）→ doc.open → write → doc.close → print
// 并核对 Diag 三行顺序 memo= → window opened → doc <N>B、
// blocked 分支（open 返 null → 提示 + 不开窗 + 无报错）、
// 写入目标消失分支（closed 恒真 → pdf_failed 提示 + Diag 行）、
// 弹窗往返后 opener 体检（几何/命中/打字/无 pageerror）。
// 用法：node probe_export_open_order.mjs [base] [chromium|webkit]
import { chromium, webkit } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8121/';
const engine = process.argv[3] || 'chromium';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};

// ---------- stored zip 夹具（同 smoke-rustweb-export 口径） ----------
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
const png1 = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const png2 = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64');
const para = (bid, text) => ({ id: bid, type: 'paragraph', children: [{ text }] });
const richDoc = [
  { id: 'x-head', type: 'heading', attrs: { level: 2 }, children: [{ text: '开窗顺序小标题' }] },
  para('x-p1', '普通段落正文。'),
  { id: 'x-img', type: 'image', attrs: { fileId: 'img1' }, children: [] },
  { id: 'x-gal', type: 'gallery', attrs: { items: ['img1', 'img2'] }, children: [] },
  para('x-fill0', '填充段落一。'),
  para('x-fill1', '填充段落二。'),
];
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'rich1', title: '开窗顺序测试', pinned: false, createdAt: ts, updatedAt: ts, doc: richDoc },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { img1: { name: '图一.png', type: 'image/png' }, img2: { name: '图二.png', type: 'image/png' } } }) },
  { name: 'attachments/img1', data: png1 },
  { name: 'attachments/img2', data: png2 },
]);

const SNAP = () => {
  const blocks = [...document.querySelectorAll('.editor-body [data-bid]')].slice(0, 30).map(el => {
    const r = el.getBoundingClientRect();
    return { bid: el.getAttribute('data-bid'), x: Math.round(r.x * 10) / 10, y: Math.round(r.y * 10) / 10, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10 };
  });
  const hit = document.elementFromPoint(innerWidth / 2, Math.min(innerHeight - 40, 500));
  return {
    blocks,
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
  await page.setInputFiles('#file-import', { name: 'open_order.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=rich1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(900);
  await page.waitForFunction(() => document.querySelectorAll('.editor-body img').length >= 3, null, { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(300);
}

async function clickPdf(page) {
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  await page.evaluate(() => { window.__clickT = performance.now(); });
  await page.click('[data-export-format="pdf"]');
}

const diagLines = (page) => page.evaluate(() => {
  const raw = localStorage.getItem('mynote_diag_v1') || '';
  try { const a = JSON.parse(raw); if (Array.isArray(a)) return a.map(String); } catch (e) {}
  return raw.split('\n');
});

async function launch() {
  if (engine === 'webkit') {
    return webkit.launch();
  }
  return chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
}

const browser = await launch();
console.log('ENGINE', engine);

// ---------- 流程 A：真实开窗 + 调用序 + Diag 顺序 + opener 体检 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  let popup = null;
  ctx.on('page', (p) => { if (p !== page) popup = p; });
  await page.addInitScript(() => {
    window.__mnOrder = [];
    // collect 的 blob 转换走 fetch(blob:)：人为延迟 600ms，
    // 使「先收集后开窗」的旧顺序在此探针下必然露馅
    const of = window.fetch.bind(window);
    window.fetch = (u, ...a) => (typeof u === 'string' && u.startsWith('blob:'))
      ? new Promise((res) => setTimeout(() => res(of(u, ...a)), 600))
      : of(u, ...a);
    const origOpen = window.open.bind(window);
    window.open = function (...args) {
      window.__mnOrder.push({ ev: 'open', t: performance.now() });
      const w = origOpen(...args);
      if (w) {
        try {
          const d = w.document;
          const oo = d.open.bind(d), ow = d.write.bind(d), oc = d.close.bind(d);
          d.open = (...a) => { window.__mnOrder.push({ ev: 'doc.open', t: performance.now() }); return oo(...a); };
          d.write = (...a) => { window.__mnOrder.push({ ev: 'write', t: performance.now() }); return ow(...a); };
          d.close = (...a) => { window.__mnOrder.push({ ev: 'doc.close', t: performance.now() }); return oc(...a); };
          w.print = () => { window.__mnOrder.push({ ev: 'print', t: performance.now() }); };
        } catch (e) {
          window.__mnOrder.push({ ev: 'instr-error', t: performance.now() });
        }
      }
      return w;
    };
  });
  await importAndOpen(page);
  // 经菜单挂一张图：附件走 IDB Blob → 编辑器内 img 为 blob:
  // 地址，collect 快照必须 fetch 它转 data:，600ms 延迟才咬得住
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.setInputFiles('#file-attach', { name: 'px.png', mimeType: 'image/png', buffer: png1 });
  await page.waitForSelector('.atomic[data-type="image"] img', { timeout: 10000 });
  await page.waitForTimeout(500);
  const imgSrcs = await page.$$eval('.editor-body img', (els) => els.map((e) => (e.getAttribute('src') || '').split(':')[0]));
  console.log('IMG SRC SCHEMES', JSON.stringify(imgSrcs));
  const hasBlob = imgSrcs.includes('blob');
  // 关掉菜单（若还开着）再走导出
  if (await page.locator('.editor-menu-panel').count()) {
    await page.click('.editor-fab.right');
    await page.waitForTimeout(400);
  }
  const s0 = await page.evaluate(SNAP);
  await clickPdf(page);
  let order = [];
  try {
    await page.waitForFunction(() => (window.__mnOrder || []).some((e) => e.ev === 'print'), null, { timeout: 20000 });
  } catch (e) {}
  order = await page.evaluate(() => window.__mnOrder || []);
  const clickT = await page.evaluate(() => window.__clickT || 0);
  const seq = order.map((e) => e.ev);
  const at = (ev) => { const f = order.find((e) => e.ev === ev); return f ? f.t : -1; };
  console.log('ORDER', JSON.stringify(order), 'clickT', Math.round(clickT));
  ok('A 开窗发生在点击后 550ms 内（先于被延迟的 collect）', at('open') >= 0 && at('open') - clickT < 550, `open-click=${at('open') >= 0 ? Math.round(at('open') - clickT) : -1}ms`);
  ok('A 调用序 open<doc.open<write<doc.close<print',
    JSON.stringify(seq.filter((s) => s !== 'instr-error')) === JSON.stringify(['open', 'doc.open', 'write', 'doc.close', 'print']),
    seq.join('>'));
  if (hasBlob) {
    ok('A write 在 open 后 ≥550ms（collect 确在开窗之后）', at('write') - at('open') >= 550, `${Math.round(at('write') - at('open'))}ms`);
  } else {
    console.log('· A 无 blob: 图，collect 无 fetch 可延迟，跳过 write-open 间隔断言（img schemes=' + JSON.stringify(imgSrcs) + '）');
  }
  const lines = await diagLines(page);
  const iMemo = lines.findIndex((l) => l.includes('export pdf memo='));
  const iOpened = lines.findIndex((l) => l.includes('export pdf window opened'));
  const iDoc = lines.findIndex((l) => l.includes('export pdf doc '));
  const iBlocked = lines.findIndex((l) => l.includes('export pdf blocked'));
  ok('A Diag 顺序 memo= → window opened → doc <N>B', iMemo >= 0 && iOpened > iMemo && iDoc > iOpened, `memo@${iMemo} opened@${iOpened} doc@${iDoc}`);
  ok('A Diag 无 blocked 行', iBlocked === -1);
  if (popup) {
    await popup.waitForTimeout(300);
    const ptxt = await popup.evaluate(() => document.documentElement.outerHTML.length).catch(() => 0);
    ok('A 弹窗文档已写入（非空白页）', ptxt > 5000, ptxt);
    await popup.close().catch(() => {});
  } else {
    ok('A 弹窗已创建', false, 'no popup page');
  }
  await page.waitForTimeout(600);
  const s1 = await page.evaluate(SNAP);
  const diffs = [];
  if (s1.blocks.length !== s0.blocks.length) diffs.push(`count ${s0.blocks.length}->${s1.blocks.length}`);
  for (let i = 0; i < Math.min(s0.blocks.length, s1.blocks.length); i++) {
    if (Math.abs(s0.blocks[i].y - s1.blocks[i].y) > 1.5) diffs.push(`${s0.blocks[i].bid}.y`);
    if (Math.abs(s0.blocks[i].x - s1.blocks[i].x) > 1.5) diffs.push(`${s0.blocks[i].bid}.x`);
    if (Math.abs(s0.blocks[i].h - s1.blocks[i].h) > 1.5) diffs.push(`${s0.blocks[i].bid}.h`);
  }
  ok('A 返回后块几何一致', diffs.length === 0, diffs.join(';') || 'identical');
  ok('A 返回后无残留遮罩/面板', s1.overlays.length === 0, JSON.stringify(s1.overlays));
  ok('A 返回后正文中心命中正文', s1.hitInBody, s1.hitLabel);
  // 打字仍可用且进 DOM
  const firstPara = await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-bid="x-p1"]');
    return el ? true : false;
  });
  ok('A 正文段落仍在', firstPara);
  if (firstPara) {
    await page.click('[data-bid="x-p1"]');
    await page.keyboard.type('Z');
    await page.waitForTimeout(400);
    const txt = await page.$eval('[data-bid="x-p1"]', (e) => e.innerText);
    ok('A 返回后打字进正文', txt.includes('Z'), txt.trim());
  }
  ok('A 全程无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ---------- 流程 B：blocked 分支（open 返 null） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(() => { window.open = () => null; });
  await importAndOpen(page);
  await clickPdf(page);
  let toast = '';
  try {
    await page.waitForFunction(() => (document.querySelector('.status-toast')?.innerText || '').includes('阻止'), null, { timeout: 8000 });
    toast = await page.evaluate(() => document.querySelector('.status-toast')?.innerText || '');
  } catch (e) {}
  ok('B 被拦截时给出明确提示', toast.includes('阻止'), toast);
  const lines = await diagLines(page);
  ok('B Diag 有 blocked 行', lines.some((l) => l.includes('export pdf blocked by popup blocker')));
  ok('B Diag 无 window opened / doc 行',
    !lines.some((l) => l.includes('export pdf window opened')) && !lines.some((l) => l.includes('export pdf doc ')));
  ok('B 未产生多余页签', ctx.pages().length === 1, ctx.pages().length);
  ok('B 全程无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ---------- 流程 C：写入目标消失（closed 恒真） ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(() => {
    const origOpen = window.open.bind(window);
    window.open = function (...args) {
      const w = origOpen(...args);
      if (w) {
        try { Object.defineProperty(w, 'closed', { get: () => true }); } catch (e) {}
      }
      return w;
    };
  });
  await importAndOpen(page);
  await clickPdf(page);
  let toast = '';
  try {
    await page.waitForFunction(() => (document.querySelector('.status-toast')?.innerText || '').includes('失败'), null, { timeout: 15000 });
    toast = await page.evaluate(() => document.querySelector('.status-toast')?.innerText || '');
  } catch (e) {}
  ok('C 写入目标消失时给出失败提示', toast.includes('失败'), toast);
  const lines = await diagLines(page);
  ok('C Diag 有 window gone before write 行', lines.some((l) => l.includes('export pdf window gone before write')));
  ok('C 全程无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

await browser.close();
console.log(failures === 0 ? 'PROBE ALL PASS' : `PROBE FAILURES: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
