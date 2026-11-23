// 标题胶囊拼音组字对照探针（CDP Input.imeSetComposition / imeCommitText）。
// 组字事件流由 Chromium 内核 IME 管线产生，页面侧感知与真实拼音同型。
// 检查：组字期间 composition 事件序列完整（start/update*/end 恰一次）、
// 标题节点零替换、文本零重敷、选区不被重置；提交后落字位置正确。
// 用法: node probe_title_ime.mjs <rust|orig> <new|seed>
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const app = process.argv[2] || 'rust';
const mode = process.argv[3] || 'new';

const RUST = 'http://localhost:8133/';
const ORIG = 'http://localhost:8132/Moment.html';
const TITLE_SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 200)));
const cdp = await ctx.newCDPSession(page);

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
  const evs = ['focus', 'blur', 'focusin', 'focusout', 'keydown', 'beforeinput', 'input', 'compositionstart', 'compositionupdate', 'compositionend'];
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
    L('sel', { off: r.startOffset, end: r.endOffset, col: r.collapsed, node: desc(r.startContainer), activeIsTitle: document.activeElement === el, sameNode: document.querySelector(SEL) === el });
  });
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
    return { tag, active: document.activeElement === el, sameNode: el === window.__tel, text: el.textContent, off, node };
  }, [TITLE_SEL, tag]);
  console.log('STATE', JSON.stringify(s));
  return s;
}
async function composeRound(steps, commitText, tagPrefix) {
  for (const [text, selStart] of steps) {
    await cdp.send('Input.imeSetComposition', { text, selectionStart: selStart, selectionEnd: selStart });
    await page.waitForTimeout(200);
    await snapState(tagPrefix + ':comp=' + text);
  }
  // headless-shell 的 Input 域未实现 imeCommitText（实测报 wasn't
  // found），回退 Input.insertText：Blink 在组合中收到 insertText
  // 会以给定文本确认组合（compositionend 同型触发），事件序列可比。
  try {
    await cdp.send('Input.imeCommitText', { text: commitText });
  } catch (e) {
    console.log('COMMIT-FALLBACK Input.insertText:', String(e).slice(0, 80));
    await cdp.send('Input.insertText', { text: commitText });
  }
  await page.waitForTimeout(350);
  await snapState(tagPrefix + ':committed=' + commitText);
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
    await page.getByText('新建笔记', { exact: false }).first().click();
  } else {
    await page.getByText('周末看展记录', { exact: true }).first().click();
  }
  await page.waitForSelector(TITLE_SEL, { timeout: 10000 });
}
await page.waitForTimeout(600);

console.log('INSTR', await page.evaluate(INSTR, TITLE_SEL));
await snapState('before-tap1');

// ---- 会话 1：tap 聚焦 + 组字「nihao」→ 提交「你好」 ----
const c1 = await titleCenter();
await page.touchscreen.tap(c1.x, c1.y);
await page.waitForTimeout(500);
await snapState('after-tap1');
await composeRound([['n', 1], ['ni', 2], ['nihao', 5]], '你好', 's1');

// 失焦
await page.touchscreen.tap(200, 420);
await page.waitForTimeout(500);
await snapState('after-blur');

// ---- 会话 2：再次 tap + 组字「zaijian」→ 提交「再见」 ----
const c2 = await titleCenter();
await page.touchscreen.tap(c2.x, c2.y);
await page.waitForTimeout(500);
await snapState('after-tap2');
await composeRound([['zai', 3], ['zaijian', 7]], '再见', 's2');
await snapState('end');

const log = await page.evaluate(() => window.__tlog);
const outName = `/home/hatch/.tmp/time_${app}_${mode}.json`;
fs.writeFileSync(outName, JSON.stringify(log, null, 1));
console.log('LOG saved', outName, 'entries', log.length);
// 组字事件序列摘要
const comp = log.filter(([, k, d]) => k === 'ev' && (String(d.type).startsWith('composition') || (d.type === 'beforeinput' && d.isComposing) || (d.type === 'input' && d.isComposing)));
console.log('COMP EVENTS', comp.length);
for (const [t, , d] of comp) console.log(' ', t, d.type, JSON.stringify(d.data), 'text=' + JSON.stringify(d.text));
await browser.close();
