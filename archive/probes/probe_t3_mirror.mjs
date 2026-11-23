// 标题三症重查 · 双存储分叉镜像面：组字（未溢出）→提交→同会话纯
// 打字跨过溢出阈值，量类锁存与桥内联谁在驱动几何；附短段平台宽
// 来源量测（meta 行宽 vs 滚动区宽 vs 胶囊宽）。
// 用法: node probe_t3_mirror.mjs <rust|orig>
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
  const meta = capsule ? capsule.querySelector('.editor-title-meta') : null;
  const cs = getComputedStyle(el), csc = getComputedStyle(capsule), scs = getComputedStyle(scroller);
  const R = (v) => Math.round(v * 10) / 10;
  return {
    len: (el.textContent || '').length,
    capW: R(capsule.getBoundingClientRect().width),
    scrW: R(scroller.getBoundingClientRect().width),
    metaW: meta ? R(meta.getBoundingClientRect().width) : null,
    metaText: meta ? meta.textContent : null,
    fs: cs.fontSize, align: cs.textAlign,
    capPad: csc.paddingLeft + '/' + csc.paddingRight,
    scrPad: scs.paddingLeft + '/' + scs.paddingRight,
    capStyleW: (capsule.getAttribute('style') || '').match(/width: ([^;]+)/)?.[1] || '(none)',
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
await state('F0-display');
const c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(750);
await state('F1-focused-empty');
// 组字到 8（长标题集，未溢出）→ 提交 6 字
for (const s of ['wei', 'weishen', 'weishenme']) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(130);
}
await state('F2-composing-8');
try { await cdp.send('Input.imeCommitText', { text: '为什么需要这' }); }
catch (e) { await cdp.send('Input.insertText', { text: '为什么需要这' }); }
await page.waitForTimeout(500);
await state('F3-committed-6');
// 纯打字续 8 个 ASCII（总长 14，跨溢出阈值）
await page.keyboard.type('abcdefgh', { delay: 70 });
await page.waitForTimeout(500);
await state('F4-typed-to-14');
// 纯打字再续 14 个（总长 28，内容宽应远超 184 锁）
await page.keyboard.type('ijklmnopqrstuv', { delay: 70 });
await page.waitForTimeout(500);
await state('F5-typed-to-28');
await browser.close();
