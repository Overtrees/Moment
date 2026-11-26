// 页面退出过渡探针（弹跳根治验收）：4x CPU 节流下测设置→列表、
// 编辑→列表两条退出路径的进场动画时钟与几何：
//  ① 新页（列表 .page-enter）进场动画 currentTime 在其首现后
//     3 个 rAF 帧内必须 >0（帧数口径；毫秒值只打印作参考——采样
//     器在 rAF 回调读 ct，结构性地板为插入后 1–2 帧，毫秒判据随
//     宿主帧间隔拉伸误红，详见 TESTING.md 判据治理登记）；
//     适用面（2026-11-24 过渡统一收敛后）：全部返回路径均为
//     串行同帧交换（设置→列表已并入，见 ⑤），挂载长任务冻结
//     进场起步是用户知情接受的代价，各段 ct 起步只打印参考、
//     不判红（serial 标志）；
//  ② 交换后地标（限定 .page-current 内、进入页自身的
//     .main-header / 首条 .list-item）单帧步进 ≤10px
//     （原版 4x 基线 6.9px）；步进自新页首现帧起算、且仅
//     同一元素（采样器身份戳一致）的相邻帧计入——首现前
//     一帧是旧页内容（如设置页复用 .list-item 类名的设置
//     行），与首现帧成对即跨页换对象伪影（40−20=20px
//     实证，2026-11-23 方案 1 治理，见 TESTING.md 登记）；
//  ③ 定格后（首现 +900ms 起）步进 ≤1px、scrollTop 全程恒定；
//  ④ 编辑路径窗口互洽（2026-11-23 晚审计恢复集 (a) 口径，
//     audit_band_diff_45b5b46.md）：编辑→列表恢复基线
//     45b5b46 串行同帧交换——出场窗口内文档只有编辑器一
//     层：列表不预挂载（离页帧 .page-enter 不在场、
//     .page-current 无子元素），编辑器不进 fixed 离页层
//     （.editor-stage.leaving 计算 position 非 fixed）、以
//     当前页身份在流内播 slideOut，#editor-root 自有底恒
//     为开时基线；根色派生（页面状态纯函数、输入无离页
//     特例）窗口内恒为编辑值（提交点语义保留：selected
//     留至卸载帧同任务才清除）；提交帧编辑器卸载、列表
//     挂载、根色翻转同帧（列表首现与根色撤除 ±1 帧对
//     齐）、其后根色不回现、终值变量已撤且 html 计算色
//     = 列表默认。此前重叠交接口径（列表预挂载为上层进
//     入层、离页编辑器 fixed 下层、窗口内根色恒编辑值）
//     已随恢复集退役：其结构差（列表挂载与根色翻转解
//     耦）为审计定罪的白带唯一结构差异。三条结构判据
//     （无列表层/舞台非 fixed/挂载与翻转同帧）在 assess
//     内归入「防回归判据组（串行同帧语义）」，改判据须
//     连同 Nav 时序一起评审。判据边界：无头
//     只锁事件序、计算色与结构不变量，iOS 视口外带区本
//     身测不到，终判待真机。
//     setup 双路径（2026-11-23 收尾补段）：原「编辑→列表」
//     段点列表首行新建卡、走空备忘 close-empty 删除路径，
//     断言全保留；另加「编辑→列表·现有」段排除新建卡打开
//     真内容备忘，同 ④ 口径外加 slideOut 在播（离页帧
//     slideOutToRight 的 currentTime 推进）与 Diag 无
//     close-empty deleted 行两断言，两段互不替代。
//  ⑤ 设置→列表·串行同帧组（2026-11-24 过渡统一收敛，
//     diagnose_settings_topbar.md）：与 ④ 同口径锁组件页
//     返回——出场窗口内列表不挂载、设置本页在流内播
//     slideOut（ct 推进）、全程无 .page-leaving 节点（旧
//     栈式快照层已退役）、提交帧列表出现紧随出场结束；
//     Diag 须有 TRANS settings -> leaving / -> committed
//     两行且提交后 CENSUS leaving=0（此前组件页提交静默
//     无打点，缺陷在日志中不可见）。
//  ⑥ 滚动保存/恢复（同上确诊的直接成因）：(a) 列表在 0
//     进设置（设置内 scrollY=0）→ 返回落定 scrollY=0 且
//     顶部像素剖面（中心/左侧两列 RLE）与进入前一致；
//     (b) 列表滚至最大（实测值，深滚位）经紧凑胶囊进设置
//     → 返回落定 scrollY=实测值±1 且剖面与进入前同滚动
//     位一致。此前组
//     件页路径不管理滚动，返回停在浏览器钳制残值（真机
//     实测 ~110pt、顶栏被截断）。
//  ⑦ 组件页链（设置→备份→设置→列表）：前进即刻交换、
//     返回逐跳走 go_back 提交语义；全程 MutationObserver
//     监测 .page-leaving 计数恒 0；Diag 中 backup 与
//     settings 的 committed 行齐。
//  ⑧ 图片页进入/返回组（2026-11-24 过渡一致性审计，
//     diagnose_transition_consistency.md）：图片页是页化
//     线落码、其方向从未专项核过——进入（编辑器点图）：
//     内容层 slideIn 在播（ct 推进）、页头静止（返回钮
//     rect.left 全程恒定）、编辑器槽位同提交隐藏
//     （stage-hidden）、Diag 有 IMGPAGE open；返回：
//     内容层 slideOut 在播、出场窗口内编辑器不显形
//     （提交点语义）、TRANS image leaving/committed 两
//     行齐、提交后编辑器恢复且滚动 == 进页前实测 ±2。
//  ⑨ 子页动画落点组（同上审计 D-1 回归锁）：诊断/语言
//     进场根层无 slideIn 动画、内容层挂 page-slide-in；
//     出场采样窗口内内容层挂 page-slide-out、根层无
//     slideOut 动画——与设置/备份/图片的内容层落点同形
//     （根层整页连页头滑动为已根治偏差，不得复活）。
// 用法：node probe_page_transitions.mjs [baseURL]
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const base = process.argv[2] || 'http://localhost:8096/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let failures = 0;
const ok = (name, cond, val) => {
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
  if (!cond) failures++;
};

