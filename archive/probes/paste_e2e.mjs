import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
await page.goto('http://127.0.0.1:8095/', { waitUntil: 'networkidle' });
await page.waitForTimeout(6000);
await page.mouse.click(150, 200);
await page.waitForTimeout(2000);
await page.mouse.click(60, 118); // 正文首段
await page.waitForTimeout(600);
async function firePaste(text) {
  await page.evaluate((t) => {
    const ev = new Event('paste', { bubbles: true, cancelable: true });
    Object.defineProperty(ev, 'clipboardData', { value: { getData: (f) => f === 'text/plain' ? t : '', files: [] } });
    document.dispatchEvent(ev);
  }, text);
}
await firePaste('https://example.com/article');
await page.waitForTimeout(3500); // 等解析回填（沙箱无外网 → error 态也算通路）
await page.screenshot({ path: '/tmp/paste-card.png' });
console.log('PAGE_ERRORS:', errors.length, errors.slice(0,1).join(''));
await browser.close();
