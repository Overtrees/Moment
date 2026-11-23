import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(2600);
await page.click('text=周末看展记录');
await page.waitForTimeout(1300);
const box = await page.evaluate(() => {
  const el = document.querySelectorAll('.editor-fab')[1];
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
});
await page.mouse.click(box.x, box.y);
await page.waitForTimeout(500);
console.log(await page.evaluate(() => {
  const p = document.querySelector('.editor-menu-panel');
  const wrap = p.firstElementChild;
  const cs = getComputedStyle(wrap);
  const rows = [...wrap.children].map((c) => {
    const r = c.getBoundingClientRect();
    const ccs = getComputedStyle(c);
    return c.className.slice(0, 20) + ' top=' + Math.round(r.top) + ' h=' + Math.round(r.height) + ' mt=' + ccs.marginTop + ' mb=' + ccs.marginBottom;
  });
  return 'wrap display=' + cs.display + ' gap=' + cs.rowGap + ' pad=' + cs.padding + ' h=' + Math.round(wrap.getBoundingClientRect().height) + '\n' + rows.join('\n');
}));
await browser.close();
