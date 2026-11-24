// 标题胶囊几何探针（用户口径重构验收：原生 input + 单源
// 对称内距 + 镜像实测弹性定宽）：结构断言 + 对称矩阵 +
// 逐字增长/transition 中间帧 + 钳制 + CDP 组字跟随 +
// 提交完整性（Enter/Esc 还原/点按落点/scrollLeft 零写入/
// foreign=0）。
// 验收口径（2026-11-23 按新规格重写判据，变更清单见提
// 交信息）：旧判据围绕 contenteditable + scroller + 原
// 版闩锁（is_long/is_overflow/184 定宽/gutter 16/字号
// 11↔14 翻转/聚焦不超 cap/失焦 inline 清零）——新机制
// 下这些对象全部不存在，判据整体作废。新判据：① 结构
// ——标题元素为 <input type="text">、无 scroller、胶囊
// inline 无 padding（内距只来自类规则单值）、我方
// scrollLeft 写入计数（原型 setter 仪表化）全程为 0；
// ② 对称——多长度下输入态与回车后展示态左右留白差
// ≤1px（探针以自身镜像独立量全文宽合成左右留白，不读
// 控制器镜像）；③ 增长——逐字输入胶囊宽单调不回退、
// 单步增量 ≤ 一个字宽+3、transition 中间帧存在（采样
// 宽严格介于前后之间）；④ 钳制——40 字时胶囊宽 = 坞
// 内可用宽（±2）、光标仍在文末；⑤ 组字——CDP 组字全
// 程胶囊宽跟随含组字串的实时全文（探针按组字区间拼
// 接独立计算期望宽，±2.5）、compend 落定值与宽正确；
// ⑥ 提交——Enter 落定、Esc 还原（值回展示态且无新
// commit 行）、长标题点按落点映射（前缀内同位/省略号
// 落文末）、foreign=0、Diag focus 行 fs=14；⑦ 焦点框
// ——聚焦态标题 input 的 computed outline-style=none
// 且 box-shadow=none（共享 :focus-visible 蓝环不得命
// 中标题 input，真机蓝色方形框的回归守卫）。
// 用法: node probe_title_geom.mjs [baseURL]
import { chromium } from 'playwright-core';

const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = process.argv[2] || 'http://localhost:8096/';

let pass = 0, fail = 0;
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ok', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}
const approx = (a, b, tol) => Math.abs(a - b) <= tol;

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 393, height: 852 }, hasTouch: true });
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

