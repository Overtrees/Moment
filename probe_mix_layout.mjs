// 混排专项探针：同一交错夹具（fixtures/mix-layout.zip）在
// ①Rust 编辑页 ②Rust 导出 HTML/PDF ③原版编辑页 ④原版导出文档
// 四方逐项量测对照（标题胶囊/返回钮/更多钮/页眉 meta/正文每块
// 顺序·间距·边距·字号行高/卡片内排版/Md 块形态）。
// 用法：
//   node probe_mix_layout.mjs [rustBase] [origBase] report  —— 只出差异表
//   node probe_mix_layout.mjs [rustBase] [origBase] assert  —— 按 1:1 口径断言
// 导出口径：window.open 桩捕获 PDF 文档、createObjectURL 桩捕获
// HTML 下载 blob（与 smoke-rustweb-export 同手法）。
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = process.argv[2] || 'http://localhost:8121/';
const ORIG = process.argv[3] || 'http://localhost:8117/';
const MODE = process.argv[4] || 'report';
const ZIP = process.env.HOME + '/workspace/Mynote/fixtures/mix-layout.zip';
const TITLE = '混排验收长标题一二三四五';

let failures = 0;
const ok = (cond, label, detail = '') => {
  console.log(`${cond ? '✓' : '✗'} ${label}${detail ? ' | ' + detail : ''}`);
  if (!cond) failures++;
};
const info = (label, detail = '') => console.log(`· ${label}${detail ? ' | ' + detail : ''}`);

const MEASURE = () => {
  const R = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) };
  };
  const prop = (el, p) => (el ? getComputedStyle(el)[p] : null);
  const body = document.querySelector('.editor-body');
  const kids = body ? [...body.children] : [];
  const blocks = kids.map((el, i) => {
    const r = R(el);
    const prev = i > 0 ? kids[i - 1].getBoundingClientRect() : null;
    const o = {
      i,
      cls: String(el.className || '').slice(0, 56),
      bid: el.getAttribute('data-bid') || el.getAttribute('data-wrapbid') || '',
      rect: r,
      gap: prev && r ? +(r.y - (prev.y + prev.height)).toFixed(1) : null,
      mT: prop(el, 'marginTop'), mB: prop(el, 'marginBottom'),
      pL: prop(el, 'paddingLeft'), pR: prop(el, 'paddingRight'),
      fs: prop(el, 'fontSize'), lh: prop(el, 'lineHeight'),
      text: (el.innerText || '').replace(/\n/g, '⏎').slice(0, 18),
    };
    const img = el.querySelector('img');
    if (img) o.img = R(img);
    // 复选框按类量（原版是 input、Rust 是 button，量的是盒不是标签）
    const cb = el.querySelector('.todo-checkbox');
    if (cb) o.checkbox = R(cb);
    const pre = el.querySelector('pre');
    if (pre) { o.pre = R(pre); o.preBg = prop(pre, 'backgroundColor'); }
    const tt = el.querySelector('.lkc-title, .itc-text, .lkc-subtitle, .lkc-source');
    if (tt) o.cardLine = { cls: String(tt.className).slice(0, 30), rect: R(tt), fs: prop(tt, 'fontSize'), text: (tt.innerText || '').slice(0, 14) };
    return o;
  });
  const back = document.querySelector('.editor-fab.left, .mynote-export-back');
  const more = document.querySelector('.editor-fab.right, .mynote-export-more');
  const dock = document.querySelector('.editor-title-dock, .mynote-export-dock');
  const titleEl = document.querySelector('#editor-title-text, .editor-title-input, .note-title');
  let pill = null;
  if (titleEl) {
    pill = titleEl.closest('.mynote-export-title-pill') ||
      (titleEl.parentElement && titleEl.parentElement.parentElement);
  }
  const meta = document.querySelector('.editor-title-meta, .mynote-export-meta');
  const avatar = document.querySelector('.editor-avatar-button, .mynote-export-avatar');
  const headerEl = document.querySelector('.mynote-export-header');
  const header = {
    back: R(back), more: R(more), dock: R(dock), avatar: R(avatar),
    pill: R(pill), pillBg: pill ? prop(pill, 'backgroundColor') : null,
    pillFilter: pill ? prop(pill, 'backdropFilter') : null,
    titleText: titleEl ? titleEl.textContent : null,
    titleRect: R(titleEl), titleFs: prop(titleEl, 'fontSize'), titleFw: prop(titleEl, 'fontWeight'),
    metaText: meta ? meta.textContent : null, metaRect: R(meta), metaFs: prop(meta, 'fontSize'),
    headerRect: R(headerEl),
  };
  return { header, blocks, bodyRect: R(body), n: kids.length };
};

