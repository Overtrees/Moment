// 深色模式下两边导出面板关键色值对照（令牌同源性抽查）
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
for (const app of ['orig', 'rust']) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'dark' });
  const page = await ctx.newPage();
  await page.goto(app === 'orig' ? 'http://localhost:8109/Moment.html' : 'http://localhost:8108/', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  if (app === 'orig') await page.locator('.memo-card, .list-item, .memo-item, [data-memo-id]').first().click();
  else await page.locator('.img-card, .list-item').first().click();
  await page.waitForSelector('.editor-fab.right', { timeout: 15000 });
  await page.waitForTimeout(600);
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  await page.locator('.editor-menu-panel button', { hasText: '导出笔记' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(600);
  const d = await page.evaluate(() => {
    const p = document.querySelector('.editor-export-panel');
    const cs = getComputedStyle(p);
    const label = p.querySelector('.editor-export-choice span span') || p.querySelector('.export-label');
    return {
      bg: cs.backgroundColor,
      border: cs.borderTopColor,
      color: cs.color,
      labelColor: label ? getComputedStyle(label).color : null,
    };
  });
  console.log(app, JSON.stringify(d));
  await ctx.close();
}
await browser.close();
