// 双栏混排成员稳定性探针：独立滚动 + 默认（flow）双栏两模式下，
// 逐块记录栏归属；独立模式下再在右栏段落追加 300 字、返回重进，
// 比对成员是否漂移；并读回落库的 layout 锚。
// 期望（修复后口径）：
//  A1 独立模式渲染两个物理栏容器
//  A2 图片 tc05 在左栏（原版规范估高分界：左 tc01–tc05）
//  A3 追加文字+重进后成员与首开逐块一致（不漂移）
//  A4 首开后即落锚 layout，right[0] = tc06
//  F1 flow 模式也是两个物理栏容器（非 CSS 多列拼凑）
//  F2 flow 下音乐卡不跨栏（宽度 ≈ 栏宽）
//  F3 flow 与独立模式成员一致（tc05 在左栏）
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const base = process.argv[2] || 'http://localhost:8196/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const fx = JSON.parse(execSync(
  `python3 -c "
import zipfile, json, base64
z = zipfile.ZipFile('fixtures/twocol-mix.zip')
out = {'memos': z.read('memos.json').decode(), 'manifest': z.read('manifest.json').decode(),
       'atts': {n.split('/')[1]: base64.b64encode(z.read(n)).decode() for n in z.namelist() if n.startswith('attachments/')}}
print(json.dumps(out))
"`, { cwd: process.env.HOME + '/workspace/Mynote' }).toString());

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' — ' + extra : '')); if (!cond) fails++; };

async function inject(page) {
  await page.evaluate(async ({ memos, manifest, atts }) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('mynote-web', 1);
      r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
    });
    const put = (store, val, key) => new Promise((res, rej) => {
      const rq = store.put(val, key); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error);
    });
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
}

async function openMemo(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('.img-card-title-text', (e) => e.click());
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1200);
}

const snapshot = () => {
  const body = document.querySelector('.editor-body');
  if (!body) return null;
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
        blocks.push({ bid: bidOf(child), col: name, w: Math.round(r.width), h: Math.round(r.height) });
      }
    });
    return { mode: body.classList.contains('is-independent-scroll') ? 'independent' : 'flowcols', blocks };
  }
  const br = body.getBoundingClientRect();
  const mid = br.x + br.width / 2;
  for (const child of body.children) {
    if (child.classList.contains('md-trail')) continue;
    const r = child.getBoundingClientRect();
    blocks.push({ bid: bidOf(child), col: (r.x + r.width / 2) < mid ? 'L' : 'R', w: Math.round(r.width), h: Math.round(r.height), span: r.width > br.width * 0.62 });
  }
  return { mode: 'multicol-or-single', bodyW: Math.round(br.width), blocks };
};

const colMap = (snap) => Object.fromEntries(snap.blocks.map((b) => [b.bid, b.col]));
const diffCols = (a, b) => Object.keys(a).filter((k) => b[k] && a[k] !== b[k]);

// ---------- 独立滚动模式 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  await ctx.addInitScript(() => localStorage.setItem('sj_editor_independent_scroll', '1'));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await inject(page);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });

  await openMemo(page);
  const s1 = await page.evaluate(snapshot);
  console.log('S1 mode=' + s1.mode, JSON.stringify(colMap(s1)));
  ok('A1 独立模式两个物理栏', s1.mode === 'independent');
  ok('A2 图片 tc05 在左栏', colMap(s1).tc05 === 'L', 'tc05=' + colMap(s1).tc05);

  const layoutAfterOpen = await page.evaluate(async () => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    const v = await new Promise((res, rej) => { const rq = db.transaction('kv').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
    const m = JSON.parse(v).memos.find((x) => x.id === 'twocolmix1');
    return m && m.layout ? m.layout : (m && m.extra && m.extra.layout) || null;
  });
  console.log('LAYOUT AFTER OPEN:', JSON.stringify(layoutAfterOpen));
  ok('A4 首开即落锚且 right[0]=tc06', !!layoutAfterOpen && Array.isArray(layoutAfterOpen.right) && layoutAfterOpen.right[0] === 'tc06');

  // 右栏 tc08 追加 300 字 → 返回 → 重进
  await page.click('[data-bid="tc08"]');
  await page.keyboard.press('End');
  await page.keyboard.insertText('追'.repeat(300));
  await page.waitForTimeout(1500);
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 15000 });
  await page.$eval('.img-card-title-text', (e) => e.click());
  await page.waitForSelector('.editor-body', { timeout: 15000 });
  await page.waitForTimeout(1200);
  const s3 = await page.evaluate(snapshot);
  console.log('S3 mode=' + s3.mode, JSON.stringify(colMap(s3)));
  const drift = diffCols(colMap(s1), colMap(s3));
  ok('A3 追加300字+重进成员不漂移', drift.length === 0, '漂移块: ' + JSON.stringify(drift));
  await ctx.close();
}

// ---------- 默认 flow 双栏 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
  await ctx.addInitScript(() => localStorage.setItem('sj_editor_independent_scroll', '0'));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await inject(page);
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await openMemo(page);
  const f1 = await page.evaluate(snapshot);
  console.log('F1 mode=' + f1.mode, JSON.stringify(f1.blocks.map((b) => [b.bid, b.col, b.w])));
  ok('F1 flow 为物理双栏容器', f1.mode === 'flowcols', 'mode=' + f1.mode);
  const music = f1.blocks.find((b) => b.bid === 'tc01');
  ok('F2 音乐卡不跨栏', !!music && !music.span, music ? 'w=' + music.w : 'missing');
  ok('F3 flow 成员与独立一致（tc05 左栏）', colMap(f1).tc05 === 'L', 'tc05=' + colMap(f1).tc05);
  await ctx.close();
}

await browser.close();
console.log(fails === 0 ? 'TWOCOL ALL PASS' : `TWOCOL ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
