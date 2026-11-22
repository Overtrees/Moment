// mtd padding-block:0.23em 覆盖注入验证（借 mech6 夹具/流程）：
// 在当前 dist（已含字体栈）上注入新内衬值，量字母阵/分数阵总高。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = process.argv[2] || 'http://localhost:8221/';
const R2 = (n) => Math.round(n * 100) / 100;

const memo = {
  id: 'kfont1', title: '字体栈量测', pinned: false,
  createdAt: '2026-11-22T03:00:00.000Z', updatedAt: '2026-11-22T03:00:00.000Z',
  doc: [
    { id: 'f4', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$' }] },
    { id: 'f5', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} \\frac{1}{2} & \\frac{1}{3} \\\\ \\frac{1}{4} & \\frac{1}{5} \\end{pmatrix}$$' }] },
    { id: 'f6', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a \\end{pmatrix}$$' }] },
    { id: 'f7', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a & b & c \\\\ d & e & f \\\\ g & h & i \\end{pmatrix}$$' }] },
    { id: 'f8', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a & b & c & d \\\\ e & f & g & h \\\\ i & j & k & l \\\\ m & n & o & p \\end{pmatrix}$$' }] },
  ],
};
const payload = { version: 2, exportedAt: '2026-11-22T03:00:00.000Z', memos: [memo], avatars: {} };

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

for (const [name, css] of [['dist-as-is (0.5ex, Noto ex)', null], ['override 0.23em', '.editor-body mtd{padding-block:0.23em}']]) {
  const m = await page.evaluate(async (css) => {
    const R = (n) => Math.round(n * 100) / 100;
    document.querySelectorAll('style[data-mtdprobe]').forEach((s) => s.remove());
    if (css) {
      const st = document.createElement('style');
      st.dataset.mtdprobe = '1'; st.textContent = css;
      document.head.appendChild(st);
    }
    await new Promise((r) => setTimeout(r, 350));
    return [...document.querySelectorAll('.editor-body math')].map((mt) => R(mt.getBoundingClientRect().height));
  }, css);
  console.log(name, JSON.stringify(m), ' targets: letters2x2=38.39 fractions=38.56 1x1=20.19 3x3=57.59 4x4=76.8');
}
await ctx.close();
await browser.close();
console.log('MTD-EM DONE');
