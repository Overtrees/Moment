// 标题三症重查 · 症1 组字期 DOM 变更档案：MutationObserver 记录组字
// 全程胶囊/滚动区/标题三元素的 class/style/childList/characterData
// 变更时间线，与原版对照（找组字期「多余」的属性变更/节点扰动）。
// 用法: node probe_t3_mut.mjs <rust|orig>
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

const INSTALL = (SEL) => {
  window.__mut = [];
  const el = document.querySelector(SEL);
  const scroller = el.parentElement;
  const capsule = scroller && scroller.parentElement;
  const role = (n) => n === el ? 'el' : n === scroller ? 'scr' : n === capsule ? 'cap' : 'other';
  const obs = new MutationObserver((ms) => {
    for (const m of ms) {
      window.__mut.push({
        t: Math.round(performance.now()),
        target: role(m.target), type: m.type, attr: m.attributeName || null,
        val: m.type === 'attributes' ? (m.target.getAttribute(m.attributeName) || '').slice(0, 130) : null,
        added: m.addedNodes ? m.addedNodes.length : 0,
        removed: m.removedNodes ? m.removedNodes.length : 0,
        data: m.type === 'characterData' ? (m.target.data || '').slice(0, 26) : null,
      });
    }
  });
  obs.observe(capsule, { attributes: true, attributeFilter: ['class', 'style'], childList: true, characterData: true, subtree: true });
  window.__selchg = 0;
  document.addEventListener('selectionchange', () => { window.__selchg++; });
  window.__snapAtFocusIn = 'n/a';
  return 'installed';
};

async function mark(tag) {
  await page.evaluate((tag) => { window.__mut.push({ mark: tag, t: Math.round(performance.now()) }); }, tag);
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
await page.waitForTimeout(1300);
console.log('INSTALL', await page.evaluate(INSTALL, SEL));
await mark('M0-before-focus');
const c = await titleCenter();
await page.touchscreen.tap(c.x, c.y);
await page.waitForTimeout(800);
await mark('M1-focused');

// 组字1：跨 5 与 11 两阈值
for (const s of ['n', 'nik', 'niknin', 'nikninkklo', 'nikninkklook']) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(150);
}
await mark('M2-composed-13');
try { await cdp.send('Input.imeCommitText', { text: '你看宁看看咯OK了' }); }
catch (e) { await cdp.send('Input.insertText', { text: '你看宁看看咯OK了' }); }
await page.waitForTimeout(600);
await mark('M3-committed');
// 组字2（二次组字，同会话）
for (const s of ['h', 'ha', 'hao']) {
  await cdp.send('Input.imeSetComposition', { text: s, selectionStart: s.length, selectionEnd: s.length });
  await page.waitForTimeout(150);
}
await mark('M4-composed-2nd');
try { await cdp.send('Input.imeCommitText', { text: '好' }); }
catch (e) { await cdp.send('Input.insertText', { text: '好' }); }
await page.waitForTimeout(500);
await mark('M5-committed-2nd');
await page.touchscreen.tap(200, 430);
await page.waitForTimeout(550);
await mark('M6-blurred');

const mut = await page.evaluate(() => window.__mut);
const selchg = await page.evaluate(() => window.__selchg);
console.log('SELCHANGE total', selchg, 'MUT total', mut.length);
for (const m of mut) console.log(JSON.stringify(m));
await browser.close();
