// 问题 2 验证探针：新备忘关闭删除语义（原版 handleClose 口径）
// A 仅打标题 → 应保留；B 全空未动 → 应删除；C 正文打字后删光 → 应保留
// 用法: node probe_close_empty.mjs <base>
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8200/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));

const titles = () => page.evaluate(() =>
  [...document.querySelectorAll('.list-item .item-title-text')].map((e) => e.innerText.trim()).filter((t) => t && t !== '新建笔记'));
// 持久层口径（列表 DOM 有日期组折叠，计数不可靠）：IDB
// mynote-web/kv 的 memos_json 才是备忘全集
const persistedTitles = () => page.evaluate(async () => {
  const db = await new Promise((res, rej) => { const r = indexedDB.open('mynote-web', 1); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const raw = await new Promise((res, rej) => { const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json'); rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error); });
  const v = typeof raw === 'string' ? JSON.parse(raw) : raw;
  const memos = Array.isArray(v) ? v : (v.memos || []);
  return memos.map((m) => (m.title || '').trim());
});
const deletedCount = () => page.evaluate(() =>
  ((localStorage.getItem('mynote_diag_v1') || '').match(/close empty memo -> deleted/g) || []).length);

async function newMemo() {
  await page.locator('.list-item', { hasText: '新建笔记' }).first().click();
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(700);
}
async function back() {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(700);
}

await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
const t0 = await titles();
console.log('initial titles:', JSON.stringify(t0));
const d0 = await deletedCount();

// B：全空未动 → 应删除
await newMemo();
await back();
const tB = await titles();
ok('B 全空新备忘关闭即删除（列表无新增）', tB.length === t0.length, `${t0.length} -> ${tB.length}`);
ok('B Diag 记录 close empty deleted', (await deletedCount()) === d0 + 1, await deletedCount());

// A：仅打标题 → 应保留
await newMemo();
await page.click('#editor-title-text');
await page.waitForTimeout(300);
await page.keyboard.type('只有标题的备忘');
await page.waitForTimeout(600);
await back();
const tA = await titles();
ok('A 仅标题新备忘关闭后保留在列表', tA.includes('只有标题的备忘'), JSON.stringify(tA));
ok('A 未触发空删除', (await deletedCount()) === d0 + 1, await deletedCount());
const pA = await persistedTitles();

// C：正文打字后删光 → 应保留（hasTyped 粘性）
await newMemo();
const pt = await page.evaluate(() => {
  const el = document.querySelector('.editor-body [data-bid]');
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
});
await page.mouse.click(pt.x, pt.y);
await page.keyboard.type('临时内容');
await page.waitForTimeout(500);
await page.keyboard.press('Backspace');
await page.keyboard.press('Backspace');
await page.keyboard.press('Backspace');
await page.keyboard.press('Backspace');
await page.waitForTimeout(500);
await back();
const pC = await persistedTitles();
ok('C 正文打字后删光仍保留（持久层 +1）', pC.length === pA.length + 1, `${pA.length} -> ${pC.length}`);
ok('C 未触发空删除', (await deletedCount()) === d0 + 1, await deletedCount());

await browser.close();
console.log('ERRORS: ' + (failures ? `${failures} assertion(s) failed` : 'none'));
process.exit(failures ? 1 : 0);
