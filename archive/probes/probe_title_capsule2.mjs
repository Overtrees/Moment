// 标题胶囊探针 2：长标题（>10 字，显示截断态）聚焦时的全文替换路径
// + 两次编辑会话之间字号内联样式被清的度量。
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8115/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));

async function snap(label) {
  const s = await page.evaluate(() => {
    const el = document.getElementById('editor-title-text');
    const cap = document.querySelector('.editor-title-capsule');
    const sel = window.getSelection();
    const cr = cap.getBoundingClientRect();
    return {
      text: el.textContent,
      textNodeSame: !!(el.firstChild && el.firstChild.__probeTextNode),
      fontSize: getComputedStyle(el).fontSize,
      styleAttr: el.getAttribute('style'),
      active: document.activeElement && document.activeElement.id,
      caretOffset: sel && sel.rangeCount ? sel.focusOffset : null,
      caretNodeText: sel && sel.focusNode && sel.focusNode.nodeType === 3 ? sel.focusNode.textContent : null,
      capW: Math.round(cr.width * 10) / 10,
      capCls: cap.className,
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

// 先把标题打到 12 字以上并失焦（制造截断显示态）
const capBox = await page.locator('.editor-title-capsule').boundingBox();
await page.touchscreen.tap(capBox.x + capBox.width / 2, capBox.y + 20);
await page.waitForTimeout(400);
await page.keyboard.type('ABCDEFGH'); // 6 + 8 = 14 字（追加到点选处附近即可，只需总长 >11）
await page.waitForTimeout(300);
await snap('long-typed');
await page.tap('.editor-body');
await page.waitForTimeout(600);
await snap('long-blurred (truncated display expected)');

// 标记当前文本节点，再聚焦长标题：观察文本节点是否被替换、光标被强制到末尾
await page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  if (el.firstChild) el.firstChild.__probeTextNode = true;
});
const box2 = await page.locator('.editor-title-capsule').boundingBox();
// 点标题靠左位置（光标本应落在靠前位置）
await page.touchscreen.tap(box2.x + 30, box2.y + 20);
await page.waitForTimeout(700);
await snap('long-first-tap-after-truncation');
for (const ch of ['Q', 'R']) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(250);
  await snap('long-type-' + ch);
}
await page.tap('.editor-body');
await page.waitForTimeout(600);
await snap('long-blur2');
await browser.close();
