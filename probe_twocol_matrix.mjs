// 双栏逐块适配矩阵探针（mix-layout 夹具，16 块全类型）：
//  M1 判据变更（A-2 决策 D1，2026-11-24）：流式改渲染分段
//     后两模式成员按设计不再一致，旧「逐块一致」判据废止。
//     新判据——M1a 独立成员 == layout 锚分界（开后落锚回读
//     对账）；M1b 流式成员分段确定性（两次流式快照逐块
//     全等，含跨栏块 SPAN 标记）。
//  M2 菜单开关往返（独立→flow→独立）成员不变
//  M3 右栏 md 预览块点击进源码编辑
//  M4 右栏文本块内斜杠面板可见且在视口内
//  M5 跨栏方向键：左栏末可编辑块 End+→ 到右栏首块；右栏首块 Home+← 回左栏末块
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8196/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' — ' + extra : '')); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
await ctx.addInitScript(() => localStorage.setItem('sj_editor_independent_scroll', '1'));
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));

// 夹具注入改走设置页备份导入（2026-11-24 随 A-2 探针笔
// 同步）：直接写 IDB kv 已不是数据源头（启动被真存储覆
// 盖、注入不生效），与 probe_undo_granularity 等现行探针
// 统一口径。导入后回列表再点开夹具。
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', process.env.HOME + '/workspace/Mynote/fixtures/mix-layout.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.evaluate(() => {
  const el = Array.from(document.querySelectorAll('.img-card-title-text, .item-title-text')).find((e) => e.textContent.includes('混排验收'));
  if (el) el.click();
});
await page.waitForSelector('.editor-body', { timeout: 15000 });
await page.waitForTimeout(1200);

const snapshot = () => {
  const body = document.querySelector('.editor-body');
  // 身份解析：MD 预览单元（.md-hit）以 data-bids 组属性
  // 携带块 id（可多块成组，逐 id 展开记账）；其余单元走
  // wrapbid/bid。'?md:' 文本键仅作无身份时的最后兜底。
  const bidOf = (el) => el.getAttribute('data-wrapbid')
    || el.querySelector('[data-wrapbid]')?.getAttribute('data-wrapbid')
    || el.getAttribute('data-bid')
    || el.querySelector('[data-bid]')?.getAttribute('data-bid')
    || ('?md:' + (el.textContent || '').trim().slice(0, 10));
  const blocks = [];
  const pushCol = (colEl, name) => {
    for (const child of colEl.children) {
      if (child.classList.contains('md-trail')) continue;
      const r = child.getBoundingClientRect();
      const multi = child.getAttribute('data-bids');
      if (multi) {
        for (const id of multi.split(',').filter(Boolean)) blocks.push({ bid: id, col: name, w: Math.round(r.width) });
      } else {
        blocks.push({ bid: bidOf(child), col: name, w: Math.round(r.width) });
      }
    }
  };
  const cols = body.querySelectorAll(':scope > .editor-column');
  if (cols.length === 2) {
    pushCol(cols[0], 'L');
    pushCol(cols[1], 'R');
    return { mode: body.classList.contains('is-independent-scroll') ? 'independent' : 'flowcols', blocks };
  }
  // A-2 流式分段 DOM：body 直子 = .editor-flow-seg（内两栏）
  // 与跨栏块直子（记 SPAN）。
  const segs = body.querySelectorAll(':scope > .editor-flow-seg');
  if (segs.length > 0) {
    for (const child of body.children) {
      if (child.classList.contains('editor-flow-seg')) {
        const sc = child.querySelectorAll(':scope > .editor-column');
        pushCol(sc[0], 'L');
        pushCol(sc[1], 'R');
      } else if (!child.classList.contains('md-trail')) {
        const r = child.getBoundingClientRect();
        blocks.push({ bid: bidOf(child), col: 'SPAN', w: Math.round(r.width) });
      }
    }
    return { mode: 'flowcols', blocks };
  }
  return { mode: 'no-columns', blocks: [] };
};

const sIndep = await page.evaluate(snapshot);
console.log('INDEP:', JSON.stringify(Object.fromEntries(sIndep.blocks.map((b) => [b.bid, b.col]))));

// 开关往返：独立 → flow → 独立
async function toggle() {
  const panelVisible = await page.evaluate(() => !!document.querySelector('.editor-menu-panel'));
  if (!panelVisible) {
    // fab 走指针手势路径开菜单（合成 click 不开，同
    // probe_twocol_flow_span 的 toggleMode 口径）
    await page.$eval('.editor-fab.right', (e) => {
      const r = e.getBoundingClientRect();
      const o = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, pointerId: 1, pointerType: 'mouse', isPrimary: true };
      e.dispatchEvent(new PointerEvent('pointerdown', o));
      e.dispatchEvent(new PointerEvent('pointerup', o));
    });
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
// M1a：独立成员 == 锚分界。夹具无 layout，独立首开落锚后
// 回读 IDB 的 layout 名单逐块对账快照成员。
const anchor = await page.evaluate(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const raw = await new Promise((res, rej) => { const rq = db.transaction('kv').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  const m = JSON.parse(raw).memos.find((x) => String(x.id) === 'mixfix1');
  return m && m.layout ? { left: m.layout.left || [], right: m.layout.right || [] } : null;
});
const indepMap = map(sIndep);
ok('M1a 独立成员 == 锚分界', !!anchor
  && anchor.left.every((id) => indepMap[id] === 'L')
  && anchor.right.every((id) => indepMap[id] === 'R')
  && [...anchor.left, ...anchor.right].every((id) => id in indepMap),
  anchor ? `left=${anchor.left.join(',')} right=${anchor.right.join(',')}` : 'no anchor');
// M1b：流式分段确定性——再切回流式，快照与首次流式逐块全等。
await toggle();
const sFlow2 = await page.evaluate(snapshot);
console.log('FLOW2:', sFlow2.mode, JSON.stringify(map(sFlow2)));
await toggle();
const sIndep3 = await page.evaluate(snapshot);
ok('M1b 流式成员分段确定性（两次全等）', sFlow.mode === 'flowcols' && sFlow2.mode === 'flowcols' && sameMap(map(sFlow), map(sFlow2)));
ok('M2 开关往返成员不变', sIndep2.mode === 'independent' && sameMap(map(sIndep), map(sIndep2)) && sIndep3.mode === 'independent' && sameMap(map(sIndep), map(sIndep3)));

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
