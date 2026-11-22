// 背景色同步逐帧采样探针 2：大文档（300 段）负载下换色层间帧差，
// 以及已滚动（渐变生效）状态下换色后渐变的收敛/陈旧检查。
// 用法: node probe_bgsync_frames2.mjs <url>
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8221/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

const SAMPLER = () => {
  window.__fr = { on: false, samples: [] };
  window.__frStart = () => {
    window.__fr.samples = [];
    window.__fr.on = true;
    const t0 = performance.now();
    const loop = () => {
      if (!window.__fr.on) return;
      const root = document.getElementById('editor-root');
      const st = document.getElementById('body-before-bg');
      const bi = getComputedStyle(document.body, '::before').backgroundImage;
      const gm = bi ? bi.match(/rgba\((\d+,\s*\d+,\s*\d+),/) : null;
      window.__fr.samples.push({
        t: Math.round(performance.now() - t0),
        root: root ? getComputedStyle(root).backgroundColor : null,
        body: getComputedStyle(document.body).backgroundColor,
        html: getComputedStyle(document.documentElement).backgroundColor,
        gradRgb: gm ? gm[1] : (st ? 'transparent' : null),
        sy: Math.round(window.scrollY || 0),
      });
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  };
  window.__frStop = () => { window.__fr.on = false; return window.__fr.samples; };
};

async function importFixture(page, zip) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });
}

function analyze(name, samples, targets) {
  const hits = {};
  for (const [layer, target] of Object.entries(targets)) {
    if (target === undefined) continue;
    hits[layer] = samples.findIndex((s) => s[layer] === target);
  }
  const found = Object.values(hits).filter((i) => i >= 0);
  const base = found.length ? Math.min(...found) : -1;
  const parts = Object.entries(hits).map(([l, i]) =>
    i < 0 ? `${l}=NEVER` : `${l}=f${i}(${samples[i].t}ms,+${i - base}f)`);
  console.log(`[${name}] n=${samples.length} ${parts.join(' ')}`);
  return hits;
}

async function run(page, fn, waitMs = 1400) {
  await page.evaluate(SAMPLER);
  await page.evaluate(() => window.__frStart());
  await fn();
  await page.waitForTimeout(waitMs);
  return page.evaluate(() => window.__frStop());
}

const ctx = await browser.newContext({ viewport: { width: 393, height: 700 }, hasTouch: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('pageerror:', String(e)));
await importFixture(page, '/tmp/pagebg/fixture_big.zip');

// 打开大文档（自带 #FF5722）
let s = await run(page, async () => { await page.click('.list-item:has-text("大文档背景备忘")'); }, 1800);
analyze('open big ->#FF5722', s, { root: 'rgb(255, 87, 34)', body: 'rgb(255, 87, 34)', html: 'rgb(255, 87, 34)' });
await page.waitForSelector('#editor-root', { timeout: 10000 });
await page.waitForTimeout(600);

// 换色@顶部（大文档负载）：#FF5722 → #d4e8d0
await page.click('.editor-fab.right');
await page.waitForSelector('.menu-item', { timeout: 8000 });
await page.click('.menu-item:has-text("更换背景色")');
await page.waitForSelector('.bg-dot', { timeout: 8000 });
await page.waitForTimeout(150);
s = await run(page, async () => { await page.click('.bg-dot[style*="d4e8d0"]'); }, 1600);
analyze('big change@top ->#d4e8d0', s, { root: 'rgb(212, 232, 208)', body: 'rgb(212, 232, 208)', html: 'rgb(212, 232, 208)', gradRgb: '212, 232, 208' });

// 滚动让渐变生效并稳定（色应为 d4e8d0）
await page.evaluate(() => window.scrollTo(0, 500));
await page.waitForTimeout(600);
const pre = await page.evaluate(() => {
  return { sy: window.scrollY, grad: getComputedStyle(document.body, '::before').backgroundImage.slice(0, 130) };
});
console.log('[pre-scroll]', JSON.stringify(pre));

// 换色@已滚动：#d4e8d0 → #fff3e0，点击后不滚动，观察渐变收敛
await page.click('.editor-fab.right');
await page.waitForSelector('.menu-item', { timeout: 8000 });
await page.click('.menu-item:has-text("更换背景色")');
await page.waitForSelector('.bg-dot', { timeout: 8000 });
await page.waitForTimeout(150);
s = await run(page, async () => { await page.click('.bg-dot[style*="fff3e0"]'); }, 1800);
analyze('big change@scrolled ->#fff3e0', s, { root: 'rgb(255, 243, 224)', body: 'rgb(255, 243, 224)', html: 'rgb(255, 243, 224)', gradRgb: '255, 243, 224' });
console.log('  grad final =', s[s.length - 1]?.gradRgb);

await ctx.close();
await browser.close();
