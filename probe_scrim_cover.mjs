// 备份确认弹窗遮罩覆盖 + 恢复动画验收探针（Chromium 口径）：
// A. 包含块已解除：.page-enter 动画结束后不再常驻 transform，
//    遮罩 offsetParent 回到 null（真 fixed）、计算高度 = 视口高；
// B. 四角像素采样均为根色被 rgba(0,0,0,0.28) 压暗的混合值；
// C. 恢复的进场动画真实播放：.backup-modal 的 sheetIn（250ms
//    弹簧，采样到中间态）、.backup-toast 的 toastSlideUpBar
//    （220ms 弹簧，采样到中间态）；
// D. 取消后遮罩无残留、无 pageerror。
// 滚动钉视口的判别在 probe_scrim_scroll.mjs（小视口场景）。
// 用法：node probe_scrim_cover.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8221/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : ''));
  if (!cond) fails++;
};
const info = (name, extra = '') => console.log('· ' + name + (extra ? ' | ' + extra : ''));

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(() => document.querySelector('h1.page-title').dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForSelector('.set-row', { timeout: 10000 });
await page.evaluate(() => {
  const row = [...document.querySelectorAll('.set-row')].find((r) => r.textContent.includes('备份'));
  row.dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
await page.waitForSelector('.backup-card', { timeout: 10000 });
await page.waitForTimeout(700); // 等 .page-enter 进入动画（280ms）结束

// ---------- 打开确认弹窗 + 动画中间态采样 ----------
await page.evaluate(() => {
  window.__animSamples = [];
  const watch = () => {
    const m = document.querySelector('.backup-modal');
    if (m) {
      const s = getComputedStyle(m);
      window.__animSamples.push({ opacity: parseFloat(s.opacity), transform: s.transform, name: s.animationName, dur: s.animationDuration });
      if (window.__animSamples.length < 14) setTimeout(watch, 30);
    } else setTimeout(watch, 10);
  };
  watch();
  const row = [...document.querySelectorAll('.backup-row')].find((b) => b.offsetParent !== null && b.textContent.includes('导出'));
  row.dispatchEvent(new MouseEvent('click', { bubbles: true }));
});
await page.waitForSelector('.backup-modal-scrim', { timeout: 10000 });
await page.waitForTimeout(600);

const A = await page.evaluate(() => {
  const scrim = document.querySelector('.backup-modal-scrim');
  const r = scrim.getBoundingClientRect();
  const pe = document.querySelector('.page-enter');
  const peS = getComputedStyle(pe);
  const modal = document.querySelector('.backup-modal');
  const ms = getComputedStyle(modal);
  return {
    innerH: window.innerHeight,
    scrimRect: { top: r.top, height: r.height },
    scrimOffsetParent: scrim.offsetParent ? String(scrim.offsetParent.className || scrim.offsetParent.tagName) : null,
    peTransform: peS.transform, peAnimFill: peS.animationFillMode,
    modalAnim: { name: ms.animationName, dur: ms.animationDuration, tf: ms.animationTimingFunction },
    samples: window.__animSamples || [],
  };
});
info('page-enter 终态', `transform=${A.peTransform} fill=${A.peAnimFill}`);
ok(A.peTransform === 'none', '页面进入动画结束后 transform 不常驻', A.peTransform);
ok(A.scrimOffsetParent === null, '遮罩 offsetParent=null（真 viewport fixed）', String(A.scrimOffsetParent));
ok(Math.abs(A.scrimRect.top) < 1 && Math.abs(A.scrimRect.height - A.innerH) < 1, '遮罩覆盖视口全高', JSON.stringify(A.scrimRect));
ok(A.modalAnim.name.includes('sheetIn') && A.modalAnim.dur === '0.25s', '底表 sheetIn 250ms 已挂', JSON.stringify(A.modalAnim));
const midSample = A.samples.find((s) => s.opacity < 0.99);
ok(!!midSample, '底表进场动画实播（采样到中间态）', midSample ? `opacity=${midSample.opacity} tf=${midSample.transform}` : `samples=${A.samples.length}`);

// ---------- B. 四角像素采样 ----------
const shot = await page.screenshot();
const px = await page.evaluate(async (b64) => {
  const img = new Image();
  await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = 'data:image/png;base64,' + b64; });
  const cv = document.createElement('canvas');
  cv.width = img.width; cv.height = img.height;
  const ctx = cv.getContext('2d');
  ctx.drawImage(img, 0, 0);
  const at = (x, y) => Array.from(ctx.getImageData(x, y, 1, 1).data.slice(0, 3));
  return { tl: at(8, 8), tr: at(img.width - 9, 8), bl: at(8, img.height - 9), br: at(img.width - 9, img.height - 9) };
}, shot.toString('base64'));
info('四角采样', JSON.stringify(px));
// 根色 rgb(242,242,247) × (1-0.28) ≈ (174,174,178)
const darkened = (p) => p[0] > 150 && p[0] < 200 && Math.abs(p[0] - p[2]) < 12;
ok(darkened(px.tl), '左上角已压暗', JSON.stringify(px.tl));
ok(darkened(px.tr), '右上角已压暗', JSON.stringify(px.tr));
ok(darkened(px.bl), '左下角已压暗', JSON.stringify(px.bl));
ok(darkened(px.br), '右下角已压暗', JSON.stringify(px.br));

// ---------- C. toast 动画 ----------
await page.evaluate(() => document.querySelector('.backup-modal .backup-btn.secondary').dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForTimeout(300);
ok(await page.evaluate(() => !document.querySelector('.backup-modal-scrim')), '取消后遮罩无残留');
const toastAnim = await page.evaluate(async () => {
  const btn = [...document.querySelectorAll('.backup-btn.primary')].find((b) => b.offsetParent !== null && !b.closest('.backup-modal'));
  btn.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  const samples = [];
  const t0 = performance.now();
  while (performance.now() - t0 < 900) {
    const t = document.querySelector('.backup-toast');
    if (t) {
      const s = getComputedStyle(t);
      samples.push({ opacity: parseFloat(s.opacity), transform: s.transform, name: s.animationName, dur: s.animationDuration });
      if (samples.length > 4 && parseFloat(s.opacity) >= 0.99) break;
    }
    await new Promise((r) => setTimeout(r, 25));
  }
  return samples;
});
const tFirst = toastAnim[0] || {};
info('toast 采样', JSON.stringify(toastAnim.slice(0, 3)));
ok(tFirst.name && tFirst.name.includes('toastSlideUpBar') && tFirst.dur === '0.22s', 'toast toastSlideUpBar 220ms 已挂', JSON.stringify(tFirst));
ok(toastAnim.some((s) => s.opacity < 0.99 || (s.transform !== 'none' && !s.transform.includes('(1, 0, 0, 1, 0, 0)'))), 'toast 上滑进场实播（采样到中间态）');

info('pageerror', errors.length ? errors.join('; ') : 'none');
ok(errors.length === 0, '无 pageerror');
console.log(fails === 0 ? 'PROBE PASS' : `PROBE FAIL x${fails}`);
await browser.close();
process.exit(fails === 0 ? 0 : 1);
