// 双栏几何对照：同一夹具（twocol-mix）在原版（8097）与 Rust
// （8196）默认双栏下量测栏宽/列距/文本块宽高/音乐卡宽高。
// 原版附件走 OPFS，本探针只注 MemosDB 备忘记录，图片块在原
// 版为占位渲染——图片高度不纳入对照（口径注明）。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const fx = JSON.parse(execSync(
  `python3 -c "
import zipfile, json, base64
z = zipfile.ZipFile('fixtures/twocol-mix.zip')
out = {'memos': z.read('memos.json').decode(), 'manifest': z.read('manifest.json').decode(),
       'atts': {n.split('/')[1]: base64.b64encode(z.read(n)).decode() for n in z.namelist() if n.startswith('attachments/')}}
print(json.dumps(out))
"`, { cwd: process.env.HOME + '/workspace/Mynote' }).toString());
const memoObj = JSON.parse(fx.memos).memos[0];

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

const measure = () => {
  const body = document.querySelector('.editor-body');
  if (!body) return null;
  const br = body.getBoundingClientRect();
  const mid = br.x + br.width / 2;
  const rows = [];
  const walk = (el, col) => {
    for (const child of el.children) {
      if (child.classList && child.classList.contains('md-trail')) continue;
      const r = child.getBoundingClientRect();
      if (r.height === 0 && r.width === 0) continue;
      rows.push({
        id: child.getAttribute('data-wrapbid') || child.getAttribute('data-bid')
          || child.getAttribute('data-blockid')
          || (child.querySelector && (child.querySelector('[data-bid]')?.getAttribute('data-bid') || child.querySelector('[data-type]')?.getAttribute('data-type')))
          || ('?md:' + (child.textContent || '').trim().slice(0, 8)),
        col, x: Math.round(r.x), w: Math.round(r.width), h: Math.round(r.height),
      });
    }
  };
  const cols = body.querySelectorAll(':scope > .editor-column');
  if (cols.length === 2) { walk(cols[0], 'L'); walk(cols[1], 'R'); }
  else {
    for (const child of body.children) {
      if (child.classList && child.classList.contains('md-trail')) continue;
      const r = child.getBoundingClientRect();
      if (r.height === 0 && r.width === 0) continue;
      rows.push({
        id: child.getAttribute('data-blockid') || child.getAttribute('data-bid')
          || (child.querySelector && child.querySelector('[data-type]')?.getAttribute('data-type'))
          || ('?md:' + (child.textContent || '').trim().slice(0, 8)),
        col: (r.x + r.width / 2) < mid ? 'L' : 'R', x: Math.round(r.x), w: Math.round(r.width), h: Math.round(r.height),
      });
    }
  }
  const firstL = rows.find((r) => r.col === 'L');
  const firstR = rows.find((r) => r.col === 'R');
  return {
    bodyW: Math.round(br.width), bodyX: Math.round(br.x),
    gap: firstL && firstR ? firstR.x - (firstL.x + firstL.w) : null,
    rows,
  };
};

async function rustGeom(width, height) {
  const ctx = await browser.newContext({ viewport: { width, height }, hasTouch: true });
  await ctx.addInitScript(() => localStorage.setItem('sj_editor_independent_scroll', '0'));
  const page = await ctx.newPage();
  await page.goto('http://localhost:8196/', { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.evaluate(async ({ memos, manifest, atts }) => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    const put = (store, val, key) => new Promise((res, rej) => { const rq = store.put(val, key); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error); });
    let tx = db.transaction('kv', 'readwrite');
    await put(tx.objectStore('kv'), memos, 'memos_json');
    await put(tx.objectStore('kv'), manifest, 'manifest_raw');
    tx = db.transaction('attachments', 'readwrite');
    const st = tx.objectStore('attachments');
    await new Promise((res, rej) => { const rq = st.clear(); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error); });
    for (const [id, b64] of Object.entries(atts)) {
      const bin = atob(b64); const arr = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      await put(st, arr, id);
    }
  }, fx);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('.img-card-title-text', (e) => e.click());
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1500);
  const g = await page.evaluate(measure);
  await ctx.close();
  return g;
}

async function origGeom(width, height) {
  const ctx = await browser.newContext({ viewport: { width, height }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('ORIG PAGEERROR:', String(e).slice(0, 160)));
  await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.evaluate(async (memo) => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open('MemosDB', 8); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    await new Promise((res, rej) => { const rq = db.transaction('memos', 'readwrite').objectStore('memos').put(memo); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error); });
  }, memoObj);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.evaluate(() => {
    const el = Array.from(document.querySelectorAll('*')).find((e) => e.children.length === 0 && e.textContent.includes('双栏混排'));
    if (el) el.click();
  });
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1500);
  const g = await page.evaluate(measure);
  await ctx.close();
  return g;
}

for (const [w, h] of [[1280, 800], [1024, 768]]) {
  const r = await rustGeom(w, h);
  const o = await origGeom(w, h);
  const pick = (g, id) => g && g.rows.find((x) => x.id === id);
  console.log(`\n== ${w}x${h} ==`);
  console.log('RUST  bodyW=' + (r && r.bodyW) + ' gap=' + (r && r.gap), JSON.stringify(r && r.rows.map((x) => [x.id, x.col, x.w, x.h])));
  console.log('ORIG  bodyW=' + (o && o.bodyW) + ' gap=' + (o && o.gap), JSON.stringify(o && o.rows.map((x) => [x.id, x.col, x.w, x.h])));
  for (const id of ['tc01', 'tc03', 'tc07']) {
    const a = pick(r, id), b = pick(o, id);
    console.log(`  ${id}: rust w=${a && a.w} h=${a && a.h} | orig w=${b && b.w} h=${b && b.h}`);
  }
}
await browser.close();
