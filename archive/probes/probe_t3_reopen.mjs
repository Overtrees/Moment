// 标题三症重查 · 症3 补充 E：截断长标题重进时的光标落位与滚动同步。
// 建 13 字标题→失焦→再点标题，逐 100ms 采样 scrollLeft、选区锚点
// 形态、光标 rect，并读 Diag 的 title caret sync 行。
// 用法: node probe_t3_reopen.mjs <rust|orig>
import { chromium } from 'playwright-core';

const app = process.argv[2] || 'rust';
const RUST = 'http://localhost:8396/';
const ORIG = 'http://localhost:8397/Moment.html';
const SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 200)));

const SAMPLE = (SEL) => {
  const el = document.querySelector(SEL);
  if (!el) return null;
  const scroller = el.parentElement;
  const sel = window.getSelection();
  let anchor = null, caretX = null;
  if (sel.rangeCount) {
    const r = sel.getRangeAt(0);
    if (el.contains(r.startContainer)) {
      anchor = {
        nodeType: r.startContainer.nodeType,
        offset: r.startOffset,
        collapsed: r.collapsed,
      };
      const rc = r.getClientRects();
      if (rc.length) caretX = Math.round(rc[0].x * 10) / 10;
    }
  }
  return {
    focused: document.activeElement === el,
    len: (el.textContent || '').length,
    scrL: scroller.scrollLeft,
    scrW: scroller.scrollWidth, scrCW: scroller.clientWidth,
    anchor, caretX,
  };
};
async function titleCenter() {
  const box = await page.locator(SEL).boundingBox();
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

if (app === 'rust') {
  await page.goto(RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.click('.new-card-title');
} else {
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  await page.getByText('新建笔记', { exact: false }).first().click();
}
await page.waitForSelector(SEL, { timeout: 10000 });
await page.waitForTimeout(1300);
let c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(750);
await page.keyboard.type('标题测试文字一二三四五六七', { delay: 55 }); // 13 字
await page.waitForTimeout(500);
console.log('built', JSON.stringify(await page.evaluate(SAMPLE, SEL)));
await page.touchscreen.tap(200, 430);
await page.waitForTimeout(600);
// 重进：逐 100ms 采样
c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
for (let i = 0; i < 15; i++) {
  console.log('reopen+' + (i * 100) + 'ms', JSON.stringify(await page.evaluate(SAMPLE, SEL)));
  await page.waitForTimeout(100);
}
if (app === 'rust') {
  const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch { return []; } });
  console.log('DIAG title lines:');
  for (const d of diag) { const s = typeof d === 'string' ? d : JSON.stringify(d); if (/title/i.test(s)) console.log(' ', s.slice(0, 170)); }
}
await browser.close();
