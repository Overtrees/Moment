// 热点扫描探针（调优续推线·任务 3）：300 篇压测集，暖态下走
// 主要旅程（滚动/展开/搜索/编辑器温开+输入/导出），采集每段
// longtask 明细（>50ms），只认实测有据的热点。
// 用法：node perf_scan.mjs <base>
import { chromium } from 'playwright-core';

const base = process.argv[2];
const ZIP = '/tmp/big300.zip';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const out = {};

await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
// 导入 300 篇
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 15000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 15000 });
const ti0 = Date.now();
await page.setInputFiles('#file-import', ZIP);
await page.waitForSelector('.backup-modal', { timeout: 15000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 30000 });
out.importMs = Date.now() - ti0;
await page.reload({ waitUntil: 'load' });
await page.waitForFunction(() => {
  return [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')]
    .some((e) => e.textContent.includes('压测笔记'));
}, null, { timeout: 60000 });
await page.waitForTimeout(800);

// longtask 收集器（分段打标）
await page.evaluate(() => {
  window.__lt = { tag: 'boot', segs: {} };
  try {
    const po = new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        const t = window.__lt.tag;
        (window.__lt.segs[t] = window.__lt.segs[t] || []).push(Math.round(e.duration));
      }
    });
    po.observe({ entryTypes: ['longtask'] });
  } catch (_) {}
});
const setTag = (t) => page.evaluate((t) => { window.__lt.tag = t; }, t);

// 旅程 1：列表滚动（滚轮到底再回顶）
await setTag('scroll');
await page.mouse.move(196, 426);
for (let i = 0; i < 12; i++) { await page.mouse.wheel(0, 1400); await page.waitForTimeout(120); }
for (let i = 0; i < 12; i++) { await page.mouse.wheel(0, -1400); await page.waitForTimeout(120); }
await page.waitForTimeout(600);

// 旅程 2：展开一个折叠组
await setTag('expand');
const hasExpand = await page.evaluate(() => !!document.querySelector('.card-expand-wrapper .expand-btn'));
if (hasExpand) {
  await page.click('.card-expand-wrapper .expand-btn');
  await page.waitForTimeout(1200);
}
out.hasExpand = hasExpand;

// 旅程 3：搜索
await setTag('search');
await page.evaluate(() => document.querySelector('.glass-search-trigger')?.click());
await page.waitForSelector('.glass-search-input', { timeout: 10000 });
await page.evaluate(() => document.querySelector('.glass-search-input')?.focus());
const ts0 = Date.now();
await page.keyboard.type('ZEBRA', { delay: 30 });
// 收敛判据：卡片只剩匹配篇（+composer）。结果卡渲染的是常
// 规摘要而非命中上下文，「独特关键词」不会进 innerText。
await page.waitForFunction(() => {
  const cards = [...document.querySelectorAll('.list-item, .img-card')];
  return cards.length <= 2 && cards.some((e) => e.textContent.includes('压测笔记'));
}, null, { timeout: 15000 }).catch(() => {});
out.searchMs = Date.now() - ts0;
await page.keyboard.press('Escape');
await page.waitForTimeout(600);

// 旅程 4：编辑器温开 + 输入（折叠组首卡先点一次展开，不计时）
await page.evaluate(() => {
  const card = [...document.querySelectorAll('.list-item, .img-card')]
    .find((e) => e.textContent.includes('压测笔记'));
  if (card && card.closest('.card-expand-wrapper')) card.click();
});
await page.waitForTimeout(800);
await setTag('open');
const to0 = Date.now();
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item, .img-card')]
    .find((e) => e.textContent.includes('压测笔记'));
  el && el.click();
});
await page.waitForSelector('.editor-body', { timeout: 20000 });
out.openMs = Date.now() - to0;
await page.waitForTimeout(500);
await setTag('type');
// md 段落初始是预览态：先点预览进源码编辑态，等 [data-bid] 出现
await page.evaluate(() => document.querySelector('.md-hit .md-preview-inline, .md-hit')?.click());
await page.waitForSelector('.editor-body [data-bid]', { timeout: 10000 });
await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  if (el) { el.focus(); const r = document.createRange(); r.selectNodeContents(el); r.collapse(false); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
});
const tt0 = Date.now();
await page.keyboard.type('延迟测试文字输入', { delay: 20 });
await page.waitForFunction(() => document.body.innerText.includes('延迟测试文字输入'), null, { timeout: 10000 }).catch(() => {});
out.typeMs = Date.now() - tt0;
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.waitForTimeout(500);

// 旅程 5：导出（下载事件计时；失败只记录不中断）
await setTag('export');
try {
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  // 导出备份行（.backup-row 首个）→ 确认底表 → primary → 下载
  await page.evaluate(() => document.querySelector('.backup-row')?.click());
  await page.waitForSelector('.backup-modal .backup-btn.primary', { timeout: 15000 });
  const te0 = Date.now();
  const dlPromise = page.waitForEvent('download', { timeout: 25000 }).catch(() => null);
  await page.click('.backup-modal .backup-btn.primary');
  const dl = await dlPromise;
  out.exportMs = dl ? Date.now() - te0 : null;
} catch (e) {
  out.exportError = String(e).slice(0, 120);
  out.exportState = await page.evaluate(() => document.body.innerText.slice(0, 150).replace(/\n/g, ' | ')).catch(() => '');
}

out.longtasks = await page.evaluate(() => window.__lt.segs);
console.log(JSON.stringify(out, null, 1));
await browser.close();
