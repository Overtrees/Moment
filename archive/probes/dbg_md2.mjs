import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8096/', { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
const dump = async (tag) => console.log(tag, await page.evaluate(() => {
  const ae = document.activeElement;
  return {
    ae: ae ? (ae.dataset?.btype + '|' + (ae.innerText || '').slice(0, 40)) : 'none',
    blocks: [...document.querySelectorAll('.detail [data-bid]')].map((e) => e.dataset.btype + ':' + (e.innerText || '').slice(0, 24)),
  };
}));
// 模拟 W3 第 3 节结尾：在首段末尾回车出新块并打字（焦点在新块末尾）
await page.click('.detail .ed-line >> nth=0');
await page.evaluate(() => {
  const el = document.querySelector('.detail .ed-line');
  el.focus();
  const r = document.createRange();
  r.selectNodeContents(el);
  r.collapse(false);
  const s = getSelection();
  s.removeAllRanges();
  s.addRange(r);
});
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await dump('AFTER ENTER');
await page.keyboard.type('/');
await page.waitForSelector('.slash-panel .slash-row', { timeout: 8000 });
await page.click('.slash-panel .slash-row[data-act="bulletList"]');
await page.waitForTimeout(500);
await dump('AFTER CONVERT');
await page.keyboard.press('ControlOrMeta+a');
await page.keyboard.type('- 列表项一');
await page.waitForTimeout(300);
await dump('AFTER LINE1');
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await dump('AFTER ENTER2');
await page.keyboard.type('- 列表项二');
await page.waitForTimeout(300);
await dump('AFTER LINE2');
await browser.close();
