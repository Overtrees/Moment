// 标题三症重查 · 症3 多会话留白量测：三轮「聚焦→输入态量测→失焦」，
// 量胶囊内文本左右留白（文本 rect 对胶囊 rect）、胶囊/滚动区 computed
// 内边距、scrollLeft、对齐与字号。用法: node probe_t3_pad.mjs <rust|orig>
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

const MEASURE = (SEL) => {
  const el = document.querySelector(SEL);
  if (!el) return null;
  const scroller = el.parentElement;
  const capsule = scroller && scroller.parentElement;
  const capR = capsule.getBoundingClientRect();
  const range = document.createRange();
  range.selectNodeContents(el);
  const rects = [...range.getClientRects()].filter(r => r.height > 0);
  let tl = null, tr = null;
  for (const r of rects) { tl = tl === null ? r.left : Math.min(tl, r.left); tr = tr === null ? r.right : Math.max(tr, r.right); }
  const cs = getComputedStyle(el), csc = getComputedStyle(capsule), scs = getComputedStyle(scroller);
  const R = (v) => v === null || v === undefined ? null : Math.round(v * 10) / 10;
  return {
    len: (el.textContent || '').length,
    text: (el.textContent || '').slice(0, 20),
    capL: R(capR.left), capR: R(capR.right), capW: R(capR.width),
    textL: R(tl), textR: R(tr),
    gapL: tl === null ? null : R(tl - capR.left),
    gapR: tr === null ? null : R(capR.right - tr),
    capPad: csc.paddingLeft + '/' + csc.paddingRight,
    scrPad: scs.paddingLeft + '/' + scs.paddingRight,
    scrL: scroller.scrollLeft,
    align: cs.textAlign, fs: cs.fontSize,
    elCls: el.getAttribute('class'), capCls: capsule.getAttribute('class'),
    scrStyle: (scroller.getAttribute('style') || '').slice(0, 90),
    capStyle: (capsule.getAttribute('style') || '').slice(0, 90),
    elStyle: (el.getAttribute('style') || '').slice(0, 90),
    focused: document.activeElement === el,
  };
};

async function titleCenter() {
  const box = await page.locator(SEL).boundingBox();
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}
async function measure(tag) {
  const m = await page.evaluate(MEASURE, SEL);
  console.log(tag, JSON.stringify(m));
}
async function focusTitle() {
  const c = await titleCenter();
  await page.touchscreen.tap(c.x, c.y);
  await page.waitForTimeout(750);
}
async function blurTitle() {
  await page.touchscreen.tap(200, 430);
  await page.waitForTimeout(550);
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
await measure('S0-display-initial');

// ---- 会话1：输 8 字（长标题非溢出）----
await focusTitle();
await measure('S1-focus-empty');
await page.keyboard.type('标题测试文字一二', { delay: 60 });
await page.waitForTimeout(600);
await measure('S1-input-len8');
await blurTitle();
await measure('S1-after-blur');

// ---- 会话2：重进（不打字）→ 续打到 13 字（溢出）----
await focusTitle();
await measure('S2-reopen-len8');
await page.keyboard.type('三四五六七', { delay: 60 });
await page.waitForTimeout(600);
await measure('S2-input-len13');
await blurTitle();
await measure('S2-after-blur');

// ---- 会话3：重进溢出标题 → 删到 3 字 ----
await focusTitle();
await measure('S3-reopen-len13');
for (let i = 0; i < 10; i++) { await page.keyboard.press('Backspace'); await page.waitForTimeout(70); }
await page.waitForTimeout(600);
await measure('S3-input-len3');
await blurTitle();
await measure('S3-after-blur');

// ---- 会话4：重进短标题（不打字）----
await focusTitle();
await measure('S4-reopen-len3');
await blurTitle();

await browser.close();
