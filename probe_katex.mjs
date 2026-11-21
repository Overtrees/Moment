// KaTeX 立项（Rust 原生 MathML）验证探针：
// 含公式夹具直注 IDB → 编辑页预览断言（<math> 存在、无裸 $ 残留、
// 块级 .math-block 居中块、防误判段零公式、错误公式红色兜底、
// Diag MATH 记录）→ 导出 HTML/PDF 带 MathML、MD 留源码。
// 用法：node probe_katex.mjs <baseUrl>（默认 http://localhost:8096/）
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const PARAS = [
  '质能方程 $E=mc^2$ 与分式 $\\frac{a+b}{2}$、根号 $\\sqrt{x^2+1}$ 中英混排。',
  '$$\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}$$',
  '$$\n\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\n$$',
  '$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix} + \\begin{bmatrix} 1 & 0 \\\\ 0 & 1 \\end{bmatrix}$$',
  '希腊字母 $\\alpha + \\beta = \\gamma$，上下标 $x_1^2 + x_2^2 = r^2$，行内求和 $\\sum_{k=1}^{n} k^2$。',
  '售价 $128 元整，标价 \\$9.9 的写法不应成为公式。',
  '错误公式 $\\frac{1}{$ 与未知命令 $\\unknowncmd{x}$ 的容错测试。',
];
const memo = {
  id: 'mathprobe1', title: '公式渲染探针', pinned: false,
  createdAt: '2026-11-21T02:00:00.000Z', updatedAt: '2026-11-21T02:00:00.000Z',
  doc: PARAS.map((t, i) => ({ id: 'mp' + (i + 1), type: 'paragraph', children: [{ text: t }] })),
};
const payload = { version: 2, exportedAt: '2026-11-21T02:00:00.000Z', memos: [memo], avatars: {} };
const manifest = JSON.stringify({ version: 1, attachments: {} });

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' | ' + val : ''));
};
const soft = (name, cond, val) => {
  console.log((cond ? '✓ ' : '· ') + name + (val !== undefined ? ' | ' + val : ''));
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
await page.addInitScript(() => {
  window.__blobs = [];
  window.__pdfHtml = null;
  const oc = URL.createObjectURL.bind(URL);
  URL.createObjectURL = (b) => { try { window.__blobs.push(b); } catch (e) {} return oc(b); };
  window.open = () => ({
    closed: false, focus() {}, print() {},
    document: { open() {}, write(s) { window.__pdfHtml = (window.__pdfHtml || '') + s; }, close() {}, images: [] },
  });
});
await page.goto(base, { waitUntil: 'load' });
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
await page.waitForFunction(() => document.body.innerText.includes('公式渲染探针'), { timeout: 15000 });

// 存储保真：公式源码逐字无损
const stored = await page.evaluate(async () => {
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('mynote-web', 1);
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const v = await new Promise((res, rej) => {
    const rq = db.transaction('kv').objectStore('kv').get('memos_json');
    rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error);
  });
  const bf = JSON.parse(v);
  return bf.memos[0].doc.map((b) => (b.children || []).map((c) => c.text || '').join(''));
});
ok('存储无损（公式源码逐字一致）', JSON.stringify(stored) === JSON.stringify(PARAS));

await page.evaluate(() => {
  const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('公式渲染探针'));
  (t.querySelector('.item-title-text') || t).click();
});
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1200);

