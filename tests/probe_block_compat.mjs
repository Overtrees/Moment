// 探针（真块型兼容批 W4，plan_web_native_block_compat §3.6）：
// 夹具 ZIP（与 core 契约测试 block_compat.rs 同一样本：真
// codeBlock/callout 五变体/start=3 嵌套列表 + 存量 MD 源
// 段落篇）导入 → 逐篇打开核三类块呈现（§1.2/1.3 三臂形态）
// → 编辑器内斜杠转 callout（顶层）与列表项转 codeBlock
// （G2 提出路径）产真型 → MD 导出核围栏/变体头/start
// （G3）→ 存量源段落篇预览不回归（§3 验收 5/6）。
// tree Chromium 口径。用法：node probe_block_compat.mjs [base]
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
  const end = new DataView(new ArrayBuffer(22)); end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const ts = new Date().toISOString();
const memo = (id, title, doc) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc });
const trueDoc = [
  { type: 'paragraph', id: 'p-intro', children: [{ text: '开头' }, { text: '加粗', bold: true }, { text: '段落' }] },
  { type: 'codeBlock', id: 'b-code', children: [{ text: 'fn main() {\n' }, { text: 'let s = "``";', code: true }, { text: '\n}' }] },
  { type: 'callout', id: 'b-note', calloutType: 'note', children: [{ text: '提示一' }] },
  { type: 'callout', id: 'b-warning', calloutType: 'warning', children: [{ text: '提示二' }] },
  { type: 'callout', id: 'b-tip', calloutType: 'tip', children: [{ text: '提示三' }] },
  { type: 'callout', id: 'b-important', calloutType: 'important', children: [{ text: '提示四' }] },
  { type: 'callout', id: 'b-caution', calloutType: 'caution', children: [{ text: '提示五' }] },
  { type: 'numbered-list', id: 'b-num', attrs: { start: 3 }, children: [
    { type: 'list-item', id: 'b-num-1', children: [{ text: '第三项' }] },
    { type: 'list-item', id: 'b-num-2', children: [
      { text: '第四项' },
      { type: 'bulleted-list', id: 'b-num-2-sub', children: [
        { type: 'list-item', id: 'b-num-2-sub-1', children: [{ text: '嵌套子项' }] },
      ] },
    ] },
  ] },
  { type: 'bulleted-list', id: 'b-bul', children: [
    { type: 'list-item', id: 'b-bul-1', children: [
      { text: '父项' }, { text: '粗体', bold: true },
      { type: 'link', url: 'https://example.com', children: [{ text: '链接' }] },
    ] },
    { type: 'list-item', id: 'b-bul-2', children: [{ text: '次项' }] },
  ] },
  { type: 'paragraph', id: 'p-editable', children: [{ text: '可编辑段落' }] },
];
const stockDoc = [
  { type: 'paragraph', id: 's-code', children: [{ text: '```\nlet x = 1;\n```' }] },
  { type: 'paragraph', id: 's-callout', children: [{ text: '> [!WARNING]\n> 小心' }] },
  { type: 'paragraph', id: 's-bul', children: [{ text: '- 甲\n- 乙' }] },
  { type: 'paragraph', id: 's-num', children: [{ text: '1. 甲\n2. 乙' }] },
];
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('bc-true', '真块型夹具', trueDoc),
    memo('bc-stock', '存量源段落', stockDoc),
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.addInitScript(() => {
  window.__blobs = [];
  const oc = URL.createObjectURL.bind(URL);
  URL.createObjectURL = (b) => { try { window.__blobs.push(b); } catch (e) {} return oc(b); };
});

// 导入夹具
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', { name: 'block_compat.zip', mimeType: 'application/zip', buffer: fixtureZip });
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
ok('fixture imported', true);

// 打开真块型篇 → 三臂呈现
await page.goto(base + '?open=bc-true', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(900);
const callouts = await page.$$eval('.editor-body .callout', (els) => els.map((e) => e.className));
ok('five callouts rendered', callouts.length === 5, callouts.join(','));
ok('warning variant class', callouts.some((c) => c.includes('callout-warning')));
const calloutTitle = await page.$eval('.editor-body .callout-warning .callout-title', (e) => e.innerText).catch(() => '');
ok('callout header title present', calloutTitle.length > 0, calloutTitle);
const codeInEditor = await page.$eval('.editor-body .blk-code', (e) => e.innerText).catch(() => '');
ok('code block rendered with runs text', codeInEditor.includes('fn main()') && codeInEditor.includes('let s = "``";'), JSON.stringify(codeInEditor.slice(0, 40)));
const markers = await page.$$eval('.editor-body .list-marker', (els) => els.map((e) => e.innerText.trim()));
ok('numbered list starts at 3', markers.includes('3.') && markers.includes('4.'), markers.join(','));
const bodyText = await page.evaluate(() => document.querySelector('.editor-body')?.innerText || '');
ok('nested item rendered', bodyText.includes('嵌套子项'));
// 编辑器内联呈现为源码形态（既有约定：**粗**、[文](url)、
// `码` 在可编辑面以源码呈现）——本层断言 runs 无损保留。
const itemSrc = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.editor-body .ed-line')].find((e) => e.innerText.includes('父项'));
  return el ? el.innerText : '';
});
ok('inline runs preserved in editor source form', itemSrc.includes('**粗体**') && itemSrc.includes('[链接](https://example.com)'), itemSrc);

