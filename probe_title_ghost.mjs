// 标题胶囊「双光标 + 跳变」复现探针：逐帧采样选区 rects、
// 三元素（胶囊/滚动区/标题）style 与 class、胶囊宽度、焦点归属。
// 场景：新备忘 → 自动聚焦后点标题 → 长组字（>11）→ 提交 →
// 逐字删空 → 失焦 → 二次聚焦 → 组字由长缩短到空。
// 用法: node probe_title_ghost.mjs <rust|orig>
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const app = process.argv[2] || 'rust';
const RUST = 'http://localhost:8296/';
const ORIG = 'http://localhost:8297/Moment.html';
const SEL = app === 'rust' ? '#editor-title-text' : '.editor-title-input';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 200)));
const cdp = await ctx.newCDPSession(page);

const SAMPLER = (SEL) => {
  window.__frames = [];
  window.__fstop = false;
  const R = (v) => Math.round(v * 10) / 10;
  function sample() {
    const el = document.querySelector(SEL);
    if (el) {
      const scroller = el.parentElement;
      const capsule = scroller && scroller.parentElement;
      const sel = window.getSelection();
      let rects = [], selInfo = null;
      if (sel.rangeCount) {
        const r = sel.getRangeAt(0);
        if (r.startContainer === el || el.contains(r.startContainer)) {
          rects = [...r.getClientRects()].map(rc => [R(rc.x), R(rc.y), R(rc.width), R(rc.height)]);
          selInfo = { col: r.collapsed, so: r.startOffset, eo: r.endOffset, sn: r.startContainer.nodeType, en: r.endContainer.nodeType, same: r.startContainer === r.endContainer };
        }
      }
      const ae = document.activeElement;
      window.__frames.push({
        t: Math.round(performance.now()),
        act: ae === el ? 'title' : (ae ? (ae.dataset && ae.dataset.bid ? 'body:' + ae.dataset.bid : (ae.id || ae.tagName)) : 'none'),
        text: el.textContent, html: el.innerHTML.slice(0, 90),
        rects, selInfo,
        capW: capsule ? R(capsule.getBoundingClientRect().width) : null,
        capStyle: capsule ? capsule.getAttribute('style') : null,
        scrStyle: scroller ? scroller.getAttribute('style') : null,
        elStyle: el.getAttribute('style'),
        elCls: el.getAttribute('class'), capCls: capsule ? capsule.getAttribute('class') : null,
        scrL: scroller ? scroller.scrollLeft : null,
      });
    }
    if (!window.__fstop) requestAnimationFrame(sample);
  }
  requestAnimationFrame(sample);
  return 'sampling';
};

async function mark(tag) {
  await page.evaluate((tag) => { window.__frames.push({ mark: tag, t: Math.round(performance.now()) }); }, tag);
}
async function titleCenter() {
  const box = await page.locator(SEL).boundingBox();
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

// ---- 导航：新备忘 ----
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
await page.waitForTimeout(400);
console.log('SAMPLER', await page.evaluate(SAMPLER, SEL));
await mark('P0-open');
await page.waitForTimeout(1300); // 等自动聚焦落定
await mark('P1-after-autofocus');

// ---- 点标题 ----
const c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(900);
await mark('P2-after-title-tap');

// ---- 长组字 → 提交 → 删空 ----
const growth = ['w', 'we', 'wei', 'weis', 'weish', 'weishe', 'weishen', 'weishenm', 'weishenme', 'weishenmex', 'weishenmexu', 'weishenmexuy', 'weishenmexuya', 'weishenmexuyao', 'weishenmexuyaoz', 'weishenmexuyaozh', 'weishenmexuyaozhe'];
for (const s of growth) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(110);
}
await mark('P3-composed-17');
try { await cdp.send('Input.imeCommitText', { text: '为什么需要这' }); }
catch (e) { await cdp.send('Input.insertText', { text: '为什么需要这' }); }
await page.waitForTimeout(500);
await mark('P4-committed');
for (let i = 0; i < 6; i++) { await page.keyboard.press('Backspace'); await page.waitForTimeout(160); }
await page.waitForTimeout(600);
await mark('P5-deleted-empty');

// ---- 失焦 → 二次聚焦 ----
await page.touchscreen.tap(200, 430);
await page.waitForTimeout(500);
await mark('P6-blurred');
const c2 = await titleCenter();
await page.touchscreen.tap(c2.x, c2.y);
await page.waitForTimeout(900);
await mark('P7-second-tap');

// ---- 组字由长缩短到空 ----
const shrink = ['zhegemingzifeich', 'zhegemingzifei', 'zhegemingzi', 'zhegemi', 'zhe', 'z', ''];
for (const s of shrink) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(140);
}
await page.waitForTimeout(500);
await mark('P8-composition-shrunk-empty');

await page.evaluate(() => { window.__fstop = true; });
const frames = await page.evaluate(() => window.__frames);
const out = `/home/hatch/.tmp/ghost_${app}.json`;
fs.writeFileSync(out, JSON.stringify(frames));
console.log('FRAMES', frames.length, 'saved', out);
if (app === 'rust') {
  const diag = await page.evaluate(() => { try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch { return []; } });
  console.log('DIAG title/focus lines:');
  for (const d of diag) { const s = typeof d === 'string' ? d : JSON.stringify(d); if (/title|focus/i.test(s)) console.log(' ', s.slice(0, 160)); }
}
await browser.close();
