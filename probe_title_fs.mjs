import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8100/', { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('新建'));
  if (el) el.click();
});
await page.waitForSelector('#editor-root', { timeout: 10000 });
await page.waitForTimeout(600);
const snap = () => page.evaluate(() => {
  const t = document.querySelector('#editor-title-text');
  return { style: t?.getAttribute('style') || '', fs: t ? getComputedStyle(t).fontSize : '', cls: t?.className || '', cap: document.querySelector('.editor-title-capsule')?.className || '' };
});
console.log('EMPTY', JSON.stringify(await snap()));
await page.evaluate(() => { const t = document.querySelector('#editor-title-text'); t?.focus(); });
await page.keyboard.type('一二三四五六');
await page.waitForTimeout(400);
console.log('6CHARS_EDITING', JSON.stringify(await snap()));
await page.keyboard.type('七八九十甲乙');
await page.waitForTimeout(400);
console.log('12CHARS_EDITING', JSON.stringify(await snap()));
await page.evaluate(() => document.querySelector('#editor-title-text')?.blur());
await page.waitForTimeout(600);
console.log('12CHARS_BLURRED', JSON.stringify(await snap()));
await browser.close();