// —— 探针侧独立量测：自建镜像（字体取自 input 计算样式） ——
async function probeTw(text) {
  return page.evaluate((t) => {
    let m = document.getElementById('__probe_mirror');
    if (!m) {
      m = document.createElement('span');
      m.id = '__probe_mirror';
      const inp = document.querySelector('#editor-title-text');
      const cs = getComputedStyle(inp);
      m.style.cssText = 'position:fixed;left:-9999px;top:0;visibility:hidden;white-space:nowrap;pointer-events:none;'
        + `font-family:${cs.fontFamily};font-size:${cs.fontSize};font-weight:${cs.fontWeight};letter-spacing:${cs.letterSpacing};`;
      document.body.appendChild(m);
    }
    m.textContent = t;
    return m.getBoundingClientRect().width;
  }, text);
}
async function metaW() {
  return page.evaluate(() => {
    const meta = document.querySelector('.editor-title-meta');
    if (!meta || getComputedStyle(meta).display === 'none') return 0;
    const r = document.createRange();
    r.selectNodeContents(meta);
    return r.getBoundingClientRect().width;
  });
}
// 几何快照：cw/左右留白（以探针镜像的全文宽合成）/字号/内距/选区
async function geom() {
  const g = await page.evaluate(() => {
    const inp = document.querySelector('#editor-title-text');
    const cap = document.querySelector('.editor-title-capsule');
    const cs = getComputedStyle(cap);
    const ics = getComputedStyle(inp);
    const cr = cap.getBoundingClientRect();
    const ir = inp.getBoundingClientRect();
    return {
      v: inp.value,
      cw: cr.width,
      irw: ir.width, irLeft: ir.left, irRight: ir.right,
      contentL: cr.left + parseFloat(cs.borderLeftWidth) + parseFloat(cs.paddingLeft),
      contentR: cr.right - parseFloat(cs.borderRightWidth) - parseFloat(cs.paddingRight),
      padL: parseFloat(cs.paddingLeft),
      padR: parseFloat(cs.paddingRight),
      fs: ics.fontSize,
      sel: inp.selectionStart,
      sl: inp.scrollLeft,
      active: document.activeElement === inp,
    };
  });
  const tw = await probeTw(g.v);
  const slack = Math.max(0, g.irw - tw) / 2;
  g.tw = tw;
  g.gapL = (g.irLeft - g.contentL) + slack;
  g.gapR = (g.contentR - g.irRight) + slack;
  g.wsd = g.gapL - g.gapR;
  return g;
}
async function settleCw() {
  let last = -1, stable = 0;
  for (let i = 0; i < 40; i++) {
    const cw = await page.evaluate(() => document.querySelector('.editor-title-capsule').getBoundingClientRect().width);
    if (Math.abs(cw - last) < 0.05) { stable++; if (stable >= 3) return cw; }
    else stable = 0;
    last = cw;
    await page.waitForTimeout(60);
  }
  return last;
}
async function availW() {
  return page.evaluate(() => {
    const dock = document.querySelector('.editor-title-dock');
    let a = dock.clientWidth;
    if (getComputedStyle(dock).flexDirection === 'row') {
      const av = dock.querySelector('.editor-avatar-button');
      if (av) a -= av.getBoundingClientRect().width + 8;
    }
    return a;
  });
}
async function diagRows() {
  return page.evaluate(() => {
    try {
      const arr = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
      return arr.map((x) => x.line || String(x)).filter((l) => l.includes('titleGeom'));
    } catch { return []; }
  });
}
// Diag 落盘为 1s 节流合并写（批10 T-F）：动作后直接读会落在
// 节流窗内假红/假过。正向断言改轮询等目标行落盘（200ms 步
// 进、上限约 6s）后仍按原判据断言；计数不变类断言先等落盘
// 静默（连续两次读间隔 ≥1.2s 内容不变）再读。只改读取时序。
const diagRawText = () => page.evaluate(() => { try { return localStorage.getItem('mynote_diag_v1') || ''; } catch { return ''; } });
async function waitDiagRows(pred, timeoutMs = 6000) {
  const t0 = Date.now();
  let rows = await diagRows();
  while (!pred(rows) && Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(200);
    rows = await diagRows();
  }
  return rows;
}
async function waitDiagSettle(timeoutMs = 6000) {
  const t0 = Date.now();
  let prev = await diagRawText();
  while (Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(1200);
    const cur = await diagRawText();
    if (cur === prev) return;
    prev = cur;
  }
}
const parseRow = (line) => {
  const o = {};
  for (const m of line.matchAll(/(\w+)=([-\d.]+)/g)) o[m[1]] = parseFloat(m[2]);
  const ph = /ph=(\w+)/.exec(line);
  o.ph = ph ? ph[1] : '';
  return o;
};

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.new-card-title', { timeout: 15000 });
await page.click('.new-card-title');
await page.waitForSelector('#editor-title-text', { timeout: 8000 });
await page.waitForTimeout(900);

