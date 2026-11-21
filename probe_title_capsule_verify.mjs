// 标题胶囊修复验证探针（配合 probe_title_capsule.mjs 复现探针）：
// 断言首次点击即可输入、失焦后字号不漂移、逐字光标单调、溢出态
// 光标跟随滚动、删字跨阈值布局锁存不跳、组合输入不回归、落库。
// 用法：node probe_title_capsule_verify.mjs http://localhost:8116/
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8116/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : ''));
  if (!cond) fails++;
};
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

const snap = () => page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const cap = document.querySelector('.editor-title-capsule');
  const sc = document.querySelector('.editor-title-scroller');
  const sel = window.getSelection();
  let glyphX = null;
  if (sel && sel.rangeCount && sel.focusNode && sel.focusNode.nodeType === 3 && sel.focusNode.length) {
    const n = sel.focusNode;
    const off = Math.max(0, Math.min(sel.focusOffset, n.length));
    const gr = document.createRange();
    if (off > 0) { gr.setStart(n, off - 1); gr.setEnd(n, off); } else { gr.setStart(n, 0); gr.setEnd(n, 1); }
    const g = gr.getBoundingClientRect();
    glyphX = off > 0 ? g.right : g.left;
  }
  const cr = cap.getBoundingClientRect();
  return {
    text: el.textContent,
    font: getComputedStyle(el).fontSize,
    style: el.getAttribute('style'),
    active: document.activeElement && document.activeElement.id,
    off: sel && sel.rangeCount ? sel.focusOffset : null,
    glyphX,
    capL: cr.left, capR: cr.right, capW: cr.width, capCls: cap.className,
    scrollLeft: sc ? sc.scrollLeft : null,
  };
});
async function tapCapsule(dx = null) {
  const box = await page.locator('.editor-title-capsule').boundingBox();
  await page.touchscreen.tap(box.x + (dx === null ? box.width / 2 : dx), box.y + 20);
  await page.waitForTimeout(500);
}

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(500);

// —— 会话 1（短标题，首次点击） ——
await tapCapsule();
let s = await snap();
ok(s.active === 'editor-title-text', 'S1 首次点击即聚焦标题', s.active);
const offs = [];
for (const ch of ['X', 'Y']) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(200);
  s = await snap();
  offs.push(s.off);
}
ok(s.text.includes('XY'), 'S1 首次点击即可打字', s.text);
ok(offs[1] === offs[0] + 1, 'S1 逐字光标 +1', JSON.stringify(offs));
await page.tap('.editor-body');
await page.waitForTimeout(600);
s = await snap();
ok(s.font === '11px', 'S1 失焦后字号仍 11px（不漂移）', s.font + ' style=' + s.style);
ok(s.text === '周末看XY展记录', 'S1 失焦提交全文', s.text);

// —— 会话 2（第二次点击，字号/几何应与会话 1 同口径） ——
await tapCapsule();
s = await snap();
ok(s.font === '11px', 'S2 第二次编辑字号仍 11px', s.font);
const offs2 = [];
for (const ch of ['Z', 'W', 'V', 'U']) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(200);
  s = await snap();
  offs2.push(s.off);
}
ok(offs2.every((v, i) => i === 0 || v === offs2[i - 1] + 1), 'S2 逐字光标单调 +1', JSON.stringify(offs2));
ok(s.text.length === 12, 'S2 打字落字（现 12 字，进溢出态）', s.text);
ok(s.capCls.includes('overflow'), 'S2 >11 字进入溢出态', s.capCls);
// 溢出态继续打字：光标应被滚动跟随在胶囊内
for (const ch of ['T', 'S', 'R', 'Q', 'P', 'O', 'N', 'M']) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(120);
}
s = await snap();
ok(s.scrollLeft > 0, 'S2 溢出打字滚动区跟随', 'scrollLeft=' + s.scrollLeft);
ok(s.glyphX !== null && s.glyphX >= s.capL + 8 && s.glyphX <= s.capR - 8, 'S2 光标保持在胶囊内', `glyphX=${s.glyphX} cap=[${s.capL},${s.capR}]`);
// 删字跨回阈值：布局锁存——字号与溢出类在本会话内不回落
for (let i = 0; i < 12; i++) await page.keyboard.press('Backspace');
await page.waitForTimeout(400);
s = await snap();
ok(s.font === '11px' && s.capCls.includes('overflow'), 'S2 删到 9 字布局锁存（字号/溢出不回落）', s.font + ' ' + s.capCls + ' text=' + s.text);
await page.tap('.editor-body');
await page.waitForTimeout(600);
s = await snap();
ok(!s.capCls.includes('overflow') && s.font === '11px', 'S2 失焦后溢出解除、字号 11px', s.font + ' ' + s.capCls);

// —— 长标题截断态聚焦：全文展开 + 输入落字 ——
await tapCapsule();
await page.keyboard.press('End').catch(() => {});
for (const ch of ['1', '2', '3', '4', '5', '6']) await page.keyboard.press(ch);
await page.waitForTimeout(300);
await page.tap('.editor-body');
await page.waitForTimeout(600);
s = await snap();
ok(s.text.includes('…'), 'S3 长标题失焦回截断显示', s.text);
await tapCapsule(30);
s = await snap();
ok(!s.text.includes('…') && s.text.length >= 14, 'S3 聚焦同步展开全文', s.text);
await page.keyboard.press('K');
await page.waitForTimeout(250);
s = await snap();
ok(s.text.includes('K'), 'S3 展开后输入落字', s.text);
await page.tap('.editor-body');
await page.waitForTimeout(600);

// —— 组合输入：composition 期间不提交、结束提交一次 ——
await tapCapsule();
const comp = await page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  el.focus();
  const r = document.createRange();
  r.selectNodeContents(el);
  r.collapse(false);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(r);
  el.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
  document.execCommand('insertText', false, 'pin');
  el.dispatchEvent(new CompositionEvent('compositionupdate', { bubbles: true, data: 'pin' }));
  const during = el.textContent;
  document.execCommand('insertText', false, '拼');
  el.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '拼' }));
  return { during, after: el.textContent };
});
await page.waitForTimeout(400);
s = await snap();
ok(comp.after.includes('拼') && s.text.includes('拼'), 'S4 组合输入上屏并提交', JSON.stringify(comp) + ' -> ' + s.text);
await page.tap('.editor-body');
await page.waitForTimeout(600);

// —— 落库：返回 + 刷新 + 重开 ——
const finalTitle = s.text;
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
const cardTitle = await page.evaluate((t) => {
  const els = [...document.querySelectorAll('.list-item .item-title-text, .img-card .img-card-title-text')];
  return els.map((e) => e.textContent).find((x) => x && t.startsWith(x.replace('…', ''))) || null;
}, finalTitle.replace('…', ''));
ok(!!cardTitle, 'S5 标题落库（刷新后列表可见）', String(cardTitle));

ok(errors.length === 0, '全程无 pageerror', errors.slice(0, 2).join(' ; '));
console.log(fails === 0 ? 'TITLE PROBE ALL PASS' : `TITLE PROBE FAILURES: ${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
