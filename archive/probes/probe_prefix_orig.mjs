// 原版活体实测：智能前缀触发 + 新建自动聚焦 + 列表/有序/粘贴回车行为
import { chromium } from 'playwright-core';
const base = 'http://localhost:8222/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, permissions: ['clipboard-read', 'clipboard-write'] });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
const L = (...a) => console.log(...a);

const selDump = () => page.evaluate(() => {
  const s = window.getSelection();
  const n = s && s.anchorNode;
  const el = n ? (n.nodeType === 1 ? n : n.parentElement) : null;
  const blk = el && el.closest ? el.closest('[data-blockid]') : null;
  return {
    active: (document.activeElement && document.activeElement.className || '').toString().slice(0, 30),
    blkType: blk ? blk.dataset.type || '(none)' : null,
    blkText: blk ? (blk.textContent || '').slice(0, 24) : null,
    off: s ? s.anchorOffset : null,
  };
});
const domBlocks = () => page.evaluate(() =>
  [...document.querySelectorAll('.editor-body [data-blockid]')].map((e) => ({
    type: e.dataset.type || '(none)', ce: e.contentEditable,
    text: (e.textContent || '').replace(/\s+/g, ' ').slice(0, 30),
  })));
const storedDoc = () => page.evaluate(() => {
  const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
  if (!arr.length) return null;
  const m = arr.reduce((a, b) => (a.createdAt > b.createdAt ? a : b));
  return m.doc.map((b) => ({ type: b.type, level: b.attrs && b.attrs.level, checked: b.attrs && b.attrs.checked, text: ((b.children || []).map((c) => c.text || '').join('')).slice(0, 30) }));
});
const newMemo = async () => {
  const card = page.locator('.list-item', { hasText: '新建笔记' }).first();
  await card.click();
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1300);
};
const back = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(1300); };
const type = async (t) => { await page.keyboard.type(t, { delay: 25 }); await page.waitForTimeout(650); };

await page.goto(base + 'Moment.html', { waitUntil: 'load' });
await page.waitForTimeout(3200);

// ===== 备忘1：自动聚焦 + 转换链 # / > / [ ] / [] / --- =====
await newMemo();
L('FOCUS-AFTER-NEW', JSON.stringify(await selDump()));
await type('# 标题一');
L('CONV-H1', JSON.stringify(await domBlocks()));
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('> 引用文');
L('CONV-QUOTE', JSON.stringify(await domBlocks()));
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('[ ] 待办一');
L('CONV-TODO1', JSON.stringify(await domBlocks()));
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('[] 待办二');
L('CONV-TODO2', JSON.stringify(await domBlocks()));
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('---');
L('CONV-DIVIDER', JSON.stringify(await domBlocks()));
L('SEL-AFTER-DIVIDER', JSON.stringify(await selDump()));
L('STORED-1', JSON.stringify(await storedDoc()));
await back();

// ===== 备忘2：## / ### / >无空格 =====
await newMemo();
await type('## 标题二');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('### 标题三');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('>无空格引用');
L('STORED-2', JSON.stringify(await storedDoc()));
await back();

// ===== 备忘3：不转换组 #无空格 / > [!NOTE] =====
await newMemo();
await type('#无空格标题');
L('NOCONV-HASH', JSON.stringify(await domBlocks()));
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('> [!NOTE] 标注文');
L('STORED-3', JSON.stringify(await storedDoc()));
await back();

// ===== 备忘4：列表/有序回车 =====
await newMemo();
await type('- 列表甲');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
L('LIST-ENTER', JSON.stringify(await domBlocks()));
await type('1. 第一项');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
L('ORDERED-ENTER', JSON.stringify(await domBlocks()));
L('STORED-4', JSON.stringify(await storedDoc()));
await back();

// ===== 备忘5：粘贴 =====
await newMemo();
await page.evaluate(() => navigator.clipboard.writeText('# 粘贴标题'));
await page.keyboard.press('Control+V');
await page.waitForTimeout(800);
L('PASTE-H1', JSON.stringify(await domBlocks()));
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await page.evaluate(() => navigator.clipboard.writeText('- 粘甲\n- 粘乙\n1. 粘丙'));
await page.keyboard.press('Control+V');
await page.waitForTimeout(800);
L('PASTE-MULTI', JSON.stringify(await domBlocks()));
L('STORED-5', JSON.stringify(await storedDoc()));
await back();

// ===== 备忘6（种子）：单空段旧备忘自动聚焦 / 普通旧备忘不聚焦 =====
await page.evaluate(async () => {
  const now = new Date().toISOString();
  const seed = [
    { id: 'seedempty1', title: '种子空备忘', doc: [{ id: 'se1', type: 'paragraph', children: [{ text: '' }] }], pinned: false, createdAt: now, updatedAt: now },
    { id: 'seednorm1', title: '种子普通备忘', doc: [{ id: 'sn1', type: 'paragraph', children: [{ text: '已有内容' }] }], pinned: false, createdAt: now, updatedAt: now },
  ];
  localStorage.setItem('memos_app_v2', JSON.stringify(seed));
  try {
    const db = await window.MynoteIdb.getDB();
    await window.MynoteIdb.saveMemosToDB(db, seed);
  } catch (e) { console.log('seed idb failed', String(e).slice(0, 100)); }
});
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2800);
const openByTitle = async (t) => {
  const card = page.locator('.list-item', { hasText: t }).first();
  await card.click();
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1100);
};
await openByTitle('种子空备忘');
L('FOCUS-SEEDED-EMPTY', JSON.stringify(await selDump()));
await back();
await openByTitle('种子普通备忘');
L('FOCUS-SEEDED-NORMAL', JSON.stringify(await selDump()));
await back();

await browser.close();
L('DONE');