console.log('S0 结构');
{
  const s = await page.evaluate(() => {
    const inp = document.querySelector('#editor-title-text');
    const cap = document.querySelector('.editor-title-capsule');
    return {
      tag: inp.tagName, type: inp.getAttribute('type'),
      scroller: !!document.querySelector('.editor-title-scroller'),
      styleAttr: cap.getAttribute('style') || '',
      fs: getComputedStyle(inp).fontSize,
    };
  });
  ok('title element is <input type=text>', s.tag === 'INPUT' && s.type === 'text', JSON.stringify(s));
  ok('no scroller element', !s.scroller);
  ok('capsule inline style carries no padding (single-source class padding)', !/padding/.test(s.styleAttr), s.styleAttr);
  ok('display font-size is 14px', s.fs === '14px', s.fs);
  // scrollLeft 写入仪表化：原型 setter 计数（目标=标题 input）
  await page.evaluate(() => {
    window.__slWrites = 0;
    const proto = Object.getPrototypeOf(document.querySelector('#editor-title-text'));
    const desc = Object.getOwnPropertyDescriptor(proto, 'scrollLeft')
      || Object.getOwnPropertyDescriptor(Object.getPrototypeOf(proto), 'scrollLeft');
    if (desc && desc.set) {
      Object.defineProperty(proto, 'scrollLeft', {
        configurable: true, enumerable: desc.enumerable, get: desc.get,
        set(v) { if (this.id === 'editor-title-text') window.__slWrites++; return desc.set.call(this, v); },
      });
    }
  });
}

async function focusTitle() {
  await page.click('#editor-title-text');
  await page.waitForTimeout(250);
}
async function selectAllType(text) {
  await page.keyboard.press('Control+a');
  await page.keyboard.type(text);
  await page.waitForTimeout(120);
}

console.log('S0b 焦点框接管（聚焦态无 outline/box-shadow 框）');
{
  await focusTitle();
  const f = await page.evaluate(() => {
    const inp = document.querySelector('#editor-title-text');
    const cs = getComputedStyle(inp);
    return {
      active: document.activeElement === inp,
      fv: inp.matches(':focus-visible'),
      outlineStyle: cs.outlineStyle,
      outlineWidth: cs.outlineWidth,
      boxShadow: cs.boxShadow,
    };
  });
  ok('title input focused for frame check', f.active, JSON.stringify(f));
  ok('focused title input outline is none', f.outlineStyle === 'none' || parseFloat(f.outlineWidth) === 0, JSON.stringify(f));
  ok('focused title input has no box-shadow frame', f.boxShadow === 'none', f.boxShadow);
  await page.evaluate(() => document.querySelector('#editor-title-text').blur());
  await page.waitForTimeout(150);
}

console.log('S1 对称矩阵（输入态 + 回车展示态）');
for (const s of ['标', '标题胶囊', '标题胶囊测试文', '一二三四五六七八九十']) {
  await focusTitle();
  await selectAllType(s);
  await settleCw();
  const g = await geom();
  ok(`edit symmetry len=${s.length}`, Math.abs(g.wsd) <= 1, `wsd=${g.wsd.toFixed(2)} cw=${g.cw.toFixed(1)} tw=${g.tw.toFixed(1)}`);
  ok(`edit width formula len=${s.length}`, approx(g.cw, Math.max(g.tw, await metaW()) + g.padL + g.padR + 1, 2), `cw=${g.cw.toFixed(1)} tw=${g.tw.toFixed(1)}`);
  ok(`edit fs 14 + padding single value len=${s.length}`, g.fs === '14px' && g.padL === 20 && g.padR === 20, `fs=${g.fs} pad=${g.padL}/${g.padR}`);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  await settleCw();
  const d = await geom();
  ok(`display value len=${s.length}`, d.v === s, d.v);
  ok(`display symmetry len=${s.length}`, Math.abs(d.wsd) <= 1, `wsd=${d.wsd.toFixed(2)}`);
  ok(`display blurred len=${s.length}`, !d.active);
}

