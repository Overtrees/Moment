// KaTeX 残差机制五轮：math 字体栈变体在应用内实测。
// 对同一 dist 以 addStyleTag 注入不同 font-family 覆盖，量
// 符号宽（∥/∈/∪）、字母阵总高、分数阵总高、1x1 字母盒。
// 用法：node probe_katex_mech6.mjs [rustBase]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = process.argv[2] || 'http://localhost:8221/';
const R2 = (n) => Math.round(n * 100) / 100;

const memo = {
  id: 'kfont1', title: '字体栈量测', pinned: false,
  createdAt: '2026-11-22T03:00:00.000Z', updatedAt: '2026-11-22T03:00:00.000Z',
  doc: [
    { id: 'f1', type: 'paragraph', children: [{ text: '$\\parallel$' }] },
    { id: 'f2', type: 'paragraph', children: [{ text: '$\\in$' }] },
    { id: 'f3', type: 'paragraph', children: [{ text: '$\\cup$' }] },
    { id: 'f4', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$' }] },
    { id: 'f5', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} \\frac{1}{2} & \\frac{1}{3} \\\\ \\frac{1}{4} & \\frac{1}{5} \\end{pmatrix}$$' }] },
    { id: 'f6', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a \\end{pmatrix}$$' }] },
  ],
};
const payload = { version: 2, exportedAt: '2026-11-22T03:00:00.000Z', memos: [memo], avatars: {} };

const VARIANTS = {
  currentStack: '"STIX Two Math","Cambria Math","Latin Modern Math","Noto Sans Math",math,serif',
  genericFirst: 'math,"STIX Two Math","Cambria Math","Latin Modern Math",serif',
  genericOnly: 'math',
  notoFirst: '"Noto Sans Math",math,serif',
  dejavuFirst: '"DejaVu Sans",math,serif',
  none: null,
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
await page.goto(RUST, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(async ({ mj, mf }) => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => { const tx = db.transaction('kv', 'readwrite'); tx.objectStore('kv').put(mj, 'memos_json'); tx.objectStore('kv').put(mf, 'manifest_raw'); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
}, { mj: JSON.stringify(payload), mf: JSON.stringify({ version: 1, attachments: {} }) });
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(900);
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('字体栈量测'));
  (el.querySelector('.item-title-text') || el).click();
});
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1500);

for (const [name, ff] of Object.entries(VARIANTS)) {
  const m = await page.evaluate(async (ff) => {
    const R = (n) => Math.round(n * 100) / 100;
    document.querySelectorAll('style[data-ffprobe]').forEach((s) => s.remove());
    if (ff) {
      const st = document.createElement('style');
      st.dataset.ffprobe = '1';
      st.textContent = `.editor-body math, .markdown-render math { font-family: ${ff} !important; }`;
      document.head.appendChild(st);
    }
    await new Promise((r) => setTimeout(r, 350));
    const maths = [...document.querySelectorAll('.editor-body math')];
    const w = (i) => maths[i] ? R(maths[i].getBoundingClientRect().width) : null;
    const h = (i) => maths[i] ? R(maths[i].getBoundingClientRect().height) : null;
    return {
      par: w(0), in: w(1), cup: w(2),
      letters: h(3), fractions: h(4), oneByOne: h(5),
      computedFF: maths[0] ? getComputedStyle(maths[0]).fontFamily : null,
    };
  }, ff);
  console.log(name.padEnd(14), JSON.stringify(m));
}
await ctx.close();
await browser.close();
console.log('PROBE-KATEX-MECH6 DONE');
