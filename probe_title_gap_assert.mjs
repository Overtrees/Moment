// 标题胶囊编辑态左右留空对称断言探针（修复回归门）：
// 溢出编辑态两端 gutter 相等（文首光标距胶囊左缘 == 文末光标距
// 胶囊右缘，差 ≤1px）；二次聚焦后光标必须被同步进胶囊内且
// scrollLeft 到位；Diag 留下 title caret sync 行。
// 【E2 口径变更，2026-11-22 调优】截断长标题点按聚焦改走调优
// 落点（尊重落点，见 probe_title_reopen2 头注）：旧 E2 以「点按
// 二次聚焦→光标文末（元素锚）」为前提，该前提只剩非点按聚焦
// 成立。故 E2 拆两段：E2a 点按→落映射位且光标在胶囊内；E2 本体
// 改用程序聚焦（el.focus()）触发元素锚路径，文末断言全保留。
// 用法：node probe_title_gap_assert.mjs [rustBase]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8201/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : ''));
  if (!cond) fails++;
};

const MEASURE = () => {
  const el = document.getElementById('editor-title-text');
  const sc = el.parentElement;
  const cap = sc.parentElement;
  const cr = cap.getBoundingClientRect();
  const sel = window.getSelection();
  let caretX = null;
  if (sel && sel.rangeCount && sel.focusNode && el.contains(sel.focusNode)) {
    let node = sel.focusNode.nodeType === 3 ? sel.focusNode : null;
    let off = node ? Math.max(0, Math.min(sel.focusOffset, node.length)) : 0;
    if (!node && sel.focusNode.nodeType === 1) {
      const atEnd = sel.focusOffset > 0;
      const child = sel.focusNode.childNodes[atEnd ? sel.focusOffset - 1 : sel.focusOffset];
      let t = null;
      const find = (n, fromEnd) => { if (t || !n) return; if (n.nodeType === 3) { if (n.length) t = n; return; } const ks = [...n.childNodes]; if (fromEnd) ks.reverse(); for (const k of ks) find(k, fromEnd); };
      find(child, atEnd);
      if (t) { node = t; off = atEnd ? t.length : 0; }
    }
    if (node && node.length) {
      const from = off > 0 ? off - 1 : off;
      const to = off > 0 ? off : Math.min(off + 1, node.length);
      const gr = document.createRange();
      gr.setStart(node, from); gr.setEnd(node, to);
      const g = gr.getBoundingClientRect();
      if (g.height) caretX = off > 0 ? g.right : g.left;
    }
  }
  const r2 = (v) => (v === null ? null : Math.round(v * 100) / 100);
  return {
    capL: cr.left, capR: cr.right,
    scrollLeft: sc.scrollLeft, maxScroll: sc.scrollWidth - sc.clientWidth,
    gapCaretL: caretX !== null ? r2(caretX - cr.left) : null,
    gapCaretR: caretX !== null ? r2(cr.right - caretX) : null,
    caretIn: caretX !== null && caretX >= cr.left && caretX <= cr.right,
  };
};

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(600);
const M = () => page.evaluate(MEASURE);
const tapCap = async () => {
  const box = await page.locator('.editor-title-capsule').boundingBox();
  await page.touchscreen.tap(box.x + box.width / 2, box.y + 20);
  await page.waitForTimeout(800);
};
const inGutter = (v) => v !== null && v >= 33.5 && v <= 36.5;
// 当前选区在标题全文内的字符位（元素锚经 Range 收尾归一）。
const caretOffset = () => page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const sel = window.getSelection();
  if (!sel || !sel.rangeCount || !el.contains(sel.focusNode)) return -1;
  const r = document.createRange();
  r.selectNodeContents(el);
  r.setEnd(sel.focusNode, sel.focusOffset);
  return r.toString().length;
});
// 点按胶囊中心前：按截断串字形边界推导期望截断位 c 与截断长。
const tapExpect = () => page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const cap = document.querySelector('.editor-title-capsule');
  const node = el.firstChild;
  const text = el.textContent;
  const cr = cap.getBoundingClientRect();
  const tapX = cr.x + cr.width / 2;
  let c = 0, best = Infinity;
  for (let i = 0; i <= text.length; i++) {
    const r = document.createRange();
    let x;
    if (i < text.length) { r.setStart(node, i); r.setEnd(node, i + 1); x = r.getBoundingClientRect().left; }
    else { r.setStart(node, i - 1); r.setEnd(node, i); x = r.getBoundingClientRect().right; }
    const d = Math.abs(x - tapX);
    if (d < best) { best = d; c = i; }
  }
  return { c, truncLen: text.length };
});