const INIT_STUB = () => {
  window.__exportHtml = null;
  window.__blobs = [];
  const oc = URL.createObjectURL.bind(URL);
  URL.createObjectURL = (b) => { try { window.__blobs.push(b); } catch (e) {} return oc(b); };
  window.open = () => ({
    closed: false,
    focus() {}, print() {},
    document: {
      open() {}, write(s) { window.__exportHtml = s; }, close() {},
      images: [],
    },
  });
};

async function scrollPass(page) {
  await page.evaluate(async () => {
    const H = document.documentElement.scrollHeight;
    for (let y = 0; y < H; y += 400) { window.scrollTo(0, y); await new Promise(r => setTimeout(r, 60)); }
    window.scrollTo(0, 0);
  });
  await page.waitForTimeout(500);
}

async function importRust(page, base) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', ZIP);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.goto(base + '?open=mixfix1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1200);
}

async function importOrig(page, base) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForTimeout(1200);
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.list-item, .set-row')].find(e => e.innerText.includes('备份与恢复'));
    if (el) el.click();
  });
  await page.waitForTimeout(1000);
  const chooserP = page.waitForEvent('filechooser', { timeout: 10000 });
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.backup-row')]
      .find(e => (e.innerText || '').includes('导入备份'));
    if (el) el.click();
  });
  const chooser = await chooserP;
  await chooser.setFiles(ZIP);
  await page.waitForTimeout(1000);
  // 确认恢复弹层（.backup-btn.primary = 确认恢复）
  await page.click('.backup-btn.primary:has-text("确认恢复")');
  await page.waitForTimeout(1500);
  // 导入后原版自动回列表；真实点击标题行打开（SwipeRow 靠指针
  // 事件，evaluate 的 el.click() 不触发）
  await page.click('text=' + TITLE.slice(0, 6));
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1200);
}

async function triggerExport(page, kind) {
  // kind: 'html' | 'pdf'；两版同口径：更多钮 → 导出 → 格式
  await page.click('.editor-fab.right');
  await page.waitForTimeout(700);
  const entry = await page.$('.editor-export-entry');
  if (entry) await entry.click();
  else await page.evaluate(() => {
    const el = [...document.querySelectorAll('.editor-menu-panel .menu-item')]
      .find(e => (e.innerText || '').startsWith('导出'));
    window.__dbgEntry = el ? (el.className + ' :: ' + (el.innerText || '').slice(0, 20)) : 'NOT FOUND';
    if (el) el.click();
  });
  await page.waitForTimeout(800);
  console.log('  [dbg] menuOpen=', await page.evaluate(() => !!document.querySelector('.editor-menu-panel')),
    'entry=', await page.evaluate(() => window.__dbgEntry),
    'exportPanel=', await page.evaluate(() => !!document.querySelector('.editor-export-panel')));
  await page.evaluate((k) => {
    const panel = document.querySelector('.editor-export-panel') || document.body;
    const byAttr = panel.querySelector(`[data-export-format="${k}"]`);
    if (byAttr) { byAttr.click(); return; }
    const el = [...panel.querySelectorAll('button, [class*="choice"], [class*="option"], div')]
      .filter(e => e.children.length < 5)
      .find(e => (e.innerText || '').toUpperCase().includes(k === 'pdf' ? 'PDF' : 'HTML'));
    if (el) el.click();
  }, kind);
  await page.waitForTimeout(2000);
}

