// 标题胶囊几何探针（原版闩锁机制验收）：rAF 逐帧采样胶
// 囊宽/内距/滚动/字号 + 读应用内 titleGeom 外来变更计数
// （window.__mnTitleGeomForeign），组字序列走 CDP
// Input.imeSetComposition 跨 5/11 阈值。
// 验收口径（2026-11-23 按原版机制改判据，变更清单见提
// 交信息）：① 组字全程 foreign=0；② 组字期布局跟随实
// 时全文——非 overflow 时胶囊宽 = max(在场全文宽, meta
// 宽) + 左右内距（±2.5）、scrollLeft=0；字号闩锁随实
// 时长度单向切换（≤5 字 14px、>5 字 11px、会话内不回
// 退）；增长期（字号未变时）宽不回退、单帧步长 <30
// （含 12 字 overflow 闩锁翻转到 184 的一步）；overflow
// 后宽恒 184、Diag compupdate 的 tw 随组字串增长（不
// 再恒定）；③ 非 cap 态左右留白差 ≤1px、cap 态滚动区
// gutter 16/16、compend 收敛后 scrollLeft 回到边距规则
// 终点；④ compend 后 sl 不塌陷（无旧帧循环的归零写
// 者）、长标题聚焦逐帧宽 ≤184（无弹簧超调）、失焦
// inline 清零且展示与基线口径一致；⑤ 组字提交/Enter/
// 点出/空回退/二次会话。
// 用法: node probe_title_geom.mjs [baseURL]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8096/';
const SEL = '#editor-title-text';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 200)));
const cdp = await ctx.newCDPSession(page);