const SAMPLER = () => {
  window.__fr = [];
  window.__run = true;
  window.__ptSeq = 0;
  const loop = (ts) => {
    if (!window.__run) return;
    const pe = document.querySelector('.page-enter');
    let ct = null;
    if (pe) {
      const a = pe.getAnimations()[0];
      if (a) ct = Math.round(a.currentTime);
    }
    const cur = document.querySelector('.page-current');
    const hdr = cur ? cur.querySelector('.main-header') : null;
    const li = cur ? cur.querySelector('.list-item') : null;
    const stamp = (el) => {
      if (!el) return null;
      if (el.__ptid === undefined) el.__ptid = ++window.__ptSeq;
      return el.__ptid;
    };
    const hdrId = stamp(hdr);
    const liId = stamp(li);
    const layerOf = (el) => {
      if (!el) return null;
      if (el.closest('.page-current')) return 'current';
      if (el.closest('.page-leaving')) return 'leaving';
      if (el.closest('.page-enter')) return 'enter';
      return 'other';
    };
    let rootbg = '';
    try { rootbg = getComputedStyle(document.documentElement).getPropertyValue('--mn-root-bg').trim(); } catch (e) {}
    let edbg = null;
    const edEl = document.querySelector('.editor-stage.leaving #editor-root');
    if (edEl) { try { edbg = getComputedStyle(edEl).backgroundColor; } catch (e) {} }
    let lvCt = null;
    const lvStage = document.querySelector('.editor-stage.leaving');
    if (lvStage) {
      try {
        const anims = lvStage.getAnimations({ subtree: true })
          .filter((a) => a.animationName === 'slideOutToRight');
        if (anims.length) lvCt = Math.round(Math.max(...anims.map((a) => a.currentTime || 0)));
      } catch (e) {}
    }
    // 串行口径采样（恢复集 (a)）：离页舞台的计算 position
    // （在流内应为 relative、不得为 fixed）与 .page-current
    // 的元素子节点数（窗口内应为 0——列表层未挂载）
    let stagePos = null;
    if (lvStage) { try { stagePos = getComputedStyle(lvStage).position; } catch (e) {} }
    const curKids = cur ? cur.childElementCount : null;
    window.__fr.push({
      t: Math.round(ts),
      pe: !!pe,
      lv: !!lvStage,
      edbg,
      lvCt,
      stagePos,
      curKids,
      ct,
      hdrL: hdr ? Math.round(hdr.getBoundingClientRect().left * 10) / 10 : null,
      liL: li ? Math.round(li.getBoundingClientRect().left * 10) / 10 : null,
      hdrId,
      liId,
      hdrLayer: layerOf(hdr),
      liLayer: layerOf(li),
      sy: window.scrollY,
      rootbg,
    });
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
};

function assess(label, fr, t0, { checkBg, edBase, checkSlide, serial }) {
  const F = fr.map((f) => ({ ...f, t: f.t - t0 })).filter((f) => f.t >= -100);
  const first = F.find((f) => f.pe);
  ok(`${label} 新页出现`, !!first);
  if (!first) return;
  // ① ct 冻结：首现后 3 个 rAF 帧内 ct>0（帧数口径；毫秒仅参考打印）
  // 串行路径（serial，编辑→列表恢复集 (a)）不判：挂载长任务冻结
  // 进场起步是恢复串行时序的已知代价，只打印参考值
  const firstIdx = F.findIndex((f) => f.pe);
  let ctFrameOff = -1;
  for (let i = firstIdx; i < F.length; i++) {
    if (F[i].ct !== null && F[i].ct > 0) { ctFrameOff = i - firstIdx; break; }
  }
  const ctMs = ctFrameOff >= 0 ? F[firstIdx + ctFrameOff].t - first.t : null;
  if (serial) {
    console.log(`  ↳ ${label} 串行口径 ct 起步仅参考: ` +
      (ctFrameOff >= 0 ? `ct>0 @第${ctFrameOff}帧（${ctMs}ms）` : 'ct 未起步'));
  } else {
    ok(`${label} 进场动画 3 帧内起步`, ctFrameOff >= 0 && ctFrameOff <= 3,
       ctFrameOff >= 0 ? `ct>0 @第${ctFrameOff}帧（${ctMs}ms）` : 'ct 未起步');
  }
  // ② 单帧步进（自首现帧起算；仅同一元素相邻帧计入，跨页对排除）
  let maxStep = 0;
  let argmax = null;
  for (let i = firstIdx + 1; i < F.length; i++) {
    for (const k of ['hdrL', 'liL']) {
      const idk = k === 'hdrL' ? 'hdrId' : 'liId';
      const a = F[i - 1][k], b = F[i][k];
      if (a !== null && b !== null && F[i - 1][idk] !== null && F[i - 1][idk] === F[i][idk]) {
        const s = Math.abs(b - a);
        if (s > maxStep) {
          maxStep = s;
          argmax = { k, t: F[i].t, dt: F[i].t - F[i - 1].t, layer: k === 'hdrL' ? F[i].hdrLayer : F[i].liLayer };
        }
      }
    }
  }
  ok(`${label} 地标单帧步进 ≤10px`, maxStep <= 10, Math.round(maxStep * 10) / 10);
  if (argmax) console.log(`  ↳ ${label} max 步进帧: t=${argmax.t}ms 地标=${argmax.k} 所属层=${argmax.layer} 相邻帧间隔=${argmax.dt}ms`);
  // ③ 定格后步进 + 滚动恒定
  let lateStep = 0;
  for (let i = 1; i < F.length; i++) {
    if (F[i].t < first.t + 900) continue;
    for (const k of ['hdrL', 'liL']) {
      const idk = k === 'hdrL' ? 'hdrId' : 'liId';
      const a = F[i - 1][k], b = F[i][k];
      if (a !== null && b !== null && F[i - 1][idk] !== null && F[i - 1][idk] === F[i][idk]) lateStep = Math.max(lateStep, Math.abs(b - a));
    }
  }
  ok(`${label} 定格后步进 ≤1px`, lateStep <= 1, Math.round(lateStep * 10) / 10);
  const syVar = Math.max(...F.map((f) => f.sy)) - Math.min(...F.map((f) => f.sy));
  ok(`${label} scrollTop 恒定`, syVar === 0, syVar);
  // ④ 窗口互洽（串行同帧交换口径，恢复集 (a)）：离页期间
  // 文档只有编辑器一层（无列表层、编辑器在流内）、根色恒
  // 为编辑值、编辑器根自有底恒为开时基线；提交帧编辑器
  // 卸载、列表出现、根色撤除三者同帧且其后不回现；终值已撤
  if (checkBg) {
    const lvIdxs = F.map((f, i) => (f.lv ? i : -1)).filter((i) => i >= 0);
    ok(`${label} 离页层出现`, lvIdxs.length > 0, `${lvIdxs.length} 帧`);
    ok(`${label} 离页基线已捕获`, !!edBase && !!edBase.varBg && !!edBase.edBg,
       edBase ? `var=${edBase.varBg} ed=${edBase.edBg}` : '无基线');
    if (lvIdxs.length > 0 && edBase) {
      ok(`${label} 离页期间编辑器根自有底恒为基线`,
         lvIdxs.every((i) => F[i].edbg === edBase.edBg),
         String(F[lvIdxs[0]].edbg));
      ok(`${label} 离页期间根色恒为编辑值（状态未提交）`,
         lvIdxs.every((i) => F[i].rootbg === edBase.varBg),
         String(F[lvIdxs[0]].rootbg));
      // ===== 防回归判据组（串行同帧语义）=====
      // 本组三条（无列表层 / 舞台非 fixed / 挂载与翻转
      // 同帧）锁编辑→列表的串行同帧交换结构，防 #14
      // 重叠交接回归——其结构差（列表预挂载 + 离页层
      // fixed + 挂载/翻转解耦）为审计定罪的白带唯一
      // 结构差异（audit_band_diff_45b5b46.md）。改本
      // 组任一判据须连同 Nav 时序（main.rs arm_unload
      // 提交点与 editor_slot 槽位口径）一起评审，不得
      // 单独放宽。本组第一、二条：窗口内列表不预挂载
      // ——离页帧 .page-enter 恒不在场、.page-current
      // 恒无子元素；编辑器不进 fixed 离页层——舞台计
      // 算 position 恒非 fixed（在流内以当前页身份出场）
      ok(`${label} 离页期间无列表层（未预挂载）`,
         lvIdxs.every((i) => !F[i].pe && F[i].curKids === 0),
         `pe 帧=${lvIdxs.filter((i) => F[i].pe).length} curKids 首帧=${F[lvIdxs[0]].curKids}`);
      ok(`${label} 离页期间编辑器在流内（舞台非 fixed）`,
         lvIdxs.every((i) => F[i].stagePos !== null && F[i].stagePos !== 'fixed'),
         String(F[lvIdxs[0]].stagePos));
      if (checkSlide) {
        const cts = lvIdxs.map((i) => F[i].lvCt).filter((v) => v !== null);
        const adv = cts.length >= 2 ? Math.max(...cts) - Math.min(...cts) : 0;
        ok(`${label} 离页 slideOut 在播（currentTime 推进）`,
           cts.length >= 2 && adv >= 20,
           cts.length ? `ct ${Math.min(...cts)}→${Math.max(...cts)}ms / ${cts.length} 帧` : '无 slideOut 采样');
      }
      const lastLv = lvIdxs[lvIdxs.length - 1];
      const firstClear = F.findIndex((f, i) => i > lastLv && f.rootbg === '');
      ok(`${label} 提交帧根色撤除与卸载对齐（±1 帧）且不回现`,
         firstClear > lastLv && firstClear <= lastLv + 2
           && F.slice(lastLv + 1).every((f) => f.rootbg === ''),
         `lastLv@${F[lastLv].t} firstClear=${firstClear >= 0 ? F[firstClear].t : '无'}`);
      // 同帧交换锁（防回归判据组第三条）：列表首现必须
      // 在离页结束之后、且与根色撤除同帧（±1）——挂载
      // 与翻转同属提交帧一次渲染提交
      const firstPe = F.findIndex((f) => f.pe);
      ok(`${label} 提交帧列表出现与根色翻转同帧（±1）`,
         firstPe > lastLv && firstPe <= lastLv + 2
           && firstClear >= 0 && Math.abs(firstPe - firstClear) <= 1,
         `lastLv@${F[lastLv].t} firstPe=${firstPe >= 0 ? F[firstPe].t : '无'} firstClear=${firstClear >= 0 ? F[firstClear].t : '无'}`);
    }
    ok(`${label} 根色终值已撤除`, F[F.length - 1].rootbg === '', F[F.length - 1].rootbg);
  }
}

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function runPath(label, setup, opts = {}) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(800);
  await setup(page);
  // 编辑路径：点返回前捕获窗口互洽基线（根色变量值 + 编辑
  // 器根计算背景），④ 断言离页帧与基线逐帧比对
  let edBase = null;
  if (label.startsWith('编辑')) {
    edBase = await page.evaluate(() => {
      const el = document.querySelector('#editor-root');
      return {
        varBg: getComputedStyle(document.documentElement).getPropertyValue('--mn-root-bg').trim(),
        edBg: el ? getComputedStyle(el).backgroundColor : null,
      };
    });
  }
  await page.evaluate(SAMPLER);
  await page.waitForTimeout(150);
  const t0 = await page.evaluate(() => performance.now());
  await page.click('.editor-fab.left');
  await page.waitForTimeout(2400);
  const fr = await page.evaluate(() => { window.__run = false; return window.__fr; });
  assess(label, fr, t0, { checkBg: label.startsWith('编辑'), edBase, checkSlide: !!opts.checkSlide, serial: !!opts.serial });
  if (label.startsWith('编辑')) {
    const fin = await page.evaluate(() => ({
      bg: getComputedStyle(document.documentElement).backgroundColor,
      inline: document.documentElement.style.getPropertyValue('--mn-root-bg').trim(),
    }));
    ok('编辑→列表 html 计算色 = 列表默认且变量未残留',
       fin.bg === 'rgb(242, 242, 247)' && fin.inline === '', `${fin.bg} / var="${fin.inline}"`);
  }
  if (opts.post) await opts.post(page);
  await ctx.close();
}