// 斜杠转 callout（顶层段落 → 真型，正文保真）
await page.click('.editor-body .ed-line:has-text("可编辑段落")');
await page.keyboard.press('End');
await page.keyboard.type('/');
await page.waitForSelector('.slash-panel .slash-row', { timeout: 8000 });
await page.click('.slash-panel .slash-row[data-act="callout"]');
await page.waitForTimeout(500);
const calloutsAfter = await page.$$eval('.editor-body .callout', (els) => els.length);
ok('slash callout produces real callout', calloutsAfter === 6, String(calloutsAfter));
const newCalloutText = await page.evaluate(() => {
  const els = [...document.querySelectorAll('.editor-body .callout .callout-body')];
  return els.map((e) => e.innerText).join('|');
});
ok('converted callout keeps body text', newCalloutText.includes('可编辑段落'), newCalloutText.slice(0, 60));

// G2：列表项斜杠转 codeBlock（提出 → 真型，不再静默变段落）
await page.click('.editor-body .list-wrap .ed-line:has-text("次项")');
await page.keyboard.press('End');
await page.keyboard.type('/');
await page.waitForSelector('.slash-panel .slash-row', { timeout: 8000 });
await page.click('.slash-panel .slash-row[data-act="codeBlock"]');
await page.waitForTimeout(500);
const codeBlocks = await page.$$eval('.editor-body .blk-code', (els) => els.map((e) => e.innerText));
ok('item slash code produces real code block', codeBlocks.some((t) => t.includes('次项')), JSON.stringify(codeBlocks.map((t) => t.slice(0, 20))));
const bulRows = await page.evaluate(() => {
  const wraps = [...document.querySelectorAll('.editor-body .list-wrap')];
  return wraps.map((w) => w.querySelectorAll('.list-row').length).join(',');
});
ok('source list lost exactly the lifted item', bulRows.split(',').includes('1'), bulRows);

// MD 导出（G3）：围栏/变体头/start
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(400);
await page.click('[data-export-format="markdown"]');
await page.waitForTimeout(1800);
const md = await page.evaluate(async () => {
  const b = window.__blobs[window.__blobs.length - 1];
  return b ? await b.text() : '';
});
ok('md export has fenced code block', md.includes('```\nfn main() {') && md.includes('let s = "``";'), md.slice(0, 120).replace(/\n/g, '␤'));
ok('md export has variant header', md.includes('> [!WARNING]') && md.includes('> 提示二'));
ok('md export keeps list start', md.includes('3. 第三项') && md.includes('4. 第四项'));
ok('md export has converted callout as note', md.includes('> [!NOTE]') && md.includes('> 可编辑段落'));
ok('md export has lifted code block', md.includes('```\n次项\n```'));

// 存量源段落篇：预览不回归（仍是段落 + MD 预览，非真型块）
await page.goto(base + '?open=bc-stock', { waitUntil: 'load' });
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(900);
const stockText = await page.evaluate(() => document.querySelector('.editor-body')?.innerText || '');
ok('stock code source previews as code', stockText.includes('let x = 1;'));
ok('stock list source previews items', stockText.includes('甲') && stockText.includes('乙'));
// 真型块的选择器面须排除 MD 预览内部渲染（源段落的 callout
// 预览同样产 .callout 标记，属预览形态、非块类型）。
const stockTrueBlocks = await page.evaluate(() => {
  const inPreview = (e) => !!e.closest('.md-preview');
  const codes = [...document.querySelectorAll('.editor-body .blk-code')].filter((e) => !inPreview(e));
  const callouts = [...document.querySelectorAll('.editor-body .callout')].filter((e) => !inPreview(e));
  return codes.length + callouts.length;
});
ok('stock paragraphs stay source form (no true blocks)', stockTrueBlocks === 0, String(stockTrueBlocks));

ok('no pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
