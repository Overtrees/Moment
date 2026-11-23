// Rust 版验证：智能前缀转换 + 新建/单空段自动聚焦
// 用法: node probe_prefix_rust.mjs [base]  (默认 http://localhost:8231/)
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8231/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, permissions: ['clipboard-read', 'clipboard-write'] });
const page = await ctx.newPage();
let fails = 0;
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
const L = (...a) => console.log(...a);
const check = (name, cond, extra = '') => { L((cond ? 'PASS' : 'FAIL'), name, extra); if (!cond) fails++; };

const idbDoc = () => page.evaluate(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const raw = await new Promise((res, rej) => { const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  const v = typeof raw === 'string' ? JSON.parse(raw) : raw;
  const memos = Array.isArray(v) ? v : (v.memos || []);
  return memos.map((m) => ({ title: m.title, doc: (m.doc || []).map((b) => ({ type: b.type, level: b.attrs && b.attrs.level, checked: b.attrs && b.attrs.checked, text: ((b.children || []).map((c) => c.text || '').join('')).slice(0, 26) })) }));
});
const newestDoc = async () => {
  const all = await idbDoc();
  if (!all || !all.length) return null;
  return all[all.length - 1].doc; // 新建备忘 push 在末尾（main.rs 口径）
};
const selDump = () => page.evaluate(() => {
  const s = window.getSelection();
  const n = s && s.anchorNode;
  const el = n ? (n.nodeType === 1 ? n : n.parentElement) : null;
  const blk = el && el.closest ? el.closest('[data-bid]') : null;
  return { active: (document.activeElement && (document.activeElement.dataset && document.activeElement.dataset.bid || document.activeElement.className) || '').toString().slice(0, 30), blkText: blk ? (blk.textContent || '').slice(0, 24) : null, off: s ? s.anchorOffset : null };
});
const newMemo = async () => {
  await page.locator('.list-item', { hasText: '新建笔记' }).first().click();
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1500);
};
const back = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(1300); };
const type = async (t) => { await page.keyboard.type(t, { delay: 25 }); await page.waitForTimeout(700); };

await page.goto(base, { waitUntil: 'load' });
await page.waitForTimeout(3000);