await runPath('设置→列表', async (page) => {
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(1500);
}, { serial: true });
await runPath('编辑→列表', async (page) => {
  await page.locator('.img-card-title-text, .list-item .item-title-text').first().click();
  await page.waitForSelector('#editor-root', { timeout: 15000 });
  await page.waitForTimeout(2500);
}, { serial: true });
await runPath('编辑→列表·现有', async (page) => {
  // 现有备忘路径：排除新建卡（.new-card-title 所在行）的
  // 首个内容卡——种子序下命中置顶的内容备忘；点标题文本
  // 与空备忘段同一点法、仅定位域不同。标题打印留证，
  // 证本段命中的确为真备忘而非新建卡。
  const title = page.locator(
    '.swipe-wrapper:not(:has(.new-card-title)) .img-card-title-text, '
    + '.swipe-wrapper:not(:has(.new-card-title)) .item-title-text').first();
  console.log('  ↳ 现有段打开备忘标题 = ' + (await title.textContent()));
  await title.click();
  await page.waitForSelector('#editor-root', { timeout: 15000 });
  await page.waitForTimeout(2500);
}, {
  serial: true,
  checkSlide: true,
  post: async (page) => {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
    });
    ok('编辑→列表·现有 Diag 无 close-empty deleted 行',
       !lines.some((l) => String(l).includes('close empty memo')),
       `${lines.length} 行`);
  },
});