await tapCap();
await page.evaluate(() => document.execCommand('selectAll', false, null));
await page.keyboard.type('阿阿阿阿头哦婆婆婆婆给的', { delay: 30 });
await page.waitForTimeout(700);
let s = await M();
ok(inGutter(s.gapCaretR), 'E1 ovf13 文末右 gutter ≈35', `gapCaretR=${s.gapCaretR} scrollLeft=${s.scrollLeft}/${s.maxScroll}`);
await page.keyboard.type('七八九', { delay: 30 });
await page.waitForTimeout(700);
s = await M();
ok(inGutter(s.gapCaretR), 'E1 ovf16 文末右 gutter ≈35', `gapCaretR=${s.gapCaretR} scrollLeft=${s.scrollLeft}/${s.maxScroll}`);
const endGutter16 = s.gapCaretR;

await page.touchscreen.tap(196, 500);
await page.waitForTimeout(600);
// E2a（调优新段）：点按二次聚焦 → 落映射位、光标在胶囊内
const exp2a = await tapExpect();
await tapCap();
s = await M();
const off2a = await caretOffset();
const fullLen2a = await page.evaluate(() => document.getElementById('editor-title-text').textContent.length);
const want2a = exp2a.c <= exp2a.truncLen - 1 ? exp2a.c : fullLen2a;
ok(Math.abs(off2a - want2a) <= 1, 'E2a ovf16 点按二次聚焦落映射位(调优)', `off=${off2a} 期望≈${want2a} (截断位 ${exp2a.c}/${exp2a.truncLen})`);
ok(s.caretIn, 'E2a ovf16 点按后光标在胶囊内', `caretIn=${s.caretIn}`);
await page.touchscreen.tap(196, 500);
await page.waitForTimeout(600);
// E2（原段，改程序聚焦触发）：聚焦事务把光标放到文末（元素锚）
await page.evaluate(() => document.getElementById('editor-title-text').focus());
await page.waitForTimeout(800);
s = await M();
ok(s.caretIn, 'E2 ovf16 二次聚焦后光标在胶囊内', `caretIn=${s.caretIn}`);
ok(Math.abs(s.scrollLeft - s.maxScroll) <= 1, 'E2 ovf16 二次聚焦后 scrollLeft 到底', `scrollLeft=${s.scrollLeft}/${s.maxScroll}`);
ok(inGutter(s.gapCaretR), 'E2 ovf16 文末右 gutter ≈35', `gapCaretR=${s.gapCaretR}`);
await page.keyboard.press('Home');
await page.waitForTimeout(600);
s = await M();
ok(inGutter(s.gapCaretL), 'E2 ovf16 文首左 gutter ≈35', `gapCaretL=${s.gapCaretL}`);
ok(Math.abs(s.gapCaretL - endGutter16) <= 1, 'ovf16 左右留空差 ≤1px', `L=${s.gapCaretL} R=${endGutter16}`);

await page.evaluate(() => document.execCommand('selectAll', false, null));
await page.keyboard.type('你的爹给你弟弟等哥哥哥哥哥', { delay: 30 });
await page.waitForTimeout(700);
s = await M();
const endGutter15 = s.gapCaretR;
ok(inGutter(endGutter15), 'E2 ovf15 文末右 gutter ≈35', `gapCaretR=${endGutter15}`);
await page.keyboard.press('Home');
await page.waitForTimeout(600);
s = await M();
ok(Math.abs(s.gapCaretL - endGutter15) <= 1, 'ovf15 左右留空差 ≤1px', `L=${s.gapCaretL} R=${endGutter15}`);

const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
ok(/title caret sync scroll/.test(diag), 'Diag 有 title caret sync 行', (diag.match(/title caret sync scroll[^\n]*/) || [''])[0]);
ok(errors.length === 0, '无 pageerror', errors.slice(0, 2).join('; '));
await browser.close();
console.log(fails === 0 ? 'ALL PASS' : `FAILS: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
