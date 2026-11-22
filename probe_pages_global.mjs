// 全局项只读审计探针：启动/toast/深色/语言/字号/SW/滚动/错误兜底
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const RUST = 'http://localhost:8100/';
const ORIG = 'http://localhost:8101/Moment.html';
const REALZIP = process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const R = {};
const log = (...a) => console.log(...a);
async function section(name, fn) {
  try { R[name] = await fn(); log('##', name, JSON.stringify(R[name]).slice(0, 3000)); }
  catch (e) { R[name] = { error: String(e).slice(0, 500) }; log('##', name, 'ERROR', R[name].error); }
}
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
async function ctx(opts = {}) {
  return browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, ...opts });
}
async function rustPage(c) { const p = await c.newPage(); return p; }
async function toSettings(p) { await p.$eval('h1.page-title', e => e.click()); await p.waitForTimeout(800); }
async function backToList(p) { for (let i = 0; i < 2; i++) { const f = await p.$('.editor-fab.left'); if (f) { await f.click(); await p.waitForTimeout(600); } } }
const cs = (p, sel, props) => p.evaluate(([s, ps]) => {
  const el = document.querySelector(s); if (!el) return null;
  const c = getComputedStyle(el); const o = {}; for (const k of ps) o[k] = c[k]; return o;
}, [sel, props]);
const overflow = p => p.evaluate(() => ({ sw: document.documentElement.scrollWidth, bw: document.body ? document.body.scrollWidth : -1, iw: innerWidth, se: document.scrollingElement === document.documentElement ? 'html' : String(document.scrollingElement) }));
async function visibleCJK(p) {
  return p.evaluate(() => {
    const out = new Set();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT_NODE);
    let n; while ((n = walker.nextNode())) {
      const el = n.parentElement; if (!el) continue;
      const c = getComputedStyle(el);
      if (c.display === 'none' || c.visibility === 'hidden') continue;
      const t = (n.textContent || '').trim();
      if (t && /[\u4e00-\u9fff]/.test(t)) out.add(t.slice(0, 60));
    }
    return [...out];
  });
}

// ---------- 0. 语言包键集（程序化） ----------
await section('langKeys', async () => {
  const codes = ['zh-CN', 'zh-TW', 'en-US', 'ja-JP', 'ko-KR'];
  const packs = {}; for (const c of codes) packs[c] = JSON.parse(fs.readFileSync(`rust/apps/web/lang/${c}.json`, 'utf8'));
  const base = new Set(Object.keys(packs['zh-CN'])); const out = { counts: {}, diffs: {} };
  for (const c of codes) { const s = new Set(Object.keys(packs[c])); out.counts[c] = s.size; out.diffs[c] = { missing: [...base].filter(k => !s.has(k)), extra: [...s].filter(k => !base.has(k)) }; }
  // en-US 值含汉字 / ja-JP 值与 zh-CN 完全相同（疑似未译）
  out.enCJK = Object.entries(packs['en-US']).filter(([, v]) => /[\u4e00-\u9fff]/.test(v)).map(([k]) => k);
  out.jaSameAsZh = Object.keys(packs['ja-JP']).filter(k => packs['ja-JP'][k] === packs['zh-CN'][k]);
  out.enSameAsZh = Object.keys(packs['en-US']).filter(k => packs['en-US'][k] === packs['zh-CN'][k]);
  return out;
});