// ===== ⑤⑥⑦ 过渡统一收敛段（2026-11-24） =====
const scratch = await browser.newPage();
await scratch.goto('about:blank');

async function diagLines(page) {
  return page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
  });
}
// Diag 落盘 1s 节流：轮询等目标行出现（判据本身不变）
async function waitDiag(page, substr, timeout = 6000) {
  const t0 = Date.now();
  let lines = [];
  while (Date.now() - t0 < timeout) {
    lines = await diagLines(page);
    if (lines.some((l) => String(l).includes(substr))) return lines;
    await page.waitForTimeout(250);
  }
  return lines;
}
// 顶部像素剖面：截图经 scratch 页 canvas 解码，取 x=60/196
// 两列 y 0..219 的逐行色 RLE 串（同滚动位/同内容应逐字一致）
async function topProfile(page) {
  const b64 = (await page.screenshot({ type: 'png' })).toString('base64');
  return scratch.evaluate(async (b64) => {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = 'data:image/png;base64,' + b64; });
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    const dsf = img.width / 393;
    const H = 220;
    const data = g.getImageData(0, 0, img.width, Math.floor(H * dsf)).data;
    const rows = [];
    for (let y = 0; y < H; y++) {
      const py = Math.floor(y * dsf);
      const vals = [];
      for (const x of [60, 196]) {
        const px = Math.floor(x * dsf);
        const i = (py * img.width + px) * 4;
        vals.push(`${data[i]},${data[i + 1]},${data[i + 2]}`);
      }
      rows.push(vals.join('|'));
    }
    const rle = [];
    let s = 0;
    for (let y = 1; y <= rows.length; y++) {
      if (y === rows.length || rows[y] !== rows[s]) { rle.push(`y${s}-${y - 1}:${rows[s]}`); s = y; }
    }
    return rle.join(';');
  }, b64);
}

