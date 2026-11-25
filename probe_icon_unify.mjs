// 探针（图标集统一批）：UI emoji → SVG 替换的盒尺寸等价与残留断言。
// 用法：node probe_icon_unify.mjs <base> <base|after> [baseline.json]
// base 模式只量测并打印 JSON；after 模式另断言：每个量测点恰含一个
// svg、无 emoji 字面、盒宽高与 baseline 同点 ±1px。Chromium 口径。
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const base = process.argv[2] || 'http://localhost:8096/';
const mode = process.argv[3] || 'base';
const baseline = process.argv[4] ? JSON.parse(fs.readFileSync(process.argv[4], 'utf8')) : null;
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
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}

const ts = new Date().toISOString();
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const memo = (id, title, doc) => ({ id, title, pinned: false, createdAt: ts, updatedAt: ts, doc });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    memo('ic-cards', '图标夹具', [
      para('ic-p0', '图标量测夹具'),
      { id: 'ic-mus', type: 'musicCard', url: 'https://music.example.com/s/1', status: 'ready', meta: { title: '歌名甲', subtitle: '歌手甲', source: '示例音乐', type: 'music' }, children: [{ text: '' }] },
      { id: 'ic-muserr', type: 'musicCard', url: 'https://music.example.com/s/2', status: 'error', meta: null, children: [{ text: '' }] },
      { id: 'ic-muspill', type: 'musicCard', children: [{ text: '' }] },
      { id: 'ic-lcv', type: 'link-card', url: 'https://video.example.com/v', meta: { title: '视频标题', source: 'ExampleVideo', type: 'video' }, children: [{ text: '' }] },
      { id: 'ic-lcm', type: 'link-card', url: 'https://m.example.com/v', meta: { title: '音乐链接', source: 'ExampleMusic', type: 'music' }, children: [{ text: '' }] },
      { id: 'ic-lce', type: 'link-card', url: 'https://err.example.com/x', meta: null, children: [{ text: '' }] },
      { id: 'ic-musfile', type: 'musicCard', attrs: { fileId: 'att-mp3' }, children: [{ text: '' }] },
      { id: 'ic-att', type: 'attachment', fileId: 'att-txt', status: 'done', children: [{ text: '' }] },
      { id: 'ic-gal', type: 'gallery', attrs: { items: [] }, children: [] },
      { id: 'ic-itr', type: 'imageTextRow', attrs: { fileId: '' }, children: [{ text: '图文说明' }] },
      { id: 'ic-co1', type: 'callout', calloutType: 'warning', children: [{ text: '警告正文' }] },
      { id: 'ic-co2', type: 'callout', calloutType: 'tip', children: [{ text: '提示正文' }] },
      { id: 'ic-co3', type: 'callout', calloutType: 'important', children: [{ text: '重要正文' }] },
      { id: 'ic-co4', type: 'callout', calloutType: 'caution', children: [{ text: '谨慎正文' }] },
      { id: 'ic-co5', type: 'callout', calloutType: 'note', children: [{ text: '备注正文' }] },
      para('ic-mdco', '> [!warning]\n> MD 警告正文'),
    ]),
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: { 'att-mp3': { name: '歌.mp3', type: 'audio/mpeg' }, 'att-txt': { name: '说明.txt', type: 'text/plain' } } }) },
  { name: 'attachments/att-mp3', data: Buffer.from([0x49, 0x44, 0x33, 1, 2, 3]) },
  { name: 'attachments/att-txt', data: 'hello' },
]);