// ---------- 1+2+7. 启动 / 启动无 toast / 二次不重复播种 / 滚动 ----------
await section('startup', async () => {
  const c = await ctx(); const p = await rustPage(c);
  const t0 = Date.now();
  const nav = p.goto(RUST, { waitUntil: 'commit' });
  let splashAt = null, listAt = null;
  const poll = (async () => {
    for (let i = 0; i < 200; i++) {
      const s = await p.evaluate(() => ({ splash: !!document.querySelector('.splash'), item: document.querySelectorAll('.list-item').length, toast: document.querySelectorAll('.status-toast').length })).catch(() => null);
      if (s) { if (s.splash && splashAt === null) splashAt = Date.now() - t0; if (s.item > 0 && listAt === null) { listAt = Date.now() - t0; break; } }
      await p.waitForTimeout(25);
    }
  })();
  await nav; await poll;
  await p.waitForTimeout(3500); // 等过 toast 淡出窗口，确认启动不弹
  const first = await p.evaluate(() => ({ items: document.querySelectorAll('.list-item').length, titles: [...document.querySelectorAll('.item-title-text')].map(e => e.textContent.trim()).slice(0, 8), toast: document.querySelectorAll('.status-toast').length, bodyBg: getComputedStyle(document.body).backgroundColor }));
  const ov1 = await overflow(p);
  await p.reload({ waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 }); await p.waitForTimeout(800);
  const second = await p.evaluate(() => ({ items: document.querySelectorAll('.list-item').length, titles: [...document.querySelectorAll('.item-title-text')].map(e => e.textContent.trim()).slice(0, 8) }));
  await c.close();
  return { splashSeenAtMs: splashAt, listAtMs: listAt, first, second, seedStable: first.items === second.items && JSON.stringify(first.titles) === JSON.stringify(second.titles), overflowList: ov1 };
});

// ---------- 2. Toast 实测（导入触发 ×2） ----------
await section('toast', async () => {
  const c = await ctx(); const p = await rustPage(c);
  await p.goto(RUST, { waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 }); await p.waitForTimeout(500);
  async function doImport() {
    await toSettings(p);
    await p.click('.set-row >> nth=0'); await p.waitForTimeout(800);
    await p.setInputFiles('#file-import', REALZIP);
    await p.waitForSelector('.backup-modal .backup-btn.primary', { timeout: 10000 });
    const t0 = Date.now();
    await p.click('.backup-modal .backup-btn.primary');
    let appear = null, gone = null, maxCount = 0, info = null;
    for (let i = 0; i < 160; i++) {
      const s = await p.evaluate(() => {
        const ts = [...document.querySelectorAll('.status-toast')];
        return { n: ts.length, vis: ts.map(t => { const c = getComputedStyle(t); return { text: t.textContent.trim(), opacity: c.opacity, vis: c.visibility, bottom: Math.round(innerHeight - t.getBoundingClientRect().bottom), left: Math.round(t.getBoundingClientRect().left) }; }) };
      });
      maxCount = Math.max(maxCount, s.n);
      const vis = s.vis.find(v => v.opacity !== '0' && v.vis !== 'hidden');
      if (vis && appear === null) { appear = Date.now() - t0; info = vis; }
      if (appear !== null && !vis) { gone = Date.now() - t0; break; }
      await p.waitForTimeout(50);
    }
    return { appearMs: appear, goneMs: gone, visibleDurMs: appear !== null && gone !== null ? gone - appear : null, maxToastCount: maxCount, info };
  }
  const first = await doImport();
  await backToList(p);
  const itemsAfter = await p.evaluate(() => document.querySelectorAll('.list-item').length);
  const second = await doImport();
  await c.close();
  return { first, second, itemsAfterImport: itemsAfter };
});

