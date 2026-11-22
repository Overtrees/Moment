// 标题胶囊首次编辑态探针：复现「首次点击键盘弹起但打不出字、
// 第二次可打但光标跳动」，并量化每次击键后的选区与胶囊几何。
// 用法：node probe_title_capsule.mjs http://localhost:8115/
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8115/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

async function sample(label) {
  const s = await page.evaluate(() => {
    const el = document.getElementById('editor-title-text');
    const cap = document.querySelector('.editor-title-capsule');
    const scroller = document.querySelector('.editor-title-scroller');
    const sel = window.getSelection();
    let caret = null;
    if (sel && sel.rangeCount) {
      const r = sel.getRangeAt(0);
      const rects = r.getClientRects();
      const rect = rects && rects.length ? rects[rects.length - 1] : r.getBoundingClientRect();
      caret = {
        focusTag: sel.focusNode && sel.focusNode.nodeType === 3 ? '#text' : (sel.focusNode && sel.focusNode.nodeName) || null,
        focusText: sel.focusNode && sel.focusNode.nodeType === 3 ? sel.focusNode.textContent : null,
        offset: sel.focusOffset,
        collapsed: sel.isCollapsed,
        rect: rect ? { x: rect.x, y: rect.y, w: rect.width, h: rect.height } : null,
      };
      // 折叠光标 rect 常为 0 宽/假值，按原版 S6 方法取相邻字形边界
      if (sel.focusNode && sel.focusNode.nodeType === 3 && sel.focusNode.length) {
        const n = sel.focusNode;
        const off = Math.max(0, Math.min(sel.focusOffset, n.length));
        const gr = document.createRange();
        if (off > 0) { gr.setStart(n, off - 1); gr.setEnd(n, off); }
        else { gr.setStart(n, 0); gr.setEnd(n, Math.min(1, n.length)); }
        const g = gr.getBoundingClientRect();
        caret.glyph = { x: off > 0 ? g.right : g.left, y: g.top, h: g.height };
      }
    }
    const cr = cap ? cap.getBoundingClientRect() : null;
    return {
      text: el ? el.textContent : null,
      sameNode: !!(el && el.__probeTitleNode),
      activeId: document.activeElement && document.activeElement.id,
      activeClass: document.activeElement && document.activeElement.className,
      capsuleClass: cap ? cap.className : null,
      capsuleRect: cr ? { x: cr.x, y: cr.y, w: cr.width, h: cr.height } : null,
      scrollerScrollLeft: scroller ? scroller.scrollLeft : null,
      scrollerClass: scroller ? scroller.className : null,
      titleClass: el ? el.className : null,
      titleStyle: el ? el.getAttribute('style') : null,
      caret,
    };
  });
  console.log(label, JSON.stringify(s));
  return s;
}

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(500);
await page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  if (el) el.__probeTitleNode = true;
});
await sample('before-first-tap');

// 第一次：点标题胶囊中心（模拟真机点胶囊）
const capBox = await page.locator('.editor-title-capsule').boundingBox();
await page.touchscreen.tap(capBox.x + capBox.width / 2, capBox.y + capBox.height / 2);
await page.waitForTimeout(600);
await sample('after-first-tap');
for (const ch of ['X', 'Y']) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(250);
  await sample('first-type-' + ch);
}

// 失焦提交（点正文区）
await page.tap('.editor-body');
await page.waitForTimeout(600);
await sample('after-first-blur');

// 第二次：再点标题胶囊
await page.touchscreen.tap(capBox.x + capBox.width / 2, capBox.y + capBox.height / 2);
await page.waitForTimeout(600);
await sample('after-second-tap');
for (const ch of ['Z', 'W']) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(250);
  await sample('second-type-' + ch);
}
await page.tap('.editor-body');
await page.waitForTimeout(600);
await sample('after-second-blur');

// 持久化：返回列表再重开，标题应保留两次输入
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text').catch(async () => {
  // 标题改了文本后列表卡标题也变，按当前标题文本兜底点第一张文本卡
  await page.locator('.list-item .item-title-text').nth(1).click();
});
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(500);
await sample('after-reopen');

console.log('PAGEERRORS', errors.length ? errors.join(' | ') : 'none');
await browser.close();