console.log('S2 逐字增长弹性');
{
  await focusTitle();
  await page.keyboard.press('Control+a');
  await page.keyboard.press('Backspace');
  await settleCw();
  const chars = ['一', '二', '三', '四', '五', '六', '七', '八'];
  const charW = await probeTw('一');
  let prev = (await geom()).cw;
  let monotonic = true, stepOk = true, sampledMid = false;
  for (let i = 0; i < chars.length; i++) {
    const before = await geom();
    // 在文本宽已越过 meta 主导区时，对这一字做 transition 中间帧采样
    const doSample = !sampledMid && before.tw > (await metaW()) - 2;
    if (doSample) {
      await page.evaluate(() => {
        window.__cwSamples = [];
        const cap = document.querySelector('.editor-title-capsule');
        const t0 = performance.now();
        const tick = () => {
          window.__cwSamples.push(cap.getBoundingClientRect().width);
          if (performance.now() - t0 < 330) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
    }
    await page.keyboard.type(chars[i]);
    const cw = await settleCw();
    if (cw < prev - 0.05) monotonic = false;
    const delta = cw - prev;
    if (delta > charW + 3) stepOk = false;
    if (doSample) {
      const samples = await page.evaluate(() => window.__cwSamples || []);
      const mid = samples.filter((w) => w > prev + 0.5 && w < cw - 0.5);
      if (cw - prev > 2) {
        ok('transition mid-frame sample exists', mid.length >= 1, `samples=${samples.length} prev=${prev.toFixed(1)} cw=${cw.toFixed(1)}`);
        if (mid.length >= 1) sampledMid = true;
      }
    }
    prev = cw;
  }
  ok('growth monotonic non-decreasing', monotonic);
  ok('growth step <= one char width + 3', stepOk);
  ok('transition sampling performed', sampledMid);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
}

console.log('S3 钳制与溢出');
{
  const LONG = '长'.repeat(40);
  await focusTitle();
  await selectAllType(LONG);
  const cw = await settleCw();
  const avail = await availW();
  const g = await geom();
  ok('capsule clamped at dock avail width', approx(cw, avail, 2), `cw=${cw.toFixed(1)} avail=${avail}`);
  ok('caret stays at end under overflow', g.sel === 40, `sel=${g.sel}`);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  await settleCw();
  const d = await geom();
  ok('display truncated to 10 + …', d.v === LONG.slice(0, 10) + '…', d.v);
  ok('display symmetry (truncated)', Math.abs(d.wsd) <= 1, `wsd=${d.wsd.toFixed(2)}`);
}

console.log('S4 组字跟随');
{
  await focusTitle();
  await page.keyboard.press('Control+a');
  await page.keyboard.press('Backspace');
  await settleCw();
  const cdp = await page.context().newCDPSession(page);
  const comp = async (t) => {
    await cdp.send('Input.imeSetComposition', { text: t, selectionStart: -1, selectionEnd: -1 });
    await page.waitForTimeout(200);
    return settleCw();
  };
  const cw1 = await comp('nihaoma');
  const cw2 = await comp('nihaomahaode');
  const expW = Math.max(await probeTw('nihaomahaode'), await metaW()) + 41;
  ok('composition width follows live text (incl. comp string)', approx(cw2, expW, 2.5), `cw2=${cw2.toFixed(1)} exp=${expW.toFixed(1)}`);
  ok('composition width monotonic', cw2 >= cw1 - 0.05, `${cw1.toFixed(1)} -> ${cw2.toFixed(1)}`);
  const rows = (await waitDiagRows((rs) => {
    const u = rs.map(parseRow).filter((r) => r.ph === 'compupdate');
    return u.length > 0 && u[u.length - 1].len === 12;
  })).map(parseRow);
  const upd = rows.filter((r) => r.ph === 'compupdate');
  ok('diag compupdate len counts live text incl. comp string', upd.length > 0 && upd[upd.length - 1].len === 12, JSON.stringify(upd.slice(-2)));
  const CJK = '你好吗这是一个长标题呀';
  await cdp.send('Input.insertText', { text: CJK });
  await page.waitForTimeout(300);
  await settleCw();
  const g = await geom();
  ok('compend value is committed candidate text', g.v === CJK, g.v);
  ok('compend width settled on committed text', approx(g.cw, Math.max(await probeTw(CJK), await metaW()) + 41, 2.5), `cw=${g.cw.toFixed(1)}`);
  const rows2 = (await waitDiagRows((rs) => rs.map(parseRow).some((r) => r.ph === 'compend' && r.len === CJK.length))).map(parseRow);
  ok('diag compend row len = committed length', rows2.some((r) => r.ph === 'compend' && r.len === CJK.length));
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
}

console.log('S5 提交完整性');
{
  const FULL = '你好吗这是一个长标题呀';
  // Esc 还原：聚焦（值=全文）→ 全选改写 → Esc → 回展示截断、无新 commit
  await waitDiagSettle();
  const commitsBefore = (await diagRows()).filter((l) => l.includes('ph=commit')).length;
  await focusTitle();
  const gv = await page.evaluate(() => document.querySelector('#editor-title-text').value);
  ok('focus expands display to full text', gv === FULL, gv);
  await selectAllType('改动测试文本');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  const after = await geom();
  ok('esc restores display (truncated original)', after.v === FULL.slice(0, 10) + '…', after.v);
  ok('esc blurs', !after.active);
  await waitDiagSettle();
  const commitsAfter = (await diagRows()).filter((l) => l.includes('ph=commit')).length;
  ok('esc produces no commit', commitsAfter === commitsBefore, `${commitsBefore} -> ${commitsAfter}`);

  // 点按落点：前缀内同位
  const box = await page.evaluate(() => {
    const inp = document.querySelector('#editor-title-text');
    const r = inp.getBoundingClientRect();
    return { left: r.left, width: r.width, cy: r.top + r.height / 2 };
  });
  const disp = FULL.slice(0, 10) + '…';
  const dispW = await probeTw(disp);
  const textLeft = box.left + (box.width - dispW) / 2;
  const x1 = textLeft + (await probeTw(FULL.slice(0, 3))) + 1;
  await page.mouse.click(x1, box.cy);
  await page.waitForTimeout(450);
  const sel1 = await page.evaluate(() => document.querySelector('#editor-title-text').selectionStart);
  ok('tap on prefix lands at mapped char (±1)', Math.abs(sel1 - 3) <= 1, `sel=${sel1}`);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  // 点按落点：省略号 → 文末
  const x2 = textLeft + dispW - 2;
  await page.mouse.click(x2, box.cy);
  await page.waitForTimeout(450);
  const sel2 = await page.evaluate(() => document.querySelector('#editor-title-text').selectionStart);
  ok('tap on ellipsis lands at full end', sel2 === FULL.length, `sel=${sel2}`);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);

  // Enter 提交新标题 + 列表可见
  await focusTitle();
  await selectAllType('终验标题');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(400);
  const dv = await page.evaluate(() => document.querySelector('#editor-title-text').value);
  ok('enter commits new title', dv === '终验标题', dv);
  await page.click('.editor-fab.left');
  await page.waitForTimeout(900);
  const inList = await page.evaluate(() => document.body.innerText.includes('终验标题'));
  ok('committed title visible in list', inList);

  const slW = await page.evaluate(() => window.__slWrites);
  ok('zero JS scrollLeft writes on title input (whole run)', slW === 0, `writes=${slW}`);
  const foreign = await page.evaluate(() => window.__mnTitleGeomForeign);
  ok('foreign mutations = 0', foreign === 0 || foreign === null || foreign === undefined, `foreign=${foreign}`);
  const frows = (await waitDiagRows((rs) => rs.map(parseRow).some((r) => r.ph === 'focus'))).map(parseRow).filter((r) => r.ph === 'focus');
  ok('diag focus rows record fs=14', frows.length > 0 && frows.every((r) => r.fs === 14));
}

console.log(`\nprobe_title_geom: ${pass} passed, ${fail} failed`);
await browser.close();
if (fail > 0) { console.log('PROBE FAILED'); process.exit(1); }
console.log('ALL PASS');
