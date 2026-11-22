// Rust Web 冒烟 · 导出全路径（2026-11-21 导出根治批）：
// 三格式各一轮「导出 → 返回 → 体检」：块几何与导出前一致、
// 无残留遮罩/类、正文可点击可打字且桥同步、下载文件名净化；
// 导出内容口径：MD（标题层级/图片 data URL/画廊/附件纯文本/
// 链接与音乐卡/图文说明）、HTML/PDF 文档（实时 DOM 快照正文、
// chrome 快照页眉、主题钉死、媒体齐全、无原始 md 源码泄漏）；
// PDF 打印流：开窗→写入→等图→打印的调用序；打印媒体下与
// 原版导出文档（8097，MynoteEditorExport 同输入生成）逐项
// 对照（原版不可达时整段跳过并注明）。
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8096/';
const origBase = process.argv[3] || 'http://localhost:8097/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};

// ---------- stored zip（内存夹具，无磁盘依赖） ----------
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
const ts3 = new Date(now.getTime() - 3 * 864e5).toISOString();
const PNG1_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const PNG2_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const png1 = Buffer.from(PNG1_B64, 'base64');
const png2 = Buffer.from(PNG2_B64, 'base64');
const para = (bid, text) => ({ id: bid, type: 'paragraph', children: [{ text }] });
const richDoc = [
  { id: 'x-head', type: 'heading', attrs: { level: 2 }, children: [{ text: '导出小标题' }] },
  { id: 'x-p1', type: 'paragraph', children: [{ text: '普通段落 ' }, { text: '加粗', bold: true }, { text: ' 结尾文字。' }] },
  { id: 'x-todo1', type: 'todo', attrs: { checked: true }, children: [{ text: '已完成待办' }] },
  { id: 'x-todo2', type: 'todo', attrs: { checked: false }, children: [{ text: '未完成待办' }] },
  { id: 'x-quote', type: 'quote', children: [{ text: '引用一行' }] },
  para('x-code', '```js\nconst a = 1;\n```'),
  para('x-list', '- 苹果\n- 香蕉'),
  para('x-callout', '> [!NOTE]\n提示内容'),
  { id: 'x-img', type: 'image', attrs: { fileId: 'img1' }, children: [] },
  { id: 'x-gal', type: 'gallery', attrs: { items: ['img1', 'img2'] }, children: [] },
  { id: 'x-att', type: 'attachment', fileId: 'att1', name: '报告.pdf', status: 'done', image: false, children: [] },
  { id: 'x-link', type: 'link-card', url: 'https://example.com/page', meta: { title: '示例页面', subtitle: '副标题', source: 'example.com', cover: '' }, status: 'done', children: [] },
  { id: 'x-music', type: 'musicCard', url: 'https://music.example.com/song', meta: { title: '示例歌曲', subtitle: '示例歌手', source: '示例音乐', cover: '' }, status: 'done', children: [] },
  { id: 'x-itc', type: 'imgTextCard', attrs: { fileId: 'img1' }, children: [{ text: '图文卡片说明' }] },
  { id: 'x-div', type: 'divider', children: [] },
];
for (let i = 0; i < 10; i++) richDoc.push(para('x-fill' + i, '填充段落 ' + i + '：' + '内容文字'.repeat(10)));
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'rich1', title: '打印测试', pinned: false, createdAt: ts, updatedAt: ts, doc: richDoc },
    { id: 'rich2', title: '另一篇', pinned: false, createdAt: ts3, updatedAt: ts3, doc: [para('y1', '第二篇正文。')] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { img1: { name: '图一.png', type: 'image/png' }, img2: { name: '图二.png', type: 'image/png' }, att1: { name: '报告.pdf', type: 'application/pdf' } } }) },
  { name: 'attachments/img1', data: png1 },
  { name: 'attachments/img2', data: png2 },
  { name: 'attachments/att1', data: Buffer.from('%PDF-1.4 fake pdf bytes for export test') },
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
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=rich1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(900);
  // 等媒体块图片就绪（导出快照以实时 DOM 为准，图未到齐时
  // 快照里是占位形态）；等不到不中断，后续断言会如实反映
  await page.waitForFunction(() => document.querySelectorAll('.editor-body img').length >= 4, null, { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(300);
}

async function healthCheck(page, label, s0) {
  const s1 = await page.evaluate(SNAP);
  const diffs = [];
  if (s1.blocks.length !== s0.blocks.length) diffs.push(`count ${s0.blocks.length}->${s1.blocks.length}`);
  const n = Math.min(s0.blocks.length, s1.blocks.length);
  for (let i = 0; i < n; i++) {
    if (s0.blocks[i].bid !== s1.blocks[i].bid) { diffs.push(`bid[${i}]`); continue; }
    if (Math.abs(s0.blocks[i].y - s1.blocks[i].y) > 1.5) diffs.push(`${s0.blocks[i].bid}.y ${s0.blocks[i].y}->${s1.blocks[i].y}`);
    if (Math.abs(s0.blocks[i].x - s1.blocks[i].x) > 1.5) diffs.push(`${s0.blocks[i].bid}.x`);
    if (Math.abs(s0.blocks[i].h - s1.blocks[i].h) > 1.5) diffs.push(`${s0.blocks[i].bid}.h ${s0.blocks[i].h}->${s1.blocks[i].h}`);
    if (Math.abs(s0.blocks[i].w - s1.blocks[i].w) > 1.5) diffs.push(`${s0.blocks[i].bid}.w`);
  }
  ok(`${label} 返回后块几何与导出前一致`, diffs.length === 0, diffs.join(';') || 'identical');
  ok(`${label} 返回后无残留遮罩/面板`, s1.overlays.length === 0, JSON.stringify(s1.overlays));
  ok(`${label} 返回后 body/root 类与样式未变`, s1.bodyClass === s0.bodyClass && s1.bodyStyle === s0.bodyStyle && s1.rootStyle === s0.rootStyle);
  ok(`${label} 返回后正文中心命中正文`, s1.hitInBody, s1.hitLabel);
  // 打字探针的目标块须恒为可编辑块：x-p1 是存量 bool 标记段，
  // S3 起打开时归一为字面形态、按统一分类渲染为 md 预览（无
  // data-bid、点击进源码编辑），不再是普通可编辑段落；改用
  // 恒可编辑的引用块 x-quote，断言意图（返回后可打字且桥
  // 同步）不变。
  const pt = await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-bid="x-quote"]');
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
      const el = document.querySelector('.editor-body [data-bid="x-quote"]');
      const dom = el ? el.innerText.includes('Z') : false;
      const sync = window.__mnSyncAll ? JSON.stringify(window.__mnSyncAll()).includes('Z') : false;
      return dom && sync;
    });
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(300);
  }
  ok(`${label} 返回后可打字且桥同步`, alive);
}

