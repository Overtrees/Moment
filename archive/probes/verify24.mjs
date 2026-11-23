import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const ctx = await chromium.launchPersistentContext('/tmp/mynote-test-profile', {
  executablePath: exe, headless: true,
  viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true,
  args: ['--no-sandbox'],
});
const page = ctx.pages()[0] || await ctx.newPage();
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(25000);
async function probe(tag) {
  const info = await page.evaluate(() => {
    const root = document.getElementById('root');
    const host = document.getElementById('host');
    return {
      rootStyleH: root?.style.height, rootRectH: root?.getBoundingClientRect().height,
      hostH: host?.getBoundingClientRect().height, hostPos: getComputedStyle(host).position,
      scrollY: window.scrollY, scrollH: document.documentElement.scrollHeight,
    };
  });
  console.log(tag, JSON.stringify(info));
}
await probe('on-list:');
// scroll to bottom via window
await page.evaluate(() => window.scrollTo(0, 999999));
await page.waitForTimeout(1500);
await probe('after-scrollTo-bottom:');
await page.screenshot({ path: '/tmp/v24_bottom.png' });
await ctx.close();
console.log('done');
