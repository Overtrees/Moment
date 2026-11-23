// KaTeX 残差复测探针（Chromium 口径）：
//   Part A 定界符分级段深几何：段高、每个 math 高、定界字形盒的
//          基线上下分布（orig 另记 .katex 高与 strut 内联高）；
//   Part B 符号电池：单符号行内式的 math 宽/高，两侧对照；
//   断言：① 定界段总高两侧差 ≤2px（mpadded strut 钳制后）；
//        ② 字体栈修复后 ∥/∈/∪ 的 math 宽回到数学字体口径
//          （≤ 18 / 24 / 20.5px，不再被 CJK 全角回退撑宽）。
// 用法：node probe_katex_residual.mjs [origBase] [rustBase]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = process.argv[2] || 'http://localhost:8222/Moment.html';
const RUST = process.argv[3] || 'http://localhost:8221/';
const R2 = (n) => Math.round(n * 100) / 100;

const DELIM = '定界分级 $\\big($ $\\Big($ $\\bigg($ $\\Bigg($ 与普通 $(x)$ 对照。';
const SYMS = ['\\sum', '\\prod', '\\int', '\\coprod', '\\oint', '\\bigcup', '\\bigcap', '\\bigvee',
  '\\alpha', '\\beta', '\\gamma', '\\delta', '\\epsilon', '\\zeta', '\\eta', '\\theta', '\\lambda', '\\mu',
  '\\nu', '\\xi', '\\pi', '\\rho', '\\sigma', '\\tau', '\\phi', '\\chi', '\\psi', '\\omega',
  '\\Gamma', '\\Delta', '\\Theta', '\\Lambda', '\\Xi', '\\Pi', '\\Sigma', '\\Phi', '\\Psi', '\\Omega',
  '\\infty', '\\partial', '\\nabla', '\\pm', '\\mp', '\\times', '\\div', '\\cdot', '\\cdots', '\\ldots',
  '\\leq', '\\geq', '\\neq', '\\approx', '\\equiv', '\\propto', '\\in', '\\notin', '\\subset', '\\supset',
  '\\cup', '\\cap', '\\forall', '\\exists', '\\neg', '\\land', '\\lor', '\\rightarrow', '\\leftarrow',
  '\\Rightarrow', '\\Leftrightarrow', '\\uparrow', '\\mapsto', '\\hbar', '\\ell', '\\wp', '\\Re', '\\Im',
  '\\aleph', '\\prime', '\\emptyset', '\\surd', '\\angle', '\\perp', '\\parallel', '\\sim', '\\cong',
  '\\oplus', '\\otimes', '\\sum_{k=1}^n', '\\int_0^1', '\\lim', '\\sin', '\\ln'];
const memo = {
  id: 'kresid1', title: '残差量测', pinned: false,
  createdAt: '2026-11-22T03:00:00.000Z', updatedAt: '2026-11-22T03:00:00.000Z',
  doc: [
    { id: 'kd0', type: 'paragraph', children: [{ text: DELIM }] },
    ...SYMS.map((s, i) => ({ id: 'ks' + i, type: 'paragraph', children: [{ text: '$' + s + '$' }] })),
  ],
};
const payload = { version: 2, exportedAt: '2026-11-22T03:00:00.000Z', memos: [memo], avatars: {} };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function openMemo(isOrig) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log((isOrig ? 'ORIG' : 'RUST') + ' PAGEERROR', String(e).slice(0, 150)));
  await page.goto(isOrig ? ORIG : RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  if (isOrig) {
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
  } else {
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
    }, { mj: JSON.stringify(payload), mf: JSON.stringify({ version: 1, attachments: {} }) });
  }
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(900);
  await page.evaluate(() => {
    const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('残差量测'));
    (t.querySelector('.item-title-text') || t).click();
  });
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
  return { ctx, page };
}

// ---------- Part A + B：原版 ----------
let origDelim = null, origSyms = [];
{
  const { ctx, page } = await openMemo(true);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const body = document.querySelector('.editor-body');
    const blocks = [...body.children];
    // 定界段：块高 + 每个 .katex 的高/基线分布（以段内首个文本的基线为参照，
    // 用文本 Range 的 rect 底边近似基线下沿，另记 strut 内联 height）
    const seg = blocks[0];
    const segRect = seg.getBoundingClientRect();
    const maths = [...seg.querySelectorAll('.katex')].map((k) => {
      const kr = k.getBoundingClientRect();
      const strut = k.querySelector('.strut');
      return {
        katexH: R(kr.height), katexW: R(kr.width),
        topRelSeg: R(kr.top - segRect.top), botRelSeg: R(kr.bottom - segRect.top),
        strutStyleH: strut ? strut.style.height : null,
        strutStyleVA: strut ? strut.style.verticalAlign : null,
      };
    });
    const syms = blocks.slice(1).map((b) => {
      const k = b.querySelector('.katex');
      return k ? { w: R(k.getBoundingClientRect().width), h: R(k.getBoundingClientRect().height) } : null;
    });
    return { segH: R(segRect.height), maths, syms };
  });
  origDelim = m; origSyms = m.syms;
  console.log('PART-A-ORIG', JSON.stringify(m));
  await ctx.close();
}

