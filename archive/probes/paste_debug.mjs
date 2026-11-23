import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
page.on('pageerror', e => console.log('PAGEERROR', String(e)));
page.on('console', m => { if (m.type() === 'error') console.log('CONSOLE', m.text().slice(0, 160)); });
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200);
await page.waitForTimeout(2000);
await page.mouse.click(60, 118);
await page.waitForTimeout(600);
const hookState = await page.evaluate(() => ({
  hasHook: typeof window.__mynotePasteText !== 'undefined',
}));
console.log('HOOK:', JSON.stringify(hookState));
await page.evaluate(() => {
  const ev = new Event('paste', { bubbles: true, cancelable: true });
  Object.defineProperty(ev, 'clipboardData', { value: { getData: (f) => f === 'text/plain' ? 'https://example.com/article' : '', files: [] } });
  document.dispatchEvent(ev);
});
await page.waitForTimeout(2500);
const st = await page.evaluate(() => ({ text: window.__mynotePasteText, n: window.__mynotePasteImageCount }));
console.log('AFTER PASTE:', JSON.stringify(st));
await page.mouse.click(24, 42);
await page.waitForTimeout(1000);
await page.mouse.click(330, 42);
await page.waitForTimeout(1000);
await page.mouse.click(200, 140);
await page.waitForTimeout(1000);
await page.screenshot({ path: '/tmp/paste-debug-log.png' });
await browser.close();
