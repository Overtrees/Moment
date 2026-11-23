// 两边编辑器正文度量探针：字号/行高/字距/段落宽/字体栈
import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function probe(base, openFn, label) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await openFn(page);
  const m = await page.evaluate(() => {
    const all = Array.from(document.querySelectorAll('*'));
    const leaf = all.find((e) => e.children.length === 0 && (e.textContent || '').includes('今天去了'));
    if (!leaf) return 'not found';
    let p = leaf;
    while (p && !(p.textContent || '').includes('站久了会忘记时间')) p = p.parentElement;
    const target = p || leaf;
    const cs = getComputedStyle(target);
    const r = target.getBoundingClientRect();
    return {
      tag: target.tagName + '.' + target.className,
      fontSize: cs.fontSize, lineHeight: cs.lineHeight, letterSpacing: cs.letterSpacing,
      fontFamily: cs.fontFamily.slice(0, 80), fontWeight: cs.fontWeight,
      width: Math.round(r.width), left: Math.round(r.left),
    };
  });
  console.log(label, JSON.stringify(m));
  await ctx.close();
}

await probe('http://localhost:8097/Moment.html', async (page) => {
  await page.waitForTimeout(5000);
  await page.getByText('周末看展记录', { exact: true }).first().click();
  await page.waitForTimeout(2500);
}, 'ORIG');

await probe('http://localhost:8096/', async (page) => {
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.click('.list-item:has-text("周末看展记录") .item-title-text');
  await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
  await page.waitForTimeout(600);
}, 'RUST');

await browser.close();
