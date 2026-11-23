// 标题胶囊编辑态左右留空量测探针（Rust vs 原版同语料同流程）：
// 三态（非编辑 / 首次聚焦编辑 / 失焦后二次聚焦）× 短/长/溢出标题，
// 量胶囊与 scroller 的 padding、scrollPadding、scrollLeft/Width、
// 文本首尾与光标（相邻字形法）到胶囊两缘的距离。
// 用法：node probe_title_gap.mjs [rustBase] [origBase]
import { chromium } from 'playwright-core';

const RUST = process.argv[2] || 'http://localhost:8201/';
const ORIG = process.argv[3] || 'http://localhost:8202/Moment.html';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const MEASURE = (inputSel) => {
  const el = document.querySelector(inputSel);
  if (!el) return { err: 'no input' };
  const sc = el.parentElement;
  const cap = sc && sc.parentElement;
  const cs = getComputedStyle(el), ss = getComputedStyle(sc), ps = getComputedStyle(cap);
  const cr = cap.getBoundingClientRect(), sr = sc.getBoundingClientRect();
  // 全文范围 rect（第一个文本节点）
  let tn = null;
  const walk = (n) => { if (tn) return; if (n.nodeType === 3 && n.length) { tn = n; return; } for (const c of n.childNodes) walk(c); };
  walk(el);
  let textL = null, textR = null;
  if (tn) {
    const r = document.createRange();
    r.setStart(tn, 0); r.setEnd(tn, tn.length);
    const b = r.getBoundingClientRect();
    textL = b.left; textR = b.right;
  }
  // 光标 x：相邻字形边界法（同原版 scheduleTitleCaretSync 口径）
  const sel = window.getSelection();
  let caretX = null, caretOff = null;
  if (sel && sel.rangeCount && sel.focusNode && el.contains(sel.focusNode)) {
    caretOff = sel.focusOffset;
    let node = sel.focusNode.nodeType === 3 ? sel.focusNode : null;
    let off = node ? Math.max(0, Math.min(sel.focusOffset, node.length)) : 0;
    if (!node && sel.focusNode.nodeType === 1) {
      const atEnd = sel.focusOffset > 0;
      const child = sel.focusNode.childNodes[atEnd ? sel.focusOffset - 1 : sel.focusOffset];
      let t = null;
      const find = (n, fromEnd) => { if (t) return; if (!n) return; if (n.nodeType === 3) { if (n.length) t = n; return; } const ks = [...n.childNodes]; if (fromEnd) ks.reverse(); for (const k of ks) find(k, fromEnd); };
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
  const r2 = (v) => (v === null || v === undefined ? null : Math.round(v * 100) / 100);
  return {
    text: el.textContent,
    cls: el.className, capCls: cap.className, scCls: sc.className,
    font: cs.fontSize, align: cs.textAlign,
    capL: r2(cr.left), capR: r2(cr.right), capW: r2(cr.width),
    capPadL: ps.paddingLeft, capPadR: ps.paddingRight,
    scPadL: ss.paddingLeft, scPadR: ss.paddingRight,
    scScrollPad: ss.scrollPaddingInline,
    scL: r2(sr.left), scR: r2(sr.right), scW: r2(sr.width),
    scrollLeft: r2(sc.scrollLeft), scrollWidth: sc.scrollWidth, clientWidth: sc.clientWidth,
    maxScroll: sc.scrollWidth - sc.clientWidth,
    textL: r2(textL), textR: r2(textR),
    gapStart: textL !== null ? r2(textL - cr.left) : null,
    gapEnd: textR !== null ? r2(cr.right - textR) : null,
    caretOff, caretX: r2(caretX),
    gapCaretL: caretX !== null ? r2(caretX - cr.left) : null,
    gapCaretR: caretX !== null ? r2(cr.right - caretX) : null,
    inlineStyle: el.getAttribute('style'), scInline: sc.getAttribute('style'), capInline: cap.getAttribute('style'),
  };
};

async function drive(browser, base, inputSel, isOrig) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  const out = {};
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  if (isOrig) {
    await page.getByText('周末看展记录', { exact: true }).first().click();
  } else {
    await page.click('.list-item:has-text("周末看展记录") .item-title-text');
  }
  await page.waitForSelector(inputSel, { timeout: 10000 });
  await page.waitForTimeout(600);
  const M = () => page.evaluate(MEASURE, inputSel);
  const tapCap = async (fx = 0.5) => {
    const box = await page.locator(inputSel).boundingBox();
    await page.touchscreen.tap(box.x + box.width * fx, box.y + box.height / 2);
    await page.waitForTimeout(700);
  };
  const blurTap = async () => {
    await page.touchscreen.tap(196, 500);
    await page.waitForTimeout(600);
  };
  const setTitle = async (t) => {
    await page.evaluate(() => document.execCommand('selectAll', false, null));
    await page.keyboard.type(t, { delay: 30 });
    await page.waitForTimeout(700);
  };

  out['N-short6'] = await M();
  await tapCap();
  await setTitle('周末看展记录补遗'); // 8 字：is-long 非溢出
  out['E1-long8-end'] = await M();
  await blurTap();
  out['N-long8'] = await M();
  await tapCap();
  await setTitle('阿阿阿阿头哦婆婆婆婆给的'); // 13 字溢出（截图 1）
  out['E1-ovf13-end'] = await M();
  await page.keyboard.type('七八九', { delay: 30 }); // 继续生长到 16 字
  await page.waitForTimeout(700);
  out['E1-ovf16-end'] = await M();
  await blurTap();
  out['N-ovf16'] = await M();
  await tapCap(); // 第二会话：聚焦后 rAF 光标到末尾
  out['E2-ovf16-focus'] = await M();
  await page.keyboard.press('Home');
  await page.waitForTimeout(500);
  out['E2-ovf16-start'] = await M();
  await page.keyboard.press('End');
  await page.waitForTimeout(500);
  out['E2-ovf16-end'] = await M();
  await setTitle('你的爹给你弟弟等哥哥哥哥哥'); // 15 字（截图 2），第二会话内输入
  out['E2-ovf15-end'] = await M();
  await page.keyboard.press('Home');
  await page.waitForTimeout(500);
  out['E2-ovf15-start'] = await M();
  await ctx.close();
  return out;
}

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
for (const [name, base, sel, isOrig] of [
  ['RUST', RUST, '#editor-title-text', false],
  ['ORIG', ORIG, '.editor-title-input', true],
]) {
  try {
    const res = await drive(browser, base, sel, isOrig);
    console.log('=====', name, base);
    for (const [k, v] of Object.entries(res)) console.log(k.padEnd(18), JSON.stringify(v));
  } catch (e) {
    console.log('=====', name, 'FAILED', String(e).slice(0, 400));
  }
}
await browser.close();
