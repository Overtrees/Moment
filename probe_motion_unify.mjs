// 浮层动效统一断言探针（Chromium 口径）：
// A. 令牌与各浮层计算样式（动画名/时长/曲线）与原版数值全等；
// B. 菜单进场实采样（opacity/transform 随时间推进、终态归位）；
// C. prefers-reduced-motion 下全局熔断生效。
// 断言变更（出场补齐线）：①菜单进场由关键帧改为原版
// closing 态 + transition 机制（关键帧 fill 会压住出场终
// 态值，与出场实现冲突；数值/曲线不变）——A/B 段按
// transition 口径断言；②toast/modal 进场动画经用户裁量
// 保留（有意偏离原版），A 段按保留口径断言存在。
// 用法：node probe_motion_unify.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8221/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : ''));
  if (!cond) fails++;
};

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });

// ---------- A. 令牌 + 合成元素计算样式 ----------
const A = await page.evaluate(() => {
  const cs = getComputedStyle(document.documentElement);
  const tok = (n) => cs.getPropertyValue(n).trim();
  const probe = (cls) => {
    const el = document.createElement('div');
    el.className = cls;
    document.body.appendChild(el);
    const s = getComputedStyle(el);
    const r = {
      animName: s.animationName, animDur: s.animationDuration, animTf: s.animationTimingFunction,
      trProp: s.transitionProperty, trDur: s.transitionDuration, trTf: s.transitionTimingFunction,
    };
    el.remove();
    return r;
  };
  return {
    spring: tok('--motion-spring'), pop: tok('--motion-pop'), fade: tok('--motion-fade'),
    sheet: tok('--motion-sheet'), sheetFade: tok('--motion-sheet-fade'), slash: tok('--motion-slash'),
    menu: probe('editor-menu-panel'),
    toast: probe('backup-toast'),
    modal: probe('backup-modal'),
    sheetWrap: probe('sheet-wrap'),
    slashPanel: probe('slash-panel'),
    imgSheet: probe('image-text-sheet-wrap'),
    imgBackdrop: probe('image-text-sheet-backdrop'),
    scrim: probe('menu-scrim'),
  };
});
const SPRING = 'cubic-bezier(0.34, 1.56, 0.64, 1)';
ok(A.spring.replace(/\s/g, '') === SPRING.replace(/\s/g, ''), 'token --motion-spring', A.spring);
ok(A.pop === '220ms' && A.fade === '180ms' && A.sheet === '250ms' && A.sheetFade === '200ms' && A.slash === '140ms',
  'token durations pop/fade/sheet/sheetFade/slash', [A.pop, A.fade, A.sheet, A.sheetFade, A.slash].join('/'));
ok(A.menu.animName === 'none', 'menu has NO enter keyframes (原版 closing 态 + transition 机制)', A.menu.animName);
ok(A.menu.trProp === 'opacity, transform' && A.menu.trDur === '0.18s, 0.22s', 'menu transition durations = fade 180 / pop 220', A.menu.trProp + ' ' + A.menu.trDur);
ok(A.menu.trTf.replace(/\s/g, '') === ('ease,' + SPRING).replace(/\s/g, ''), 'menu transition timing = ease, spring', A.menu.trTf);
ok(A.toast.animName === 'toastSlideUpBar' && A.toast.animDur === '0.22s', 'toast enter keyframes KEPT by user decision (有意偏离原版)', A.toast.animName + ' ' + A.toast.animDur);
ok(A.toast.trDur === '0.18s, 0.22s' && A.toast.trTf.replace(/\s/g, '').includes(SPRING.replace(/\s/g, '')),
  'toast transition = opacity 180 ease / transform 220 spring', A.toast.trDur + ' ' + A.toast.trTf);
ok(A.modal.animName === 'sheetIn' && A.modal.animDur === '0.25s', 'backup confirm modal enter KEPT by user decision (有意偏离原版)', A.modal.animName + ' ' + A.modal.animDur);
ok(A.sheetWrap.animName === 'none', 'bg sheet wrap has NO enter keyframes (原版挂载即终态)', A.sheetWrap.animName);
ok(A.sheetWrap.trDur === '0.2s, 0.25s' && A.sheetWrap.trTf.replace(/\s/g, '').includes(SPRING.replace(/\s/g, '')),
  'bg sheet transition = opacity 200 ease / transform 250 spring', A.sheetWrap.trDur + ' ' + A.sheetWrap.trTf);