async function measureExportDoc(browser, html, label) {
  const out = {};
  for (const vp of [{ width: 393, height: 852 }, { width: 1280, height: 800 }]) {
    const ctx = await browser.newContext({ viewport: vp, hasTouch: true });
    const p = await ctx.newPage();
    await p.setContent(html, { waitUntil: 'load' });
    await p.waitForTimeout(700);
    out['screen' + vp.width] = await p.evaluate(MEASURE);
    await p.emulateMedia({ media: 'print' });
    await p.waitForTimeout(300);
    out['print' + vp.width] = await p.evaluate(MEASURE);
    await ctx.close();
  }
  return out;
}

async function runSide(browser, base, importer, label) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.addInitScript(INIT_STUB);
  await importer(page, base);
  await scrollPass(page);
  const editor = await page.evaluate(MEASURE);
  await triggerExport(page, 'html');
  const htmlDoc = await page.evaluate(async () => {
    const types = window.__blobs.map(b => b.type + ':' + b.size).join(',');
    const b = [...window.__blobs].reverse().find(x => x.type.includes('text/html'));
    return { types, html: b ? await b.text() : null };
  }).then(r => { console.log('  [rust/orig html blobs]', r.types); return r.html; });
  await page.keyboard.press('Escape').catch(() => {});
  await page.waitForTimeout(400);
  await triggerExport(page, 'pdf');
  const pdfDoc = await page.evaluate(() => window.__exportHtml);
  await ctx.close();
  const res = { editor, errors };
  if (htmlDoc) { res.html = await measureExportDoc(browser, htmlDoc, label + '-html'); res.htmlRaw = htmlDoc; }
  if (pdfDoc) { res.pdf = await measureExportDoc(browser, pdfDoc, label + '-pdf'); res.pdfRaw = pdfDoc; }
  return res;
}

