// color-scheme 调优评估探针（Chromium 口径）：
// 同一 dist 三方对照——原版(无声明) / Rust 现行(无声明) / Rust 注入 color-scheme:light dark。
// 量测：根 used scheme、裸原生控件 UA 计算色（代表一切未样式化原生面）、
// 真实控件（搜索框 ::placeholder）、经典滚动条宽度与右缘像素条颜色。
// 用法：node probe_colorscheme.mjs  （需 8213=Rust dist、8214=原版仓库根 已起服务）
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = 'http://localhost:8213/';
const ORIG = 'http://localhost:8214/Moment.html';

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function bareMeasure(page) {
  return page.evaluate(() => {
    const out = {};
    out.rootColorScheme = getComputedStyle(document.documentElement).colorScheme;
    out.sbWidth = window.innerWidth - document.documentElement.clientWidth;
    const host = document.createElement('div');
    host.innerHTML = `
      <input id="b-text" type="text" placeholder="ph">
      <input id="b-check" type="checkbox" checked>
      <input id="b-radio" type="radio" checked>
      <select id="b-select"><option>opt</option></select>
      <input id="b-range" type="range">
      <input id="b-date" type="date">
      <textarea id="b-ta" placeholder="ph"></textarea>
      <button id="b-btn">btn</button>`;
    document.body.appendChild(host);
    const cs = (id, pseudo) => {
      const el = document.getElementById(id);
      const s = getComputedStyle(el, pseudo || undefined);
      return { bg: s.backgroundColor, color: s.color, border: s.borderTopColor };
    };
    out.bare = {
      text: cs('b-text'), textPh: cs('b-text', '::placeholder'),
      check: cs('b-check'), radio: cs('b-radio'), select: cs('b-select'),
      range: cs('b-range'), date: cs('b-date'), ta: cs('b-ta'), btn: cs('b-btn'),
    };
    const tall = document.createElement('div');
    tall.style.height = '4000px';
    document.body.appendChild(tall);
    out.sbWidthTall = window.innerWidth - document.documentElement.clientWidth;
    return out;
  });
}

// 截右缘 16px 条并在独立页用 canvas 读像素均值（滚动条轨/块的综合色）
async function stripColor(page, width, height) {
  const buf = await page.screenshot({ clip: { x: width - 16, y: 0, width: 16, height } });
  const b64 = buf.toString('base64');
  const p2 = await browser.newPage();
  const res = await p2.evaluate(async (b64) => {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = 'data:image/png;base64,' + b64; });
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    c.getContext('2d').drawImage(img, 0, 0);
    const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
    let r = 0, g = 0, b = 0, n = 0;
    for (let i = 0; i < d.length; i += 4) { r += d[i]; g += d[i + 1]; b += d[i + 2]; n++; }
    return `rgb(${Math.round(r / n)},${Math.round(g / n)},${Math.round(b / n)})`;
  }, b64);
  await p2.close();
  return res;
}

async function run(label, url, { scheme = 'dark', inject = false, realControls = false } = {}) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, colorScheme: scheme });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(3000);
  if (inject) {
    // 注：addInitScript 注入的 style 在本应用页面不存活（实测），改加载后注入；
    // 全站无其他 color-scheme 声明与之竞争，级联结果与写进 tokens.css 等价。
    await page.evaluate(() => {
      const s = document.createElement('style');
      s.id = 'cs-probe';
      s.textContent = ':root{color-scheme:light dark}';
      document.head.appendChild(s);
    });
    await page.waitForTimeout(400);
  }
  const data = await bareMeasure(page);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(250);
  data.strip = await stripColor(page, 1280, 800);
  let real = null;
  if (realControls) {
    // 列表页真实控件：打开搜索，量 .glass-search-input 的字色与 ::placeholder 色
    await page.setViewportSize({ width: 393, height: 852 });
    await page.waitForTimeout(600);
    try {
      await page.click('.glass-search-trigger', { timeout: 5000 });
      await page.waitForSelector('.glass-search-input', { timeout: 5000 });
      real = await page.evaluate(() => {
        const inp = document.querySelector('.glass-search-input');
        const s = getComputedStyle(inp);
        const ph = getComputedStyle(inp, '::placeholder');
        return { found: true, color: s.color, bg: s.backgroundColor, phColor: ph.color, phOpacity: ph.opacity };
      });
    } catch (e) {
      real = { found: false, why: String(e).slice(0, 120) };
    }
  }
  console.log(`\n### ${label} (scheme=${scheme}${inject ? ', +color-scheme' : ''})`);
  console.log(JSON.stringify({ root: data.rootColorScheme, sbW: data.sbWidthTall, strip: data.strip, bare: data.bare, real, errors: errors.length }, null, 1));
  await ctx.close();
  return data;
}

await run('原版 Moment.html', ORIG, {});
await run('Rust 现行', RUST, { realControls: true });
await run('Rust 注入', RUST, { inject: true, realControls: true });
await run('Rust 现行 浅色', RUST, { scheme: 'light' });
await run('Rust 注入 浅色', RUST, { scheme: 'light', inject: true });
await browser.close();
console.log('\nDONE');