// ---------- 3. 深色（Rust + 原版） ----------
async function darkSample(base, isOrig) {
  const c = await ctx({ colorScheme: 'dark' }); const p = await c.newPage();
  await p.goto(base, { waitUntil: 'load' });
  if (isOrig) await p.waitForTimeout(3000); else await p.waitForSelector('.list-item', { timeout: 20000 });
  await p.waitForTimeout(600);
  const list = {
    body: await cs(p, 'body', ['backgroundColor', 'color']),
    rootVar: await p.evaluate(() => { const c = getComputedStyle(document.documentElement); return { primaryBg: c.getPropertyValue('--primary-bg').trim(), textMain: c.getPropertyValue('--text-main').trim(), cardBg: c.getPropertyValue('--card-bg').trim() || c.getPropertyValue('--secondary-bg').trim() }; }),
    card: await cs(p, '.list-item', ['backgroundColor', 'color']),
    themeColorDark: await p.evaluate(() => { const m = document.querySelector('meta[name="theme-color"][media*="dark"]'); const l = document.querySelector('meta[name="theme-color"][media*="light"]'); return { dark: m && m.content, light: l && l.content }; }),
  };
  let pages = null;
  if (!isOrig) {
    await toSettings(p);
    const settings = { body: await cs(p, 'body', ['backgroundColor']), card: await cs(p, '.list-item', ['backgroundColor', 'color']), ov: await overflow(p) };
    await p.click('.set-row >> nth=0'); await p.waitForTimeout(800);
    const backup = { card: await cs(p, '.backup-card, .list-item', ['backgroundColor', 'color']), ov: await overflow(p) };
    await backToList(p);
    await toSettings(p);
    await p.click('.set-row >> nth=2'); await p.waitForTimeout(800);
    const diag = { body: await cs(p, '.diag-body', ['backgroundColor', 'color']), ov: await overflow(p) };
    await backToList(p);
    const item = await p.$('.list-item'); if (item) { await item.click(); await p.waitForTimeout(1200); }
    const editor = { body: await cs(p, '.editor-body', ['backgroundColor', 'color']), dock: await cs(p, '.editor-title-dock', ['backgroundColor', 'color']), text: await cs(p, '.editor-body [contenteditable], .editor-body .blk', ['color']), ov: await overflow(p) };
    pages = { settings, backup, diag, editor };
  }
  await c.close();
  return { list, pages };
}
await section('darkRust', () => darkSample(RUST, false));
await section('darkOrig', () => darkSample(ORIG, true));

// ---------- 4. 语言完整性 en-US / ja-JP ----------
await section('i18nRuntime', async () => {
  const c = await ctx(); const p = await rustPage(c);
  await p.goto(RUST, { waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 }); await p.waitForTimeout(500);
  const seedTitles = await p.evaluate(() => [...document.querySelectorAll('.item-title-text')].map(e => e.textContent.trim()));
  await toSettings(p); await p.click('.set-row >> nth=1'); await p.waitForTimeout(800);
  await p.click('.list-item:has-text("English")'); await p.waitForTimeout(1500);
  const pages = {};
  await backToList(p); pages.list_en = await visibleCJK(p);
  await toSettings(p); pages.settings_en = await visibleCJK(p);
  await p.click('.set-row >> nth=0'); await p.waitForTimeout(800); pages.backup_en = await visibleCJK(p);
  await backToList(p);
  const item = await p.$('.list-item'); if (item) { await item.click(); await p.waitForTimeout(1200); }
  pages.editor_en = await visibleCJK(p);
  await p.click('.editor-fab.left'); await p.waitForTimeout(700);
  await toSettings(p); await p.click('.set-row >> nth=2'); await p.waitForTimeout(800); pages.diag_en_raw = await visibleCJK(p); // 诊断含日志文本，单独标注
  // 切 ja-JP 看设置页
  await backToList(p); await toSettings(p); await p.click('.set-row >> nth=1'); await p.waitForTimeout(800);
  await p.click('.list-item:has-text("日本語")'); await p.waitForTimeout(1500);
  await backToList(p); await toSettings(p); pages.settings_ja = await visibleCJK(p);
  const settingsJaText = await p.evaluate(() => document.body.innerText.slice(0, 400));
  await c.close();
  return { seedTitles, pages, settingsJaText };
});

