// 探针 2：列表紧凑头/搜索面板 + 编辑器背景色底表，原版 vs Rust。
import { chromium } from 'playwright-core';
const [origBase, rustBase] = process.argv.slice(2);
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});

async function run(label, base, isOrig) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForTimeout(2800);
  if (!isOrig) await page.waitForSelector('.list-item', { timeout: 20000 });
  const out = { label };

  // 紧凑头：不同 scrollY 下标题区采样
  out.header = await page.evaluate(async () => {
    const res = [];
    const title = document.querySelector('h1.page-title, .page-title');
    for (const y of [0, 15, 30, 60, 120]) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 120));
      const cs = title ? getComputedStyle(title) : null;
      const search = document.querySelector('.search-pill, .search-trigger, [class*=search]');
      res.push({
        y,
        titleOpacity: cs ? cs.opacity : null,
        titleH: title ? Math.round(title.getBoundingClientRect().height) : null,
        searchCls: search ? search.className.slice(0, 30) : null,
      });
    }
    window.scrollTo(0, 0);
    return res;
  });

  // 打开编辑器 → 菜单 → 更换背景色 → 底表采样
  if (isOrig) await page.click('text=周末看展记录');
  else await page.click('.list-item:has-text("周末看展记录") .item-title-text');
  await page.waitForTimeout(1400);
  const fab = await page.evaluate(() => {
    const el = document.querySelectorAll('.editor-fab')[1];
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  await page.mouse.click(fab.x, fab.y);
  await page.waitForTimeout(500);
  await page.evaluate(() => {
    const rows = [...document.querySelectorAll('.editor-menu-panel button, .editor-menu-panel .menu-item')];
    const t = rows.find((e) => (e.innerText || '').includes('更换背景色'));
    if (t) t.click();
  });
  await page.waitForTimeout(600);
  out.bgSheet = await page.evaluate(() => {
    const el = document.querySelector('.bg-sheet') || [...document.querySelectorAll('div')].find((d) => (d.innerText || '').startsWith('背景颜色'));
    if (!el) return null;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return { bottom: Math.round(innerHeight - r.bottom), w: Math.round(r.width), radius: cs.borderRadius, anim: cs.animationName, animDur: cs.animationDuration, pad: cs.padding };
  });
  console.log(JSON.stringify(out, null, 1));
  await ctx.close();
}

await run('ORIG', origBase, true);
await run('RUST', rustBase, false);
await browser.close();
