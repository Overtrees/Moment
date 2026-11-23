// KaTeX 矩阵总高补偿量测探针：
//   Part 1 原版 KaTeX 同语料各矩阵块高（.katex 高）；
//   Part 2 Rust MathML 同语料（math 高 + mtable 高 + 行顶距）；
//   Part 3 机制页：取 Rust 实际发射的 <math> 串，扫 rowspacing
//          增量，量字母阵与分数阵（高内容行）总高变化，
//          判断温和补偿是否可落地。
// 用法：node probe_matrix_height.mjs [origBase] [rustBase]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = process.argv[2] || 'http://localhost:8199/Moment.html';
const RUST = process.argv[3] || 'http://localhost:8197/';
const R2 = (n) => Math.round(n * 100) / 100;

const PARAS = [
  '$$\\begin{pmatrix} a \\end{pmatrix}$$',
  '$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$',
  '$$\\begin{pmatrix} a & b & c \\\\ d & e & f \\\\ g & h & i \\end{pmatrix}$$',
  '$$\\begin{pmatrix} a & b & c & d \\\\ e & f & g & h \\\\ i & j & k & l \\\\ m & n & o & p \\end{pmatrix}$$',
  '$$\\begin{pmatrix} \\frac{1}{2} & \\frac{1}{3} \\\\ \\frac{1}{4} & \\frac{1}{5} \\end{pmatrix}$$',
  '$$\\begin{bmatrix} 1 & 2 \\\\ 3 & 4 \\end{bmatrix}$$',
  '$$f(x)=\\begin{cases} a, & x>0 \\\\ b, & x \\le 0 \\end{cases}$$',
  '$$\\begin{aligned} a &= b \\\\ c &= d \\\\ e &= f \\end{aligned}$$',
];
const NAMES = ['pmatrix 1x1', 'pmatrix 2x2 letters', 'pmatrix 3x3 letters', 'pmatrix 4x4 letters', 'pmatrix 2x2 fractions', 'bmatrix 2x2 nums', 'cases 2 rows', 'aligned 3 rows'];
const memo = {
  id: 'mxprobe1', title: '矩阵量测', pinned: false,
  createdAt: '2026-11-22T02:00:00.000Z', updatedAt: '2026-11-22T02:00:00.000Z',
  doc: PARAS.map((t, i) => ({ id: 'mx' + (i + 1), type: 'paragraph', children: [{ text: t }] })),
};
const payload = { version: 2, exportedAt: '2026-11-22T02:00:00.000Z', memos: [memo], avatars: {} };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

// ---------------- Part 1：原版 ----------------
let origH = [];
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('ORIG PAGEERROR', String(e).slice(0, 150)));
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  // 原版以 IDB MemosDB 为准（LS 直注会被 IDB 覆盖，见
  // audit_katex_eval §5）：直注 memos 表（keyPath id）。
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
  await page.waitForTimeout(900);
  await page.evaluate(() => {
    const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('矩阵量测'));
    (t.querySelector('.item-title-text') || t).click();
  });
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1600);
  origH = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const body = document.querySelector('.editor-body');
    return [...body.children].map((el) => {
      const k = el.querySelector('.katex');
      return {
        blockH: R(el.getBoundingClientRect().height),
        katexH: k ? R(k.getBoundingClientRect().height) : null,
      };
    });
  });
  console.log('PART1-ORIG', JSON.stringify(origH));
  await ctx.close();
}

// ---------------- Part 2：Rust ----------------
let rustM = [];
let rustMathHTML = [];
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
  }, { mj: JSON.stringify(payload), mf: JSON.stringify({ version: 1, attachments: {} }) });
  await page.reload({ waitUntil: 'load' });
  await page.waitForFunction(() => document.body.innerText.includes('矩阵量测'), { timeout: 15000 });
  await page.evaluate(() => {
    const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('矩阵量测'));
    (t.querySelector('.item-title-text') || t).click();
  });
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1200);
  const m = await page.evaluate(() => {
    const R = (n) => Math.round(n * 100) / 100;
    const body = document.querySelector('.editor-body');
    const blocks = [];
    const htmls = [];
    // Rust 编辑器把每个 $$ 段渲染为「公式块 + 尾随空段」两块，
    // 只取含 math 的块与原版 8 段对位（2026-11-22 修正）。
    for (const el of [...body.children].filter((e) => e.querySelector('math'))) {
      const math = el.querySelector('math');
      const tab = el.querySelector('mtable');
      const rows = tab ? [...tab.querySelectorAll(':scope > mtr')] : [];
      blocks.push({
        blockH: R(el.getBoundingClientRect().height),
        mathH: math ? R(math.getBoundingClientRect().height) : null,
        tableH: tab ? R(tab.getBoundingClientRect().height) : null,
        rowTops: rows.map((r) => R(r.getBoundingClientRect().top)),
        rowspacing: tab ? tab.getAttribute('rowspacing') : null,
      });
      htmls.push(math ? math.outerHTML : '');
    }
    return { blocks, htmls };
  });
  rustM = m.blocks; rustMathHTML = m.htmls;
  console.log('PART2-RUST', JSON.stringify(rustM));
  await ctx.close();
}

// ---------------- 对照表 ----------------
console.log('\n=== 矩阵总高对照（px @16px 根字号） ===');
for (let i = 0; i < NAMES.length; i++) {
  const o = origH[i]?.katexH, r = rustM[i]?.mathH;
  console.log(`${NAMES[i].padEnd(24)} orig=${o} rust=${r} diff=${o != null && r != null ? R2(o - r) : 'n/a'} (em diff=${o != null && r != null ? R2((o - r) / 16) : 'n/a'})`);
}

// ---------------- Part 3：rowspacing 扫描 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 800, height: 900 } });
  const page = await ctx.newPage();
  await page.setContent('<!DOCTYPE html><body style="font-size:16px;margin:0"></body>');
  const targets = [1, 4]; // 2x2 letters, 2x2 fractions 在语料中的下标
  for (const ti of targets) {
    const html = rustMathHTML[ti];
    if (!html) { console.log(`PART3 skip ${NAMES[ti]}: no math`); continue; }
    const m = await page.evaluate(({ html, deltas }) => {
      const R = (n) => Math.round(n * 100) / 100;
      const out = {};
      for (const d of deltas) {
        const host = document.createElement('div');
        host.innerHTML = html;
        const tab = host.querySelector('mtable');
        const cur = parseFloat((tab.getAttribute('rowspacing') || '0').split(' ')[0]);
        tab.setAttribute('rowspacing', String(Math.round((cur + d) * 1000) / 1000) + 'em');
        document.body.appendChild(host);
        out['+' + d] = R(host.querySelector('math').getBoundingClientRect().height);
        host.remove();
      }
      return out;
    }, { html, deltas: [0, 0.3, 0.57, 0.85, 1.15] });
    console.log(`PART3-SCAN ${NAMES[ti]} orig=${origH[ti]?.katexH} rust-scan=`, JSON.stringify(m));
  }
  await ctx.close();
}

await browser.close();
console.log('PROBE-MATRIX-HEIGHT DONE');
