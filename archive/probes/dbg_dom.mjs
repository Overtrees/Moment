import { chromium } from 'playwright-core';
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8096/', { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForTimeout(700);
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForTimeout(700);
await page.setInputFiles('#file-import', '/tmp/allblocks.zip');
await page.waitForTimeout(1000);
await page.click('.backup-modal .backup-btn.primary');
await page.waitForTimeout(1500);
await page.click('.editor-fab.left');
await page.waitForTimeout(800);
await page.click('.editor-fab.left');
await page.waitForTimeout(1000);
console.log(await page.evaluate(() => {
  const all = [...document.querySelectorAll('*')].filter((e) => e.children.length === 0 && e.innerText && e.innerText.includes('全块渲染测试'));
  return all.map((e) => {
    let chain = [];
    let n = e;
    for (let i = 0; i < 6 && n; i++) { chain.push(n.tagName + '.' + String(n.className).slice(0, 30)); n = n.parentElement; }
    return chain.join(' < ');
  }).join('\n');
}));
await browser.close();
