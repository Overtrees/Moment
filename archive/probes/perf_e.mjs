// E组实测：冷启动首屏 / 编辑器打开 / 键入帧时间（Flutter 8096 vs 原版 8097）
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const FL = 'http://127.0.0.1:8096/';
const ORIG = 'http://127.0.0.1:8097/Moment.html';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });

async function flutterColdStart(run) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  const t0 = Date.now();
  await page.goto(FL, { waitUntil: 'commit' });
  // 轮询：splash 被移除且 flutter-view 出现 = 首帧已渲染
  let tFrame = null;
  while (Date.now() - t0 < 30000) {
    const st = await page.evaluate(() => ({
      splash: !!document.getElementById('app-loading'),
      view: !!document.querySelector('flutter-view'),
    })).catch(() => ({ splash: true, view: false }));
    if (!st.splash && st.view) { tFrame = Date.now() - t0; break; }
    await page.waitForTimeout(50);
  }
  await page.waitForTimeout(1500);
  const timing = await page.evaluate(() => {
    const t = performance.timing;
    const paints = performance.getEntriesByType('paint').map(p => [p.name, Math.round(p.startTime)]);
    return {
      responseEnd: t.responseEnd - t.navigationStart,
      domContentLoaded: t.domContentLoadedEventEnd - t.navigationStart,
      loadEvent: t.loadEventEnd - t.navigationStart,
      paints,
      resources: performance.getEntriesByType('resource').length,
      transferredMB: +(performance.getEntriesByType('resource').reduce((a, r) => a + (r.transferSize || 0), 0) / 1048576).toFixed(2),
    };
  });
  await ctx.close();
  return { run, tFrame, ...timing };
}

async function origColdStart(run) {
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  const t0 = Date.now();
  await page.goto(ORIG, { waitUntil: 'commit' });
  let tItems = null;
  try {
    await page.waitForFunction(() => document.querySelectorAll('.list-item, .memo-item, [class*=list-item]').length > 0, null, { timeout: 20000 });
    tItems = Date.now() - t0;
  } catch { tItems = null; }
  const timing = await page.evaluate(() => {
    const t = performance.timing;
    const paints = performance.getEntriesByType('paint').map(p => [p.name, Math.round(p.startTime)]);
    return {
      responseEnd: t.responseEnd - t.navigationStart,
      domContentLoaded: t.domContentLoadedEventEnd - t.navigationStart,
      loadEvent: t.loadEventEnd - t.navigationStart,
      paints,
      resources: performance.getEntriesByType('resource').length,
      transferredMB: +(performance.getEntriesByType('resource').reduce((a, r) => a + (r.transferSize || 0), 0) / 1048576).toFixed(2),
      bodyText: document.body.innerText.slice(0, 80),
    };
  });
  await ctx.close();
  return { run, tItems, ...timing };
}

// ---- 冷启动各 3 次 ----
for (let i = 1; i <= 3; i++) console.log('FLUTTER', JSON.stringify(await flutterColdStart(i)));
for (let i = 1; i <= 3; i++) console.log('ORIG', JSON.stringify(await origColdStart(i)));

// ---- 编辑器打开 + 键入 ----
{
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true, serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 160)));
  await page.goto(FL, { waitUntil: 'load' });
  await page.waitForTimeout(7000);
  const before = await page.screenshot();
  const t0 = Date.now();
  await page.touchscreen.tap(210, 320); // 列表第一张卡（置顶：装修踩坑清单）
  let tOpen = null;
  while (Date.now() - t0 < 15000) {
    const shot = await page.screenshot();
    if (Buffer.compare(shot, before) !== 0) { tOpen = Date.now() - t0; break; }
    await page.waitForTimeout(50);
  }
  console.log('EDITOR_OPEN_MS', tOpen);
  await page.waitForTimeout(2500);
  // 帧时间记录器 + longtask
  await page.evaluate(() => {
    window.__frames = [];
    window.__longtasks = [];
    let last = performance.now();
    const loop = (t) => { window.__frames.push(+(t - last).toFixed(1)); last = t; if (window.__frames.length < 3000) requestAnimationFrame(loop); };
    requestAnimationFrame(loop);
    try {
      const po = new PerformanceObserver((l) => { for (const e of l.getEntries()) window.__longtasks.push(Math.round(e.duration)); });
      po.observe({ entryTypes: ['longtask'] });
    } catch {}
  });
  // 点入正文末尾并键入
  await page.touchscreen.tap(210, 500);
  await page.waitForTimeout(600);
  const tk = Date.now();
  await page.keyboard.type('性能测试输入abcde性能测试输入fghij', { delay: 45 });
  const typeDur = Date.now() - tk;
  await page.waitForTimeout(800);
  const stats = await page.evaluate(() => {
    const f = window.__frames.filter((x) => x > 0 && x < 1000);
    const sorted = [...f].sort((a, b) => a - b);
    const pct = (p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
    return {
      frames: f.length,
      mean: +(f.reduce((a, b) => a + b, 0) / f.length).toFixed(1),
      p50: pct(0.5), p95: pct(0.95), max: sorted[sorted.length - 1],
      over25ms: f.filter((x) => x > 25).length,
      over50ms: f.filter((x) => x > 50).length,
      longtasks: window.__longtasks,
    };
  });
  console.log('TYPING', JSON.stringify({ typeDurMs: typeDur, chars: 20, ...stats }));
  await ctx.close();
}
await browser.close();
console.log('done');
