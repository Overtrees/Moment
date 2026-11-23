// mtable 机制实验三：在真实应用页内二分环境差异。
// 手写 2x2 表分别置于：body 直下 / .editor-body 内 / 与应用
// 自身 pmatrix 公式同页对照；另读应用公式的计算样式细节。
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = process.argv[2] || 'http://localhost:8197/';
const T = `<math display="block"><mrow><mo fence="true" stretchy="true">(</mo><mtable columnalign="center center" columnspacing="1em" rowspacing="1.37em"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable><mo fence="true" stretchy="true">)</mo></mrow></math>`;
const memo = {
  id: 'mxprobe1', title: '矩阵量测', pinned: false,
  createdAt: '2026-11-22T02:00:00.000Z', updatedAt: '2026-11-22T02:00:00.000Z',
  doc: [{ id: 'mx2', type: 'paragraph', children: [{ text: '$$\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}$$' }] }],
};
const payload = { version: 2, exportedAt: '2026-11-22T02:00:00.000Z', memos: [memo], avatars: {} };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
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

const m = await page.evaluate((T) => {
  const R = (n) => Math.round(n * 100) / 100;
  const meas = (math) => {
    const tab = math.querySelector('mtable');
    const rows = [...tab.querySelectorAll(':scope > mtr')];
    const mi = math.querySelector('mi');
    return {
      mathH: R(math.getBoundingClientRect().height),
      tableH: R(tab.getBoundingClientRect().height),
      rowTops: rows.map((r) => R(r.getBoundingClientRect().top)),
      mathFS: getComputedStyle(math).fontSize,
      mathFF: getComputedStyle(math).fontFamily,
      miH: R(mi.getBoundingClientRect().height),
      miFS: getComputedStyle(mi).fontSize,
      htmlFS: getComputedStyle(document.documentElement).fontSize,
    };
  };
  const out = {};
  out.appOwn = meas(document.querySelector('.editor-body math'));
  const d1 = document.createElement('div');
  d1.innerHTML = T;
  document.body.appendChild(d1);
  out.bodyLevel = meas(d1.querySelector('math'));
  const d2 = document.createElement('div');
  d2.innerHTML = T;
  document.querySelector('.editor-body').appendChild(d2);
  out.inEditorBody = meas(d2.querySelector('math'));
  out.appOwnOuter = document.querySelector('.editor-body math').outerHTML.slice(0, 400);
  return out;
}, T);
console.log(JSON.stringify(m, null, 1));
await browser.close();
console.log('MECH3 DONE');
