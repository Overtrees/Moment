// 独立双栏五项独立性活体探针（审计用，Chromium 口径）：
//  I1 成员/结构：双物理栏、成员=锚分界、媒体栏内宽量测
//  I2 独立滚动：滚左栏右栏 scrollTop 不动、窗口不滚
//  I3 渲染隔离：左栏打字时右栏 DOM 零突变（MutationObserver + innerHTML 哈希）
//  I4 栏内排序隔离：左栏内拖拽排序后右栏 DOM 序与落盘 layout.right 不变
//  I5 数据互不扰：左栏编辑落盘后右栏块文本逐块不变、layout 成员不变
//  I6 重进稳定：重开备忘成员与上次一致
//
// 2026-11-24 探针侧修正（产品判据逐字未动，仅修量法与期望数）：
//  (1) 单元 id 解析原 bidOf 只认 data-wrapbid（自有/后代）与自有
//      data-bid，漏了两类单元：块级 md 预览单元本体即 .md-hit、
//      id 在其 data-bids 上（m03/m08/m09/m10），todo/quote 单元
//      的 id 在内层 [data-bid] 上（m05/m06/m07）——共 7 个单元
//      被解析为 null，I5a/I4d 因此误红。改按应用桥 unitBids 的
//      同一解析序（data-bids > 自有 data-bid/data-wrapbid >
//      内层 [data-bid]），复合单元（data-bids 多 id）展开计入。
//  (2) I1c 原期望 16 是夹具 doc 的块数；活体成员不止于此：
//      打开备忘时 materialize_trails 按原版 ensureTrailing 规
//      则在 m08（代码预览，其后为另一预览）与 m10（标注预览，
//      其后为原子块）之后物化 2 个真实尾随空段（生成 id），
//      它们是 layout 的真实成员（落盘 layout 亦含之），故双栏
//      成员总数为 18。期望按活体实数修正。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const base = process.argv[2] || 'http://localhost:8941/';
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

const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: true });
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

const openMemo = async () => {
  await page.evaluate(() => {
    const el = Array.from(document.querySelectorAll('.img-card-title-text, .item-title-text')).find((e) => e.textContent.includes('混排验收'));
    if (el) el.click();
  });
  await page.waitForSelector('.editor-body.is-independent-scroll', { timeout: 15000 });
  await page.waitForTimeout(1200);
};
const snap = () => page.evaluate(() => {
  // 单元 id 解析与应用桥 unitBids 同口径：data-bids（预览/列表
  // 组，逗号分隔多 id）> 自有 data-bid/data-wrapbid > 内层
  // [data-bid]（todo/quote 的内层可编辑区）。解析不出时保留
  // null 占位，让成员对账照常红出来、不静默错位。
  const unitBids = (el) => {
    const multi = el.getAttribute('data-bids');
    if (multi) return multi.split(',').filter(Boolean);
    const own = el.getAttribute('data-bid') || el.getAttribute('data-wrapbid');
    if (own) return [own];
    const inner = el.querySelector('[data-bid]');
    return inner ? [inner.getAttribute('data-bid')] : [null];
  };
  const cols = Array.from(document.querySelectorAll('.editor-body > .editor-column'));
  return {
    bodyClass: document.querySelector('.editor-body')?.className || '',
    cols: cols.map((c) => ({
      side: c.getAttribute('data-editor-column'),
      overflowY: getComputedStyle(c).overflowY,
      clientH: c.clientHeight, scrollH: c.scrollHeight, scrollTop: c.scrollTop,
      width: c.getBoundingClientRect().width,
      bids: Array.from(c.children).flatMap(unitBids),
    })),
  };
});
const readMemo = () => page.evaluate(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const raw = await new Promise((res, rej) => { const rq = db.transaction('kv').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  const data = JSON.parse(raw);
  return data.memos.find((m) => (m.title || '').includes('混排验收'));
});

await openMemo();
const s0 = await snap();
console.log('SNAP0', JSON.stringify(s0, null, 1));
ok('I1a 双物理栏容器', s0.cols.length === 2 && s0.bodyClass.includes('is-independent-scroll'), s0.bodyClass);
const L0 = s0.cols[0].bids, R0 = s0.cols[1].bids;
ok('I1b 两栏均有成员', L0.length > 0 && R0.length > 0, `L=${L0.length} R=${R0.length}`);
ok('I1c 成员无交叠且合起来 18 个成员', new Set([...L0, ...R0]).size === 18 && L0.length + R0.length === 18);

// 媒体量测：图片块(m11)与音乐卡(m02)的渲染宽 vs 所在栏内容宽
const media = await page.evaluate(() => {
  const find = (bid) => document.querySelector(`[data-wrapbid="${bid}"]`) || document.querySelector(`[data-bid="${bid}"]`);
  const out = {};
  for (const bid of ['m11', 'm02', 'm12']) {
    const el = find(bid);
    if (!el) { out[bid] = null; continue; }
    const col = el.closest('.editor-column');
    const cs = getComputedStyle(col);
    out[bid] = {
      w: Math.round(el.getBoundingClientRect().width * 10) / 10,
      colContentW: Math.round((col.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)) * 10) / 10,
    };
  }
  return out;
});
console.log('MEDIA', JSON.stringify(media));
for (const [bid, m] of Object.entries(media)) {
  if (m) ok(`I1d 媒体 ${bid} 栏内宽（不跨栏）`, m.w <= m.colContentW + 1.5, `w=${m.w} col=${m.colContentW}`);
}