const EMOJI_RE = /[\u{1F000}-\u{1FAFF}\u2600-\u27BF\u2B00-\u2BFF]/u;
const measure = (page, key, sel, blockId) => page.evaluate(([k, s, b]) => {
  let root = document;
  if (b) {
    root = document.querySelector('[data-wrapbid="' + b + '"]') || document.querySelector('[data-bid="' + b + '"]') || document.querySelector('.md-hit[data-bids="' + b + '"]');
    if (!root) return { key: k, missing: true };
    // callout 的 data-bid 在正文编辑 div 上、图标在其同级页头里：
    // 向上爬至多 3 层找含目标的块容器。
    let scope = root;
    while (scope && !scope.querySelector(s) && scope.parentElement) scope = scope.parentElement;
    if (scope && scope.querySelector(s)) root = scope;
  }
  const el = root.querySelector(s);
  if (!el) return { key: k, missing: true };
  const r = el.getBoundingClientRect();
  const svg = el.querySelector('svg') || (el.tagName === 'svg' ? el : null);
  const sr = svg ? svg.getBoundingClientRect() : null;
  return { key: k, w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10, svg: !!svg, svgW: sr ? Math.round(sr.width * 10) / 10 : 0, svgH: sr ? Math.round(sr.height * 10) / 10 : 0, emoji: /[\u{1F000}-\u{1FAFF}\u2600-\u27BF\u2B00-\u2BFF]/u.test(el.textContent || ''), text: (el.textContent || '').slice(0, 20) };
}, [key, sel, blockId || null]);

