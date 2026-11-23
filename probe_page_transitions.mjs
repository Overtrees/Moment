// 页面退出过渡探针（弹跳根治验收）：4x CPU 节流下测设置→列表、
// 编辑→列表两条退出路径的进场动画时钟与几何：
//  ① 新页（列表 .page-enter）进场动画 currentTime 在其首现后
//     40ms 内必须 >0——串行交换时代挂载长任务会把 ct 冻结在 0
//     （实测 84ms），栈式交接后动画在出场窗口内起步、不过冻；
//  ② 交换后地标（.main-header / 首条 .list-item）单帧步进 ≤10px
//     （原版 4x 基线 6.9px）；
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
  const loop = (ts) => {
    if (!window.__run) return;
    const pe = document.querySelector('.page-enter');
    let ct = null;
    if (pe) {
      const a = pe.getAnimations()[0];
      if (a) ct = Math.round(a.currentTime);
    }
    const hdr = document.querySelector('.main-header');
    const li = document.querySelector('.list-item');
    let rootbg = '';
    try { rootbg = getComputedStyle(document.documentElement).getPropertyValue('--mn-root-bg').trim(); } catch (e) {}
    window.__fr.push({
      t: Math.round(ts),
      pe: !!pe,
      ct,
      hdrL: hdr ? Math.round(hdr.getBoundingClientRect().left * 10) / 10 : null,
      liL: li ? Math.round(li.getBoundingClientRect().left * 10) / 10 : null,
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
  // ① ct 冻结：首现后 40ms 内 ct>0
  const win = F.filter((f) => f.t >= first.t && f.t <= first.t + 40 && f.ct !== null);
  const ctOk = win.some((f) => f.ct > 0) || (first.ct !== null && first.ct > 0);
  const ctAt = F.find((f) => f.pe && f.ct !== null && f.ct > 0);
  ok(`${label} 进场动画 40ms 内起步`, ctOk, ctAt ? `ct>0 @${ctAt.t - first.t}ms` : 'ct 未起步');
  // ② 单帧步进（首现后）
  let maxStep = 0;
  for (let i = 1; i < F.length; i++) {
    if (F[i].t < first.t) continue;
    for (const k of ['hdrL', 'liL']) {
      const a = F[i - 1][k], b = F[i][k];
      if (a !== null && b !== null) maxStep = Math.max(maxStep, Math.abs(b - a));
    }
  }
  ok(`${label} 地标单帧步进 ≤10px`, maxStep <= 10, Math.round(maxStep * 10) / 10);
  // ③ 定格后步进 + 滚动恒定
  let lateStep = 0;
  for (let i = 1; i < F.length; i++) {
    if (F[i].t < first.t + 900) continue;
    for (const k of ['hdrL', 'liL']) {
      const a = F[i - 1][k], b = F[i][k];
      if (a !== null && b !== null) lateStep = Math.max(lateStep, Math.abs(b - a));
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
