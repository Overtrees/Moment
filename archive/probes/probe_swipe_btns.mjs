// 左滑两按钮渲染双边探针：原版 vs Rust，同法左滑到全开，
// 量测 computed style + rect + 截图（浅/深两方案 + 开启态翻转方案）。
// 用法: node probe_swipe_btns.mjs <origBase> <rustBase> <outDir>
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const [origBase, rustBase, outDir] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function measure(page, tag) {
  return await page.evaluate((tag) => {
    const w = [...document.querySelectorAll('.swipe-wrapper')].find((e) => e.querySelector('.swipe-actions') && e.querySelector('.list-item, .img-card'));
    if (!w) return { tag, error: 'no swipe wrapper' };
    const row = w.querySelector('.list-item, .img-card');
    const acts = w.querySelector('.swipe-actions');
    const btns = [...w.querySelectorAll('.swipe-action-btn')];
    const pick = (el) => {
      if (!el) return null;
      const cs = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      return {
        rect: { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) },
        bg: cs.backgroundColor, radius: cs.borderRadius, opacity: cs.opacity,
        transform: cs.transform, backdrop: cs.backdropFilter, z: cs.zIndex,
        font: cs.fontSize + '/' + cs.fontWeight, color: cs.color,
        border: cs.borderTopWidth + ' ' + cs.borderTopColor,
        text: el.innerText ? el.innerText.replace(/\n/g, '|') : undefined,
      };
    };
    const btnInfo = btns.map((b) => {
      const info = pick(b);
      const svg = b.querySelector('svg');
      if (svg) { const r = svg.getBoundingClientRect(); info.svgRect = { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }; const scs = getComputedStyle(svg); info.svgDisplay = scs.display; }
      const span = b.querySelector('span');
      if (span) { const r = span.getBoundingClientRect(); info.spanRect = { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }; info.spanText = span.innerText; }
      info.inlineStyle = b.getAttribute('style');
      return info;
    });
    return { tag, wrapper: pick(w), actions: pick(acts), row: pick(row), btns: btnInfo, rowInline: row.getAttribute('style') };
  }, tag);
}

async function swipeOpen(page) {
  const box = await page.evaluate(() => {
    const w = [...document.querySelectorAll('.swipe-wrapper')].find((e) => e.querySelector('.swipe-actions') && e.querySelector('.list-item, .img-card'));
    const row = w.querySelector('.list-item, .img-card');
    const r = row.getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height, cy: r.y + r.height / 2 };
  });
  const cdp = await page.context().newCDPSession(page);
  const sx = Math.min(box.x + box.w - 40, 340);
  const send = (type, x) => cdp.send('Input.dispatchTouchEvent', {
    type, touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x: Math.round(x), y: Math.round(box.cy), id: 1 }],
  });
  await send('touchStart', sx);
  const steps = 14;
  for (let i = 1; i <= steps; i++) { await send('touchMove', sx - (180 * i) / steps); await page.waitForTimeout(16); }
  await page.waitForTimeout(120);
  await send('touchEnd', 0);
  await page.waitForTimeout(500);
  return box;
}

async function run(base, name, scheme) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: scheme });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 25000 });
  await page.waitForTimeout(1200);
  const rest = await measure(page, name + '-' + scheme + '-rest');
  const box = await swipeOpen(page);
  const open = await measure(page, name + '-' + scheme + '-open');
  const clip = { x: Math.max(0, box.x - 4), y: Math.max(0, box.y - 6), width: Math.min(393, box.w + 8), height: box.h + 12 };
  await page.screenshot({ path: `${outDir}/${name}-${scheme}-open.png`, clip });
  // 开启态翻转方案
  await page.emulateMedia({ colorScheme: scheme === 'light' ? 'dark' : 'light' });
  await page.waitForTimeout(600);
  const flipped = await measure(page, name + '-' + scheme + '-open-flipped');
  await page.screenshot({ path: `${outDir}/${name}-${scheme}-open-flipped.png`, clip });
  console.log(JSON.stringify({ name, scheme, errors, rest, open, flipped }, null, 1));
  await ctx.close();
}

for (const scheme of ['light', 'dark']) {
  await run(origBase, 'orig', scheme);
  await run(rustBase, 'rust', scheme);
}
await browser.close();