// I2 独立滚动
const scrollRes = await page.evaluate(() => {
  const [l, r] = document.querySelectorAll('.editor-body > .editor-column');
  const before = { l: l.scrollTop, r: r.scrollTop, win: window.scrollY, lScrollable: l.scrollHeight > l.clientHeight, rScrollable: r.scrollHeight > r.clientHeight };
  l.scrollTop = 240;
  return { before, after: { l: l.scrollTop, r: r.scrollTop, win: window.scrollY } };
});
console.log('SCROLL', JSON.stringify(scrollRes));
ok('I2 左栏可滚且右栏/窗口不动', scrollRes.after.l > 0 && scrollRes.after.r === 0 && scrollRes.after.win === scrollRes.before.win,
  `L:${scrollRes.before.l}->${scrollRes.after.l} R:${scrollRes.after.r} scrollable L=${scrollRes.before.lScrollable} R=${scrollRes.before.rScrollable}`);
// 复位左栏滚动
await page.evaluate(() => { document.querySelectorAll('.editor-body > .editor-column')[0].scrollTop = 0; });

// I3 渲染隔离 + I5 编辑
const iso = await page.evaluate(() => {
  const [, r] = document.querySelectorAll('.editor-body > .editor-column');
  window.__rcMut = 0; window.__rcTypes = {};
  window.__rcObs = new MutationObserver((ms) => { for (const m of ms) { window.__rcMut++; window.__rcTypes[m.type] = (window.__rcTypes[m.type] || 0) + 1; } });
  window.__rcObs.observe(r, { childList: true, attributes: true, characterData: true, subtree: true });
  return r.innerHTML.length;
});
const rightHashBefore = await page.evaluate(() => {
  const [, r] = document.querySelectorAll('.editor-body > .editor-column');
  let h = 0; const s = r.innerHTML; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
});
// 点左栏第一个文本块并打字
const firstLeftText = await page.evaluate(() => {
  const [l] = document.querySelectorAll('.editor-body > .editor-column');
  const el = Array.from(l.children).find((c) => (c.getAttribute('data-wrapbid') || c.querySelector('[data-wrapbid]')?.getAttribute('data-wrapbid')) === 'm01')
    || l.querySelector('[data-bid="m01"]') || l.children[0];
  const r = el.getBoundingClientRect();
  return { x: r.left + Math.min(60, r.width / 2), y: r.top + r.height / 2 };
});
await page.mouse.click(firstLeftText.x, firstLeftText.y);
await page.waitForTimeout(400);
await page.keyboard.type('XYZ');
await page.waitForTimeout(1000);
const isoRes = await page.evaluate(() => {
  window.__rcObs.disconnect();
  const [, r] = document.querySelectorAll('.editor-body > .editor-column');
  let h = 0; const s = r.innerHTML; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return { mut: window.__rcMut, types: window.__rcTypes, hash: h };
});
console.log('ISO', JSON.stringify(isoRes), 'hashBefore=', rightHashBefore);
ok('I3 左栏打字时右栏 DOM 零突变', isoRes.mut === 0, `mut=${isoRes.mut} types=${JSON.stringify(isoRes.types)}`);
ok('I3b 右栏 innerHTML 哈希不变', isoRes.hash === rightHashBefore);

