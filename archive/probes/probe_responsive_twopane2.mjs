// 原版独立双栏（pointerdown 版）
import { chromium } from 'playwright-core';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
function fire(el, type) {
  el.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 1, isPrimary: true }));
  el.dispatchEvent(new MouseEvent(type === 'pointerdown' ? 'mousedown' : 'mouseup', { bubbles: true }));
  if (type === 'pointerup') el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
}
for (const [w, h] of [[1280, 800], [800, 500]]) {
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true });
  const page = await ctx.newPage();
  await page.goto('http://localhost:8107/Moment.html', { waitUntil: 'load', timeout: 20000 });
  await page.waitForTimeout(2000);
  await page.locator('.container .list-item, .container .img-card').first().click({ timeout: 5000 });
  await page.waitForTimeout(1200);
  const opened = await page.evaluate(() => {
    const more = document.querySelector(".editor-fab.right");
    if (!more) return 'no-more-btn';
    const ev = (t) => more.dispatchEvent(new PointerEvent(t, { bubbles: true, pointerId: 1, isPrimary: true }));
    ev('pointerdown'); ev('pointerup');
    more.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    return 'clicked:' + more.className;
  });
  await page.waitForTimeout(800);
  const menu = await page.evaluate(() => {
    const tog = document.querySelector('.editor-column-mode-toggle');
    const panel = document.querySelector('.editor-menu-panel');
    return { panelOpen: !!panel, togglePresent: !!tog, toggleDisplay: tog ? getComputedStyle(tog).display : '-' };
  });
  console.log(`${w}x${h} ORIG MENU ${opened} ${JSON.stringify(menu)}`);
  if (menu.togglePresent && menu.toggleDisplay !== 'none') {
    await page.evaluate(() => {
      const tog = document.querySelector('.editor-column-mode-toggle');
      tog.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, pointerId: 1, isPrimary: true }));
      tog.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, pointerId: 1, isPrimary: true }));
      tog.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    await page.waitForTimeout(900);
    const cols = await page.evaluate(() => {
      const cs = Array.from(document.querySelectorAll('.editor-column'));
      const b = document.querySelector('.editor-body');
      return { n: cs.length, info: cs.map((c) => ({ h: c.clientHeight, sh: c.scrollHeight, oy: getComputedStyle(c).overflowY, ce: c.getAttribute('contenteditable') })), bodyDisplay: b ? getComputedStyle(b).display : '-' };
    });
    console.log(`${w}x${h} ORIG TWOPANE ${JSON.stringify(cols)}`);
  }
  await ctx.close();
}
await browser.close();
console.log('DONE');
