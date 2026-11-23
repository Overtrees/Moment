// 标题三症重查 · 症2 宽度曲线探针：逐帧采样胶囊宽度/字号/内边距/
// 类与内联样式/光标位，分三段：纯打字增删、IME 组字增长、提交后删改。
// 用法: node probe_t3_width.mjs <rust|orig>
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const app = process.argv[2] || 'rust';
const RUST = 'http://localhost:8396/';
const ORIG = 'http://localhost:8397/Moment.html';
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
      const cs = getComputedStyle(el);
      const csc = capsule ? getComputedStyle(capsule) : null;
      const sel = window.getSelection();
      let caretX = null;
      if (sel.rangeCount) {
        const r = sel.getRangeAt(0);
        if (r.collapsed && (r.startContainer === el || el.contains(r.startContainer))) {
          const rc = r.getClientRects();
          if (rc.length) caretX = R(rc[0].x);
        }
      }
      window.__frames.push({
        t: Math.round(performance.now()),
        len: (el.textContent || '').length,
        capW: capsule ? R(capsule.getBoundingClientRect().width) : null,
        capX: capsule ? R(capsule.getBoundingClientRect().x) : null,
        fs: cs.fontSize, align: cs.textAlign,
        capPad: csc ? csc.paddingLeft + '/' + csc.paddingRight : null,
        elCls: el.getAttribute('class'), capCls: capsule ? capsule.getAttribute('class') : null,
        capStyle: capsule ? (capsule.getAttribute('style') || '').slice(0, 110) : null,
        scrStyle: scroller ? (scroller.getAttribute('style') || '').slice(0, 110) : null,
        elStyle: (el.getAttribute('style') || '').slice(0, 110),
        scrL: scroller ? scroller.scrollLeft : null,
        caretX,
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
await page.waitForTimeout(1200);
await mark('P0-autofocus-done');
const c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(800);
await mark('P1-title-focused');

// ---- 纯打字：增到 16，再删到 0 ----
for (const ch of 'abcdefghijklmnop') { await page.keyboard.type(ch); await page.waitForTimeout(95); }
await page.waitForTimeout(450);
await mark('P2-typed-16');
for (let i = 0; i < 10; i++) { await page.keyboard.press('Backspace'); await page.waitForTimeout(95); }
await page.waitForTimeout(350);
await mark('P3-back-to-6');
for (let i = 0; i < 6; i++) { await page.keyboard.press('Backspace'); await page.waitForTimeout(95); }
await page.waitForTimeout(350);
await mark('P4-back-to-0');

// ---- IME 组字增长（仿九宫格串）→ 收缩 → 提交 ----
const growth = ['n', 'ni', 'nik', 'nikn', 'nikni', 'niknin', 'niknink', 'nikninkk', 'nikninkkl', 'nikninkklo', 'nikninkkloo', 'nikninkklook'];
for (const s of growth) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(115);
}
await page.waitForTimeout(350);
await mark('P5-composed-13');
for (const s of ['nikninkklo', 'niknink', 'nik', '']) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(115);
}
await page.waitForTimeout(300);
await mark('P6-composition-cancelled');
for (const s of ['wei', 'weishen', 'weishenmexu', 'weishenmexuyaozhe']) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(115);
}
try { await cdp.send('Input.imeCommitText', { text: '为什么需要这' }); }
catch (e) { await cdp.send('Input.insertText', { text: '为什么需要这' }); }
await page.waitForTimeout(500);
await mark('P7-committed-6');

await page.evaluate(() => { window.__fstop = true; });
const frames = await page.evaluate(() => window.__frames);
fs.writeFileSync(`/home/hatch/.tmp/t3_width_${app}.json`, JSON.stringify(frames));
console.log('FRAMES', frames.length, 'saved', `/home/hatch/.tmp/t3_width_${app}.json`);
await browser.close();
