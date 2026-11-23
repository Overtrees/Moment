// E组实测二轮：Flutter 首屏资源明细 + 原版编辑器键入基线 + Flutter 键入复测
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const FL = 'http://127.0.0.1:8096/';
const ORIG = 'http://127.0.0.1:8097/Moment.html';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function instrument(page) {
  await page.evaluate(() => {
    window.__frames = [];
    window.__longtasks = [];
    let last = performance.now();
    const loop = (t) => { window.__frames.push(+(t - last).toFixed(1)); last = t; if (window.__frames.length < 4000) requestAnimationFrame(loop); };
    requestAnimationFrame(loop);
    try {
      const po = new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__longtasks.push(Math.round(e.duration)); });
      po.observe({ entryTypes: ['longtask'] });
    } catch {}
  });
}
async function stats(page) {
  return page.evaluate(() => {
    const f = window.__frames.filter((x) => x > 0 && x < 1000);
    const sorted = [...f].sort((a, b) => a - b);
    const pct = (p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
    return {
      frames: f.length,
      mean: +(f.reduce((a, b) => a + b, 0) / f.length).toFixed(1),
      p50: pct(0.5), p95: pct(0.95), max: sorted[sorted.length - 1],
      over50ms: f.filter((x) => x > 50).length,
      longtaskCount: window.__longtasks.length,
      longtaskMax: window.__longtasks.length ? Math.max(...window.__longtasks) : 0,
    };
  });
}

// ---- Flutter 首屏资源明细 ----
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto(FL, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  const res = await page.evaluate(() => performance.getEntriesByType('resource')
    .map(r => [r.name.split('/').slice(-2).join('/'), Math.round((r.transferSize || 0) / 1024)])
    .sort((a, b) => b[1] - a[1]));
  console.log('FL_RESOURCES_KB', JSON.stringify(res));
  await ctx.close();
}

// ---- Flutter 键入复测（已有编辑器会话流程） ----
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  await page.goto(FL, { waitUntil: 'load' });
  await page.waitForTimeout(7000);
  await page.touchscreen.tap(210, 320);
  await page.waitForTimeout(3000);
  await instrument(page);
  await page.touchscreen.tap(210, 500);
  await page.waitForTimeout(500);
  const tk = Date.now();
  await page.keyboard.type('性能测试输入abcde性能测试输入fghij', { delay: 45 });
  console.log('FL_TYPE2', JSON.stringify({ typeDurMs: Date.now() - tk, ...(await stats(page)) }));
  await ctx.close();
}

// ---- 原版：新建笔记 → 编辑器键入基线 ----
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[orig pageerror]', String(e).slice(0, 160)));
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.screenshot({ path: '/tmp/orig_list.png' });
  await page.touchscreen.tap(210, 245); // 新建笔记卡
  await page.waitForTimeout(2500);
  await page.screenshot({ path: '/tmp/orig_editor.png' });
  await instrument(page);
  await page.touchscreen.tap(210, 400);
  await page.waitForTimeout(500);
  const tk = Date.now();
  await page.keyboard.type('性能测试输入abcde性能测试输入fghij', { delay: 45 });
  console.log('ORIG_TYPE', JSON.stringify({ typeDurMs: Date.now() - tk, ...(await stats(page)) }));
  await ctx.close();
}
await browser.close();
console.log('done');
