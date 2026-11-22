// 原版编辑器多视口度量（真实点击版）
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const VIEWPORTS = [[393, 852], [852, 393], [768, 1024], [1280, 800]];
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
for (const [w, h] of VIEWPORTS) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto('http://localhost:8107/Moment.html', { waitUntil: 'load', timeout: 20000 });
  await page.waitForTimeout(2000);
  const card = page.locator('.container .list-item, .container .img-card').first();
  await card.click({ timeout: 5000 }).catch((e) => console.log(`${w}x${h} ORIG click fail ${String(e).slice(0, 80)}`));
  await page.waitForTimeout(1200);
  const ed = await page.evaluate(() => {
    const body = document.querySelector('.editor-body');
    if (!body) return { err: 'no .editor-body', html: document.body.innerHTML.slice(0, 120) };
    const cs = getComputedStyle(body);
    const spread = document.querySelector('.editor-spread');
    const cols = document.querySelectorAll('.editor-column');
    return {
      columnCount: cs.columnCount, display: cs.display, bodyW: body.clientWidth,
      spreadMaxW: spread ? getComputedStyle(spread).maxWidth : '-',
      indepCols: cols.length,
      h1Size: (() => { const h1 = body.querySelector('h1'); return h1 ? getComputedStyle(h1).fontSize : '-'; })(),
    };
  });
  console.log(`${w}x${h} ORIG EDIT ${JSON.stringify(ed)}`);
  await ctx.close();
}
await browser.close();
console.log('DONE');
