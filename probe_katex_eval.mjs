// KaTeX 立项评估探针（只读）：同夹具在 Rust(8096) 与原版(8097) 的
// 公式渲染 / 存储保真 / 导出形态三方取证。IDB/localStorage 直注种子。
import { chromium } from 'playwright-core';

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

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);

// ---------------- Rust ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L('RUST PAGEERROR', String(e).slice(0, 150)));
  await page.addInitScript(() => {
    window.__blobs = [];
    window.__pdfHtml = null;
    const oc = URL.createObjectURL.bind(URL);
    URL.createObjectURL = (b) => { try { window.__blobs.push(b); } catch (e) {} return oc(b); };
    window.open = () => ({
      closed: false, focus() {}, print() {},
      document: { open() {}, write(s) { window.__pdfHtml = s; }, close() {}, images: [] },
    });
  });
  await page.goto('http://localhost:8096/', { waitUntil: 'load' });
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
  // 存储保真：IDB 里的 doc 文本与夹具逐字比对
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
  L('RUST-STORAGE-LOSSLESS', JSON.stringify(stored) === JSON.stringify(PARAS), stored.map((s, i) => s === PARAS[i]));
  await page.evaluate(() => {
    const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('公式渲染探针'));
    (t.querySelector('.item-title-text') || t).click();
  });
  await page.waitForSelector('.detail, .editor-body', { timeout: 10000 });
  await page.waitForTimeout(1200);
  const blocks = await page.evaluate(() => {
    const body = document.querySelector('.editor-body') || document;
    return [...body.querySelectorAll('[data-bid]')].map((el) => ({
      bid: el.dataset.bid, cls: el.className, btype: el.dataset.btype || '',
      text: (el.innerText || '').replace(/\s+/g, ' ').slice(0, 95),
      katex: el.querySelectorAll('.katex').length,
      mathBlk: el.querySelectorAll('.math-block').length,
      mathInl: el.querySelectorAll('.math-inline').length,
      editable: el.getAttribute('contenteditable'),
    }));
  });
  for (const b of blocks) L('RUST-BLOCK', JSON.stringify(b));
  // 导出 MD / HTML / PDF
  for (const fmt of ['markdown', 'html', 'pdf']) {
    await page.click('.editor-fab.right');
    await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
    await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
    await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
    await page.waitForTimeout(350);
    await page.click(`[data-export-format="${fmt}"]`);
    await page.waitForTimeout(1600);
    if (fmt === 'pdf') {
      const h = await page.evaluate(() => window.__pdfHtml);
      L('RUST-EXPORT-PDF', 'len=' + (h ? h.length : 0),
        'hasKatexClass=' + (h ? h.includes('katex') : false),
        'hasMathBlock=' + (h ? h.includes('math-block') : false),
        'hasRawDollarTex=' + (h ? h.includes('$E=mc^2$') : false),
        'hasFrac=' + (h ? h.includes('frac') : false));
    } else {
      const content = await page.evaluate(async () => {
        const b = window.__blobs[window.__blobs.length - 1];
        return b ? await b.text() : null;
      });
      const c = content || '';
      L('RUST-EXPORT-' + fmt.toUpperCase(), 'len=' + c.length,
        'hasKatexClass=' + c.includes('katex'),
        'hasMathBlock=' + c.includes('math-block'),
        'hasRawDollarTex=' + c.includes('$E=mc^2$'),
        'hasSqrtPi=' + c.includes('\\sqrt{\\pi}'));
      if (fmt === 'markdown') L('RUST-MD-SNIPPET', JSON.stringify(c.slice(0, 400)));
    }
  }
  await ctx.close();
}

// ---------------- 原版 ----------------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L('ORIG PAGEERROR', String(e).slice(0, 150)));
  await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate((memos) => {
    localStorage.setItem('memos_app_v2', JSON.stringify(memos));
  }, payload.memos);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(1000);
  const found = await page.evaluate(() => document.body.innerText.includes('公式渲染探针'));
  L('ORIG-SEEDED-VIA-LS', found);
  if (found) {
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('公式渲染探针'));
      (t.querySelector('.item-title-text') || t).click();
    });
    await page.waitForSelector('.editor-body', { timeout: 10000 });
    await page.waitForTimeout(1500);
    const info = await page.evaluate(() => {
      const body = document.querySelector('.editor-body');
      const blocks = [...body.children].map((el) => ({
        cls: el.className, tag: el.tagName,
        text: (el.innerText || '').replace(/\s+/g, ' ').slice(0, 95),
        katex: el.querySelectorAll('.katex').length,
        mathBlk: el.querySelectorAll('.math-block').length,
        mathInl: el.querySelectorAll('.math-inline').length,
        mathSrc: el.querySelectorAll('.math-source').length,
      }));
      const kx = document.querySelector('.katex');
      return {
        blocks,
        katexVersion: window.katex ? window.katex.version : null,
        katexFont: kx ? getComputedStyle(kx).fontFamily.slice(0, 60) : null,
        fontLoaded: document.fonts ? document.fonts.check('16px KaTeX_Main') : null,
        stored: JSON.parse(localStorage.getItem('memos_app_v2'))[0].doc.map((b) => (b.children || []).map((c) => c.text || '').join('')),
      };
    });
    L('ORIG-KATEX-VERSION', info.katexVersion, 'fontLoaded=', info.fontLoaded, 'katexFont=', info.katexFont);
    L('ORIG-STORAGE-LOSSLESS', JSON.stringify(info.stored) === JSON.stringify(PARAS));
    for (const b of info.blocks) L('ORIG-BLOCK', JSON.stringify(b));
  }
  await ctx.close();
}
await browser.close();
