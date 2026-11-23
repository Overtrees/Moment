import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
for (const [w, name] of [[1280, '31-wide-1280.png'], [1024, '32-wide-1024.png']]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: 800 } });
  const page = await ctx.newPage();
  await page.goto('http://127.0.0.1:8095/', { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: process.env.HOME + '/workspace/mynote-shots-round2/' + name });
  await ctx.close();
}
await browser.close();
console.log('done');
