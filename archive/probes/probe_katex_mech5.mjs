// KaTeX 残差机制四轮：定界字形真实墨迹（截图像素扫描）。
// 对定界段逐个 math 元素按其 x 范围扫描暗像素纵向 extent，
// 得墨迹高与墨迹顶/底（相对段顶），两侧同法对照。
// 用法：node probe_katex_mech5.mjs [origBase] [rustBase]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ORIG = process.argv[2] || 'http://localhost:8222/Moment.html';
const RUST = process.argv[3] || 'http://localhost:8221/';
const R2 = (n) => Math.round(n * 100) / 100;

const delimMemo = {
  id: 'kresid1', title: '残差量测', pinned: false,
  createdAt: '2026-11-22T03:00:00.000Z', updatedAt: '2026-11-22T03:00:00.000Z',
  doc: [{ id: 'kd0', type: 'paragraph', children: [{ text: '定界分级 $\\big($ $\\Big($ $\\bigg($ $\\Bigg($ 与普通 $(x)$ 对照。' }] }],
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function openMemo(isOrig) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log((isOrig ? 'ORIG' : 'RUST') + ' PAGEERROR', String(e).slice(0, 150)));
  await page.goto(isOrig ? ORIG : RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  if (isOrig) {
    await page.evaluate(async (m) => {
      const db = await new Promise((res, rej) => { const r = indexedDB.open('MemosDB', 8); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
      await new Promise((res, rej) => { const tx = db.transaction('memos', 'readwrite'); tx.objectStore('memos').put(m); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
    }, delimMemo);
  } else {
    const payload = { version: 2, exportedAt: '2026-11-22T02:00:00.000Z', memos: [delimMemo], avatars: {} };
    await page.evaluate(async ({ mj, mf }) => {
      const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
      await new Promise((res, rej) => { const tx = db.transaction('kv', 'readwrite'); tx.objectStore('kv').put(mj, 'memos_json'); tx.objectStore('kv').put(mf, 'manifest_raw'); tx.oncomplete = res; tx.onerror = () => rej(tx.error); });
    }, { mj: JSON.stringify(payload), mf: JSON.stringify({ version: 1, attachments: {} }) });
  }
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(900);
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('残差量测'));
    (el.querySelector('.item-title-text') || el).click();
  });
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
  return { ctx, page };
}

async function inkMeasure(isOrig) {
  const { ctx, page } = await openMemo(isOrig);
  const geo = await page.evaluate((orig) => {
    const seg = document.querySelector('.editor-body').children[0];
    const sr = seg.getBoundingClientRect();
    const maths = [...seg.querySelectorAll(orig ? '.katex' : 'math')].map((el) => {
      const r = el.getBoundingClientRect();
      return { x: r.x, w: r.width };
    });
    return { segTop: sr.top, segH: sr.height, maths };
  }, isOrig);
  const shot = await page.screenshot({ type: 'png' });
  const b64 = shot.toString('base64');
  const ink = await page.evaluate(async ({ b64, geo }) => {
    const R = (n) => Math.round(n * 100) / 100;
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = 'data:image/png;base64,' + b64; });
    const cv = document.createElement('canvas');
    cv.width = img.width; cv.height = img.height;
    const cx = cv.getContext('2d');
    cx.drawImage(img, 0, 0);
    const dsf = 2;
    const y0 = Math.max(0, Math.floor((geo.segTop - 30) * dsf));
    const y1 = Math.min(cv.height, Math.ceil((geo.segTop + geo.segH + 30) * dsf));
    const data = cx.getImageData(0, y0, cv.width, y1 - y0).data;
    const W = cv.width;
    return geo.maths.map((m) => {
      const xa = Math.max(0, Math.floor(m.x * dsf) - 2);
      const xb = Math.min(W, Math.ceil((m.x + m.w) * dsf) + 2);
      let top = -1, bot = -1;
      for (let y = 0; y < y1 - y0; y++) {
        let dark = false;
        for (let x = xa; x < xb; x++) {
          const i = (y * W + x) * 4;
          if (data[i] < 140 && data[i + 1] < 140 && data[i + 2] < 140 && data[i + 3] > 200) { dark = true; break; }
        }
        if (dark) { if (top < 0) top = y; bot = y; }
      }
      if (top < 0) return null;
      return {
        inkTopRelSeg: R((y0 + top) / dsf - geo.segTop),
        inkBotRelSeg: R((y0 + bot) / dsf - geo.segTop),
        inkH: R((bot - top + 1) / dsf),
      };
    });
  }, { b64, geo });
  console.log((isOrig ? 'M9-ORIG-INK segH=' : 'M9-RUST-INK segH=') + geo.segH, JSON.stringify(ink));
  await ctx.close();
}

await inkMeasure(true);
await inkMeasure(false);
await browser.close();
console.log('PROBE-KATEX-MECH5 DONE');