ok(A.slashPanel.animName === 'slashIn' && A.slashPanel.animDur === '0.14s' && A.slashPanel.animTf === 'ease',
  'slash panel enter = slashIn 140ms ease', A.slashPanel.animName + ' ' + A.slashPanel.animDur + ' ' + A.slashPanel.animTf);
ok(A.imgSheet.trDur === '0.2s, 0.25s', 'image-text wrap transition durations via tokens', A.imgSheet.trDur);
ok(A.imgBackdrop.trDur === '0.2s', 'image-text backdrop fade 200ms', A.imgBackdrop.trDur);
ok(A.scrim.trDur === '0.22s', 'menu scrim transition background 220ms (原版惰性口径)', A.scrim.trDur);

// ---------- B. 菜单进场实采样 ----------
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
const samples = [];
for (const t of [40, 110, 200, 320]) {
  const s = await page.evaluate(() => {
    const el = document.querySelector('.editor-menu-panel');
    if (!el) return null;
    const cs = getComputedStyle(el);
    return { opacity: parseFloat(cs.opacity), transform: cs.transform, anims: el.getAnimations().map((a) => a.animationName + ':' + a.playState) };
  });
  samples.push({ t, ...s });
  await page.waitForTimeout(60);
}
console.log('samples:', JSON.stringify(samples));
ok(samples[0] && samples[0].opacity < 1, 'menu enter starts below opacity 1', JSON.stringify(samples[0]));
// 终态归位改为轮询等落定（transition 机制的起点是双 rAF
// 翻转，固定采样点会与弹簧尾巴竞速）
let settled = null;
for (let i = 0; i < 12 && !settled; i++) {
  const s = await page.evaluate(() => {
    const el = document.querySelector('.editor-menu-panel');
    if (!el) return null;
    const cs = getComputedStyle(el);
    return { opacity: parseFloat(cs.opacity), transform: cs.transform };
  });
  if (s && s.opacity === 1 && (s.transform === 'none' || s.transform.includes('matrix(1, 0, 0, 1'))) settled = s;
  else await page.waitForTimeout(80);
}
ok(!!settled, 'menu enter settles at opacity 1 / identity', JSON.stringify(settled));
ok(samples.some((s) => s && s.anims && s.anims.join().includes('running')), 'menu enter runs a transition/animation', JSON.stringify(samples[0] && samples[0].anims));

// 背景底表：打开后计算样式应无 animation（瞬时终态）
await page.locator('.editor-menu-panel .menu-item:has-text("更换背景色")').click();
await page.waitForSelector('.bg-sheet', { timeout: 8000 });
const bg = await page.evaluate(() => {
  const w = document.querySelector('.sheet-wrap');
  const cs = getComputedStyle(w);
  return { anim: cs.animationName, opacity: cs.opacity, transform: cs.transform };
});
ok(bg.anim === 'none' && bg.opacity === '1', 'bg sheet appears at final state, no enter animation', JSON.stringify(bg));
await page.click('.sheet-scrim');
await page.waitForTimeout(300);

// ---------- C. reduced motion 熔断 ----------
const ctx2 = await browser.newContext({ reducedMotion: 'reduce', viewport: { width: 390, height: 844 } });
const p2 = await ctx2.newPage();
await p2.goto(BASE, { waitUntil: 'load' });
await p2.waitForSelector('.list-item', { timeout: 20000 });
const C = await p2.evaluate(() => {
  const el = document.createElement('div');
  el.className = 'editor-menu-panel';
  document.body.appendChild(el);
  const s = getComputedStyle(el);
  const r = { dur: s.animationDuration, trDur: s.transitionDuration, pageTok: getComputedStyle(document.documentElement).getPropertyValue('--motion-page-transition').trim() };
  el.remove();
  return r;
});
ok(C.dur.split(',').every((d) => parseFloat(d) < 0.001), 'reduced-motion: menu animation squashed by global guard', C.dur);
ok(C.trDur.split(',').every((d) => parseFloat(d) < 0.001), 'reduced-motion: menu transition squashed by global guard', C.trDur);
ok(C.pageTok === '0ms', 'reduced-motion: --motion-page-transition = 0ms', C.pageTok);
await ctx2.close();

ok(errors.length === 0, 'no pageerror', errors.join('; '));
await browser.close();
console.log(fails === 0 ? 'MOTION ALL PASS' : `MOTION FAILS: ${fails}`);
process.exit(fails ? 1 : 0);
