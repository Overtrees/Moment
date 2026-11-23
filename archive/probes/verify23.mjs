import { chromium } from 'playwright-core';
import fs from 'node:fs';

const OUT = '/tmp/v21';
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
await sleep(13000);

await page.touchscreen.tap(52, 84);
await sleep(1600);
await page.touchscreen.tap(210, 322);
await sleep(1600);
const [chooser] = await Promise.all([
  page.waitForEvent('filechooser', { timeout: 15000 }),
  page.touchscreen.tap(210, 386),
]);
await chooser.setFiles('/tmp/memos84.zip');
await sleep(1500);
await page.touchscreen.tap(210, 437); // 确认恢复
await sleep(3500);
await page.screenshot({ path: `${OUT}/1-after-import.png` });
console.log('import confirmed');

// back to list
await page.touchscreen.tap(39, 30);
await sleep(1400);
await page.touchscreen.tap(39, 30);
await sleep(1400);
await page.screenshot({ path: `${OUT}/2-list-top.png` });

// scroll-to-bottom loop: record spacer + scrollY each round
let prevY = -1;
for (let i = 0; i < 24; i++) {
  const m = await page.evaluate(() => {
    window.scrollTo(0, 100000000);
    const sp = document.getElementById('root');
    return {
      y: Math.round(window.scrollY),
      spacer: sp ? sp.style.height : '?',
      scrollH: document.documentElement.scrollHeight,
      innerH: window.innerHeight,
    };
  });
  console.log(`round ${i}:`, JSON.stringify(m));
  await sleep(900);
  if (m.y === prevY && i > 2) { console.log('scrollY stable'); break; }
  prevY = m.y;
}
await page.screenshot({ path: `${OUT}/3-list-bottom.png` });
const diag = await page.evaluate(() => {
  try { return (localStorage.getItem('mynote_diag_v1') || '').slice(-800); } catch { return 'n/a'; }
});
console.log('DIAG tail:', diag);
await browser.close();
console.log('done');