// ⑤ 设置→列表·串行同帧组
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(800);
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(1500);
  await page.evaluate(() => {
    window.__fr5 = [];
    window.__run5 = true;
    const loop = () => {
      if (!window.__run5) return;
      const cur = document.querySelector('.page-current');
      const content = cur ? cur.querySelector('.page-content') : null;
      let soCt = null;
      if (content) {
        const a = content.getAnimations().find((x) => x.animationName === 'slideOutToRight');
        if (a) soCt = Math.round(a.currentTime);
      }
      window.__fr5.push({
        list: !!(cur && cur.querySelector('.page-enter')),
        settings: !!content,
        soCt,
        leaving: document.querySelectorAll('.page-leaving').length,
      });
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  });
  await page.waitForTimeout(150);
  await page.click('.editor-fab.left');
  await page.waitForTimeout(2600);
  const fr = await page.evaluate(() => { window.__run5 = false; return window.__fr5; });
  ok('⑤ 全程无 .page-leaving 节点（快照层已退役）', fr.every((f) => f.leaving === 0));
  const soIdx = fr.map((f, i) => (f.soCt !== null ? i : -1)).filter((i) => i >= 0);
  ok('⑤ 设置出场窗口存在（slideOut 在场）', soIdx.length > 0, `${soIdx.length} 帧`);
  if (soIdx.length > 0) {
    const first = soIdx[0];
    const last = soIdx[soIdx.length - 1];
    ok('⑤ 出场窗口内列表未挂载（串行）',
       fr.slice(first, last + 1).every((f) => !f.list));
    const cts = soIdx.map((i) => fr[i].soCt);
    ok('⑤ 离页 slideOut 在播（currentTime 推进 ≥20ms）',
       Math.max(...cts) - Math.min(...cts) >= 20,
       `ct ${Math.min(...cts)}→${Math.max(...cts)}ms / ${cts.length} 帧`);
    const firstList = fr.findIndex((f, i) => i > last && f.list);
    ok('⑤ 提交帧列表出现紧随出场结束（≤2 帧）',
       firstList > last && firstList <= last + 2,
       `last=${last} firstList=${firstList}`);
  }
  const lines = await waitDiag(page, 'TRANS settings -> committed');
  ok('⑤ Diag 有 TRANS settings -> leaving',
     lines.some((l) => String(l).includes('TRANS settings -> leaving')));
  ok('⑤ Diag 有 TRANS settings -> committed',
     lines.some((l) => String(l).includes('TRANS settings -> committed')));
  const ci = lines.findIndex((l) => String(l).includes('TRANS settings -> committed'));
  const censusAfter = ci >= 0 ? lines.slice(ci).find((l) => String(l).includes('CENSUS')) : null;
  ok('⑤ 提交后 CENSUS leaving=0（哨兵）',
     !!censusAfter && String(censusAfter).includes('leaving=0'),
     censusAfter ? String(censusAfter).slice(0, 90) : '无');
  await ctx.close();
}

