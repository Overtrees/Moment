import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true });
const page = await ctx.newPage();
await page.goto('http://localhost:8095/', { waitUntil: 'load' });
await page.waitForTimeout(10000);
await page.touchscreen.tap(210, 320);
await page.waitForTimeout(3500);
const probe = async (label) => {
  const info = await page.evaluate(() => {
    const els = [...document.querySelectorAll('textarea, input, [contenteditable]')].map(e => ({
      tag: e.tagName, ce: e.getAttribute('contenteditable'), cls: (e.className || '').slice(0, 40),
      focused: document.activeElement === e,
    }));
    return { active: document.activeElement?.tagName + '/' + (document.activeElement?.className || '').slice(0, 30), els: els.slice(0, 6) };
  });
  console.log(label, JSON.stringify(info));
};
await probe('before-tap');
await page.mouse.click(200, 290); // 第三个待办
await page.waitForTimeout(900);
await probe('after-tap-todo3');
await page.keyboard.type('Q');
await page.waitForTimeout(800);
await probe('after-type');
await browser.close();
