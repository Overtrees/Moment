// 数学公式视觉对齐量测探针（三部分）：
//   Part 1 原版（KaTeX）同夹具几何规格；
//   Part 2 Rust 版（MathML）同夹具几何（需当前源码构建的 dist 在 8096）；
//   Part 3 引擎机制验证页（与应用无关）：mo minsize/maxsize 钉高、
//          mtable rowlines 描线、物化空行高度、mfrac linethickness。
// 用法：node probe_katex_visual.mjs [origBase] [rustBase]
//   默认 orig http://localhost:8117/Moment.html，rust http://localhost:8096/
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = process.argv[2] || 'http://localhost:8117/Moment.html';
const RUST = process.argv[3] || 'http://localhost:8096/';

const PARAS = [
  '质能方程 $E=mc^2$ 与分式 $\\frac{a+b}{2}$、根号 $\\sqrt{x^2+1}$ 中英混排。',
  '$$\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}$$',
  '前文混排 $$x^2+y^2=z^2$$ 后文继续，段中块式几何量测。',
  '定界分级 $\\big($ $\\Big($ $\\bigg($ $\\Bigg($ 与普通 $(x)$ 对照。',
  '$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$',
  '$$\\begin{array}{|c|c|} \\hline a & b \\\\ \\hline c & d \\\\ \\hline \\end{array}$$',
  '行内求和 $\\sum_{k=1}^{n} k^2$ 与块级 $$\\sum_{k=1}^{n} k^2$$ 对照段。',
];
const memo = {
  id: 'mathvis1', title: '公式视觉量测', pinned: false,
  createdAt: '2026-11-21T02:00:00.000Z', updatedAt: '2026-11-21T02:00:00.000Z',
  doc: PARAS.map((t, i) => ({ id: 'mv' + (i + 1), type: 'paragraph', children: [{ text: t }] })),
};
const payload = { version: 2, exportedAt: '2026-11-21T02:00:00.000Z', memos: [memo], avatars: {} };
const manifest = JSON.stringify({ version: 1, attachments: {} });
const R2 = (n) => Math.round(n * 100) / 100;

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

// ---------------- Part 1：原版规格 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('ORIG PAGEERROR', String(e).slice(0, 150)));
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate((memos) => {
    localStorage.setItem('memos_app_v2', JSON.stringify(memos));
  }, [memo]);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(800);
  await page.evaluate(() => {
    const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('公式视觉量测'));
    (t.querySelector('.item-title-text') || t).click();
  });
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const body = document.querySelector('.editor-body');
    const out = { blocks: [] };
    out.bodyFontSize = parseFloat(getComputedStyle(body).fontSize);
    const kx = body.querySelector('.katex');
    if (kx) {
      out.katexFontSize = parseFloat(getComputedStyle(kx).fontSize);
      const p = kx.closest('p,div');
      out.paraFontSize = p ? parseFloat(getComputedStyle(p).fontSize) : null;
    }
    const fl = body.querySelector('.frac-line');
    if (fl) out.fracLineBorderBottom = getComputedStyle(fl).borderBottomWidth;
    // 按顶层块逐个量（编辑器顶层子元素与夹具段一一对应）
    for (const el of [...body.children]) {
      const b = { h: R(el.getBoundingClientRect().height), cls: el.className.slice(0, 24) };
      b.katex = [...el.querySelectorAll('.katex')].map((k) => {
        const r = k.getBoundingClientRect();
        return { h: R(r.height), w: R(r.width) };
      });
      const mb = el.querySelector('.math-block') || (el.classList.contains('math-block') ? el : null);
      if (mb) {
        const cs = getComputedStyle(mb);
        const r = mb.getBoundingClientRect();
        b.mathBlock = {
          display: cs.display, h: R(r.height), w: R(r.width),
          marginTop: cs.marginTop, marginBottom: cs.marginBottom,
          parentTag: mb.parentElement ? mb.parentElement.tagName : '',
        };
      }
      out.blocks.push(b);
    }
    return out;
  });
  console.log('PART1-ORIG', JSON.stringify(m, null, 1));
  await ctx.close();
}

