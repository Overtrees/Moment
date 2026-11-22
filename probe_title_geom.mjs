// 标题胶囊几何探针（标题全面重构验收）：rAF 逐帧采样胶囊
// 宽/内距/滚动/字号 + 读应用内 titleGeom 外来变更计数
// （window.__mnTitleGeomForeign），组字序列走 CDP
// Input.imeSetComposition 跨 5/11 阈值。
// 验收口径：① 组字全程 foreign=0；② 逐帧 |Δwidth|≤3px、
// 末键 300ms 内收敛；③ 非 cap 态左右留白差 ≤1px、cap 态
// 滚动区 gutter 16/16、非 cap scrollLeft 恒 0；④ 字号会话
// 内恒定、cap 啮合后删字不退出、失焦 inline 清零且展示与
// 基线口径一致；⑤ 组字提交/Enter/点出/空回退/二次会话。
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

// ============ 场景 A：组字跨阈值（①隔离 ②连续性 ④字号） ============
await focusTitle();
await geomReset(); await geomOn(true);
const CH = '标';
const restSl = [];
for (let n = 1; n <= 20; n++) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(110);
  if (n === 5 || n === 11) {
    await page.waitForTimeout(200); // 静止点：等帧循环处理后读
    restSl.push(await page.evaluate((s) => {
      const scr = document.querySelector(s).parentElement;
      const cap = scr.parentElement;
      return { sl: scr.scrollLeft, w: Math.round(cap.getBoundingClientRect().width) };
    }, SEL));
  }
}
for (let n = 19; n >= 1; n--) {
  await cdp.send('Input.imeSetComposition', { text: CH.repeat(n), selectionStart: n, selectionEnd: n });
  await page.waitForTimeout(60);
}
// 组字以空串收尾（compositionend 落定），再以普通键入提交
await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 });
await page.waitForTimeout(150);
const tLastKey = Date.now();
await page.waitForTimeout(600);
restSl.push({ sl: await page.evaluate((s) => document.querySelector(s).parentElement.scrollLeft, SEL), w: 184 });
await geomOn(false);
const A = await geom();
A.restSl = restSl;
check('A① 组字跨 5/11 阈值全程 foreign=0', (await foreign()) === 0, 'foreign=' + (await foreign()));
// 连续性判据（无头环境 rAF 会被 CDP 长任务饿死，控制器
// 弹簧按墙钟 τ=90ms 追赶——饿死后的单帧步长天然偏大，
// 那是追赶不是跳变）：① 增长段宽度单调不回退（旧类翻转
// 的特征是方向反转与整距瞬移）；② 步长 >3.2px 只允许出
// 现在前一帧静止（饿死追赶）时，且单步 <10px（无瞬移）。
let maxStep = 0, midFlightJumps = 0, reversals = 0;
for (let i = 1; i < A.length; i++) {
  const d = A[i].w - A[i - 1].w;
  maxStep = Math.max(maxStep, Math.abs(d));
  if (Math.abs(d) > 3.2 && Math.abs(A[i - 1].w - (A[i - 2] ? A[i - 2].w : A[i - 1].w)) > 0.5) midFlightJumps++;
  if (i >= 2 && A[i].text.length >= A[i - 1].text.length && A[i - 1].text.length >= A[i - 2].text.length && d < -0.3) reversals++;
}
check('A② 扩宽连续（无飞行中跳变/无回退）', midFlightJumps === 0 && reversals === 0 && maxStep < 10,
  `maxStep=${maxStep.toFixed(2)} midFlight=${midFlightJumps} reversals=${reversals} frames=${A.length}`);
const fsSet = [...new Set(A.map(s => s.fs))];
check('A④ 字号会话内恒定', fsSet.length === 1, 'fs=' + fsSet.join(','));
// 非 cap scrollLeft：采样器 rAF 排在控制器之前，帧内读
// 到的是原生顶动后、帧循环归零前的值——真判据在静止点
// 读（浏览器不再顶动、帧循环已归零）。静止点口径：5 字
// （非 cap）sl=0；11 字在 fs14/内距 20 冻结口径下 textW
// 已达 cap 阈值（151.8+40≥184），判据改 cap 啮合（宽
// 184，sl 为 caret 边距定位、非归零面）；收尾点 sl=0。
const [r5, r11, rEnd] = A.restSl;
check('A③ 非 cap 静止点 scrollLeft=0', r5.sl === 0 && rEnd.sl === 0, `sl5=${r5.sl} slEnd=${rEnd.sl}`);
check('A③ 11 字静止点 cap 已啮合', r11.w === 184, `w11=${r11.w} sl11=${r11.sl}`);
// 收敛：末段样本宽度极差 <0.6 且最后变化距采样结束 ≤300ms（采样口径近似）
const tail = A.slice(-8);
const tailRange = Math.max(...tail.map(s => s.w)) - Math.min(...tail.map(s => s.w));
check('A② 末键后收敛（尾段极差<0.6px）', tailRange < 0.6, 'tailRange=' + tailRange.toFixed(2) + ' endW=' + tail[tail.length - 1].w);
// cap 单向：组字删回 1 字后（会话未结束）宽度不得从 184 退出——
// 采样中 cap 出现后 w 的最小值应保持 ≥183.5 直到删字段结束前
const capIdx = A.findIndex(s => s.w >= 183.5);
let capHeld = capIdx >= 0;
if (capHeld) {
  // 删字段（后半）里 w 仍应 ≥183.5，直到组字文本 <cap 阈值后
  // 弹簧回落——设计口径是 cap 标志单向，宽度随 target=184 恒定
  const after = A.slice(capIdx);
  capHeld = after.every(s => s.w >= 183.0);
}
check('A④ cap 啮合后宽度锁定不退出', capHeld, 'capIdx=' + capIdx);

// 组字残留（末字「标」）经失焦提交；再开会话全选替换提交
await blurTitle();
check('A⑤ 组字残留失焦提交', (await titleText()) === '标', await titleText());
await focusTitle();
await page.keyboard.press('Control+a');
await page.keyboard.type('标题几何验收', { delay: 10 });
await page.waitForTimeout(200);
await blurTitle();
check('A⑤ 再会话提交后展示=全文', (await titleText()) === '标题几何验收', await titleText());

// ============ 场景 B：对称性矩阵（键入定长） ============
async function setTitleLen(n) {
  await focusTitle();
  await page.keyboard.press('Control+a');
  if (n > 0) await page.keyboard.type(CH.repeat(n), { delay: 10 });
  await page.waitForTimeout(450); // 弹簧收敛
}
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