// ===== R1：新建自动聚焦 =====
await newMemo();
{
  const s = await selDump();
  check('R1 new memo auto-focus in first block', s.blkText !== null && s.off === 0, JSON.stringify(s));
}
await type('# 标题一');
{
  const d = await newestDoc();
  check('R1 "# " -> heading1', !!d && d[0] && d[0].type === 'heading' && d[0].level === 1 && d[0].text === '标题一', JSON.stringify(d));
  const s = await selDump();
  check('R1 caret at end after conversion', s.blkText === '标题一' && s.off === 3, JSON.stringify(s));
}
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('> 引用文');
{
  const d = await newestDoc();
  check('R1 "> " -> quote', !!d && d.some((b) => b.type === 'quote' && b.text === '引用文'), JSON.stringify(d));
}
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
// 待办/引用回车是已调优的延续口径：引用回车产生新引用块，在其中输入 [ ] 不应被转（块已是 quote 非段落）；改走正文段验证 todo：先回列表新建一篇
await back();
await newMemo();
await type('[ ] 待办一');
{
  const d = await newestDoc();
  check('R2 "[ ] " -> todo unchecked', !!d && d[0] && d[0].type === 'todo' && d[0].checked === false && d[0].text === '待办一', JSON.stringify(d));
}
await back();
await newMemo();
await type('[] 待办二');
{
  const d = await newestDoc();
  check('R3 "[] " -> todo', !!d && d[0] && d[0].type === 'todo' && d[0].text === '待办二', JSON.stringify(d));
}
await back();
await newMemo();
await type('## 标题二');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('### 标题三');
{
  const d = await newestDoc();
  check('R4 ## / ### levels', !!d && d[0] && d[0].type === 'heading' && d[0].level === 2 && d[1] && d[1].type === 'heading' && d[1].level === 3, JSON.stringify(d));
}
await back();
await newMemo();
await type('---');
await page.waitForTimeout(500);
{
  const d = await newestDoc();
  check('R5 "---" -> divider (+trailing para)', !!d && d[0] && d[0].type === 'divider', JSON.stringify(d));
  const s = await selDump();
  check('R5 caret in trailing para after divider', s.blkText === '', JSON.stringify(s));
}
await back();
// 不转换组
await newMemo();
await type('#无空格标题');
{
  const d = await newestDoc();
  // 不命中模式的文本按现行架构只在 DOM（靠结构 op 落模型），
  // 故首检看 DOM 渲染态：块仍是 paragraph 且原文完整、无任何块被转
  const dom6 = await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-bid]');
    return el ? { btype: el.dataset.btype, text: el.innerText } : null;
  });
  check('R6 "#x" no conversion', !!d && !d.some((b) => b.type !== 'paragraph') && !!dom6 && dom6.btype === 'paragraph' && dom6.text === '#无空格标题', JSON.stringify({ d, dom6 }));
}
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('> [!NOTE] 标注文');
{
  const d = await newestDoc();
  check('R6 callout guard no quote conversion', !!d && !d.some((b) => b.type === 'quote'), JSON.stringify(d));
}
await back();
// 列表/有序回车：无前缀延续（与原版一致）
await newMemo();
await type('- 列表甲');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
await type('1. 第一项');
await page.keyboard.press('Enter'); await page.waitForTimeout(400);
{
  const d = await newestDoc();
  check('R7 list/ordered Enter no prefix added', !!d && d[0] && d[0].text === '- 列表甲' && d[1] && d[1].text === '1. 第一项' && d[2] && d[2].text === '', JSON.stringify(d));
}
await back();
// 粘贴触发转换
await newMemo();
await page.evaluate(() => navigator.clipboard.writeText('# 粘贴标题'));
await page.keyboard.press('Control+V');
await page.waitForTimeout(900);
{
  const d = await newestDoc();
  check('R8 paste "# " converts', !!d && d.some((b) => b.type === 'heading' && b.text === '粘贴标题'), JSON.stringify(d));
}
await back();
// ===== R9/R10：种子旧备忘——单空段聚焦 / 普通不聚焦 =====
await page.evaluate(async () => {
  const seed = { version: 2, exportedAt: '2026-01-01T00:00:00.000Z', avatars: [], memos: [
    { id: 'seedempty1', title: '种子空备忘', pinned: false, createdAt: '2026-01-01T10:00:00.000Z', updatedAt: '2026-01-01T10:00:00.000Z', doc: [{ id: 'se1', type: 'paragraph', children: [{ text: '' }] }] },
    { id: 'seednorm1', title: '种子普通备忘', pinned: false, createdAt: '2026-01-02T10:00:00.000Z', updatedAt: '2026-01-02T10:00:00.000Z', doc: [{ id: 'sn1', type: 'paragraph', children: [{ text: '已有内容' }] }] },
  ] };
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  await new Promise((res, rej) => { const rq = db.transaction('kv', 'readwrite').objectStore('kv').put(JSON.stringify(seed), 'memos_json'); rq.onsuccess = () => res(); rq.onerror = () => rej(rq.error); });
});
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(3000);
const openByTitle = async (t) => {
  for (let i = 0; i < 4; i++) {
    const card = page.locator('.list-item', { hasText: t }).first();
    if (await card.count()) {
      await card.click();
      try { await page.waitForSelector('.editor-body', { timeout: 2500 }); return true; } catch (e) {}
    }
    const ex = page.locator('.expand-btn').first();
    if (await ex.count()) { await ex.click(); await page.waitForTimeout(800); } else break;
  }
  return false;
};
check('R9 seeded empty memo opens', await openByTitle('种子空备忘'));
await page.waitForTimeout(600);
{
  const s = await selDump();
  check('R9 single-empty old memo auto-focus', s.blkText !== null && s.off === 0, JSON.stringify(s));
}
await back();
check('R10 seeded normal memo opens', await openByTitle('种子普通备忘'));
await page.waitForTimeout(600);
{
  const s = await selDump();
  check('R10 normal old memo NOT auto-focused', s.blkText === null, JSON.stringify(s));
}
await back();
L(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
await browser.close();
