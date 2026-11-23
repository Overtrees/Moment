// 标题三症重查 · 症3 补充 D：失焦后迟到组字事件的守卫行为。
// 会话内组字→点正文失焦→向已失焦的标题元素派发 compositionupdate/
// input 事件（模拟 iOS 组字会话晚于焦点变更的事件序），看桥是否
// 在无会话状态下重建快照并回写内联样式；再进二会话量测初始态。
// 用法: node probe_t3_late.mjs <rust|orig>
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
const cdp = await ctx.newCDPSession(page);

const STATE = (SEL) => {
  const el = document.querySelector(SEL);
  if (!el) return null;
  const scroller = el.parentElement;
  const capsule = scroller && scroller.parentElement;
  const cs = getComputedStyle(el), csc = getComputedStyle(capsule);
  return {
    focused: document.activeElement === el,
    len: (el.textContent || '').length,
    capW: Math.round(capsule.getBoundingClientRect().width * 10) / 10,
    fs: cs.fontSize, align: cs.textAlign,
    capStyle: (capsule.getAttribute('style') || '').slice(0, 100),
    scrStyle: (scroller.getAttribute('style') || '').slice(0, 100),
    elStyle: (el.getAttribute('style') || '').slice(0, 100),
    elCls: el.getAttribute('class'), capCls: capsule.getAttribute('class'),
    scrL: scroller.scrollLeft,
  };
};
async function state(tag) { console.log(tag, JSON.stringify(await page.evaluate(STATE, SEL))); }
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
const c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(800);
// 组字到 9（跨长标题阈值，未溢出）
for (const s of ['wei', 'weishen', 'weishenme']) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(140);
}
await state('D1-composing-9');
// 不结束组字，直接点正文失焦
await page.touchscreen.tap(200, 430);
await page.waitForTimeout(700);
await state('D2-after-blur-mid-composition');
// 迟到组字事件：直接派发到标题元素（桥/React 监听均在根上冒泡）
await page.evaluate((SEL) => {
  const el = document.querySelector(SEL);
  el.dispatchEvent(new CompositionEvent('compositionupdate', { bubbles: true, data: 'weishenmexu' }));
  el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertCompositionText' }));
}, SEL);
await page.waitForTimeout(400);
await state('D3-after-late-events');
// 二次进入：量测初始输入态（不打字）
const c2 = await titleCenter();
await page.touchscreen.tap(c2.x, c2.y);
await page.waitForTimeout(750);
await state('D4-session2-initial');
await page.keyboard.type('x');
await page.waitForTimeout(400);
await state('D5-session2-typed-1');
await browser.close();
