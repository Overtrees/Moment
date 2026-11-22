// 滚动审计探针二：原版 L1(h1 选择器)/L3 恢复时序/E3 菜单/E4 斜杠跟随
import { chromium } from 'playwright-core';
const ORIG = 'http://localhost:8099/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 100)));
await page.goto(ORIG, { waitUntil: 'load' });
await page.waitForTimeout(2500);
console.log('cards', await page.evaluate(() => document.querySelectorAll('.list-item, .img-card').length),
  'scrollH', await page.evaluate(() => document.documentElement.scrollHeight));
const scrollTo = async (y) => { await page.evaluate((v) => window.scrollTo(0, v), y); await page.waitForTimeout(350); };

// L1 h1 大标题
await scrollTo(15);
console.log('ORIG L1 @15', JSON.stringify(await page.evaluate(() => {
  const h = document.querySelector('h1.page-title');
  const cs = getComputedStyle(h);
  return { tf: cs.transform, op: cs.opacity, y: window.scrollY };
})));
await scrollTo(0);

// L3 时序：滚到底(160) → 打开长文 → editorY → 返回 → 多个时点读 scrollY
await scrollTo(160);
console.log('listY before open', await page.evaluate(() => window.scrollY));
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
  if (el) el.click();
});
await page.waitForTimeout(1200);
console.log('inEditor', await page.evaluate(() => !!document.querySelector('.editor-body')),
  'editorY', await page.evaluate(() => window.scrollY));
await page.evaluate(() => document.querySelector('.editor-fab.left')?.click());
for (const wait of [100, 400, 1000]) {
  await page.waitForTimeout(wait === 100 ? 100 : wait - (wait === 400 ? 100 : 400));
  console.log('backY after ~' + wait + 'ms', await page.evaluate(() => window.scrollY),
    'list?', await page.evaluate(() => !!document.querySelector('.list-item')));
}

// 重新进编辑器做 E3/E4
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
  if (el) el.click();
});
await page.waitForTimeout(1200);
console.log('inEditor2', await page.evaluate(() => !!document.querySelector('.editor-body')));
// E3 菜单：真实点击 fab.right
await page.click('.editor-fab.right').catch((e) => console.log('fab click err', e.message.slice(0, 80)));
await page.waitForTimeout(600);
console.log('ORIG E3 menu open?', await page.evaluate(() => !!document.querySelector('.editor-menu-panel')));
await scrollTo(200);
console.log('ORIG E3 menu after scroll200?', await page.evaluate(() => !!document.querySelector('.editor-menu-panel')));
// E4 斜杠：聚焦正文首段末尾打 /
await scrollTo(0);
await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  if (body) { body.focus(); const r = document.createRange(); r.selectNodeContents(body); r.collapse(false); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
});
await page.keyboard.type('/');
await page.waitForTimeout(700);
const sp1 = await page.evaluate(() => {
  const p = document.querySelector('.slash-panel');
  return p ? Math.round(p.getBoundingClientRect().top) : -1;
});
console.log('ORIG E4 slash top before', sp1);
await scrollTo(200);
const sp2 = await page.evaluate(() => {
  const p = document.querySelector('.slash-panel');
  return p ? Math.round(p.getBoundingClientRect().top) : -1;
});
console.log('ORIG E4 slash top after scroll200', sp2, 'panel?', sp2 !== -1);
await browser.close();
console.log('PROBE2 DONE');