// ---------- Part A + B：Rust ----------
let rustDelim = null, rustSyms = [], rustDelimHTML = '';
{
  const { ctx, page } = await openMemo(false);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const body = document.querySelector('.editor-body');
    const blocks = [...body.children];
    const seg = blocks[0];
    const segRect = seg.getBoundingClientRect();
    const maths = [...seg.querySelectorAll('math')].map((mt) => {
      const mr = mt.getBoundingClientRect();
      const mo = mt.querySelector('mo');
      const mor = mo ? mo.getBoundingClientRect() : null;
      return {
        mathH: R(mr.height), mathW: R(mr.width),
        topRelSeg: R(mr.top - segRect.top), botRelSeg: R(mr.bottom - segRect.top),
        moH: mor ? R(mor.height) : null, moW: mor ? R(mor.width) : null,
        moTopRelSeg: mor ? R(mor.top - segRect.top) : null, moBotRelSeg: mor ? R(mor.bottom - segRect.top) : null,
      };
    });
    const syms = blocks.slice(1).map((b) => {
      const mt = b.querySelector('math');
      return mt ? { w: R(mt.getBoundingClientRect().width), h: R(mt.getBoundingClientRect().height) } : null;
    });
    return { segH: R(segRect.height), maths, syms, segHTML: seg.innerHTML };
  });
  rustDelim = m; rustSyms = m.syms; rustDelimHTML = m.segHTML;
  console.log('PART-A-RUST', JSON.stringify({ segH: m.segH, maths: m.maths }));
  await ctx.close();
}

// ---------- Part B 对照 ----------
console.log('\n=== 符号电池宽度对照（px，orig -> rust，Δ 与 Δ%） ===');
let sumAbs = 0, cnt = 0, worst = [];
SYMS.forEach((s, i) => {
  const o = origSyms[i], r = rustSyms[i];
  if (!o || !r) { console.log(`${s.padEnd(16)} orig=${o?.w} rust=${r?.w} MISSING`); return; }
  const d = R2(r.w - o.w), pct = R2((r.w - o.w) / o.w * 100);
  sumAbs += Math.abs(d); cnt++;
  worst.push({ s, o: o.w, r: r.w, d, pct });
});
worst.sort((a, b) => Math.abs(b.pct) - Math.abs(a.pct));
console.log('mean|Δ| =', R2(sumAbs / cnt), 'px over', cnt, 'symbols');
console.log('worst by |Δ%|:', JSON.stringify(worst.slice(0, 15)));
console.log('best:', JSON.stringify(worst.slice(-5)));

// ---------- 断言 ----------
let fails = 0;
const assert = (name, ok, detail) => { console.log((ok ? '✓ ' : '✗ ') + name + ' ' + detail); if (!ok) fails++; };
assert('A1 定界段总高对齐', Math.abs(rustDelim.segH - origDelim.segH) <= 2,
  `orig=${origDelim.segH} rust=${rustDelim.segH}`);
const wOf = (s) => rustSyms[SYMS.indexOf(s)]?.w;
assert('B1 ∥ 宽（数学字体口径）', wOf('\\parallel') <= 18, `rust=${wOf('\\parallel')} orig=${origSyms[SYMS.indexOf('\\parallel')]?.w}`);
assert('B2 ∈ 宽（数学字体口径）', wOf('\\in') <= 24, `rust=${wOf('\\in')} orig=${origSyms[SYMS.indexOf('\\in')]?.w}`);
assert('B3 ∪ 宽（数学字体口径）', wOf('\\cup') <= 20.5, `rust=${wOf('\\cup')} orig=${origSyms[SYMS.indexOf('\\cup')]?.w}`);
console.log(fails === 0 ? 'RESIDUAL ASSERT ALL PASS' : `RESIDUAL ASSERT ${fails} FAIL`);

await browser.close();
console.log('PROBE-KATEX-RESIDUAL DONE');
