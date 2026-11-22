// 背景色同步逐帧采样探针：量测换色/打开/离开/深色四条路径上
// 中心层(#editor-root 计算色)、根层(body/html 计算色)、顶部渐变层
// (#body-before-bg 文本内嵌 rgb) 各自在第几帧到达新色，输出层间帧差。
// 用法: node probe_bgsync_frames.mjs <url>
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
      // 渐变色取 body::before 的计算 backgroundImage（解析 var() 后
      // 的实际 rgba）——注入样式文本现含 var(--mn-root-rgb)，不能
      // 再从文本里抠数字。
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

async function importFixture(page) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/pagebg/fixture.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });
}

async function openMemo(page, title) {
  await page.click(`.list-item:has-text("${title}")`);
  await page.waitForSelector('#editor-root', { timeout: 10000 });
  await page.waitForTimeout(600);
}

async function openBgSheet(page) {
  await page.click('.editor-fab.right');
  await page.waitForSelector('.menu-item', { timeout: 8000 });
  await page.click('.menu-item:has-text("更换背景色")');
  await page.waitForSelector('.bg-dot', { timeout: 8000 });
  await page.waitForTimeout(150);
}

// 分析：每层首次命中目标值的样本下标与相对最早命中层的帧差
function analyze(name, samples, targets) {
  const hits = {};
  for (const [layer, target] of Object.entries(targets)) {
    if (target === undefined) continue;
    const i = samples.findIndex((s) => s[layer] === target);
    hits[layer] = i;
  }
  const found = Object.values(hits).filter((i) => i >= 0);
  const base = found.length ? Math.min(...found) : -1;
  const parts = Object.entries(hits).map(([l, i]) =>
    i < 0 ? `${l}=NEVER` : `${l}=f${i}(${samples[i].t}ms,+${i - base}f)`);
  console.log(`[${name}] n=${samples.length} ${parts.join(' ')}`);
  return hits;
}

async function run(page, fn) {
  await page.evaluate(SAMPLER);
  await page.evaluate(() => window.__frStart());
  await fn();
  await page.waitForTimeout(1100);
  return page.evaluate(() => window.__frStop());
}

// ---------- 浅色 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 700 }, hasTouch: true, colorScheme: 'light' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('pageerror:', String(e)));
  await importFixture(page);

  // 1) 换色@顶部：默认(#FAFAFA) → #d4e8d0
  await openMemo(page, '默认背景备忘');
  await openBgSheet(page);
  let s = await run(page, async () => { await page.click('.bg-dot[style*="d4e8d0"]'); });
  analyze('change@top ->#d4e8d0', s, { root: 'rgb(212, 232, 208)', body: 'rgb(212, 232, 208)', html: 'rgb(212, 232, 208)' });

  // 2) 换色@已滚动：先滚到底让渐变生效（色=d4e8d0），再换 #fff3e0，全程不滚动
  await page.evaluate(() => window.scrollTo(0, 600));
  await page.waitForTimeout(500);
  const pre = await page.evaluate(() => {
    const st = document.getElementById('body-before-bg');
    return { sy: window.scrollY, grad: st ? st.textContent.slice(0, 110) : null };
  });
  console.log('[pre-scroll state]', JSON.stringify(pre));
  await openBgSheet(page);
  s = await run(page, async () => { await page.click('.bg-dot[style*="fff3e0"]'); });
  analyze('change@scrolled ->#fff3e0', s, { root: 'rgb(255, 243, 224)', body: 'rgb(255, 243, 224)', html: 'rgb(255, 243, 224)', gradRgb: '255, 243, 224' });
  const lastGrad = s[s.length - 1]?.gradRgb;
  console.log('  grad final rgb =', lastGrad, lastGrad === '255, 243, 224' ? '(fresh)' : '(STALE!)');

  // 3) 打开路径：列表 → 醒目背景备忘(#FF5722)
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(500);
  s = await run(page, async () => { await page.click('.list-item:has-text("醒目背景备忘")'); });
  analyze('open ->#FF5722', s, { root: 'rgb(255, 87, 34)', body: 'rgb(255, 87, 34)', html: 'rgb(255, 87, 34)' });

  // 4) 离开路径：编辑 → 列表（根色 rgb(242,242,247)）
  await page.waitForTimeout(400);
  s = await run(page, async () => { await page.click('.editor-fab.left'); });
  analyze('leave ->root', s, { body: 'rgb(242, 242, 247)', html: 'rgb(242, 242, 247)', root: null });
  await ctx.close();
}

// ---------- 深色换色 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 700 }, hasTouch: true, colorScheme: 'dark' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('pageerror:', String(e)));
  await importFixture(page);
  await openMemo(page, '默认背景备忘');
  await openBgSheet(page);
  const s = await run(page, async () => { await page.click('.bg-dot[style*="d4e8d0"]'); });
  // 深色终值以各层末帧为准，只看层间到达帧差与终值一致性
  const last = s[s.length - 1];
  console.log('[dark change final]', JSON.stringify(last));
  analyze('dark change ->darkened(d4e8d0)', s, { root: last.root, body: last.body, html: last.html });
  await ctx.close();
}

await browser.close();