function diffBlocks(a, b, label) {
  const diffs = [];
  if (!a || !b) return [`${label}: 一侧缺失`];
  if (a.n !== b.n) diffs.push(`${label}: 块数 ${a.n} vs ${b.n}`);
  const n = Math.min(a.blocks.length, b.blocks.length);
  for (let i = 0; i < n; i++) {
    const x = a.blocks[i], y = b.blocks[i];
    const tag = `${label}[${i}]`;
    if (x.text !== y.text) diffs.push(`${tag} 文本 "${x.text}" vs "${y.text}"`);
    // 图片块的框以 img 本体为准：原版块本体就是 .atomic，Rust 是
    // .blk-wrap 包裹层，两边外框不可直接比（img 几何一致才算一致）
    const imgFrame = x.img && y.img && x.rect && y.rect &&
      Math.abs(x.rect.h - x.img.h) < 20 && Math.abs(y.rect.h - y.img.h) < 20;
    if (x.rect && y.rect) {
      if (Math.abs(x.rect.h - y.rect.h) > 1) diffs.push(`${tag} 高 ${x.rect.h} vs ${y.rect.h} (${x.cls} | ${y.cls})`);
      if (!imgFrame) {
        if (Math.abs(x.rect.w - y.rect.w) > 1) diffs.push(`${tag} 宽 ${x.rect.w} vs ${y.rect.w}`);
        if (Math.abs(x.rect.x - y.rect.x) > 1) diffs.push(`${tag} x ${x.rect.x} vs ${y.rect.x}`);
      }
    }
    if (imgFrame) {
      if (Math.abs(x.img.w - y.img.w) > 1) diffs.push(`${tag} 图宽 ${x.img.w} vs ${y.img.w}`);
      if (Math.abs(x.img.x - y.img.x) > 1) diffs.push(`${tag} 图x ${x.img.x} vs ${y.img.x}`);
    }
    if (x.gap !== null && y.gap !== null && Math.abs(x.gap - y.gap) > 1) diffs.push(`${tag} 上间距 ${x.gap} vs ${y.gap}`);
    if (x.fs !== y.fs) diffs.push(`${tag} 字号 ${x.fs} vs ${y.fs}`);
    if (x.lh !== y.lh) diffs.push(`${tag} 行高 ${x.lh} vs ${y.lh}`);
    if ((x.img && !y.img) || (!x.img && y.img)) diffs.push(`${tag} 图片有无不一致`);
    else if (x.img && y.img && (Math.abs(x.img.h - y.img.h) > 1 || Math.abs(x.img.w - y.img.w) > 1))
      diffs.push(`${tag} 图尺寸 ${x.img.w}x${x.img.h} vs ${y.img.w}x${y.img.h}`);
    if ((x.checkbox && !y.checkbox) || (!x.checkbox && y.checkbox)) diffs.push(`${tag} 复选框有无不一致`);
    else if (x.checkbox && y.checkbox) {
      if (Math.abs(x.checkbox.w - y.checkbox.w) > 1 || Math.abs(x.checkbox.h - y.checkbox.h) > 1)
        diffs.push(`${tag} 复选框尺寸 ${x.checkbox.w}x${x.checkbox.h} vs ${y.checkbox.w}x${y.checkbox.h}`);
      if (Math.abs(x.checkbox.x - y.checkbox.x) > 1) diffs.push(`${tag} 复选框x ${x.checkbox.x} vs ${y.checkbox.x}`);
    }
  }
  return diffs;
}

