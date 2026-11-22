// 多视口响应式双边探针：Rust(8106) vs 原版(8107)，同视口同度量。
import { chromium } from 'playwright-core';

const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const VIEWPORTS = [
  [360, 740], [393, 852], [852, 393], [768, 1024], [1024, 768], [1280, 800], [1920, 1080],
];

async function measureList(page) {
  return page.evaluate(() => {
    const c = document.querySelector('.container');
    if (!c) return { err: 'no .container' };
    const cs = getComputedStyle(c);
    const cols = cs.display === 'grid' ? cs.gridTemplateColumns.split(' ').length : 0;
    const item = document.querySelector('.container .list-item');
    const img = document.querySelector('.container .img-card');
    const r = item ? item.getBoundingClientRect() : null;
    const ir = img ? img.getBoundingClientRect() : null;
    return {
      display: cs.display, cols, maxWidth: cs.maxWidth,
      itemW: r ? Math.round(r.width) : -1, itemH: r ? Math.round(r.height) : -1,
      imgW: ir ? Math.round(ir.width) : -1, imgH: ir ? Math.round(ir.height) : -1,
      cards: document.querySelectorAll('.container .list-item, .container .img-card').length,
    };
  });
}

async function measureEditor(page) {
  // 打开第一条备忘
  const clicked = await page.evaluate(() => {
    const el = document.querySelector('.container .list-item, .container .img-card');
    if (!el) return false;
    el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    return true;
  });
  if (!clicked) return { err: 'no card to open' };
  await page.waitForTimeout(900);
  return page.evaluate(() => {
    const body = document.querySelector('.editor-body');
    if (!body) return { err: 'no .editor-body' };
    const cs = getComputedStyle(body);
    const dock = document.querySelector('.editor-title-dock, .editor-title-capsule');
    const cols = document.querySelectorAll('.editor-column');
    const colInfo = Array.from(cols).map((c) => ({ h: c.clientHeight, sh: c.scrollHeight, oy: getComputedStyle(c).overflowY }));
    const spread = document.querySelector('.editor-spread');
    return {
      columnCount: cs.columnCount, display: cs.display,
      gridCols: cs.gridTemplateColumns === 'none' ? '-' : cs.gridTemplateColumns.split(' ').length,
      bodyW: body.clientWidth, spreadMaxW: spread ? getComputedStyle(spread).maxWidth : '-',
      indepCols: cols.length, colInfo,
      dockPresent: !!dock,
    };
  });
}

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
for (const [w, h] of VIEWPORTS) {
  for (const [name, url] of [['RUST', 'http://localhost:8106/'], ['ORIG', 'http://localhost:8107/Moment.html']]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true });
    const page = await ctx.newPage();
    try {
      await page.goto(url, { waitUntil: 'load', timeout: 20000 });
      await page.waitForTimeout(1600);
      const list = await measureList(page);
      const ed = await measureEditor(page);
      console.log(`${w}x${h} ${name} LIST ${JSON.stringify(list)}`);
      console.log(`${w}x${h} ${name} EDIT ${JSON.stringify(ed)}`);
    } catch (e) {
      console.log(`${w}x${h} ${name} FAIL ${String(e).slice(0, 120)}`);
    }
    await ctx.close();
  }
}
// 深色 + 减少动态（393x852 双边）
for (const [name, url] of [['RUST', 'http://localhost:8106/'], ['ORIG', 'http://localhost:8107/Moment.html']]) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'dark', reducedMotion: 'reduce' });
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: 'load', timeout: 20000 });
  await page.waitForTimeout(1400);
  const m = await page.evaluate(() => {
    const cs = getComputedStyle(document.documentElement);
    const item = document.querySelector('.list-item');
    return {
      primaryBg: cs.getPropertyValue('--primary-bg').trim(),
      motionVar: cs.getPropertyValue('--motion-page-transition').trim(),
      bodyBg: getComputedStyle(document.body).backgroundColor,
      itemTransDur: item ? getComputedStyle(item).transitionDuration : '-',
    };
  });
  console.log(`DARK+RM ${name} ${JSON.stringify(m)}`);
  await ctx.close();
}
await browser.close();
console.log('PROBE_DONE');
