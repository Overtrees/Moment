// 标题胶囊几何探针（标题全面重构验收）：rAF 逐帧采样胶囊
// 宽/内距/滚动/字号 + 读应用内 titleGeom 外来变更计数
// （window.__mnTitleGeomForeign）与帧循环几何写计数
// （window.__mnTitleGeomWrites），组字序列走 CDP
// Input.imeSetComposition 跨 5/11 阈值。
// 验收口径：① 组字全程 foreign=0；② 组字期几何冻结——
// 胶囊宽恒等于聚焦落定宽、帧循环几何写零增长（场景 D）、
// Diag compupdate 的 tw 恒定，compend 后弹簧收敛（尾段极
// 差 <0.6、无飞行中跳变/回退）；③ 非 cap 态左右留白差
// ≤1px、cap 态滚动区 gutter 16/16、非 cap 收敛后
// scrollLeft=0；④ 字号会话内恒定、cap 啮合后（场景 D）
// 宽锁不退出、失焦 inline 清零且展示与基线口径一致；
// ⑤ 组字提交/Enter/点出/空回退/二次会话。
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

// ============ 场景 A：组字跨阈值（①隔离 冻结 ④字号） ============
// 冻结口径：组字全程胶囊宽恒等于聚焦落定宽（帧循环在
// Composing 不量不写）；cap 啮合与跨 cap 收敛移到 compend
// 后判定（场景 D 专测）。
await focusTitle();
await geomReset(); await geomOn(true);
const CH = '标';
await page.waitForTimeout(350); // 聚焦弹簧落定后取冻结宽
const wFrozen = await page.evaluate((s) => document.querySelector(s).closest('.editor-title-capsule').getBoundingClientRect().width, SEL);
const restW = [];
for (let n = 1; n <= 20; n++) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(110);
  if (n === 5 || n === 11) {
    restW.push(await page.evaluate((s) => {
      const cap = document.querySelector(s).closest('.editor-title-capsule');
      return { w: cap.getBoundingClientRect().width };
    }, SEL));
  }
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
// 步长/回退判据保留（防回归）：冻结段步长恒 0、compend
// 后仅小幅收敛，任何飞行中跳变（步长 >3.2 且前帧在动）
// 或文本增长期方向回退仍判失败；单步 <10px（无瞬移）。
let maxStep = 0, midFlightJumps = 0, reversals = 0;
for (let i = 1; i < A.length; i++) {
  const d = A[i].w - A[i - 1].w;
  maxStep = Math.max(maxStep, Math.abs(d));
  if (Math.abs(d) > 3.2 && Math.abs(A[i - 1].w - (A[i - 2] ? A[i - 2].w : A[i - 1].w)) > 0.5) midFlightJumps++;
  if (i >= 2 && A[i].text.length >= A[i - 1].text.length && A[i - 1].text.length >= A[i - 2].text.length && d < -0.3) reversals++;
}
check('A② 无飞行中跳变/无回退', midFlightJumps === 0 && reversals === 0 && maxStep < 10,
  `maxStep=${maxStep.toFixed(2)} midFlight=${midFlightJumps} reversals=${reversals} frames=${A.length}`);
const fsSet = [...new Set(A.map(s => s.fs))];
check('A④ 字号会话内恒定', fsSet.length === 1, 'fs=' + fsSet.join(','));
// 冻结判据：组字中段（5/11 字）宽度与聚焦落定宽一致
// （≤0.6）；组字期 scrollLeft 归平台原生（冻结口径下不
// assert 中段值），compend 收敛后非 cap 静止点必须回到
// 0（不对称内距的主源封堵，收敛面判定）。
check('A冻结 组字中段宽度=聚焦落定宽', restW.length === 2 && restW.every(r => Math.abs(r.w - wFrozen) <= 0.6),
  `wFrozen=${wFrozen.toFixed(1)} mid=${restW.map(r => r.w.toFixed(1)).join('/')}`);
check('A③ compend 后非 cap scrollLeft=0', restEnd.sl === 0, `slEnd=${restEnd.sl} wEnd=${restEnd.w.toFixed(1)}`);
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

// ============ 场景 D：组字期零几何写 + 跨 cap 组字收敛 ============
// cap 已啮合的会话内开长组字：组字全程帧循环冻结——
// __mnTitleGeomWrites 零增长（不量镜像、不写宽/内距/
// scrollLeft，tw 不被用于写）、Diag compupdate 行 tw 恒
// 定（冻结值）；compend 提交长文后帧循环恢复收敛：计数
// 增长、宽锁 184、foreign 仍 0、长文落盘。
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type(CH.repeat(28), { delay: 10 });
await page.waitForTimeout(500); // cap 啮合 + 弹簧落定（写计数稳定）
const writes0 = await page.evaluate(() => window.__mnTitleGeomWrites || 0);
const segStart = new Date();
for (let n = 1; n <= 25; n++) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(70);
}
const writesMid = await page.evaluate(() => window.__mnTitleGeomWrites || 0);
check('D 组字期几何写零增长', writesMid === writes0, `writes ${writes0}->${writesMid}`);
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
check('D 组字期 Diag compupdate tw 恒定', tws.length >= 2 && tws.every(v => v === tws[0]),
  `n=${tws.length} tw=${tws.length ? tws[0] : '-'}`);
await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 });
await page.waitForTimeout(800);
const wAfterD = await page.evaluate((s) => document.querySelector(s).closest('.editor-title-capsule').getBoundingClientRect().width, SEL);
const writesAfter = await page.evaluate(() => window.__mnTitleGeomWrites || 0);
check('D compend 后帧循环恢复（几何写增长）', writesAfter > writes0, `writes ${writes0}->${writesAfter}`);
check('D compend 后宽锁 184（cap 收敛）', Math.abs(wAfterD - 184) < 0.6, 'w=' + wAfterD.toFixed(1));
check('D 全程 foreign=0', (await foreign()) === 0, 'foreign=' + (await foreign()));
await blurTitle();
check('D 长组字提交展示截断（28+25 字）', (await titleText()) === CH.repeat(10) + '…', await titleText());

// ============ 场景 B：对称性矩阵（键入定长） ============
async function setTitleLen(n) {
  await focusTitle();
  await page.keyboard.press('Control+a');
  if (n > 0) await page.keyboard.type(CH.repeat(n), { delay: 10 });
  await page.waitForTimeout(450); // 弹簧收敛
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