const results = {};
async function run(scheme, tag) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: scheme });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 160)));
  const setMemosJson = (val) => page.evaluate(async (v) => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    await new Promise((res, rej) => { const tx = db.transaction('kv', 'readwrite'); tx.objectStore('kv').put(v, 'memos_json'); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
  }, val);
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  // 导入夹具（设置 → 备份与恢复）
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', { name: 'icons.zip', mimeType: 'application/zip', buffer: fixtureZip });
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForSelector('.backup-toast-icon', { timeout: 15000 });
  results[tag + ':toastIcon'] = await measure(page, 'toastIcon', '.backup-toast-icon');
  // 手势页
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("手势")');
  await page.waitForSelector('.gesture-icon', { timeout: 8000 });
  const g = await page.evaluate(() => [...document.querySelectorAll('.gesture-icon')].map((el) => { const r = el.getBoundingClientRect(); const svg = el.querySelector('svg'); const sr = svg ? svg.getBoundingClientRect() : null; return { w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10, svg: !!svg, svgW: sr ? sr.width : 0, svgH: sr ? sr.height : 0, emoji: /[\u{1F000}-\u{1FAFF}\u2600-\u27BF\u2B00-\u2BFF]/u.test(el.textContent || '') }; }));
  g.forEach((m, i) => { results[tag + ':gesture' + i] = { key: 'gesture' + i, ...m }; });
  await page.screenshot({ path: `/tmp/icon-${tag}-gestures.png` });
  // 搜索空状态
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.click('.glass-search-trigger');
  await page.waitForSelector('.glass-search-input', { timeout: 8000 });
  await page.fill('.glass-search-input', 'zzz不存在的词zzz');
  await page.waitForSelector('.empty-state-icon', { timeout: 8000 });
  results[tag + ':emptySearch'] = await measure(page, 'emptySearch', '.empty-state-icon');
  await page.click('.empty-state-btn');
  await page.waitForTimeout(500);
  // 编辑器量测
  await page.goto(base + '?open=ic-cards', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(900);
  const pts = [
    ['musSrc', '.lkc-source-icon', 'ic-mus'],
    ['musErr', '.music-card-error-icon', 'ic-muserr'],
    ['musPill', '.music-pill > span:first-child', 'ic-muspill'],
    ['lcvSrc', '.lkc-source-icon', 'ic-lcv'],
    ['lcmSrc', '.lkc-source-icon', 'ic-lcm'],
    ['lceSrc', '.lkc-source-icon', 'ic-lce'],
    ['attMusic', '.att-icon', 'ic-musfile'],
    ['attFile', '.att-icon', 'ic-att'],
    ['gal0', '.gallery-empty-icon', 'ic-gal'],
    ['itr', '.itr-placeholder', 'ic-itr'],
    ['coWarn', '.callout-icon', 'ic-co1'],
    ['coTip', '.callout-icon', 'ic-co2'],
    ['coImp', '.callout-icon', 'ic-co3'],
    ['coCau', '.callout-icon', 'ic-co4'],
    ['coNote', '.callout-icon', 'ic-co5'],
    ['mdCo', '.callout-icon', 'ic-mdco'],
  ];
  for (const [k, s, b] of pts) results[tag + ':' + k] = await measure(page, k, s, b);
  if (process.env.ICON_DEBUG) {
    const dump = await page.evaluate(() => ({
      callouts: document.querySelectorAll('.callout').length,
      bids: [...document.querySelectorAll('[data-bid]')].map((e) => e.getAttribute('data-bid')),
      wrapbids: [...document.querySelectorAll('[data-wrapbid]')].map((e) => e.getAttribute('data-wrapbid')),
      hits: [...document.querySelectorAll('.md-hit')].map((e) => e.getAttribute('data-bids')),
    }));
    L('DOMDUMP ' + JSON.stringify(dump));
  }
  const gal1 = await page.evaluate(() => { const els = document.querySelectorAll('.gallery-empty-icon'); const el = els[1]; if (!el) return null; const r = el.getBoundingClientRect(); return { key: 'gal1', w: Math.round(r.width * 10) / 10, h: Math.round(r.height * 10) / 10, svg: !!el.querySelector('svg'), emoji: /[\u{1F000}-\u{1FAFF}\u2600-\u27BF\u2B00-\u2BFF]/u.test(el.textContent || '') }; });
  if (gal1) results[tag + ':gal1'] = gal1;
  await page.screenshot({ path: `/tmp/icon-${tag}-editor.png`, fullPage: true });
  // 错误徽章
  await page.evaluate(() => { window.dispatchEvent(new ErrorEvent('error', { message: 'icon-probe-error', filename: 'probe.js', lineno: 7 })); });
  await page.waitForSelector('.eb-badge', { timeout: 8000 }).catch(() => {});
  if (await page.locator('.eb-badge').count()) {
    await page.click('.eb-badge');
    await page.waitForSelector('.eb-entry-icon', { timeout: 8000 }).catch(() => {});
    results[tag + ':ebIcon'] = await measure(page, 'ebIcon', '.eb-entry-icon');
    await page.screenshot({ path: `/tmp/icon-${tag}-errbadge.png` });
  }
  // 加载失败空状态（warning 图标）与空库空状态（file-text 图标）：
  // 走 probe_empty_states 既有 setMemosJson 手法，最后执行（毁夹具库）。
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await setMemosJson('{corrupt-json');
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.empty-state-icon', { timeout: 10000 }).catch(() => {});
  results[tag + ':emptyError'] = await measure(page, 'emptyError', '.empty-state-icon');
  await setMemosJson(JSON.stringify({ version: 2, memos: [] }));
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.empty-state-icon', { timeout: 10000 }).catch(() => {});
  results[tag + ':emptyLib'] = await measure(page, 'emptyLib', '.empty-state-icon');
  await page.screenshot({ path: `/tmp/icon-${tag}-empty.png` });
  await ctx.close();
}
await run('light', 'light');
await run('dark', 'dark');
L('MEASUREMENTS ' + JSON.stringify(results, null, 1));
if (mode === 'after') {
  for (const [k, m] of Object.entries(results)) {
    if (m.missing) { ok(k + ' 在场', false, 'missing'); continue; }
    ok(k + ' 为 SVG', m.svg === true, JSON.stringify(m));
    ok(k + ' 无 emoji 残留', m.emoji === false, m.text || '');
    if (baseline && baseline[k]) {
      const b = baseline[k];
      // 空状态图标盒是居中列里的 fit-content 宽（emoji 前进宽 vs
      // SVG 宽），宽不参与任何布局（父列 align-items:center 居中），
      // 只比高；其余量测点宽高都比。
      if (!m.key.startsWith('empty')) ok(k + ' 盒宽等价', Math.abs(m.w - b.w) <= 1, `after ${m.w} vs base ${b.w}`);
      ok(k + ' 盒高等价', Math.abs(m.h - b.h) <= 1, `after ${m.h} vs base ${b.h}`);
    }
  }
}
await browser.close();
L(fails ? `ICON_PROBE FAIL (${fails})` : 'ICON_PROBE DONE');
process.exit(fails ? 1 : 0);
