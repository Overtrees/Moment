import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
await page.goto('http://localhost:8097/Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(1500);
console.log('LIST', await page.evaluate(() => document.body.innerText.slice(0,500)));
await page.getByText('周末看展记录', { exact: true }).first().click();
await page.waitForTimeout(2500);
const info = await page.evaluate(() => {
  const all = [...document.querySelectorAll('.editor-body *')];
  const hit = all.find(e => (e.textContent || '').includes('所谓的边界'));
  const chain = [];
  let n = hit;
  while (n && chain.length < 6) { chain.push({tag:n.tagName, cls:n.className, ce:n.getAttribute('contenteditable'), md:n.getAttribute('data-mdtext'), bid:n.getAttribute('data-blockid'), html:n.outerHTML?.slice(0,500)}); n = n.parentElement; }
  return { chain, body: document.querySelector('.editor-body')?.innerHTML.slice(0,3000) };
});
console.log(JSON.stringify(info, null, 2));
await browser.close();
