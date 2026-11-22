// 原版活体实测 2：逐模式隔离（todo/[]/---/>无空格/转换后光标/引用待办回车/扫描全doc）
import { chromium } from 'playwright-core';
const base = 'http://localhost:8222/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
const L = (...a) => console.log(...a);
const selDump = () => page.evaluate(() => {
  const s = window.getSelection();
  const n = s && s.anchorNode;
  const el = n ? (n.nodeType === 1 ? n : n.parentElement) : null;
  const blk = el && el.closest ? el.closest('[data-blockid]') : null;
  return { blkText: blk ? (blk.textContent || '').slice(0, 24) : null, off: s ? s.anchorOffset : null, nodeText: n ? (n.textContent || '').slice(0, 24) : null };
});
const storedDoc = () => page.evaluate(() => {
  const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
  if (!arr.length) return null;
  const m = arr.reduce((a, b) => (a.createdAt > b.createdAt ? a : b));
  return m.doc.map((b) => ({ type: b.type, level: b.attrs && b.attrs.level, checked: b.attrs && b.attrs.checked, text: ((b.children || []).map((c) => c.text || '').join('')).slice(0, 30) }));
});
const newMemo = async () => {
  await page.locator('.list-item', { hasText: '新建笔记' }).first().click();
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1200);
};
const back = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(1200); };
// 点第一个可编辑段落确保光标在正文（避开自动聚焦状态干扰）
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

// T1: [ ] 待办
await newMemo(); await clickFirstPara();
await type('[ ] 待办甲');
L('T1-TODO', JSON.stringify(await storedDoc()), 'SEL', JSON.stringify(await selDump()));
await back();
// T2: [] 待办
await newMemo(); await clickFirstPara();
await type('[] 待办乙');
L('T2-TODO-BRACKET', JSON.stringify(await storedDoc()));
await back();
// T3: --- 分隔线
await newMemo(); await clickFirstPara();
await type('---');
L('T3-DIVIDER', JSON.stringify(await storedDoc()), 'SEL', JSON.stringify(await selDump()));
await back();
// T4: >无空格
await newMemo(); await clickFirstPara();
await type('>无空格引用');
L('T4-QUOTE-NOSPACE', JSON.stringify(await storedDoc()));
await back();
// T5: # 转换后光标在文末
await newMemo(); await clickFirstPara();
await type('# 标');
L('T5-CARET', JSON.stringify(await storedDoc()), 'SEL', JSON.stringify(await selDump()));
await back();
// T6: 引用块内回车（B1?）
await newMemo(); await clickFirstPara();
await type('> 引用中段');
await clickFirstPara(); // 光标进引用块
await page.keyboard.press('End');
await page.keyboard.press('Enter'); await page.waitForTimeout(500);
L('T6-QUOTE-ENTER', JSON.stringify(await storedDoc()), 'SEL', JSON.stringify(await selDump()));
await type('后续段');
L('T6-AFTER-TYPE', JSON.stringify(await storedDoc()));
await back();
// T7: 待办块内回车（B1?）
await newMemo(); await clickFirstPara();
await type('[ ] 待办中段');
await clickFirstPara();
await page.keyboard.press('End');
await page.keyboard.press('Enter'); await page.waitForTimeout(500);
L('T7-TODO-ENTER', JSON.stringify(await storedDoc()), 'SEL', JSON.stringify(await selDump()));
await back();
// T8: 扫描全 doc——在别的段落输入时，下方既存的 "# 旧" 段是否被转换
await page.evaluate(async () => {
  const now = new Date().toISOString();
  const seed = [{ id: 'seedscan1', title: '种子扫描备忘', pinned: false, createdAt: now, updatedAt: now, doc: [
    { id: 'ss1', type: 'paragraph', children: [{ text: '普通首段' }] },
    { id: 'ss2', type: 'paragraph', children: [{ text: '# 旧标题段' }] },
    { id: 'ss3', type: 'paragraph', children: [{ text: '> 旧引用段' }] },
  ] }];
  localStorage.setItem('memos_app_v2', JSON.stringify(seed));
  try { const db = await window.MynoteIdb.getDB(); await window.MynoteIdb.saveMemosToDB(db, seed); } catch (e) {}
});
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2800);
await page.locator('.list-item', { hasText: '种子扫描备忘' }).first().click();
await page.waitForSelector('.editor-body', { timeout: 10000 });
await page.waitForTimeout(1200);
await clickFirstPara();
await page.keyboard.press('End');
await type('x');
L('T8-SCAN-ONE', JSON.stringify(await storedDoc()));
await type('y');
L('T8-SCAN-TWO', JSON.stringify(await storedDoc()));
await back();
await browser.close();
L('DONE');