// ---------------- Part 2：Rust 侧同夹具 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('RUST PAGEERROR', String(e).slice(0, 150)));
  await page.goto(RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate(async ({ mj, mf }) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('mynote-web', 1);
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    await new Promise((res, rej) => {
      const tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(mj, 'memos_json');
      tx.objectStore('kv').put(mf, 'manifest_raw');
      tx.oncomplete = res; tx.onerror = () => rej(tx.error);
    });
  }, { mj: JSON.stringify(payload), mf: manifest });
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(() => document.body.innerText.includes('公式视觉量测'), { timeout: 15000 });
  await page.evaluate(() => {
    const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('公式视觉量测'));
    (t.querySelector('.item-title-text') || t).click();
  });
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1200);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const body = document.querySelector('.editor-body');
    const out = { blocks: [] };
    out.bodyFontSize = parseFloat(getComputedStyle(body).fontSize);
    const mt = body.querySelector('math');
    if (mt) {
      out.mathFontSize = parseFloat(getComputedStyle(mt).fontSize);
      const p = mt.closest('p,div');
      out.paraFontSize = p ? parseFloat(getComputedStyle(p).fontSize) : null;
      out.paraLineHeight = p ? getComputedStyle(p).lineHeight : null;
    }
    for (const el of [...body.querySelectorAll('[data-bid]')]) {
      const b = { h: R(el.getBoundingClientRect().height) };
      b.math = [...el.querySelectorAll('math')].map((k) => {
        const r = k.getBoundingClientRect();
        return { h: R(r.height), w: R(r.width) };
      });
      // 定界符段：每个 math 内首个 mo 的高度（\big 四档 + 普通括号）
      b.moHeights = [...el.querySelectorAll('math')].map((k) => {
        const mo = k.querySelector('mo');
        return mo ? R(mo.getBoundingClientRect().height) : null;
      });
      const mb = el.querySelector('.math-block');
      if (mb) {
        const cs = getComputedStyle(mb);
        const r = mb.getBoundingClientRect();
        b.mathBlock = {
          display: cs.display, h: R(r.height), w: R(r.width),
          marginTop: cs.marginTop, marginBottom: cs.marginBottom,
          tag: mb.tagName,
        };
      }
      const tab = el.querySelector('mtable');
      if (tab) {
        const rows = [...tab.querySelectorAll(':scope > mtr')];
        const cells = rows.length ? [...rows[0].querySelectorAll(':scope > mtd')] : [];
        b.mtable = {
          h: R(tab.getBoundingClientRect().height),
          w: R(tab.getBoundingClientRect().width),
          rowTops: rows.map((r) => R(r.getBoundingClientRect().top)),
          rowHeights: rows.map((r) => R(r.getBoundingClientRect().height)),
          cellLefts: cells.map((c) => R(c.getBoundingClientRect().left)),
          cellWidths: cells.map((c) => R(c.getBoundingClientRect().width)),
          rowlines: tab.getAttribute('rowlines'),
          columnlines: tab.getAttribute('columnlines'),
          rowspacing: tab.getAttribute('rowspacing'),
          columnspacing: tab.getAttribute('columnspacing'),
        };
      }
      out.blocks.push(b);
    }
    return out;
  });
  console.log('PART2-RUST', JSON.stringify(m, null, 1));
  await ctx.close();
}

// ---------------- Part 3：引擎机制验证 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 800, height: 600 } });
  const page = await ctx.newPage();
  await page.setContent(`<!DOCTYPE html><body style="font-size:16px; margin:0">
    <div id="t1"><math><mo stretchy="true" minsize="1.55em" maxsize="1.55em">(</mo></math></div>
    <div id="t2"><math><mo stretchy="true" minsize="2.45em" maxsize="2.45em">(</mo></math></div>
    <div id="t3"><math><mo stretchy="true" minsize="4.25em" maxsize="4.25em">(</mo></math></div>
    <div id="t4"><math><mo>(</mo></math></div>
    <div id="t5"><math><mtable rowlines="solid"><mtr><mtd><mi>a</mi></mtd></mtr><mtr><mtd><mi>b</mi></mtd></mtr></mtable></math></div>
    <div id="t6"><math><mtable><mtr><mtd><mi>a</mi></mtd></mtr><mtr><mtd><mi>b</mi></mtd></mtr></mtable></math></div>
    <div id="t7"><math><mtable rowlines="solid none"><mtr><mtd></mtd></mtr><mtr><mtd><mi>a</mi></mtd></mtr><mtr><mtd><mi>b</mi></mtd></mtr></mtable></math></div>
    <div id="t8"><math><mfrac linethickness="0.04em"><mn>1</mn><mn>2</mn></mfrac></math></div>
    <div id="t9"><math><mfrac><mn>1</mn><mn>2</mn></mfrac></math></div>
    <div id="t10"><math><mtable columnlines="solid"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr></mtable></math></div>
  </body>`);
  await page.waitForTimeout(300);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const h = (id) => {
      const el = document.querySelector('#' + id + ' math, #' + id + ' mo, #' + id + ' mtable, #' + id + ' mfrac');
      return el ? R(el.getBoundingClientRect().height) : null;
    };
    const rows = (id) => [...document.querySelectorAll('#' + id + ' mtr')].map((r) => {
      const b = r.getBoundingClientRect();
      return { top: R(b.top), h: R(b.height) };
    });
    return {
      mo_minsize_1_55: h('t1'), mo_minsize_2_45: h('t2'), mo_minsize_4_25: h('t3'), mo_plain: h('t4'),
      table_rowlines_h: h('t5'), table_plain_h: h('t6'),
      table_emptyrow_rows: rows('t7'),
      frac_004em_h: h('t8'), frac_default_h: h('t9'),
      table_columnlines_w: (() => { const el = document.querySelector('#t10 mtable'); return el ? R(el.getBoundingClientRect().width) : null; })(),
    };
  });
  console.log('PART3-MECHANISMS', JSON.stringify(m, null, 1));
  // 判读：mo_minsize_* 应 ≈ 16×{1.55,2.45,4.25} = {24.8, 39.2, 68}（±2px）；
  // table_rowlines_h 应比 table_plain_h 大（线占位）或相等（线画在间隙内）；
  // table_emptyrow_rows[0].h 应 ≈ 0（物化空行不撑高）；
  // frac_004em_h 与 frac_default_h 的差反映默认线宽与 0.04em 的关系。
  await ctx.close();
}

await browser.close();
console.log('PROBE-KATEX-VISUAL DONE');
