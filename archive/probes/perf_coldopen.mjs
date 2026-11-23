// 冷开分段探针（调优续推线）：每轮全新浏览器（冷 wasm 编译/JIT），
// 导入 300 篇压测集后量「点开首篇」的分段耗时，再关回重开量温开。
// 分段：click→.editor-body 首现（首渲）→桥就绪（__mnFocus）→聚焦落位
// →静默 settle；附 longtask 列表与 Diag 中 WIKI/EDIT 行。
// 用法：node perf_coldopen.mjs <base> [rounds]
import { chromium } from 'playwright-core';

const base = process.argv[2];
const ROUNDS = parseInt(process.argv[3] || '5', 10);
const ZIP = '/tmp/big300.zip';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const INSTRUMENT = () => {
  window.__seg = { marks: {}, long: [] };
  try {
    const po = new PerformanceObserver((list) => {
      for (const e of list.getEntries()) window.__seg.long.push(Math.round(e.duration));
    });
    po.observe({ entryTypes: ['longtask'] });
    window.__seg.po = po;
  } catch (_) {}
  const mo = new MutationObserver(() => {
    window.__seg.lastMut = performance.now();
    if (!window.__seg.marks.body && document.querySelector('.editor-body')) {
      window.__seg.marks.body = performance.now();
    }
    if (!window.__seg.marks.backlinks && document.querySelector('.wiki-backlinks')) {
      window.__seg.marks.backlinks = performance.now();
    }
  });
  mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
  window.__seg.mo = mo;
  const poll = () => {
    if (!window.__seg.marks.bridge && typeof window.__mnFocus === 'function') {
      window.__seg.marks.bridge = performance.now();
    }
    if (!window.__seg.marks.focus) {
      const ae = document.activeElement;
      if (ae && ae.isContentEditable && ae.closest && ae.closest('[data-bid]')) {
        window.__seg.marks.focus = performance.now();
        window.__seg.focusEl = (ae.id || '') + '|' + (ae.dataset.bid || '') + '|' + (ae.className || '');
      }
    }
    if (!window.__seg.marks.bridge || !window.__seg.marks.focus) setTimeout(poll, 2);
  };
  setTimeout(poll, 0);
};

async function openFirst(page) {
  // 折叠组（>2 篇）首卡点击只展开不开篇（原版规格）：目标卡
  // 在 .card-expand-wrapper 内时先点一次展开（不计时），已
  // 展开则跳过——冷开轮组必折叠、温开轮组已展开，自适应。
  const needsExpand = await page.evaluate(() => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => e.textContent.includes('压测笔记'));
    if (card && card.closest('.card-expand-wrapper')) { card.click(); return true; }
    return false;
  });
  if (needsExpand) await page.waitForTimeout(800);
  await page.evaluate(INSTRUMENT);
  const t0 = await page.evaluate(() => {
    // 必须点卡片本体：标题文本有独立处理器、点击不打开
    const el = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => e.textContent.includes('压测笔记'));
    if (!el) return -1;
    const t = performance.now();
    el.click();
    return t;
  });
  if (t0 < 0) return { seg: { error: 'target memo not in list' }, diag: [] };
  await page.waitForTimeout(3500);
  const seg = await page.evaluate((t0) => {
    const m = window.__seg.marks || {};
    const rel = (v) => (v == null ? null : Math.round(v - t0));
    return {
      title: document.querySelector('#editor-title-text')?.textContent || '',
      blocks: document.querySelectorAll('.editor-body [data-bid]').length,
      body: rel(m.body),
      bridge: rel(m.bridge),
      focus: rel(m.focus),
      backlinks: rel(m.backlinks),
      settle: window.__seg.lastMut ? Math.round(window.__seg.lastMut - t0) : null,
      focusEl: window.__seg.focusEl || null,
      long: window.__seg.long || [],
    };
  }, t0);
  const diag = await page.evaluate(() => {
    try {
      const lines = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
      return lines.filter((l) => /WIKI|PERF|EDIT/.test(l)).slice(-8);
    } catch (_) { return []; }
  });
  return { seg, diag };
}

async function backToList(page) {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(400);
}

const results = [];
for (let r = 0; r < ROUNDS; r++) {
  const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  const row = { round: r + 1 };
  try {
    await page.goto(base, { waitUntil: 'load' });
    await page.waitForSelector('.list-item', { timeout: 30000 });
    // 导入 300 篇（选择器等待，不用固定睡眠：并行构建抢 CPU 时
    // 固定等待会间歇性错过导入流）
    await page.$eval('h1.page-title', (e) => e.click());
    await page.waitForSelector('.page-content', { timeout: 15000 });
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForSelector('#file-import', { state: 'attached', timeout: 15000 });
    await page.setInputFiles('#file-import', ZIP);
    await page.waitForSelector('.backup-modal', { timeout: 15000 });
    await page.click('.backup-modal .backup-btn.primary');
    await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 30000 });
    // 冷加载到列表（等导入集真正上屏：种子先行、分组折叠，
    // 以「首张卡是压测篇」为准入信号；各压测篇结构同构，
    // 点首张即可，标题与块数由 seg 字段自证）
    const tl0 = Date.now();
    await page.reload({ waitUntil: 'load' });
    await page.waitForFunction(() => {
      // 注意：DOM 首个标题是「新建笔记」composer 卡，须查任一
      return [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')]
        .some((e) => e.textContent.includes('压测笔记'));
    }, null, { timeout: 60000 });
    await page.waitForTimeout(800);
    row.loadMs = Date.now() - tl0;
    row.cold = await openFirst(page);
    await backToList(page);
    row.warm = await openFirst(page);
    await backToList(page);
    row.warm2 = await openFirst(page);
  } catch (e) {
    row.error = String(e).slice(0, 200);
  }
  results.push(row);
  console.log(JSON.stringify(row));
  await browser.close();
}

const med = (vals) => {
  const v = vals.filter((x) => x != null).sort((a, b) => a - b);
  return v.length ? v[Math.floor(v.length / 2)] : null;
};
const pick = (k, sub) => results.map((r) => (r[k] && !r[k].error ? r[k].seg[sub] : null));
console.log('MEDIAN loadMs=', med(results.map((r) => r.loadMs)));
for (const k of ['cold', 'warm', 'warm2']) {
  console.log(`MEDIAN ${k}: body=${med(pick(k, 'body'))} bridge=${med(pick(k, 'bridge'))} focus=${med(pick(k, 'focus'))} settle=${med(pick(k, 'settle'))} longSum=${med(results.map((r) => (r[k] ? r[k].seg.long.reduce((a, b) => a + b, 0) : null)))}`);
}