// ---------- 5. 字号全局 ----------
await section('fontSize', async () => {
  const c = await ctx(); const p = await rustPage(c);
  await p.goto(RUST, { waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 }); await p.waitForTimeout(500);
  const measure = async (where) => p.evaluate((w) => {
    const q = s => { const el = document.querySelector(s); return el ? parseFloat(getComputedStyle(el).fontSize) : null; };
    return { root: parseFloat(getComputedStyle(document.documentElement).fontSize), cardTitle: q('.list-item .item-title-text'), editorText: q('.editor-body [contenteditable="true"], .editor-body .blk-text, .editor-body p'), setRow: q('.set-row .item-title-text') };
  }, where);
  const before = await measure('list');
  await toSettings(p);
  await p.click('.seg-btn:has-text("大")'); await p.waitForTimeout(600);
  const settingsLarge = await measure('settings');
  await backToList(p); const listLarge = await measure('list');
  const item = await p.$('.list-item'); if (item) { await item.click(); await p.waitForTimeout(1200); }
  const editorLarge = await measure('editor');
  await p.evaluate(() => localStorage.setItem('sj_fontsize', 'medium'));
  await c.close();
  return { before, settingsLarge, listLarge, editorLarge };
});

// ---------- 6+8. SW + 离线 + 坏数据 ----------
await section('sw', async () => {
  const c = await ctx(); const p = await rustPage(c);
  await p.goto(RUST, { waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 });
  await p.waitForTimeout(2500);
  const reg = await p.evaluate(async () => {
    const r = await navigator.serviceWorker.getRegistration();
    const keys = await caches.keys();
    let core = null; if (keys.length) { const cache = await caches.open(keys[0]); core = (await cache.keys()).map(x => new URL(x.url).pathname); }
    return { scope: r && r.scope, active: !!(r && r.active), scriptURL: r && r.active && r.active.scriptURL, keys, core };
  });
  // 二次加载
  await p.reload({ waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 }); await p.waitForTimeout(500);
  const secondLoadOk = await p.evaluate(() => document.querySelectorAll('.list-item').length);
  // 断网刷新
  await c.setOffline(true);
  let offline = null;
  try { await p.reload({ waitUntil: 'load', timeout: 15000 }); await p.waitForTimeout(2500); offline = await p.evaluate(() => ({ items: document.querySelectorAll('.list-item').length, splash: !!document.querySelector('.splash'), text: document.body.innerText.slice(0, 80) })); }
  catch (e) { offline = { error: String(e).slice(0, 200) }; }
  await c.setOffline(false);
  // 坏诊断数据兜底（新上下文预置坏值）
  const c2 = await ctx(); await c2.addInitScript(() => { try { localStorage.setItem('mynote_diag_v1', '{{{bad json'); localStorage.setItem('sj_fontsize', 'huge-invalid'); } catch (e) {} });
  const p2 = await c2.newPage(); const errs = []; p2.on('pageerror', e => errs.push(String(e).slice(0, 160)));
  await p2.goto(RUST, { waitUntil: 'load' });
  let badData = null;
  try { await p2.waitForSelector('.list-item', { timeout: 20000 }); badData = { items: await p2.evaluate(() => document.querySelectorAll('.list-item').length), rootFs: await p2.evaluate(() => getComputedStyle(document.documentElement).fontSize) }; }
  catch (e) { badData = { error: String(e).slice(0, 200) }; }
  badData.pageerrors = errs;
  await c.close(); await c2.close();
  return { reg, secondLoadItems: secondLoadOk, offline, badData };
});

// ---------- 7. 各页横向溢出（浅色补充：设置/备份/编辑） ----------
await section('overflowPages', async () => {
  const c = await ctx(); const p = await rustPage(c);
  await p.goto(RUST, { waitUntil: 'load' }); await p.waitForSelector('.list-item', { timeout: 20000 }); await p.waitForTimeout(400);
  const out = { list: await overflow(p) };
  await toSettings(p); out.settings = await overflow(p);
  await p.click('.set-row >> nth=0'); await p.waitForTimeout(700); out.backup = await overflow(p);
  await backToList(p);
  const item = await p.$('.list-item'); if (item) { await item.click(); await p.waitForTimeout(1000); }
  out.editor = await overflow(p);
  await c.close(); return out;
});

fs.writeFileSync('/tmp/audit_pages_global_raw.json', JSON.stringify(R, null, 2));
await browser.close();
log('DONE');
