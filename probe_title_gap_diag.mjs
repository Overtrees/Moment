// 诊断探针：Rust 二次聚焦溢出标题时 syncTitleCaret 为何不滚动。
// 采样选区锚点类型/折叠 Range rect/scrollLeft 的时间序列。
import { chromium } from 'playwright-core';
const BASE = process.argv[2] || 'http://localhost:8201/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(600);
const box = await page.locator('#editor-title-text').boundingBox();
await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
await page.waitForTimeout(700);
await page.evaluate(() => document.execCommand('selectAll', false, null));
await page.keyboard.type('阿阿阿阿头哦婆婆婆婆给的七八九', { delay: 20 });
await page.waitForTimeout(600);
// 装探针：统计 selectionchange 次数
await page.evaluate(() => {
  window.__scCount = 0;
  document.addEventListener('selectionchange', () => { window.__scCount++; });
});
await page.touchscreen.tap(196, 500); // 失焦
await page.waitForTimeout(600);
const sample = () => page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const sc = el.parentElement;
  const sel = window.getSelection();
  let rr = null;
  if (sel.rangeCount) {
    const b = sel.getRangeAt(0).getBoundingClientRect();
    rr = { left: Math.round(b.left * 100) / 100, height: Math.round(b.height * 100) / 100, width: Math.round(b.width * 100) / 100 };
  }
  return {
    scCount: window.__scCount,
    active: document.activeElement && document.activeElement.id,
    focusNodeType: sel.focusNode ? sel.focusNode.nodeType : null,
    focusOffset: sel.focusOffset,
    rangeRect: rr,
    scrollLeft: sc.scrollLeft,
    text: el.textContent,
  };
});
console.log('before tap2 ', JSON.stringify(await sample()));
const box2 = await page.locator('.editor-title-capsule').boundingBox();
await page.touchscreen.tap(box2.x + box2.width / 2, box2.y + 20);
for (const t of [120, 300, 600, 1000]) {
  await page.waitForTimeout(t === 120 ? 120 : t - [120, 300, 600, 1000][[120, 300, 600, 1000].indexOf(t) - 1]);
  console.log('after tap2 +' + t + 'ms', JSON.stringify(await sample()));
}
// 直接量折叠 Range 在 (el, 1) 处的 rect（模拟聚焦事务后的选区形态）
console.log('manual range(el,1):', JSON.stringify(await page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const r = document.createRange();
  r.selectNodeContents(el); r.collapse(false);
  const b = r.getBoundingClientRect();
  return { left: b.left, right: b.right, height: b.height, width: b.width };
})));
await browser.close();
