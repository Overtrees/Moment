// 标题胶囊仪表化对照探针：Rust 版 vs 原版，同一套记录器、同一剧本。
// 记录：标题子树 MutationObserver、focus/blur/beforeinput/input/composition、
// selectionchange（offset+rect）、scroll、100ms 采样（几何/计算样式/节点同一性）。
// 用法: node probe_title_instr.mjs <chromium|webkit> <rust|orig> <new|seed|long> [scrolled]
import { chromium, webkit } from 'playwright-core';
import fs from 'node:fs';

const engine = process.argv[2] || 'chromium';
const app = process.argv[3] || 'rust';
const mode = process.argv[4] || 'seed';
const scrolled = process.argv[5] === 'scrolled';

const RUST = 'http://localhost:8131/';
const ORIG = 'http://localhost:8132/Moment.html';
const TITLE_SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';

let browser;
if (engine === 'webkit') {
  const { WK_ENV } = await import('/home/hatch/.tmp/wk_env.mjs'); browser = await webkit.launch({ headless: false, env: { ...WK_ENV, DISPLAY: ':99' } });
} else {
  const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
  browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
}
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 200)));

const INSTR = (SEL) => {
  const el = document.querySelector(SEL);
  if (!el) return 'no-title-el';
  const log = [];
  const T0 = performance.now();
  const ts = () => Math.round(performance.now() - T0);
  const desc = (n) => {
    if (!n) return 'null';
    if (n.nodeType === 3) return '#text(' + JSON.stringify((n.textContent || '').slice(0, 24)) + ')';
    if (n.nodeType === 1) return n.tagName.toLowerCase() + (n.id ? '#' + n.id : '') + ((n.className && typeof n.className === 'string') ? '.' + n.className.split(' ').join('.') : '') + (n.__tmark ? '@' + n.__tmark : '');
    return 'n' + n.nodeType;
  };
  el.__tmark = 1;
  const L = (kind, data) => log.push([ts(), kind, data]);
  window.__tlog = log; window.__tdesc = desc; window.__tel = el;
  const capsule = el.closest('.editor-title-capsule') || el.parentElement.parentElement;
  const mo = new MutationObserver((recs) => {
    for (const r of recs) {
      if (r.type === 'childList') {
        L('mut-childList', { target: desc(r.target), added: [...r.addedNodes].map(desc), removed: [...r.removedNodes].map(desc) });
      } else if (r.type === 'characterData') {
        L('mut-charData', { target: desc(r.target), old: JSON.stringify((r.oldValue || '').slice(0, 30)), now: JSON.stringify((r.target.textContent || '').slice(0, 30)) });
      } else if (r.type === 'attributes') {
        L('mut-attr', { target: desc(r.target), name: r.attributeName, old: (r.oldValue || '').slice(0, 60), now: (r.target.getAttribute(r.attributeName) || '').slice(0, 60) });
      }
    }
  });
  mo.observe(capsule, { subtree: true, childList: true, characterData: true, characterDataOldValue: true, attributes: true, attributeOldValue: true, attributeFilter: ['class', 'style', 'contenteditable'] });
  const evs = ['focus', 'blur', 'focusin', 'focusout', 'touchstart', 'touchend', 'keydown', 'beforeinput', 'input', 'compositionstart', 'compositionupdate', 'compositionend'];
  for (const ev of evs) {
    el.addEventListener(ev, (e) => {
      const d = { type: e.type };
      if (e.type === 'beforeinput' || e.type === 'input') { d.inputType = e.inputType; d.data = e.data; d.isComposing = !!e.isComposing; d.text = el.textContent; }
      if (e.type.startsWith('composition')) { d.data = e.data; d.text = el.textContent; }
      if (e.type === 'keydown') { d.key = e.key; d.isComposing = !!e.isComposing; }
      L('ev', d);
    }, true);
  }
  document.addEventListener('selectionchange', () => {
    const s = window.getSelection();
    if (!s.rangeCount) { L('sel', { none: true }); return; }
    const r = s.getRangeAt(0);
    if (r.startContainer !== el && !el.contains(r.startContainer)) return;
    const rect = r.getBoundingClientRect();
    L('sel', { off: r.startOffset, end: r.endOffset, col: r.collapsed, node: desc(r.startContainer), rect: [Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)], activeIsTitle: document.activeElement === el, sameNode: document.querySelector(SEL) === el });
  });
  window.addEventListener('scroll', () => {
    L('scroll', { y: Math.round(window.scrollY), dock: ((document.querySelector('.editor-title-dock') || {}).className || '') });
  }, { passive: true });
  setInterval(() => {
    const cs = getComputedStyle(el);
    const cr = el.getBoundingClientRect();
    const cap = capsule.getBoundingClientRect();
    L('sample', { active: document.activeElement === el, sameNode: document.querySelector(SEL) === el, text: el.textContent, font: cs.fontSize, ws: cs.whiteSpace, elR: [Math.round(cr.x), Math.round(cr.y), Math.round(cr.width), Math.round(cr.height)], capR: [Math.round(cap.x), Math.round(cap.y), Math.round(cap.width), Math.round(cap.height)], sy: Math.round(window.scrollY), vv: window.visualViewport ? Math.round(window.visualViewport.height) : -1, sl: el.parentElement ? el.parentElement.scrollLeft : -1 });
  }, 100);
  return 'ok';
};