function checkExportDoc(html, label) {
  ok(`${label} 主题已钉死（非 system）`, /data-export-theme="(light|dark)"/.test(html) && /style="color-scheme:(light|dark);--/.test(html));
  ok(`${label} 页眉为 chrome 快照（真实标题坞）`, html.includes('editor-title-dock') && html.includes('editor-fab left') || html.includes('editor-title-dock'));
  // 快照标记改查恒可编辑块 x-head（x-p1 自 S3 归一后是 md
  // 预览、无 data-bid，见 healthCheck 注）；模型 fallback 的
  // HTML 不含任何 data-bid，断言意图不变。
  ok(`${label} 正文为实时快照（含 data-bid）`, html.includes('data-bid="x-head"'));
  const dataImgs = (html.match(/<img[^>]+src="data:image\//g) || []).length;
  ok(`${label} 图片全部 data: 内嵌（图+画廊x2+图文卡）`, dataImgs >= 4, dataImgs);
  ok(`${label} 无 blob: 残留`, !html.includes('blob:'));
  ok(`${label} 待办为 checkbox 结构而非字形`, html.includes('todo-checkbox') && !html.includes('☑') && !html.includes('☐'));
  ok(`${label} 代码块已渲染（无围栏源码泄漏）`, html.includes('<pre') && !html.includes('```'));
  ok(`${label} 标注已渲染（无 [!NOTE] 源码泄漏）`, !html.includes('[!NOTE]'));
  for (const s of ['报告.pdf', '示例页面', '示例歌曲', '图文卡片说明', '已完成待办']) {
    ok(`${label} 内容含「${s}」`, html.includes(s));
  }
}

const MEASURE = () => {
  const q = (s) => document.querySelector(s);
  const cs = (el, p) => { if (!el) return null; return getComputedStyle(el).getPropertyValue(p); };
  const body = q('.editor-body');
  const header = q('.mynote-export-header');
  return {
    shellPadTop: cs(q('.mynote-export-shell'), 'padding-top'),
    headerH: header ? Math.round(header.getBoundingClientRect().height) : null,
    bodyFont: cs(body, 'font-size'),
    h2Font: cs(q('.editor-body .blk-h2, .editor-body .blk-h1, .editor-body .note-heading h2, .editor-body h2'), 'font-size'),
    preFont: cs(q('.editor-body pre'), 'font-size'),
    imgs: document.querySelectorAll('.editor-body img').length,
    todoBoxes: document.querySelectorAll('.editor-body .todo-checkbox').length,
    text: body ? body.innerText : '',
    headerText: header ? header.innerText : '',
    fabsOutsideHeader: [...document.querySelectorAll('.editor-fab')].filter(e => !e.closest('.mynote-export-header')).length,
    junk: document.querySelectorAll('#editor-root,.menu-scrim,#slash-panel,.editor-export-panel,.editor-menu-panel').length,
  };
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const captured = {};

for (const format of ['pdf', 'markdown', 'html']) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  let dlName = null;
  page.on('download', (d) => { dlName = d.suggestedFilename(); });
  await page.addInitScript(() => {
    window.__exportHtml = null;
    window.__seq = [];
    window.__blobs = [];
    window.__dlNames = [];
    // 无头 shell 的 download 事件不回传 download 属性名，
    // 改用 MutationObserver 抓锚点挂载瞬间的 download 值
    const mo = new MutationObserver((recs) => {
      for (const r of recs) for (const n of r.addedNodes) {
        if (n && n.tagName === 'A' && n.getAttribute('download')) window.__dlNames.push(n.getAttribute('download'));
        if (n && n.querySelectorAll) n.querySelectorAll('a[download]').forEach(a => window.__dlNames.push(a.getAttribute('download')));
      }
    });
    mo.observe(document, { childList: true, subtree: true });
    const oc = URL.createObjectURL.bind(URL);
    URL.createObjectURL = (b) => { try { window.__blobs.push(b); } catch (e) {} return oc(b); };
    window.open = () => {
      window.__seq.push('open');
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
  const s0 = await page.evaluate(SNAP);
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  await page.click(`[data-export-format="${format}"]`);
  await page.waitForTimeout(1800);
  if (format === 'pdf') {
    const cap = await page.evaluate(() => ({ seq: window.__seq, html: window.__exportHtml }));
    ok('pdf 调用序 open→doc.open→write→print', JSON.stringify(cap.seq) === JSON.stringify(['open', 'doc.open', 'write', 'doc.close', 'print']), cap.seq.join('>'));
    ok('pdf 导出文档已生成', !!cap.html && cap.html.length > 50000, cap.html ? cap.html.length : 0);
    captured.pdfHtml = cap.html;
    if (cap.html) checkExportDoc(cap.html, 'pdf文档');
    await page.emulateMedia({ media: 'print' });
    await page.waitForTimeout(300);
    await page.emulateMedia({ media: 'screen' });
    await page.waitForTimeout(300);
  } else {
    const content = await page.evaluate(async () => {
      const b = window.__blobs[window.__blobs.length - 1];
      return b ? await b.text() : null;
    });
    const anchorName = await page.evaluate(() => window.__dlNames[window.__dlNames.length - 1] || null);
    ok(`${format} 下载文件名净化`, anchorName === '打印测试.' + (format === 'markdown' ? 'md' : 'html'), `${anchorName} (dl event: ${dlName})`);
    if (format === 'markdown') {
      const md = content || '';
      captured.md = md;
      ok('md 标题行', md.startsWith('# 打印测试'));
      ok('md 标题块层级与原版一致（## 而非 ###）', md.includes('\n## 导出小标题\n'));
      ok('md 待办', md.includes('- [x] 已完成待办') && md.includes('- [ ] 未完成待办'));
      ok('md 图片为 data URL', /!\[图一\.png\]\(data:image\/png;base64,/.test(md));
      ok('md 画廊两图齐全', (md.match(/!\[图[一二]\.png\]\(data:image\/png;base64,/g) || []).length >= 3);
      ok('md 附件为纯文本口径', md.includes('📎 报告.pdf') && !md.includes('[📎'));
      ok('md 链接卡', md.includes('[示例页面](https://example.com/page)'));
      ok('md 音乐卡', md.includes('[示例歌曲](https://music.example.com/song)'));
      ok('md 图文卡带说明', md.includes('说明：图文卡片说明'));
      ok('md 代码段原样', md.includes('```js\nconst a = 1;\n```'));
    } else {
      captured.htmlDoc = content;
      if (content) checkExportDoc(content, 'html文档');
    }
  }
  await healthCheck(page, format, s0);
  ok(`${format} 全程无 pageerror`, errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ---------- PDF 被拦截时的提示与健康 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.addInitScript(() => { window.open = () => null; });
  await importAndOpen(page);
  const s0 = await page.evaluate(SNAP);
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  await page.click('[data-export-format="pdf"]');
  let toast = '';
  try {
    await page.waitForFunction(() => (document.querySelector('.backup-toast')?.innerText || '').includes('阻止'), null, { timeout: 6000 });
    toast = await page.evaluate(() => document.querySelector('.backup-toast')?.innerText || '');
  } catch (e) {}
  ok('pdf 被拦截时给出明确提示', toast.includes('阻止'), toast);
  await page.waitForTimeout(900);
  await healthCheck(page, 'pdf-blocked', s0);
  await ctx.close();
}

// ---------- PDF 成功后遮罩残留（rAF 饥饿口径） ----------
// 开场动画靠双 rAF 清除 closing 态；页面被遮挡/隐藏、合成
// 器停摆时 rAF 永不触发。旧实现以 closing 视觉态作关闭门
// 闩，关闭被整体吞掉：透明 .menu-scrim 与 opacity-0 面板
// 永久残留、整页点按被拒（云端 Chromium 实证）。本节以
// rAF 替身制造同一饥饿条件，断言导出成功后无残留覆盖、
// 正文命中、••• 仍可点开菜单且菜单可经遮罩关闭。
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(() => {
    window.requestAnimationFrame = () => 0; // rAF 饥饿：回调永不触发
    window.__seq = [];
    window.open = () => {
      window.__seq.push('open');
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
  // 导入流程本地复刻 importAndOpen：rAF 饥饿下
  // waitForFunction 的默认 rAF 轮询永不触发（实测导入 2s
  // 完成、等待却 60s 超时），完成判定改走 setTimeout 轮询
  // Diag 的 IMPORT ok 行；其余 waitForSelector 为突变驱动，
  // 不受 rAF 影响。
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'export_rich.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  let imported = false;
  for (let i = 0; i < 80 && !imported; i++) {
    imported = await page.evaluate(() => (localStorage.getItem('mynote_diag_v1') || '').includes('IMPORT ok'));
    if (!imported) await page.waitForTimeout(250);
  }
  ok('pdf-raf-starved 夹具导入完成', imported);
  await page.goto(base + '?open=rich1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(900);
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(600);
  await page.click('[data-export-format="pdf"]');
  let printed = false;
  for (let i = 0; i < 60 && !printed; i++) {
    printed = await page.evaluate(() => (window.__seq || []).includes('print'));
    if (!printed) await page.waitForTimeout(250);
  }
  ok('pdf-raf-starved 导出流程走完（open→write→print）', printed, (await page.evaluate(() => window.__seq || [])).join('>'));
  await page.waitForTimeout(1200);
  const s1 = await page.evaluate(SNAP);
  ok('pdf-raf-starved 导出后无残留遮罩/面板', s1.overlays.length === 0, JSON.stringify(s1.overlays));
  ok('pdf-raf-starved 导出后正文中心命中正文', s1.hitInBody, s1.hitLabel);
  let menuReopened = false;
  try {
    await page.click('.editor-fab.right');
    await page.waitForSelector('.editor-menu-panel', { timeout: 5000 });
    menuReopened = true;
  } catch (e) {}
  ok('pdf-raf-starved 导出后 ••• 可点开菜单', menuReopened);
  if (menuReopened) {
    await page.mouse.click(196, 500);
    await page.waitForTimeout(700);
    const s2 = await page.evaluate(SNAP);
    ok('pdf-raf-starved 菜单可经遮罩关闭且无残留', s2.overlays.length === 0, JSON.stringify(s2.overlays));
  }
  ok('pdf-raf-starved 全程无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ---------- 打印侧量测：Rust 文档 vs 原版文档 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
  const page = await ctx.newPage();
  let rustM = null;
  if (captured.pdfHtml) {
    await page.setContent(captured.pdfHtml, { waitUntil: 'load' });
    await page.emulateMedia({ media: 'print' });
    await page.waitForTimeout(300);
    rustM = await page.evaluate(MEASURE);
    ok('打印 文档无编辑器残留（根节点/遮罩/面板）', rustM.junk === 0, rustM.junk);
    ok('打印 FAB 仅出现在页眉快照内', rustM.fabsOutsideHeader === 0, rustM.fabsOutsideHeader);
    ok('打印 页眉含标题与副行', rustM.headerText.includes('打印测试') && rustM.headerText.includes('字'), rustM.headerText.replace(/\n/g, ' ').slice(0, 60));
    ok('打印 壳层 print 边距归零', rustM.shellPadTop === '0px', rustM.shellPadTop);
    ok('打印 正文图齐全', rustM.imgs >= 4, rustM.imgs);
    ok('打印 待办复选框齐全', rustM.todoBoxes === 2, rustM.todoBoxes);
    ok('打印 标题字号大于正文', parseFloat(rustM.h2Font) > parseFloat(rustM.bodyFont), `${rustM.h2Font} vs ${rustM.bodyFont}`);
  }
  // 原版同输入生成（不可达则跳过整段）
  let origM = null;
  try {
    const opage = await ctx.newPage();
    await opage.goto(origBase + 'Moment.html', { waitUntil: 'load', timeout: 15000 });
    await opage.waitForFunction(() => !!window.MynoteEditorExport, null, { timeout: 12000 });
    const origHtml = await opage.evaluate(({ doc, files }) => {
      return window.MynoteEditorExport.toHTMLDocument(doc, '打印测试', files, null, {
        subtitle: '11月21日 · 100字', theme: 'light', themeVariables: {},
        pageBackgroundColor: '', pageTextColor: '', avatarUrl: '',
      });
    }, { doc: richDoc, files: {
      img1: { url: 'data:image/png;base64,' + PNG1_B64, name: '图一.png', type: 'image/png', size: png1.length },
      img2: { url: 'data:image/png;base64,' + PNG2_B64, name: '图二.png', type: 'image/png', size: png2.length },
      att1: { url: 'data:application/pdf;base64,' + Buffer.from('%PDF-1.4 fake pdf bytes for export test').toString('base64'), name: '报告.pdf', type: 'application/pdf', size: 38 },
    } });
    await opage.close();
    const p2 = await ctx.newPage();
    await p2.setContent(origHtml, { waitUntil: 'load' });
    await p2.emulateMedia({ media: 'print' });
    await p2.waitForTimeout(300);
    origM = await p2.evaluate(MEASURE);
    await p2.close();
    console.log('[orig-print] ' + JSON.stringify({ shellPadTop: origM.shellPadTop, headerH: origM.headerH, bodyFont: origM.bodyFont, h2Font: origM.h2Font, preFont: origM.preFont, imgs: origM.imgs, todoBoxes: origM.todoBoxes }));
  } catch (e) {
    console.log('SKIP 原版对照（8097 不可达或导出模块未就绪）: ' + String(e).slice(0, 120));
  }
  if (rustM && origM) {
    ok('对照 正文字号一致', rustM.bodyFont === origM.bodyFont, `${rustM.bodyFont} vs ${origM.bodyFont}`);
    ok('对照 壳层 print 边距一致', rustM.shellPadTop === origM.shellPadTop, `${rustM.shellPadTop} vs ${origM.shellPadTop}`);
    ok('对照 页眉高度近似（±26px）', Math.abs(rustM.headerH - origM.headerH) <= 26, `${rustM.headerH} vs ${origM.headerH}`);
    ok('对照 图片数一致', rustM.imgs === origM.imgs, `${rustM.imgs} vs ${origM.imgs}`);
    ok('对照 待办复选框数一致', rustM.todoBoxes === origM.todoBoxes, `${rustM.todoBoxes} vs ${origM.todoBoxes}`);
    ok('对照 标题字号一致', rustM.h2Font === origM.h2Font, `${rustM.h2Font} vs ${origM.h2Font}`);
    for (const s of ['报告.pdf', '示例页面', '示例歌曲', '图文卡片说明']) {
      ok(`对照 原版含「${s}」且 Rust 亦含`, origM.text.includes(s) && rustM.text.includes(s));
    }
  }
  await ctx.close();
}

await browser.close();
console.log('ERRORS: ' + (failures ? `${failures} assertion(s) failed` : 'none'));
process.exit(failures ? 1 : 0);
