// 编辑器桥监听累积根治验收探针（Chromium 口径）：
// 插桩 addEventListener/removeEventListener/setInterval 净计数，
// 基线（列表页）→ 进编辑页 ×3 循环，断言：
//  - 打开时桥相关净计数恒为 基线+1 套（不随循环数增长）：
//    document:visibilitychange +1、document:selectionchange +2、
//    visualViewport:resize +1、visualViewport:scroll +1、
//    window:resize +1、window:scroll +2（edScroll+背景）、
//    mql:change +2（wide+scheme）、setInterval +1；
//  - 关闭后全部回到基线，__mnBridgeCleanup/__mnWideCleanup/
//    __mnInline 均为 null；
//  - 打开期间功能实证：正文键入 → visibilitychange(hidden)
//    触发 collectSync 同步 → 关闭重进后文本仍在（桥通道活）；
//  - 全部关闭后戳深色/改视口宽：无 pageerror、计数不动。
// 用法: node probe_bridge_cleanup.mjs [baseUrl]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = process.argv[2] || 'http://localhost:8211/';

const INIT = `
window.__probe = { net: {}, intervals: 0 };
window.__tgtName = (t) => {
  if (t === window) return 'window';
  if (t === document) return 'document';
  if (t === window.visualViewport) return 'visualViewport';
  if (typeof MediaQueryList !== 'undefined' && t instanceof MediaQueryList) return 'mql';
  if (t && t.nodeType === 1) return 'el';
  return 'other';
};
const __oAdd = EventTarget.prototype.addEventListener;
const __oRem = EventTarget.prototype.removeEventListener;
EventTarget.prototype.addEventListener = function (type, f, o) {
  const k = window.__tgtName(this) + ':' + type;
  window.__probe.net[k] = (window.__probe.net[k] || 0) + 1;
  return __oAdd.call(this, type, f, o);
};
EventTarget.prototype.removeEventListener = function (type, f, o) {
  const k = window.__tgtName(this) + ':' + type;
  window.__probe.net[k] = (window.__probe.net[k] || 0) - 1;
  return __oRem.call(this, type, f, o);
};
const __oSI = window.setInterval.bind(window);
const __oCI = window.clearInterval.bind(window);
window.setInterval = (...a) => { window.__probe.intervals++; return __oSI(...a); };
window.clearInterval = (id) => { window.__probe.intervals--; return __oCI(id); };
`;

const KEYS = [
  'document:visibilitychange',
  'document:selectionchange',
  'visualViewport:resize',
  'visualViewport:scroll',
  'window:resize',
  'window:scroll',
  'mql:change',
];
const DELTA = {
  'document:visibilitychange': 1,
  'document:selectionchange': 2,
  'visualViewport:resize': 1,
  'visualViewport:scroll': 1,
  'window:resize': 1,
  'window:scroll': 2,
  'mql:change': 2,
  intervals: 1,
};

