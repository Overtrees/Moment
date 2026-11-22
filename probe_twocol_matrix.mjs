// 双栏逐块适配矩阵探针（mix-layout 夹具，16 块全类型）：
//  M1 独立/ flow 两模式成员逐块一致
//  M2 菜单开关往返（独立→flow→独立）成员不变
//  M3 右栏 md 预览块点击进源码编辑
//  M4 右栏文本块内斜杠面板可见且在视口内
//  M5 跨栏方向键：左栏末可编辑块 End+→ 到右栏首块；右栏首块 Home+← 回左栏末块
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const base = process.argv[2] || 'http://localhost:8196/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const fx = JSON.parse(execSync(
  `python3 -c "
import zipfile, json, base64
z = zipfile.ZipFile('fixtures/mix-layout.zip')
out = {'memos': z.read('memos.json').decode(), 'manifest': z.read('manifest.json').decode(),
       'atts': {n.split('/')[1]: base64.b64encode(z.read(n)).decode() for n in z.namelist() if n.startswith('attachments/')}}
print(json.dumps(out))
"`, { cwd: process.env.HOME + '/workspace/Mynote' }).toString());

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' — ' + extra : '')); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
await ctx.addInitScript(() => localStorage.setItem('sj_editor_independent_scroll', '1'));
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));

await page.goto(base, { waitUntil: 'load' });
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
await page.evaluate(() => {
  const el = Array.from(document.querySelectorAll('.img-card-title-text, .item-title-text')).find((e) => e.textContent.includes('混排验收'));
  if (el) el.click();
});
await page.waitForSelector('.editor-body', { timeout: 15000 });
await page.waitForTimeout(1200);

const snapshot = () => {
  const body = document.querySelector('.editor-body');
  const bidOf = (el) => el.getAttribute('data-wrapbid')
    || el.querySelector('[data-wrapbid]')?.getAttribute('data-wrapbid')
    || el.getAttribute('data-bid')
    || el.querySelector('[data-bid]')?.getAttribute('data-bid')
    || ('?md:' + (el.textContent || '').trim().slice(0, 10));
  const cols = body.querySelectorAll(':scope > .editor-column');
  const blocks = [];
  if (cols.length === 2) {
    ['L', 'R'].forEach((name, i) => {
      for (const child of cols[i].children) {
        if (child.classList.contains('md-trail')) continue;
        const r = child.getBoundingClientRect();
        blocks.push({ bid: bidOf(child), col: name, w: Math.round(r.width) });
      }
    });
    return { mode: body.classList.contains('is-independent-scroll') ? 'independent' : 'flowcols', blocks };
  }
  return { mode: 'no-columns', blocks: [] };
};

const sIndep = await page.evaluate(snapshot);
console.log('INDEP:', JSON.stringify(Object.fromEntries(sIndep.blocks.map((b) => [b.bid, b.col]))));

// 开关往返：独立 → flow → 独立
async function toggle() {
  const panelVisible = await page.evaluate(() => !!document.querySelector('.editor-menu-panel'));
  if (!panelVisible) {
    await page.$eval('.editor-fab.right', (e) => e.click());
    await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  }
  await page.$eval('.editor-column-mode-toggle', (e) => e.click());
  await page.waitForTimeout(500);
  const stillOpen = await page.evaluate(() => !!document.querySelector('.editor-menu-panel'));
  if (stillOpen) {
    await page.$eval('.menu-scrim', (e) => e.click());
    await page.waitForTimeout(400);
  }
}
await toggle();
const sFlow = await page.evaluate(snapshot);
console.log('FLOW :', sFlow.mode, JSON.stringify(Object.fromEntries(sFlow.blocks.map((b) => [b.bid, b.col]))));
await toggle();
const sIndep2 = await page.evaluate(snapshot);
console.log('INDEP2:', JSON.stringify(Object.fromEntries(sIndep2.blocks.map((b) => [b.bid, b.col]))));

const map = (s) => Object.fromEntries(s.blocks.map((b) => [b.bid, b.col]));
const sameMap = (a, b) => JSON.stringify(Object.keys(a).sort().map((k) => [k, a[k]])) === JSON.stringify(Object.keys(b).sort().map((k) => [k, b[k]]));
ok('M1 两模式成员逐块一致', sFlow.mode === 'flowcols' && sameMap(map(sIndep), map(sFlow)));
ok('M2 开关往返成员不变', sIndep2.mode === 'independent' && sameMap(map(sIndep), map(sIndep2)));

// M3 右栏 md 预览块（m08 代码段）点击进源码编辑
const m08col = map(sIndep2)['?md:```js'] || map(sIndep2)[Object.keys(map(sIndep2)).find((k) => k.startsWith('?md:'))];
await page.evaluate(() => {
  const hits = Array.from(document.querySelectorAll('.md-hit'));
  const t = hits.find((h) => h.textContent.includes('const answer'));
  if (t) t.click();
});
await page.waitForTimeout(700);
const m08editing = await page.evaluate(() => !!document.querySelector('[data-bid="m08"][contenteditable="true"]'));
ok('M3 md 预览块点击进源码编辑', m08editing);
await page.keyboard.press('Escape');
await page.evaluate(() => { const b = document.querySelector('.editor-body'); if (b) b.click(); });
await page.waitForTimeout(500);

// M4 右栏文本块斜杠面板
const rightFirst = sIndep2.blocks.find((b) => b.col === 'R');
await page.click('[data-bid="m16"]');
await page.keyboard.press('End');
await page.keyboard.type('/');
await page.waitForTimeout(800);
const slash = await page.evaluate(() => {
  const p = document.querySelector('.slash-panel');
  if (!p) return null;
  const r = p.getBoundingClientRect();
  return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), visible: r.width > 0 && r.height > 0 };
});
console.log('SLASH:', JSON.stringify(slash), '（右栏首块:', rightFirst && rightFirst.bid, '）');
ok('M4 斜杠面板可见且在视口内', !!slash && slash.visible && slash.x >= 0 && slash.y >= 0 && slash.x + slash.w <= 1280);
await page.keyboard.press('Escape');
await page.keyboard.press('Backspace');
await page.waitForTimeout(400);

// M5 跨栏方向键
const pair = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const cols = body.querySelectorAll(':scope > .editor-column');
  const eds = (col) => Array.from(cols[col].querySelectorAll('[data-bid]')).filter((e) => e.isContentEditable).map((e) => e.getAttribute('data-bid'));
  const L = eds(0), R = eds(1);
  return { lastL: L[L.length - 1], firstR: R[0] };
});
console.log('ARROW PAIR:', JSON.stringify(pair));
await page.click(`[data-bid="${pair.lastL}"]`);
await page.keyboard.press('End');
await page.keyboard.press('ArrowRight');
await page.waitForTimeout(400);
const focusAfterRight = await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-bid'));
ok('M5a 左栏末块 → 右方向键跨到右栏首块', focusAfterRight === pair.firstR, `focus=${focusAfterRight} 期望=${pair.firstR}`);
await page.keyboard.press('Home');
await page.keyboard.press('ArrowLeft');
await page.waitForTimeout(400);
const focusAfterLeft = await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-bid'));
ok('M5b 右栏首块 → 左方向键跨回左栏末块', focusAfterLeft === pair.lastL, `focus=${focusAfterLeft} 期望=${pair.lastL}`);

await browser.close();
console.log(fails === 0 ? 'MATRIX ALL PASS' : `MATRIX ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
