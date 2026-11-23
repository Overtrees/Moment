// 页面退出过渡探针（弹跳根治验收）：4x CPU 节流下测设置→列表、
// 编辑→列表两条退出路径的进场动画时钟与几何：
//  ① 新页（列表 .page-enter）进场动画 currentTime 在其首现后
//     3 个 rAF 帧内必须 >0（帧数口径；毫秒值只打印作参考——采样
//     器在 rAF 回调读 ct，结构性地板为插入后 1–2 帧，毫秒判据随
//     宿主帧间隔拉伸误红，详见 TESTING.md 判据治理登记）；串行
//     交换时代挂载长任务把 ct 冻结约 7 帧（实测 117/133ms），
//     栈式交接后动画在出场窗口内起步、不过冻；
//     适用面（2026-11-23 审计恢复集 (a) 后）：本判据只锁栈式
//     交接路径（设置→列表）。编辑→列表已恢复串行同帧交换，
//     挂载长任务冻结进场起步是用户知情接受的代价，编辑段
//     ct 起步只打印参考、不判红（serial 标志）；
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
// 用法：node probe_page_transitions.mjs [baseURL]
import { chromium } from 'playwright-core';

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
});
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
      try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
    });
    ok('编辑→列表·现有 Diag 无 close-empty deleted 行',
       !lines.some((l) => String(l).includes('close empty memo')),
       `${lines.length} 行`);
  },
});

await browser.close();
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
