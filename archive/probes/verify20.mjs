import { chromium } from 'playwright-core';
import fs from 'node:fs';

const OUT = '/tmp/v20';
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await chromium.launchPersistentContext('/tmp/mynote-test-profile', {
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  viewport: { width: 420, height: 900 },
  hasTouch: true,
  args: ['--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=angle', '--use-angle=swiftshader'],
});
const page = browser.pages()[0] || (await browser.newPage());
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await sleep(14000);
await page.screenshot({ path: `${OUT}/1-list.png` });
console.log('booted');

// settings via avatar
await page.touchscreen.tap(52, 84);
await sleep(1800);
await page.screenshot({ path: `${OUT}/2-settings.png` });
// backup row
await page.touchscreen.tap(210, 322);
await sleep(1800);
await page.screenshot({ path: `${OUT}/3-backup.png` });

// import: file chooser armed before tapping the import row
const [chooser] = await Promise.all([
  page.waitForEvent('filechooser', { timeout: 15000 }),
  page.touchscreen.tap(210, 386),
]);
await chooser.setFiles('/tmp/memos80.zip');
await sleep(1500);
await page.screenshot({ path: `${OUT}/4-confirm.png` });
console.log('file chosen');
await browser.close();
console.log('stage1 done');
