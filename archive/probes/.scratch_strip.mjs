// 取证复现：生产逐字节 dist(cbf7e480c7) 上量备份确认模态开/关两态的根背景链
import { chromium } from 'playwright-core';

const url = 'http://localhost:8317/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));

const snapshot = () => page.evaluate(() => {
  const de = document.documentElement;
  const cs = getComputedStyle(de);
  const s = document.querySelector('.backup-modal-scrim');
  let scrim = null;
  if (s) {
    const r = s.getBoundingClientRect();
    scrim = { top: r.top, left: r.left, right: r.right, bottom: r.bottom, w: r.width, h: r.height,
              bg: getComputedStyle(s).backgroundColor };
  }
  return {
    innerW: innerWidth, innerH: innerHeight,
    rootVar: cs.getPropertyValue('--mn-root-bg').trim(),
    rootRgbVar: cs.getPropertyValue('--mn-root-rgb').trim(),
    htmlBg: cs.backgroundColor,
    bodyBg: getComputedStyle(document.body).backgroundColor,
    scrim,
  };
});

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .glass-search-trigger', { timeout: 20000 }).catch(() => {});
await page.waitForTimeout(1200);

// 进设置页 → 备份与恢复
await page.$eval('h1.page-title', (e) => e.click()).catch(async () => {
  await page.click('.glass-search-trigger').catch(() => {});
});
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('.backup-row', { timeout: 8000 });
await page.waitForTimeout(400);
console.log('CLOSED :', JSON.stringify(await snapshot()));

// 打开确认导出底表
await page.click('.backup-row:has-text("导出备份")');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.waitForTimeout(600); // 等 250ms 进场动画落定
console.log('OPEN   :', JSON.stringify(await snapshot()));

// 关闭后再量（恢复性）
await page.click('.backup-modal .backup-btn.secondary');
await page.waitForFunction(() => !document.querySelector('.backup-modal'), { timeout: 8000 });
await page.waitForTimeout(400);
console.log('CLOSED2:', JSON.stringify(await snapshot()));

await browser.close();