// ⑥ 滚动保存/恢复：(a) 0 位往返 (b) 150 位往返
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(2000);
  const profA0 = await topProfile(page);
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(1200);
  ok('⑥(a) 设置内 scrollY=0（进入已回顶）',
     (await page.evaluate(() => window.scrollY)) === 0);
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-current .page-enter', { timeout: 15000 });
  await page.waitForTimeout(1600);
  ok('⑥(a) 返回落定 scrollY=0',
     (await page.evaluate(() => window.scrollY)) === 0);
  const profA1 = await topProfile(page);
  ok('⑥(a) 返回后顶部像素剖面与进入前一致', profA1 === profA0,
     profA1 === profA0 ? 'RLE 逐字一致' : 'RLE 不一致');
  await ctx.close();
}
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(2000);
  // 滚至最大并以实测值为恢复目标：852 高视口下种子列表
  // 最大滚动仅 ~70，写死 150 会被浏览器钳制、判据测的是
  // 钳制值而非保存/恢复——目标取进入前实测（须 >30 以进
  // 紧凑态、经紧凑胶囊进入设置）。
  await page.evaluate(() => window.scrollTo(0, 99999));
  await page.waitForTimeout(700);
  const targetY = await page.evaluate(() => window.scrollY);
  ok('⑥(b) 进入前列表已深滚（>30，紧凑态）', targetY > 30, targetY);
  const profB0 = await topProfile(page);
  await page.click('.page-current .page-title.compact');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(1200);
  ok('⑥(b) 设置内 scrollY=0（进入已存滚动并回顶）',
     (await page.evaluate(() => window.scrollY)) === 0);
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-current .page-enter', { timeout: 15000 });
  await page.waitForTimeout(1600);
  const syB = await page.evaluate(() => window.scrollY);
  ok('⑥(b) 返回落定 scrollY=进入前实测值±1（保存值恢复）',
     Math.abs(syB - targetY) <= 1, `${syB} vs ${targetY}`);
  const profB1 = await topProfile(page);
  ok('⑥(b) 返回后顶部像素剖面与进入前同滚动位一致', profB1 === profB0,
     profB1 === profB0 ? 'RLE 逐字一致' : 'RLE 不一致');
  await ctx.close();
}

// ⑦ 组件页链：设置→备份→设置→列表
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(800);
  await page.evaluate(() => {
    window.__lvMax = 0;
    new MutationObserver(() => {
      window.__lvMax = Math.max(window.__lvMax,
        document.querySelectorAll('.page-leaving').length);
    }).observe(document.documentElement, { childList: true, subtree: true });
  });
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(1000);
  await page.click('.backup-card .set-row >> nth=0');
  await page.waitForSelector('.backup-hero', { timeout: 15000 });
  await page.waitForTimeout(1000);
  await page.click('.editor-fab.left');
  await page.waitForSelector('.backup-card .set-row', { timeout: 15000 });
  await waitDiag(page, 'TRANS backup -> committed');
  await page.waitForTimeout(600);
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-current .page-enter', { timeout: 15000 });
  await page.waitForTimeout(1200);
  const lines = await waitDiag(page, 'TRANS settings -> committed');
  ok('⑦ Diag 有 TRANS backup -> committed',
     lines.some((l) => String(l).includes('TRANS backup -> committed')));
  ok('⑦ Diag 有 TRANS settings -> committed',
     lines.some((l) => String(l).includes('TRANS settings -> committed')));
  const lvMax = await page.evaluate(() => window.__lvMax);
  const lvNow = await page.evaluate(() => document.querySelectorAll('.page-leaving').length);
  ok('⑦ 全程 .page-leaving 计数恒 0', lvMax === 0 && lvNow === 0, `max=${lvMax} now=${lvNow}`);
  await ctx.close();
}