const SNAP = () => {
  const net = window.__probe.net;
  const pick = {};
  for (const k of ['document:visibilitychange', 'document:selectionchange',
    'visualViewport:resize', 'visualViewport:scroll', 'window:resize',
    'window:scroll', 'mql:change']) pick[k] = net[k] || 0;
  pick.intervals = window.__probe.intervals;
  const st = (v) => (v === null ? 'null' : typeof v);
  return {
    net: pick,
    bridgeCleanup: st(window.__mnBridgeCleanup),
    wideCleanup: st(window.__mnWideCleanup),
    mnInline: st(window.__mnInline),
    mnFocus: st(window.__mnFocus),
    editorOpen: !!document.getElementById('editor-root'),
  };
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let fails = 0;
function check(label, cond, extra) {
  console.log((cond ? '✓ ' : '✗ ') + label + (extra ? '  ' + extra : ''));
  if (!cond) fails++;
}
function expectNet(label, snap, base, deltaMap) {
  for (const k of [...KEYS, 'intervals']) {
    const want = (base[k] || 0) + (deltaMap ? deltaMap[k] || 0 : 0);
    check(`${label} net ${k} == ${want}`, snap.net[k] === want, `(got ${snap.net[k]})`);
  }
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
await ctx.addInitScript(INIT);
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await sleep(1000);
const base = await page.evaluate(SNAP);
console.log('--- baseline (list, editor never opened)');
console.log(JSON.stringify(base.net));
const B = base.net;

async function openFirstMemo() {
  const item = page.locator('.list-item').first();
  const title = (await item.innerText()).split('\n')[0].trim();
  await item.click();
  try {
    await page.waitForSelector('#editor-root', { timeout: 4000 });
  } catch {
    await item.click(); // 折叠日期组首击是展开，再击打开
    await page.waitForSelector('#editor-root', { timeout: 10000 });
  }
  await sleep(1200);
  return title;
}
async function closeEditor() {
  await page.locator('.editor-fab.left').click();
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await sleep(1000);
}

for (let cycle = 1; cycle <= 3; cycle++) {
  const title = await openFirstMemo();
  const open = await page.evaluate(SNAP);
  console.log(`--- cycle ${cycle} editor open`);
  console.log(JSON.stringify(open.net));
  check(`cycle ${cycle} editorOpen`, open.editorOpen === true);
  check(`cycle ${cycle} __mnBridgeCleanup is function`, open.bridgeCleanup === 'function');
  check(`cycle ${cycle} __mnWideCleanup is function`, open.wideCleanup === 'function');
  check(`cycle ${cycle} __mnInline is function`, open.mnInline === 'function');
  expectNet(`cycle ${cycle} open`, open, B, DELTA);

  if (cycle === 1) {
    // 功能实证：正文键入 → visibilitychange(hidden) 触发桥
    // collectSync → 关闭重进后标记文本仍在。
    const marker = '桥同步标记' + Date.now();
    const blk = page.locator('.editor-body [data-bid]').first();
    await blk.click();
    await page.keyboard.press('End');
    await page.keyboard.type(marker);
    await sleep(400);
    await page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await sleep(500);
    await closeEditor();
    const closed1 = await page.evaluate(SNAP);
    expectNet('cycle 1 closed (mid)', closed1, B, null);
    // 重进同一备忘核对标记：列表首项是「新建笔记」入口卡，
    // 按 title 找会再命中入口卡开出新备忘——按正文预览里的
    // 标记文本定位刚编辑的那篇（预览含标记即已落库的旁证）。
    await page.locator('.list-item', { hasText: marker }).first().click();
    await page.waitForSelector('#editor-root', { timeout: 10000 });
    await sleep(1000);
    const bodyText = await page.evaluate(() => {
      const b = document.querySelector('.editor-body');
      return b ? b.textContent : '';
    });
    check('visibilitychange sync persisted typed text', bodyText.includes(marker));
  }

  await closeEditor();
  const closed = await page.evaluate(SNAP);
  console.log(`--- cycle ${cycle} editor closed`);
  console.log(JSON.stringify(closed.net));
  check(`cycle ${cycle} closed editorOpen false`, closed.editorOpen === false);
  check(`cycle ${cycle} closed __mnBridgeCleanup null`, closed.bridgeCleanup === 'null');
  check(`cycle ${cycle} closed __mnWideCleanup null`, closed.wideCleanup === 'null');
  check(`cycle ${cycle} closed __mnInline null`, closed.mnInline === 'null');
  check(`cycle ${cycle} closed __mnFocus null`, closed.mnFocus === 'null');
  expectNet(`cycle ${cycle} closed`, closed, B, null);
}

// 全部关闭后戳媒体：残留 mql 处理器若在，会向死通道 send
// （计数虽已归零，此步主要看 pageerror 与计数稳定）
await page.emulateMedia({ colorScheme: 'dark' });
await sleep(500);
await page.setViewportSize({ width: 900, height: 800 });
await sleep(500);
await page.emulateMedia({ colorScheme: 'light' });
await page.setViewportSize({ width: 1280, height: 800 });
await sleep(500);
const poked = await page.evaluate(SNAP);
expectNet('after media pokes', poked, B, null);
check('no pageerror through whole run', errors.length === 0, errors.join(' | '));

console.log(fails === 0 ? 'PROBE BRIDGE CLEANUP ALL PASS' : `PROBE BRIDGE CLEANUP ${fails} FAILURES`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
