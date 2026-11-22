// 原版活体实测 3：IDB 全量真值 + 块 outerHTML（todo/divider 落盘、引用/待办回车 B1）
import { chromium } from 'playwright-core';
const base = 'http://localhost:8222/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
const L = (...a) => console.log(...a);
const idbDocs = () => page.evaluate(async () => {
  const db = await window.MynoteIdb.getDB();
  const memos = await window.MynoteIdb.loadMemosFromDB(db);
  return memos.map((m) => ({
    title: m.title,
    doc: (m.doc || []).map((b) => ({ type: b.type, level: b.attrs && b.attrs.level, checked: b.attrs && b.attrs.checked, text: ((b.children || []).map((c) => c.text || '').join('')).slice(0, 26) })),
  }));
});
const blockHtml = () => page.evaluate(() =>
  [...document.querySelectorAll('.editor-body [data-blockid]')].map((e) => e.outerHTML.slice(0, 130)));
const newMemo = async () => {
  await page.locator('.list-item', { hasText: '新建笔记' }).first().click();
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1200);
};
const back = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(1200); };
const clickFirstPara = async () => {
  const pt = await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-blockid]');
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + 10, y: r.y + r.height / 2 };
  });
  if (pt) await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(300);
};
const type = async (t) => { await page.keyboard.type(t, { delay: 25 }); await page.waitForTimeout(650); };

await page.goto(base + 'Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(3200);

// U1: [ ] 待办落盘 + 块 HTML
await newMemo(); await clickFirstPara();
await type('[ ] 待办甲');
L('U1-HTML', JSON.stringify(await blockHtml()));
L('U1-IDB', JSON.stringify(await idbDocs()));
await back();
// U2: --- 分隔线落盘 + 块 HTML
await newMemo(); await clickFirstPara();
await type('---');
await page.waitForTimeout(400);
L('U2-HTML', JSON.stringify(await blockHtml()));
L('U2-IDB', JSON.stringify(await idbDocs()));
await back();
// U3: 引用块回车
await newMemo(); await clickFirstPara();
await type('> 引用中段');
await clickFirstPara();
await page.keyboard.press('End');
await page.keyboard.press('Enter'); await page.waitForTimeout(500);
L('U3-HTML', JSON.stringify(await blockHtml()));
L('U3-IDB', JSON.stringify(await idbDocs()));
await type('后续段');
L('U3-TYPED-IDB', JSON.stringify(await idbDocs()));
await back();
// U4: 待办块回车
await newMemo(); await clickFirstPara();
await type('[ ] 待办中段');
await clickFirstPara();
await page.keyboard.press('End');
await page.keyboard.press('Enter'); await page.waitForTimeout(500);
L('U4-IDB', JSON.stringify(await idbDocs()));
await type('后续段');
L('U4-TYPED-IDB', JSON.stringify(await idbDocs()));
await back();
await browser.close();
L('DONE');