let fails = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' :: ' + detail : ''}`);
  if (!ok) fails++;
};

// 采样器：rAF 逐帧记录胶囊几何（宽/计算内距/滚动区
// scrollLeft/输入字号/文本），window.__geomOn 开关。
await page.addInitScript(() => {
  window.__geom = [];
  window.__geomOn = false;
  const loop = () => {
    requestAnimationFrame(loop);
    if (!window.__geomOn) return;
    const el = document.querySelector('#editor-title-text');
    if (!el) return;
    const cap = el.closest('.editor-title-capsule');
    const scr = el.parentElement;
    const cs = getComputedStyle(cap);
    const r = cap.getBoundingClientRect();
    let textL = -1, textR = -1;
    try {
      const rg = document.createRange();
      rg.selectNodeContents(el);
      const rr = rg.getBoundingClientRect();
      textL = rr.left - r.left; textR = r.right - rr.right;
    } catch (e) { /* 空态无矩形 */ }
    window.__geom.push({
      t: Math.round(performance.now()),
      w: +r.width.toFixed(2),
      padL: parseFloat(cs.paddingLeft), padR: parseFloat(cs.paddingRight),
      sl: scr.scrollLeft, fs: parseFloat(getComputedStyle(el).fontSize),
      scrPadL: parseFloat(getComputedStyle(scr).paddingLeft),
      scrPadR: parseFloat(getComputedStyle(scr).paddingRight),
      text: el.textContent, textL: +textL.toFixed(2), textR: +textR.toFixed(2),
    });
  };
  requestAnimationFrame(loop);
});

const geom = () => page.evaluate(() => window.__geom);
const geomReset = () => page.evaluate(() => { window.__geom = []; });
const geomOn = (on) => page.evaluate((v) => { window.__geomOn = v; }, on);
const foreign = () => page.evaluate(() => window.__mnTitleGeomForeign || 0);
const titleText = () => page.evaluate((s) => document.querySelector(s).textContent, SEL);
const titleStyle = () => page.evaluate((s) => {
  const el = document.querySelector(s);
  const cap = el.closest('.editor-title-capsule');
  return { input: el.getAttribute('style'), cap: cap.getAttribute('style') };
}, SEL);

async function focusTitle() {
  const box = await page.locator(SEL).boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(120);
}
async function blurTitle() {
  await page.mouse.click(200, 700); // 点正文区失焦
  await page.waitForTimeout(250);
}

// ---- 导航：新建备忘（空标题） ----
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.new-card-title');
await page.waitForSelector(SEL, { timeout: 10000 });
await page.waitForTimeout(500);

// ============ 场景 A：组字跨阈值（①隔离 跟随 闩锁） ============
// 跟随口径：组字期布局按含组字串的实时全文定尺寸——
// 点采样断言胶囊宽由在场内容驱动且 sl=0；n=20
// （overflow 已闩锁）断言宽 184、字号 11。注意 CDP
// imeSetComposition 在本机 Chromium 有 +1 伪影（首个
// 组字字被落为普通文本，DOM 实时长 = 调用参数 +1，
// 诊断脚本实测），故跟随断言一律以采样到的 DOM 实时
// 长为准：取 n=5（实时 6）与 n=10（实时 11）两个仍在
// 非 overflow 区的点，n=11 起实时长 12 已合法闩锁。
const snapA = () => page.evaluate((s) => {
  const el = document.querySelector(s);
  const cap = el.closest('.editor-title-capsule');
  const scr = el.parentElement;
  const cs = getComputedStyle(cap);
  const rg = document.createRange(); rg.selectNodeContents(el);
  const tw = rg.getBoundingClientRect().width;
  const meta = cap.querySelector('.editor-title-meta');
  const rgm = document.createRange(); rgm.selectNodeContents(meta);
  const metaW = rgm.getBoundingClientRect().width;
  return {
    w: cap.getBoundingClientRect().width, tw, metaW,
    domLen: el.textContent.length,
    padL: parseFloat(cs.paddingLeft), padR: parseFloat(cs.paddingRight),
    sl: scr.scrollLeft, fs: parseFloat(getComputedStyle(el).fontSize),
  };
}, SEL);
await focusTitle();
await geomReset(); await geomOn(true);
const CH = '标';
await page.waitForTimeout(350); // 聚焦布局落定
const restW = {};
for (let n = 1; n <= 20; n++) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(110);
  if (n === 5 || n === 10 || n === 20) restW[n] = await snapA();
}
for (let n = 19; n >= 1; n--) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(60);
}
// 组字以空串收尾（compositionend 落定），帧循环恢复收敛
await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 });
await page.waitForTimeout(750);
const restEnd = await page.evaluate((s) => {
  const scr = document.querySelector(s).parentElement;
  return { sl: scr.scrollLeft, w: scr.parentElement.getBoundingClientRect().width };
}, SEL);
await geomOn(false);
const A = await geom();
check('A① 组字跨 5/11 阈值全程 foreign=0', (await foreign()) === 0, 'foreign=' + (await foreign()));
// 跟随判据：非 overflow 的组字中段（DOM 实时长 ≤11），
// 胶囊宽必须由在场内容驱动——等于 max(在场全文宽,
// meta 宽) + 左右内距（±2.5 含边框/取整），且横滚未
// 启动 sl=0。这是「组字串不被塞进按已提交文本定宽的
// 窄胶囊」的直接断言（冻结版在此处 cw 恒为聚焦宽、sl
// 随串长暴涨）。实时长前置条件一并断言（>11 时 184 是
// 合法闩锁结果，不在此判）。
for (const n of [5, 10]) {
  const r = restW[n];
  const expect = Math.max(r.tw, r.metaW) + r.padL + r.padR;
  check(`A跟随 组字中段(实时${r.domLen}字)宽随实时全文且 sl=0`,
    r.domLen <= 11 && Math.abs(r.w - expect) <= 2.5 && r.sl === 0,
    `w=${r.w.toFixed(1)} expect=${expect.toFixed(1)} tw=${r.tw.toFixed(1)} metaW=${r.metaW.toFixed(1)} domLen=${r.domLen} sl=${r.sl}`);
}
// overflow 闩锁（>11）后：20 字组字中胶囊恒 184、字号 11。
check('A闩锁 组字 20 字宽锁 184 且字号 11',
  Math.abs(restW[20].w - 184) <= 0.6 && restW[20].fs === 11,
  `w=${restW[20].w.toFixed(1)} fs=${restW[20].fs}`);
// 字号闩锁：随实时长度单向切换——首次出现 11 后会话内
// 不回 14（原版快照只升不降），且切换前为 14。
{
  const seq = A.map(s => s.fs);
  const first11 = seq.indexOf(11);
  const okLatch = first11 > 0 && seq.slice(0, first11).every(v => v === 14) && seq.slice(first11).every(v => v === 11);
  check('A闩锁 字号随实时长度单向切换 14→11', okLatch, 'fsSeq=' + [...new Set(seq)].join(','));
}
// 增长期单调性：文本长度非递减趋势内、字号未变的帧，
// 宽回退 >0.6 判失败（字号闩锁翻转帧的总宽台阶属原版
// 行为，豁免）；单帧步长 <30（12 字 overflow 翻转到
// 184 的一步约 +27，是全程最大合法步长）。
let maxStep = 0, reversals = 0;
for (let i = 1; i < A.length; i++) {
  const d = A[i].w - A[i - 1].w;
  maxStep = Math.max(maxStep, Math.abs(d));
  if (i >= 2 && A[i].text.length >= A[i - 1].text.length && A[i - 1].text.length >= A[i - 2].text.length
    && A[i].fs === A[i - 1].fs && d < -0.6) reversals++;
}
check('A② 增长期无回退且步长有界', reversals === 0 && maxStep < 30,
  `maxStep=${maxStep.toFixed(2)} reversals=${reversals} frames=${A.length}`);
// compend 后：提交短文、光标在文首侧，边距规则把 sl 收
// 敛回 0（终点判定，不再依赖帧循环强制归零）。
check('A③ compend 后 scrollLeft=0', restEnd.sl === 0, `slEnd=${restEnd.sl} wEnd=${restEnd.w.toFixed(1)}`);
// 收敛：末段样本宽度极差 <0.6
const tail = A.slice(-8);
const tailRange = Math.max(...tail.map(s => s.w)) - Math.min(...tail.map(s => s.w));
check('A② compend 后收敛（尾段极差<0.6px）', tailRange < 0.6, 'tailRange=' + tailRange.toFixed(2) + ' endW=' + tail[tail.length - 1].w);

// 组字残留（末字「标」）经失焦提交；再开会话全选替换提交
await blurTitle();
check('A⑤ 组字残留失焦提交', (await titleText()) === '标', await titleText());
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type('标题几何验收', { delay: 10 });
await page.waitForTimeout(200);
await blurTitle();
check('A⑤ 再会话提交后展示=全文', (await titleText()) === '标题几何验收', await titleText());

// ============ 场景 D：overflow 会话内长组字 + compend 后 sl 稳定 ============
// 已提交 28 字（聚焦即 overflow 闩锁）后再开 25 字组
// 字：组字全程胶囊恒 184（闩锁后组字不改宽）、Diag
// compupdate 的 tw 随组字串实时增长（新机制的地面真
// 值，不再是冻结恒定值）；compend 提交 53 字后光标在
// 文末，边距规则下 sl 应稳定在高位——采样断言不塌陷
// （旧帧循环曾在此处写出 412→3→412 的归零跳变）。
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type(CH.repeat(28), { delay: 10 });
await page.waitForTimeout(500); // 闩锁与 caret 同步落定
const segStart = new Date();
const wMidD = [];
for (let n = 1; n <= 25; n++) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(70);
  if (n === 5 || n === 15 || n === 25) {
    wMidD.push(await page.evaluate((s) => document.querySelector(s).closest('.editor-title-capsule').getBoundingClientRect().width, SEL));
  }
}
check('D 组字期宽恒 184（overflow 闩锁后组字不改宽）',
  wMidD.length === 3 && wMidD.every(w => Math.abs(w - 184) < 0.6),
  'w=' + wMidD.map(w => w.toFixed(1)).join('/'));
const tws = await page.evaluate((hhmmss) => {
  let lines = [];
  try { lines = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { lines = []; }
  const out = [];
  for (const l of lines) {
    const m = l.match(/^\[(\d{2}:\d{2}:\d{2})\].*titleGeom ph=compupdate .* tw=([\d.]+)/);
    if (m && m[1] > hhmmss) out.push(parseFloat(m[2]));
  }
  return out;
}, segStart.toTimeString().slice(0, 8));
check('D 组字期 Diag compupdate tw 随组字串增长', tws.length >= 2 && tws[tws.length - 1] > tws[0],
  `n=${tws.length} tw ${tws.length ? tws[0] : '-'}->${tws.length ? tws[tws.length - 1] : '-'}`);
await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 });
const slPostD = [];
for (let i = 0; i < 8; i++) {
  await page.waitForTimeout(80);
  slPostD.push(await page.evaluate((s) => document.querySelector(s).parentElement.scrollLeft, SEL));
}
// 不塌陷的判据 = 终点稳定 + 光标恰在边距内：CDP 结束
// 组字后光标停在组字起始位（环境口径，非真机候选词上
// 屏口径），绝对 sl 随光标位而定、不设下限；断言 8 次
// 采样极差 ≤1（无 412→3→412 式归零跳变、无漂移）且
// 光标视口 x 恰在滚动区左右 16 边距内（边距规则终点）。
const caretD = await page.evaluate((s) => {
  const el = document.querySelector(s);
  const scr = el.parentElement;
  const rect = scr.getBoundingClientRect();
  const sel = window.getSelection();
  if (!sel || !sel.rangeCount) return { cx: null, rectW: rect.width };
  const fn = sel.focusNode, fo = sel.focusOffset;
  let tn = null, off = 0;
  const find = (n, fromEnd) => {
    if (!n) return null;
    if (n.nodeType === 3) return n.textContent.length ? n : null;
    const kids = [...n.childNodes]; if (fromEnd) kids.reverse();
    for (const k of kids) { const f = find(k, fromEnd); if (f) return f; }
    return null;
  };
  if (fn.nodeType === 3) { tn = fn; off = fo; }
  else if (fn.nodeType === 1) {
    const atEnd = fo > 0;
    tn = find(fn.childNodes[atEnd ? fo - 1 : fo], atEnd);
    if (tn) off = atEnd ? tn.textContent.length : 0;
  }
  if (!tn || !tn.textContent.length) return { cx: null, rectW: rect.width };
  off = Math.min(off, tn.textContent.length);
  const from = off > 0 ? off - 1 : 0, to = off > 0 ? off : Math.min(1, tn.textContent.length);
  const rg = document.createRange(); rg.setStart(tn, from); rg.setEnd(tn, to);
  const gr = rg.getBoundingClientRect();
  if (!gr.height) return { cx: null, rectW: rect.width };
  return { cx: (off > 0 ? gr.right : gr.left) - rect.left, rectW: rect.width };
}, SEL);
check('D compend 后 sl 不塌陷（边距规则终点稳定）',
  Math.max(...slPostD) - Math.min(...slPostD) <= 1 && caretD.cx !== null
    && caretD.cx >= 16 - 1.5 && caretD.cx <= caretD.rectW - 16 + 1.5,
  `sl=${slPostD.map(v => Math.round(v)).join('/')} caretRel=${caretD.cx === null ? 'null' : caretD.cx.toFixed(1)}/${caretD.rectW.toFixed(0)}`);
const wAfterD = await page.evaluate((s) => document.querySelector(s).closest('.editor-title-capsule').getBoundingClientRect().width, SEL);
check('D compend 后宽锁 184（cap 收敛）', Math.abs(wAfterD - 184) < 0.6, 'w=' + wAfterD.toFixed(1));
check('D 全程 foreign=0', (await foreign()) === 0, 'foreign=' + (await foreign()));
await blurTitle();
check('D 长组字提交展示截断（28+25 字）', (await titleText()) === CH.repeat(10) + '…', await titleText());

// ============ 场景 B：对称性矩阵（键入定长） ============
async function setTitleLen(n) {
  await focusTitle();
  await page.keyboard.press('Control+a');
  if (n > 0) await page.keyboard.type(CH.repeat(n), { delay: 10 });
  await page.waitForTimeout(450); // 布局与 caret 同步落定
}
// 入口状态复位：场景 D 留下 53 字标题，B 的矩阵以短标题
// 为入口前提（与场景 A 结束态口径一致），先整表替换回
// 短标题再逐档测。
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type('标题几何验收', { delay: 10 });
await page.waitForTimeout(200);
await blurTitle();
for (const n of [0, 3, 6, 11, 17, 28]) {
  await setTitleLen(n);
  const m = await page.evaluate((s) => {
    const el = document.querySelector(s);
    const cap = el.closest('.editor-title-capsule');
    const scr = el.parentElement;
    const r = cap.getBoundingClientRect();
    const rg = document.createRange(); rg.selectNodeContents(el);
    const rr = rg.getBoundingClientRect();
    const scs = getComputedStyle(scr);
    return {
      w: r.width, sl: scr.scrollLeft,
      textL: rr.left - r.left, textR: r.right - rr.right,
      scrPadL: parseFloat(scs.paddingLeft), scrPadR: parseFloat(scs.paddingRight),
      fs: parseFloat(getComputedStyle(el).fontSize),
    };
  }, SEL);
  if (n === 0) {
    // 空态无文本矩形可量：对称由计算内距单值构造保证，
    // 查胶囊 computed padding 左右相等 + scrollLeft=0。
    const pads = await page.evaluate((s) => {
      const cap = document.querySelector(s).closest('.editor-title-capsule');
      const cs = getComputedStyle(cap);
      return [cs.paddingLeft, cs.paddingRight];
    }, SEL);
    check('B③ len=0 空态内距左右相等', pads[0] === pads[1], `pads=${pads.join('/')}`);
    check('B③ len=0 非 cap scrollLeft=0', m.sl === 0, 'sl=' + m.sl);
  } else if (m.w < 183.5) {
    check(`B③ len=${n} 非 cap 左右差≤1px`, Math.abs(m.textL - m.textR) <= 1.0,
      `L=${m.textL.toFixed(1)} R=${m.textR.toFixed(1)} w=${m.w.toFixed(1)} sl=${m.sl}`);
    check(`B③ len=${n} 非 cap scrollLeft=0`, m.sl === 0, 'sl=' + m.sl);
  } else {
    check(`B③ len=${n} cap gutter 16/16`, m.scrPadL === 16 && m.scrPadR === 16,
      `scrPad=${m.scrPadL}/${m.scrPadR} w=${m.w.toFixed(1)}`);
  }
  await blurTitle();
}

// ============ 场景 C：提交完整性 ============
// Enter 提交
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type('回车提交标题', { delay: 10 });
await page.keyboard.press('Enter');
await page.waitForTimeout(250);
check('C⑤ Enter 提交展示', (await titleText()) === '回车提交标题', await titleText());
// 空回退无标题
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.press('Backspace');
await blurTitle();
check('C⑤ 空标题失焦回退「无标题」', (await titleText()) === '无标题', await titleText());
// 长标题展示截断基线（>10 字 → 前 10 + …）+ 失焦 inline 清零
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type('一二三四五六七八九十甲乙丙丁戊', { delay: 5 });
await blurTitle();
check('C④ 长标题展示截断口径', (await titleText()) === '一二三四五六七八九十…', await titleText());
const st = await titleStyle();
check('C④ 失焦后胶囊无会话 inline width', !st.cap || !/width/.test(st.cap), 'capStyle=' + st.cap);
// 聚焦超调：15 字长标题（聚焦即 overflow 闩锁）逐帧采
// 样——新机制聚焦首帧即闩锁定宽，任何一帧不得超过
// 184（旧弹簧曾以展示涌现宽为起点冲到 269 再回落）。
await geomReset(); await geomOn(true);
await focusTitle();
await page.waitForTimeout(500);
await geomOn(false);
{
  const F = await geom();
  const maxW = Math.max(...F.map(s => s.w));
  const endW = F[F.length - 1].w;
  check('C聚焦 长标题聚焦逐帧宽不超 184 且终点锁 184',
    maxW <= 184.6 && Math.abs(endW - 184) < 0.6,
    `maxW=${maxW.toFixed(1)} endW=${endW.toFixed(1)} frames=${F.length}`);
}
await blurTitle();
// 二次会话无残留：再聚焦，foreign 仍 0，会话可正常提交
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type('二次会话', { delay: 10 });
await blurTitle();
check('C⑤ 二次会话提交正常', (await titleText()) === '二次会话', await titleText());
check('C① 全程 foreign=0', (await foreign()) === 0, 'foreign=' + (await foreign()));

console.log(fails === 0 ? 'PROBE TITLE GEOM ALL PASS' : `PROBE TITLE GEOM ${fails} FAILURES`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