// ===== ⑧⑨ 过渡一致性审计段（2026-11-24） =====
// ⑧ 图片页进入/返回组
{
  execSync(`python3 - <<'PYEOF'
import json, struct, zlib, zipfile

def png(w, h):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    raw = (b'\\x00' + b'\\x00' * (w * 3)) * h
    return (b'\\x89PNG\\r\\n\\x1a\\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

doc = []
for i in range(1, 16):
    doc.append({"id": f"tp-f{i}", "type": "paragraph", "children": [{"text": f"过渡探针填充段落 {i:02d}，用于撑起可滚动的长文档。"}]})
doc.append({"id": "tp-img", "type": "image", "attrs": {"fileId": "imgT"}, "children": []})
for i in range(16, 31):
    doc.append({"id": f"tp-f{i}", "type": "paragraph", "children": [{"text": f"过渡探针填充段落 {i:02d}，用于撑起可滚动的长文档。"}]})
memo = {"id": "tp-memo", "title": "过渡探针图", "pinned": False,
        "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00",
        "doc": doc}
z = zipfile.ZipFile('/tmp/tp_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {
    "imgT": {"name": "trans-photo.png", "type": "image/png"}}}))
z.writestr('attachments/imgT', png(120, 90))
z.close()
print('tp_probe.zip ready')
PYEOF`);
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(800);
  // 导入夹具（与 probe_lightbox_page 的 importZip 同流程）
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 15000 });
  await page.setInputFiles('#file-import', '/tmp/tp_probe.zip');
  await page.waitForSelector('.backup-modal', { timeout: 15000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { polling: 200, timeout: 20000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 15000 });
  await page.waitForTimeout(800);
  // 打开夹具备忘（身份打印留证）
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes('过渡探针图'));
    if (el) el.click();
  });
  await page.waitForSelector('#editor-root', { timeout: 15000 });
  await page.waitForTimeout(2000);
  // 编辑器滚至图片入视口处，记进页前滚动位（img_restore 目标）
  const zone = await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="tp-img"]');
    if (!w) return null;
    w.scrollIntoView({ block: 'center' });
    const img = w.querySelector('img');
    if (!img) return null;
    const r = img.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  ok('⑧ 夹具图片可定位', !!zone);
  await page.waitForTimeout(500);
  const y0 = await page.evaluate(() => window.scrollY);
  ok('⑧ 进页前编辑器已滚动（>30）', y0 > 30, y0);
  // 进入采样：内容层 slideIn 时钟 + 页头返回钮横坐标 + 槽位隐藏
  await page.evaluate(() => {
    window.__fr8 = [];
    window.__run8 = true;
    const loop = () => {
      if (!window.__run8) return;
      const ip = document.querySelector('.img-page');
      const content = ip ? ip.querySelector('.img-page-content') : null;
      let anim = null, ct = null;
      if (content) {
        const a = content.getAnimations().find((x) => x.animationName === 'slideInFromRight');
        if (a) { anim = a.animationName; ct = Math.round(a.currentTime); }
      }
      const fab = ip ? ip.querySelector('.editor-fab.left') : null;
      const stage = document.querySelector('.editor-stage');
      window.__fr8.push({
        img: !!ip, anim, ct,
        headL: fab ? Math.round(fab.getBoundingClientRect().left * 10) / 10 : null,
        stageHidden: !!stage && stage.classList.contains('stage-hidden'),
      });
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  });
  await page.waitForTimeout(150);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 15000 });
  await page.waitForTimeout(2200);
  const fr8 = await page.evaluate(() => { window.__run8 = false; return window.__fr8; });
  const inCts = fr8.filter((f) => f.anim === 'slideInFromRight' && f.ct !== null).map((f) => f.ct);
  ok('⑧ 进入：内容层 slideIn 在播（currentTime 推进 ≥20ms）',
     inCts.length >= 2 && Math.max(...inCts) - Math.min(...inCts) >= 20,
     inCts.length ? `ct ${Math.min(...inCts)}→${Math.max(...inCts)}ms / ${inCts.length} 帧` : '无 slideIn 采样');
  const headLs = fr8.filter((f) => f.img && f.headL !== null).map((f) => f.headL);
  ok('⑧ 进入：页头静止（返回钮横坐标全程恒定）',
     headLs.length > 0 && Math.max(...headLs) - Math.min(...headLs) <= 1,
     headLs.length ? `${Math.min(...headLs)}..${Math.max(...headLs)}` : '无页头采样');
  ok('⑧ 进入：编辑器槽位同提交隐藏（stage-hidden）',
     fr8.some((f) => f.img) && fr8.filter((f) => f.img).every((f) => f.stageHidden));
  const lines8a = await waitDiag(page, 'IMGPAGE open');
  ok('⑧ Diag 有 IMGPAGE open 行',
     lines8a.some((l) => String(l).includes('IMGPAGE open')));
  // 返回采样：内容层 slideOut 时钟 + 窗口内编辑器不显形
  await page.evaluate(() => {
    window.__fr8b = [];
    window.__run8b = true;
    const loop = () => {
      if (!window.__run8b) return;
      const ip = document.querySelector('.img-page');
      const content = ip ? ip.querySelector('.img-page-content') : null;
      let soCt = null;
      if (content) {
        const a = content.getAnimations().find((x) => x.animationName === 'slideOutToRight');
        if (a) soCt = Math.round(a.currentTime);
      }
      const stage = document.querySelector('.editor-stage');
      window.__fr8b.push({
        img: !!ip, soCt,
        stageHidden: !!stage && stage.classList.contains('stage-hidden'),
      });
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  });
  await page.waitForTimeout(150);
  await page.click('.img-page .editor-fab.left');
  await page.waitForTimeout(2600);
  const fr8b = await page.evaluate(() => { window.__run8b = false; return window.__fr8b; });
  const outCts = fr8b.filter((f) => f.soCt !== null).map((f) => f.soCt);
  ok('⑧ 返回：内容层 slideOut 在播（currentTime 推进 ≥20ms）',
     outCts.length >= 2 && Math.max(...outCts) - Math.min(...outCts) >= 20,
     outCts.length ? `ct ${Math.min(...outCts)}→${Math.max(...outCts)}ms / ${outCts.length} 帧` : '无 slideOut 采样');
  ok('⑧ 返回：出场窗口内编辑器不显形（槽位仍隐藏）',
     fr8b.filter((f) => f.soCt !== null).every((f) => f.stageHidden));
  const backState = await page.evaluate(() => {
    const stage = document.querySelector('.editor-stage');
    return {
      imgGone: !document.querySelector('.img-page'),
      stageShown: !!stage && !stage.classList.contains('stage-hidden'),
      sy: window.scrollY,
    };
  });
  ok('⑧ 返回：提交后图片页卸载、编辑器恢复显示',
     backState.imgGone && backState.stageShown, JSON.stringify(backState));
  ok('⑧ 返回：编辑器滚动恢复 == 进页前实测 ±2',
     Math.abs(backState.sy - y0) <= 2, `${backState.sy} vs ${y0}`);
  const lines8b = await waitDiag(page, 'TRANS image -> committed');
  ok('⑧ Diag 有 TRANS image -> leaving',
     lines8b.some((l) => String(l).includes('TRANS image -> leaving')));
  ok('⑧ Diag 有 TRANS image -> committed',
     lines8b.some((l) => String(l).includes('TRANS image -> committed')));
  await ctx.close();
}

