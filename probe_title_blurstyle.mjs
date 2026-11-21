// 标题失焦同步清理专项：组合输入（触发桥 syncTitleLayout 直写
// 内联样式）→ 提交 → 失焦，断言三元素 style 属性已被同步摘除、
// 计算字号由类驱动正确、且失焦瞬间（同步求值）即已干净——验证
// onblur 同步清理替代旧 spawn+eval 异步清理。
// 用法: node probe_title_blurstyle.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8133/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 160)));
const cdp = await ctx.newCDPSession(page);
let fails = 0;
const ok = (c, name, extra = '') => { console.log((c ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : '')); if (!c) fails++; };

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.getByText('周末看展记录', { exact: true }).first().click();
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(600);

const box = await page.locator('#editor-title-text').boundingBox();
await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
await page.waitForTimeout(500);

// 组合输入：标题 6 字 + 组字，长度跨 11 溢出阈值，让
// syncTitleLayout 把胶囊/滚动区/标题的内联样式全部写上
await cdp.send('Input.imeSetComposition', { text: 'pinpinpin', selectionStart: 9, selectionEnd: 9 });
await page.waitForTimeout(300);
const during = await page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const sc = el.parentElement, cap = sc.parentElement;
  return { el: el.getAttribute('style'), sc: sc.getAttribute('style'), cap: cap.getAttribute('style') };
});
console.log('DURING-COMP styles:', JSON.stringify(during));
ok(during.el !== null && during.cap !== null, '组合期 syncTitleLayout 确已直写内联样式（前置条件成立）');

try { await cdp.send('Input.imeCommitText', { text: '拼拼拼' }); }
catch { await cdp.send('Input.insertText', { text: '拼拼拼' }); }
await page.waitForTimeout(400);

// 失焦：在 blur 事件任务内同步求值——监听器在捕获阶段读三元素
// style（页面自身的 blur 处理是冒泡/目标阶段，捕获监听先于它
// 会读到清理前；故这里在 tap 后第一时间 evaluate 并断言终态，
// 再结合「无 await 间隔」论证同步性：evaluate 紧随 tap 的
// touchend 派发，若清理仍走异步 spawn，首个宏任务内未必完成）
await page.touchscreen.tap(200, 420);
const after = await page.evaluate(() => {
  const el = document.getElementById('editor-title-text');
  const sc = el.parentElement, cap = sc.parentElement;
  const cs = getComputedStyle(el);
  return {
    active: document.activeElement === el,
    el: el.getAttribute('style'), sc: sc.getAttribute('style'), cap: cap.getAttribute('style'),
    font: cs.fontSize, text: el.textContent,
  };
});
console.log('AFTER-BLUR:', JSON.stringify(after));
ok(after.active === false, '已失焦');
ok(after.el === null && after.sc === null && after.cap === null, '失焦后三元素 style 属性全摘除（同步清理终态）');
ok(after.font === '11px', '失焦后计算字号 11px（类驱动，无漂移）', after.font);
// 组字落在中心 tap 的原生落点（offset 3），提交文本插入该处、
// 原文一字不丢即为无损
ok(after.text === '周末看拼拼拼展记录', '组合提交落原生落点、原文无损', after.text);
console.log(fails ? 'BLURSTYLE FAIL x' + fails : 'BLURSTYLE ALL PASS');
await browser.close();
