// 页面退出过渡探针（弹跳根治验收）：4x CPU 节流下测设置→列表、
// 编辑→列表两条退出路径的进场动画时钟与几何：
//  ① 新页（列表 .page-enter）进场动画 currentTime 在其首现后
//     3 个 rAF 帧内必须 >0（帧数口径；毫秒值只打印作参考——采样
//     器在 rAF 回调读 ct，结构性地板为插入后 1–2 帧，毫秒判据随
//     宿主帧间隔拉伸误红，详见 TESTING.md 判据治理登记）；串行
//     交换时代挂载长任务把 ct 冻结约 7 帧（实测 117/133ms），
//     栈式交接后动画在出场窗口内起步、不过冻；
//  ② 交换后地标（限定 .page-current 内、进入页自身的
//     .main-header / 首条 .list-item）单帧步进 ≤10px
//     （原版 4x 基线 6.9px）；步进自新页首现帧起算、且仅
//     同一元素（采样器身份戳一致）的相邻帧计入——首现前
//     一帧是旧页内容（如设置页复用 .list-item 类名的设置
//     行），与首现帧成对即跨页换对象伪影（40−20=20px
//     实证，2026-11-23 方案 1 治理，见 TESTING.md 登记）；
//  ③ 定格后（首现 +900ms 起）步进 ≤1px、scrollTop 全程恒定；
//  ④ 编辑路径根色变化与新页首现同帧（±1 帧）。
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
    window.__fr.push({
      t: Math.round(ts),
      pe: !!pe,
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

function assess(label, fr, t0, { checkBg }) {
  const F = fr.map((f) => ({ ...f, t: f.t - t0 })).filter((f) => f.t >= -100);
  const first = F.find((f) => f.pe);
  ok(`${label} 新页出现`, !!first);
  if (!first) return;
  // ① ct 冻结：首现后 3 个 rAF 帧内 ct>0（帧数口径；毫秒仅参考打印）
  const firstIdx = F.findIndex((f) => f.pe);
  let ctFrameOff = -1;
  for (let i = firstIdx; i < F.length; i++) {
    if (F[i].ct !== null && F[i].ct > 0) { ctFrameOff = i - firstIdx; break; }
  }
  const ctMs = ctFrameOff >= 0 ? F[firstIdx + ctFrameOff].t - first.t : null;
  ok(`${label} 进场动画 3 帧内起步`, ctFrameOff >= 0 && ctFrameOff <= 3,
     ctFrameOff >= 0 ? `ct>0 @第${ctFrameOff}帧（${ctMs}ms）` : 'ct 未起步');
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
  // ④ 根色帧序
  if (checkBg) {
    const bgIdx = F.findIndex((f, i) => i > 0 && f.rootbg !== F[i - 1].rootbg);
    const peIdx = F.findIndex((f) => f.pe);
    ok(`${label} 根色与新页首现同帧`, bgIdx >= 0 && Math.abs(bgIdx - peIdx) <= 1, bgIdx >= 0 ? `bg@${F[bgIdx].t} pe@${first.t}` : '根色未变');
  }
}

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function runPath(label, setup) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 30000 });
  await page.waitForTimeout(800);
  await setup(page);
  await page.evaluate(SAMPLER);
  await page.waitForTimeout(150);
  const t0 = await page.evaluate(() => performance.now());
  await page.click('.editor-fab.left');
  await page.waitForTimeout(2400);
  const fr = await page.evaluate(() => { window.__run = false; return window.__fr; });
  assess(label, fr, t0, { checkBg: label.startsWith('编辑') });
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
});

await browser.close();
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