function diffHeader(a, b, label) {
  const diffs = [];
  if (!a || !b) return [`${label}: 一侧缺失`];
  const H = a.header, G = b.header;
  if (H.titleText !== G.titleText) diffs.push(`${label} 标题文本 "${H.titleText}" vs "${G.titleText}"`);
  if (H.titleFs !== G.titleFs) diffs.push(`${label} 标题字号 ${H.titleFs} vs ${G.titleFs}`);
  if (H.metaText !== G.metaText) diffs.push(`${label} meta "${H.metaText}" vs "${G.metaText}"`);
  for (const k of ['back', 'more', 'avatar', 'pill', 'dock']) {
    const x = H[k], y = G[k];
    if (!x !== !y) { diffs.push(`${label} ${k} 有无不一致`); continue; }
    if (x && y) {
      if (Math.abs(x.w - y.w) > 1 || Math.abs(x.h - y.h) > 1) diffs.push(`${label} ${k} 尺寸 ${x.w}x${x.h} vs ${y.w}x${y.h}`);
      if (Math.abs(x.x - y.x) > 1) diffs.push(`${label} ${k} x ${x.x} vs ${y.x}`);
    }
  }
  return diffs;
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
console.log('== Rust 侧 ==');
const rust = await runSide(browser, RUST, importRust, 'rust');
console.log('== 原版侧 ==');
const orig = await runSide(browser, ORIG, importOrig, 'orig');
await browser.close();

fs.writeFileSync('/tmp/mix_rust.json', JSON.stringify(rust, (k, v) => k.endsWith('Raw') ? undefined : v, 1));
fs.writeFileSync('/tmp/mix_orig.json', JSON.stringify(orig, (k, v) => k.endsWith('Raw') ? undefined : v, 1));
if (rust.htmlRaw) fs.writeFileSync('/tmp/mix_rust_export.html', rust.htmlRaw);
if (orig.htmlRaw) fs.writeFileSync('/tmp/mix_orig_export.html', orig.htmlRaw);

console.log('\n== 差异表 ==');
const sections = [
  ['B 编辑页 rust vs orig', diffHeader(rust.editor, orig.editor, 'HDR'), diffBlocks(rust.editor, orig.editor, 'ED')],
  ['A 导出HTML 393 rust vs orig', diffHeader(rust.html?.screen393, orig.html?.screen393, 'HDR'), diffBlocks(rust.html?.screen393, orig.html?.screen393, 'EX')],
  ['A 导出HTML print rust vs orig', diffBlocks(rust.html?.print393, orig.html?.print393, 'PR')],
  ['A 导出HTML 1280 rust vs orig', diffBlocks(rust.html?.screen1280, orig.html?.screen1280, 'EXW')],
  ['A PDF print rust vs orig', diffBlocks(rust.pdf?.print393, orig.pdf?.print393, 'PP')],
  ['A rust 导出 vs rust 编辑（自洽）', diffBlocks(rust.html?.screen393, rust.editor, 'SELF')],
  ['A orig 导出 vs orig 编辑（自洽）', diffBlocks(orig.html?.screen393, orig.editor, 'OSELF')],
];
for (const [name, ...ds] of sections) {
  const all = ds.flat();
  console.log(`\n-- ${name}: ${all.length} 处差异`);
  for (const d of all) console.log('   ' + d);
}
if (rust.errors.length) console.log('\nrust pageerror:', rust.errors.join(' | '));
if (orig.errors.length) console.log('orig pageerror:', orig.errors.join(' | '));

if (MODE === 'assert') {
  console.log('\n== 断言 ==');
  // HDR meta 的时间文本随运行时刻/打开刷新变化，形状归一到占位；
  // 节名前缀（SELF/OSELF 等）一并归一，比的是差异结构本身
  const shape = (s) => (s.startsWith('HDR meta') ? 'HDR meta' : s)
    .replace(/^[A-Z]+\[/, 'X[')
    .replace(/[0-9]+(\.[0-9]+)?/g, '#').replace(/\s*\([^)]*\)/g, '');
  const oself = sections.find(([n]) => n.startsWith('A orig'));
  const oselfShapes = oself ? oself.slice(1).flat().map(shape).sort() : [];
  for (const [name, ...ds] of sections) {
    if (name.startsWith('A orig')) continue;
    let all = ds.flat();
    if (name.startsWith('B ')) {
      // 编辑页 meta 的时间部分：原版打开备忘会刷新 updatedAt
      // （audit_pages 既有条目，非混排范围），只断言字数一致
      all = all.filter((d) => {
        if (!d.startsWith('HDR meta')) return true;
        const counts = [...d.matchAll(/(\d+)字/g)].map((m) => m[1]);
        return !(counts.length === 2 && counts[0] === counts[1]);
      });
    }
    if (name.includes('rust 导出 vs rust 编辑')) {
      // 自洽口径：导出壳 padding(14) vs 编辑页(16) 的差是原版
      // 自身行为（OSELF 同签名），断言 Rust 的自洽差与原版同构
      const shapes = all.map(shape).sort();
      const same = JSON.stringify(shapes) === JSON.stringify(oselfShapes);
      if (!same) {
        const cnt = (arr) => arr.reduce((m, s) => (m[s] = (m[s] || 0) + 1, m), {});
        const ca = cnt(shapes), cb = cnt(oselfShapes);
        for (const k of new Set([...Object.keys(ca), ...Object.keys(cb)]))
          if (ca[k] !== cb[k]) console.log(`    shape 差: "${k}" rust=${ca[k] || 0} orig=${cb[k] || 0}`);
      }
      ok(same, `${name} 与原版自洽差同构`, `rust ${all.length} 处 vs orig ${oselfShapes.length} 处`);
      continue;
    }
    ok(all.length === 0, `${name} 零差异`, all.slice(0, 4).join(' ; '));
  }
  console.log(failures ? `\nASSERT FAILURES: ${failures}` : '\nASSERT ALL PASS');
  process.exit(failures ? 1 : 0);
}