// I5 落盘核对：返回列表触发关存，再读 IDB
await page.evaluate(() => { const b = document.querySelector('.editor-back, [aria-label="返回"]'); if (b) b.click(); });
await page.waitForSelector('.list-item', { timeout: 15000 }).catch(() => {});
await page.waitForTimeout(800);
const memo1 = await readMemo();
const docText = (m, bid) => { const n = (m.doc || []).find((x) => x.id === bid); return n ? JSON.stringify(n) : null; };
console.log('LAYOUT1', JSON.stringify(memo1?.layout));
ok('I5a 落盘 layout 为 independent 且成员与首屏一致',
  memo1?.layout?.mode === 'independent' && JSON.stringify(memo1.layout.left) === JSON.stringify(L0) && JSON.stringify(memo1.layout.right) === JSON.stringify(R0),
  `left=${JSON.stringify(memo1?.layout?.left)} right=${JSON.stringify(memo1?.layout?.right)}`);
const rightTexts1 = R0.map((b) => docText(memo1, b));
ok('I5b 左栏编辑已落盘（m01 含 XYZ）', (docText(memo1, 'm01') || '').includes('XYZ'));

// I4 栏内拖拽排序隔离
await openMemo();
const s1 = await snap();
ok('I6a 重进成员稳定（拖前）', JSON.stringify(s1.cols[0].bids) === JSON.stringify(L0) && JSON.stringify(s1.cols[1].bids) === JSON.stringify(R0));
const dragGeom = await page.evaluate(() => {
  const [l] = document.querySelectorAll('.editor-body > .editor-column');
  const kids = Array.from(l.children);
  const info = (el) => { const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2, top: r.top, bottom: r.bottom }; };
  return { first: info(kids[0]), third: info(kids[2]) };
});
await page.mouse.move(dragGeom.first.x, dragGeom.first.y);
await page.mouse.down();
await page.waitForTimeout(750); // 桌面文本块静止 hold 280ms / 触摸 480ms，留足
const lifted = await page.evaluate(() => !!document.querySelector('.mn-lifted'));
console.log('LIFTED', lifted);
if (lifted) {
  const targetY = dragGeom.third.y + 4;
  for (let i = 1; i <= 10; i++) {
    await page.mouse.move(dragGeom.first.x, dragGeom.first.y + (targetY - dragGeom.first.y) * i / 10);
    await page.waitForTimeout(30);
  }
  await page.waitForTimeout(300);
  await page.mouse.up();
  await page.waitForTimeout(900);
  const s2 = await snap();
  console.log('AFTER-DRAG L', JSON.stringify(s2.cols[0].bids), 'R', JSON.stringify(s2.cols[1].bids));
  ok('I4a 左栏内排序生效（首块已移位）', s2.cols[0].bids[0] !== L0[0] && s2.cols[0].bids.includes(L0[0]));
  ok('I4b 右栏 DOM 序逐块不变', JSON.stringify(s2.cols[1].bids) === JSON.stringify(R0));
  // 落盘核对 layout.right
  await page.evaluate(() => { const b = document.querySelector('.editor-back, [aria-label="返回"]'); if (b) b.click(); });
  await page.waitForSelector('.list-item', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(800);
  const memo2 = await readMemo();
  console.log('LAYOUT2', JSON.stringify(memo2?.layout));
  ok('I4c 落盘 layout.right 逐块不变', JSON.stringify(memo2?.layout?.right) === JSON.stringify(R0));
  ok('I4d 落盘 layout.left 与 DOM 序一致', JSON.stringify(memo2?.layout?.left) === JSON.stringify(s2.cols[0].bids));
  const rightTexts2 = R0.map((b) => docText(memo2, b));
  ok('I5c 排序后右栏块内容逐块不变', JSON.stringify(rightTexts2) === JSON.stringify(rightTexts1));
  // I6 重进稳定（拖后）
  await openMemo();
  const s3 = await snap();
  ok('I6b 拖后重进成员稳定', JSON.stringify(s3.cols[0].bids) === JSON.stringify(s2.cols[0].bids) && JSON.stringify(s3.cols[1].bids) === JSON.stringify(R0));
} else {
  ok('I4 左栏拖拽拾起', false, '未拾起，拖拽隔离未活体验证');
}

console.log(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
await browser.close();
process.exit(fails ? 1 : 0);
