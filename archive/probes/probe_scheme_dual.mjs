// 双边主题翻转量测：原版 vs Rust 版，浅→深切换前后量测玻璃胶囊
// computed style（bg / backdrop-filter / radius），并以 expando 标记
// 验证翻转后节点是否被重挂载（标记丢失 = 新节点）。
// 用法: node /tmp/probe_scheme_dual.mjs <rustBase> <origBase>
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = process.argv[2] || 'http://localhost:8211/';
const ORIG = process.argv[3] || 'http://localhost:8212/Moment.html';

const MEASURE = `() => {
  const pick = (sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const cs = getComputedStyle(el);
    return {
      bg: cs.backgroundColor,
      bf: cs.backdropFilter || cs.webkitBackdropFilter || '',
      br: cs.borderTopLeftRadius,
      marked: !!el.__mnMark,
    };
  };
  return {
    trigger: pick('.glass-search-trigger'),
    panel: pick('.glass-search-panel'),
    compact: pick('.page-title.compact'),
    avatarDiv: pick('.page-title > div'),
    avatarImg: !!document.querySelector('.page-title > img'),
    listItem: pick('.list-item'),
    schemeDark: window.matchMedia('(prefers-color-scheme: dark)').matches,
  };
}`;

const MARK = `() => {
  for (const sel of ['.glass-search-trigger', '.glass-search-panel', '.page-title.compact', '.page-title > div', '.list-item']) {
    const el = document.querySelector(sel);
    if (el) el.__mnMark = true;
  }
}`;

async function run(browser, name, base, shotPrefix) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log(`[${name}] pageerror:`, String(e).slice(0, 200)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.emulateMedia({ colorScheme: 'light' });
  await page.waitForTimeout(400);
  const light1 = await page.evaluate(`(${MEASURE})()`);
  await page.evaluate(`(${MARK})()`);
  await page.screenshot({ path: `/tmp/${shotPrefix}-light.png` });
  // 打开搜索面板量一次（面板是第四胶囊之一）
  const trig = await page.$('.glass-search-trigger');
  if (trig) { await trig.tap().catch(() => {}); await page.waitForTimeout(600); }
  const lightPanel = await page.evaluate(`(${MEASURE})()`);
  await page.evaluate(`(${MARK})()`);
  // 翻到深色
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.waitForTimeout(900);
  const dark1 = await page.evaluate(`(${MEASURE})()`);
  await page.screenshot({ path: `/tmp/${shotPrefix}-dark.png` });
  // 再翻回浅色，验双向
  await page.emulateMedia({ colorScheme: 'light' });
  await page.waitForTimeout(900);
  const light2 = await page.evaluate(`(${MEASURE})()`);
  console.log(`\n===== ${name} =====`);
  console.log('light(初始):', JSON.stringify(light1));
  console.log('light(面板开):', JSON.stringify(lightPanel));
  console.log('dark(翻转后):', JSON.stringify(dark1));
  console.log('light(翻回):', JSON.stringify(light2));
  await ctx.close();
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
await run(browser, 'RUST', RUST, 'dual-rust');
await run(browser, 'ORIG', ORIG, 'dual-orig');
await browser.close();
