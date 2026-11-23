import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
for (const [label, base, open] of [['ORIG', 'http://localhost:8097/Moment.html', 'o'], ['RUST', 'http://localhost:8096/', 'r']]) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForTimeout(2600);
  if (open === 'o') await page.click('text=周末看展记录');
  else { await page.waitForSelector('.list-item', { timeout: 20000 }); await page.click('.list-item:has-text("周末看展记录") .item-title-text'); }
  await page.waitForTimeout(1300);
  const box = await page.evaluate(() => {
    const el = document.querySelectorAll('.editor-fab')[1];
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  await page.mouse.click(box.x, box.y);
  await page.waitForTimeout(500);
  console.log(label, await page.evaluate(() => {
    const p = document.querySelector('.editor-menu-panel');
    if (!p) return 'no menu';
    return [...p.querySelectorAll('button, [class*=row], [class*=item]')].map((c) => c.className.slice(0, 26) + ' h=' + Math.round(c.getBoundingClientRect().height) + ' ' + (c.innerText || '').slice(0, 22).replace(/\n/g, '/')).join(' || ');
  }));
  await ctx.close();
}
await browser.close();