const dom = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const blocks = [...body.querySelectorAll('[data-bid]')].map((el) => ({
    text: (el.innerText || '').replace(/\s+/g, ' '),
    math: el.querySelectorAll('math').length,
    mathBlk: el.querySelectorAll('.math-block').length,
    mathInl: el.querySelectorAll('.math-inline').length,
    mathSrc: el.querySelectorAll('.math-source').length,
    mfrac: el.querySelectorAll('mfrac').length,
    mtable: el.querySelectorAll('mtable').length,
    msqrt: el.querySelectorAll('msqrt').length,
    munderover: el.querySelectorAll('munderover').length,
    msubsup: el.querySelectorAll('msubsup').length,
  }));
  return {
    blocks,
    totalMath: body.querySelectorAll('math').length,
    totalBlk: body.querySelectorAll('.math-block').length,
    totalInl: body.querySelectorAll('.math-inline').length,
  };
});
console.log('DOM', JSON.stringify(dom, null, 1));
ok('预览含 <math> 元素', dom.totalMath >= 8, 'math=' + dom.totalMath);
ok('块级公式 .math-block ×3（积分/求和/矩阵）', dom.totalBlk >= 3, 'blk=' + dom.totalBlk);
ok('行内公式 .math-inline ≥6', dom.totalInl >= 6, 'inl=' + dom.totalInl);
ok('分式 mfrac 出现', dom.blocks.some((b) => b.mfrac > 0));
ok('根号 msqrt 出现', dom.blocks.some((b) => b.msqrt > 0));
ok('矩阵 mtable ×2', dom.blocks.reduce((a, b) => a + b.mtable, 0) >= 2);
ok('块级求和 munderover 出现', dom.blocks.some((b) => b.munderover > 0));
ok('上下标 msubsup 出现', dom.blocks.some((b) => b.msubsup > 0));
// 第 1–5 段渲染后不应残留裸 $
for (let i = 0; i < 5; i++) {
  ok(`第 ${i + 1} 段无裸 $ 残留`, !dom.blocks[i].text.includes('$'), dom.blocks[i].text.slice(0, 60));
}
// 第 6 段防误判：零公式、原文保留
ok('防误判段零公式', dom.blocks[5].math === 0, 'math=' + dom.blocks[5].math);
ok('防误判段保留 $128 与 $9.9 原文', dom.blocks[5].text.includes('$128') && dom.blocks[5].text.includes('$9.9'), dom.blocks[5].text.slice(0, 60));
// 第 7 段容错：残缺公式红色兜底 + 未知命令式内渲染
ok('残缺公式 .math-source 兜底', dom.blocks[6].mathSrc >= 1, 'src=' + dom.blocks[6].mathSrc);
ok('未知命令仍渲染为公式', dom.blocks[6].math >= 1, 'math=' + dom.blocks[6].math);

// Diag MATH 记录
const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
ok('Diag 含 MATH 记录', diag.includes('MATH'));

// 编辑态（软断言）：点公式段回源码应能看到 $ 原文
await page.evaluate(() => {
  const el = document.querySelectorAll('[data-bid]')[0];
  el.scrollIntoView();
  el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
await page.waitForTimeout(900);
const editText = await page.evaluate(() => document.querySelector('.editor-body').innerText);
soft('点击预览回源码可见 $E=mc^2$', editText.includes('$E=mc^2$'));

// 导出三格式
async function doExport(fmt) {
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(350);
  await page.evaluate(() => { window.__blobs = []; window.__pdfHtml = null; });
  await page.click(`[data-export-format="${fmt}"]`);
  await page.waitForTimeout(1800);
  if (fmt === 'pdf') return page.evaluate(() => window.__pdfHtml || '');
  return page.evaluate(async () => {
    const b = window.__blobs[window.__blobs.length - 1];
    return b ? await b.text() : '';
  });
}
const html = await doExport('html');
ok('导出 HTML 含 <math>', html.includes('<math'), 'len=' + html.length);
ok('导出 HTML 含 math-block', html.includes('math-block'));
ok('导出 HTML 无 $E=mc^2$ 原码残留', !html.includes('$E=mc^2$'));
const pdf = await doExport('pdf');
ok('导出 PDF 文档含 <math>', pdf.includes('<math'), 'len=' + pdf.length);
ok('导出 PDF 无 $E=mc^2$ 原码残留', pdf.length > 0 && !pdf.includes('$E=mc^2$'));
const md = await doExport('markdown');
ok('导出 MD 保留公式源码', md.includes('$E=mc^2$') && md.includes('\\frac{\\sqrt{\\pi}}{2}'), 'len=' + md.length);

await browser.close();
console.log(failures === 0 ? 'PROBE-KATEX ALL GREEN' : `PROBE-KATEX FAILURES=${failures}`);
process.exit(failures === 0 ? 0 : 1);