async function titleCenter() {
  const box = await page.locator(TITLE_SEL).boundingBox();
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function snapState(tag) {
  const s = await page.evaluate(([SEL, tag]) => {
    const el = document.querySelector(SEL);
    const sel = window.getSelection();
    let off = -1, node = '';
    if (sel.rangeCount && (sel.getRangeAt(0).startContainer === el || el.contains(sel.getRangeAt(0).startContainer))) { off = sel.getRangeAt(0).startOffset; node = sel.getRangeAt(0).startContainer.nodeType === 3 ? '#text' : sel.getRangeAt(0).startContainer.nodeName; }
    return { tag, active: document.activeElement === el, sameNode: el === window.__tel, text: el.textContent, off, node, ce: el.getAttribute('contenteditable') };
  }, [TITLE_SEL, tag]);
  console.log('STATE', JSON.stringify(s));
  return s;
}
async function typeChars(chars, tagPrefix) {
  for (const ch of chars) {
    await page.keyboard.press(ch);
    await page.waitForTimeout(150);
    await snapState(tagPrefix + ':' + ch);
  }
}

// ---- 导航 ----
if (app === 'rust') {
  await page.goto(RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  if (mode === 'new') {
    await page.click('.new-card-title');
  } else {
    await page.getByText('周末看展记录', { exact: true }).first().click();
  }
  await page.waitForSelector(TITLE_SEL, { timeout: 10000 });
} else {
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  if (mode === 'new') {
    // 原版新建入口：列表页新建卡/按钮，按文本找
    const cand = page.getByText('新建笔记', { exact: false }).first();
    await cand.click();
  } else {
    await page.getByText('周末看展记录', { exact: true }).first().click();
  }
  await page.waitForSelector(TITLE_SEL, { timeout: 10000 });
}
await page.waitForTimeout(600);

if (scrolled) {
  await page.evaluate(() => window.scrollTo(0, 260));
  await page.waitForTimeout(500);
}

console.log('INSTR', await page.evaluate(INSTR, TITLE_SEL));
await snapState('before-tap1');

// ---- 会话 1 ----
const c1 = await titleCenter();
await page.touchscreen.tap(c1.x, c1.y);
await page.waitForTimeout(400);
await snapState('after-tap1');
await typeChars(mode === 'new' ? 'LongTitleXyz' : 'Ab1', 's1');
await page.waitForTimeout(300);
// 失焦：点正文区
await page.touchscreen.tap(200, 420);
await page.waitForTimeout(500);
await snapState('after-blur');

// ---- 会话 2 ----
const c2 = await titleCenter();
await page.touchscreen.tap(c2.x, c2.y);
await page.waitForTimeout(400);
await snapState('after-tap2');
await typeChars('Cd2', 's2');
await page.waitForTimeout(300);
await snapState('end');

const log = await page.evaluate(() => window.__tlog);
const outName = `/home/hatch/.tmp/tinstr_${engine}_${app}_${mode}${scrolled ? '_scrolled' : ''}.json`;
fs.writeFileSync(outName, JSON.stringify(log, null, 1));
console.log('LOG saved', outName, 'entries', log.length);
const counts = {};
for (const [, k] of log) counts[k] = (counts[k] || 0) + 1;
console.log('COUNTS', JSON.stringify(counts));
await browser.close();
