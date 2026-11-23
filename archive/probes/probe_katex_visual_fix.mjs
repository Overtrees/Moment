// 数学公式视觉对齐量测探针（定界符分级修复复测版）：
//   Part 1 原版（KaTeX）同夹具几何规格（与原件同口径）；
//   Part 2 Rust 版（MathML）同夹具几何（与原件同口径，另记录块文本、
//          分级段四档 mo 的宽与基线上下分布，供残差说明）；
//   Part 3 引擎机制验证页：新发射形态（mathsize 校准 + stretchy=false）
//          的四档 mo 盒高，目标 16×{1.55,2.45,3.35,4.25}={24.8,39.2,53.6,68} ±2px；
//          保留 minsize 对照组（旧机制，应仍全平 16）。
// 用法：node probe_katex_visual_fix.mjs [origBase] [rustBase]
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
  // 原版主存储是 IndexedDB MemosDB v8 的 memos store（keyPath id，
  // 一条备忘一个记录）；localStorage 的 memos_app_v2 只是备份缓存，
  // 不是加载路径——原件用 localStorage 注入是其已知失效点，本副本改直注 IDB。
  await page.evaluate(async (m) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('MemosDB', 8);
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    await new Promise((res, rej) => {
      const tx = db.transaction('memos', 'readwrite');
      tx.objectStore('memos').put(m);
      tx.oncomplete = res; tx.onerror = () => rej(tx.error);
    });
  }, memo);
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(() => document.body.innerText.includes('公式视觉量测'), { timeout: 15000 });
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
    for (const el of [...body.children]) {
      const b = { h: R(el.getBoundingClientRect().height), cls: el.className.slice(0, 24), text: el.textContent.slice(0, 12) };
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
    // 枚举口径修正：现构建编辑器顶层块是 .editor-body 的直接子元素
    // （.md-hit 等），已无 [data-bid]（原件按 [data-bid] 枚举在现
    // 构建上取到 0 块，是其已知失效点）。按直接子元素逐块量，与
    // Part 1 的 body.children 口径一致，每块的量测项不变。
    for (const el of [...body.children]) {
      const b = { h: R(el.getBoundingClientRect().height), text: el.textContent.slice(0, 12) };
      b.math = [...el.querySelectorAll('math')].map((k) => {
        const r = k.getBoundingClientRect();
        return { h: R(r.height), w: R(r.width) };
      });
      // 定界符段：每个 math 内首个 mo 的高度（\big 四档 + 普通括号）
      b.moHeights = [...el.querySelectorAll('math')].map((k) => {
        const mo = k.querySelector('mo');
        return mo ? R(mo.getBoundingClientRect().height) : null;
      });
      // 附加量测（不改上两项口径）：首个 mo 的宽与相对同 math 文本基线的上下分布
      b.moDetail = [...el.querySelectorAll('math')].map((k) => {
        const mo = k.querySelector('mo');
        if (!mo) return null;
        const mr = mo.getBoundingClientRect();
        return { w: R(mr.width), top: R(mr.top), bottom: R(mr.bottom) };
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

// ---------------- Part 3：新发射机制验证 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 800, height: 600 } });
  const page = await ctx.newPage();
  // 与 mathml.rs SizedDelim 发射逐字一致的形态（( 为例，含基线参照 mi）
  const emit = (size) => `<math><mi>x</mi><mo fence="true" form="prefix" stretchy="false" mathsize="${size}">(</mo></math>`;
  await page.setContent(`<!DOCTYPE html><body style="font-size:16px; margin:0">
    <div id="n1">${emit('1.6em')}</div>
    <div id="n2">${emit('2.6em')}</div>
    <div id="n3">${emit('3.5em')}</div>
    <div id="n4">${emit('4.6em')}</div>
    <div id="o1"><math><mi>x</mi><mo stretchy="true" minsize="1.55em" maxsize="1.55em">(</mo></math></div>
    <div id="o4"><math><mi>x</mi><mo stretchy="true" minsize="4.25em" maxsize="4.25em">(</mo></math></div>
    <div id="p0"><math><mi>x</mi><mo>(</mo></math></div>
  </body>`);
  await page.waitForTimeout(300);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const meas = (id) => {
      const root = document.querySelector('#' + id);
      const mo = root.querySelector('mo');
      const mi = root.querySelector('mi');
      const mr = mo.getBoundingClientRect();
      const ir = mi.getBoundingClientRect();
      return {
        moH: R(mr.height), moW: R(mr.width),
        ascent: R(ir.bottom - mr.top), descent: R(mr.bottom - ir.bottom),
        mathsize: mo.getAttribute('mathsize'), fontSize: getComputedStyle(mo).fontSize,
      };
    };
    return {
      new_L1_1_6em: meas('n1'), new_L2_2_6em: meas('n2'), new_L3_3_5em: meas('n3'), new_L4_4_6em: meas('n4'),
      old_minsize_1_55: meas('o1'), old_minsize_4_25: meas('o4'), plain: meas('p0'),
    };
  });
  console.log('PART3-MECHANISMS', JSON.stringify(m, null, 1));
  // 判读：new_L* 的 moH 应 ≈ 16×{1.55,2.45,3.35,4.25} = {24.8, 39.2, 53.6, 68}（±2px）；
  // old_minsize_* 应仍为 16（旧机制无效的对照）；plain 为 16。
  await ctx.close();
}

await browser.close();
console.log('PROBE-KATEX-VISUAL-FIX DONE');