// ⑨ 子页动画落点组（D-1 回归锁）：诊断/语言
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(800);
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(1000);
  for (const [label, rowText, marker] of [['诊断', '诊断', '.diag-body'], ['语言', '语言', '.lang-state']]) {
    await page.locator('.set-row', { hasText: rowText }).first().click();
    await page.waitForSelector(marker, { timeout: 15000 });
    await page.waitForTimeout(900);
    const enter = await page.evaluate(() => {
      const root = document.querySelector('.page-current > div');
      const content = root ? root.querySelector('.page-content') : null;
      return {
        rootAnims: root ? root.getAnimations().map((a) => a.animationName) : [],
        contentCls: content ? content.className : '',
        contentAnims: content ? content.getAnimations().map((a) => a.animationName) : [],
      };
    });
    ok(`⑨ ${label}进场：根层无 slideIn 动画（落点不在根层）`,
       !enter.rootAnims.includes('slideInFromRight'), JSON.stringify(enter.rootAnims));
    ok(`⑨ ${label}进场：内容层挂 page-slide-in 且 slideIn 在场`,
       enter.contentCls.includes('page-slide-in') && enter.contentAnims.includes('slideInFromRight'),
       enter.contentCls);
    await page.click('.editor-fab.left');
    let sawOutCls = false;
    let rootSoEver = false;
    for (let i = 0; i < 40; i++) {
      const obs = await page.evaluate((m) => {
        if (!document.querySelector(m)) return null;
        const root = document.querySelector('.page-current > div');
        const content = root ? root.querySelector('.page-content') : null;
        return {
          cls: content ? content.className : '',
          rootSo: root ? root.getAnimations().some((a) => a.animationName === 'slideOutToRight') : false,
        };
      }, marker);
      if (!obs) break;
      if (obs.cls.includes('page-slide-out')) sawOutCls = true;
      if (obs.rootSo) rootSoEver = true;
      await page.waitForTimeout(25);
    }
    ok(`⑨ ${label}出场：内容层挂 page-slide-out`, sawOutCls);
    ok(`⑨ ${label}出场：根层无 slideOut 动画`, !rootSoEver);
    await page.waitForSelector('.seg-row', { timeout: 15000 });
    await page.waitForTimeout(800);
  }
  await ctx.close();
}

await browser.close();
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
