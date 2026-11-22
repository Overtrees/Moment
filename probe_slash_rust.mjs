// 审计探针：Rust 版斜杠菜单逐项实测（只读审计用）
import { chromium } from 'playwright-core';

const url = 'http://localhost:8102/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const L = (...a) => console.log(...a);

const readDoc = () => page.evaluate(() => new Promise((res) => {
  const req = indexedDB.open('mynote-web', 1);
  req.onsuccess = () => {
    const g = req.result.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    g.onsuccess = () => { try { res(JSON.parse(g.result)); } catch { res(null); } };
    g.onerror = () => res(null);
  };
  req.onerror = () => res(null);
}));

async function newMemo() {
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('新建'));
    if (el) el.click();
  });
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(500);
}
async function backToList() {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
  await page.waitForTimeout(300);
}
async function curDoc() {
  const all = await readDoc();
  if (!all || !all.memos) return null;
  // 当前编辑的备忘 = updatedAt 最新的一条不稳，用标题匹配：取 doc 最长的测试备忘
  return all.memos;
}
async function focusFirstBlock() {
  await page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.focus());
}
async function openSlash(filterText) {
  await focusFirstBlock();
  await page.keyboard.type('/');
  await page.waitForSelector('#slash-panel', { timeout: 5000 });
  if (filterText) { await page.keyboard.type(filterText); await page.waitForTimeout(400); }
}
async function panelInfo() {
  return page.evaluate(() => {
    const p = document.querySelector('#slash-panel');
    if (!p) return null;
    const r = p.getBoundingClientRect();
    const cs = getComputedStyle(p);
    return {
      rect: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
      radius: cs.borderRadius, z: cs.zIndex, maxH: cs.maxHeight,
      heads: [...p.querySelectorAll('.slash-section-heading')].map((e) => e.textContent),
      rows: [...p.querySelectorAll('.slash-row')].map((e) => ({
        act: e.dataset.act, sel: e.classList.contains('sel'),
        title: e.querySelector('.slash-row-title-text')?.textContent,
        sub: e.querySelector('.slash-row-subtitle')?.textContent,
        shortcut: e.querySelector('.slash-shortcut')?.textContent || '',
        pill: !!e.querySelector('.slash-recent-pill'),
        mark: !!e.querySelector('.slash-match'),
        h: Math.round(e.getBoundingClientRect().height),
      })),
      empty: p.querySelector('.slash-empty-state')?.textContent || '',
    };
  });
}

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });

// ---------- 1. 面板度量（空备忘首块） ----------
await newMemo();
await openSlash();
let info = await panelInfo();
L('PANEL', JSON.stringify({ rect: info.rect, radius: info.radius, z: info.z, maxH: info.maxH, heads: info.heads, rowCount: info.rows.length, rowH: info.rows[0]?.h }));
L('ROWACTS', info.rows.map((r) => r.act).join(','));
const blockRect = await page.evaluate(() => {
  const el = document.querySelector('#editor-root [data-bid]');
  const r = el.getBoundingClientRect();
  return { x: Math.round(r.x), top: Math.round(r.top), bottom: Math.round(r.bottom) };
});
L('BLOCKRECT', JSON.stringify(blockRect), 'panelTop-blockBottom =', info.rect.y - blockRect.bottom);

// ---------- 2. 触发位置：块中打 / ----------
await page.keyboard.press('Escape');
await page.waitForTimeout(300);
await focusFirstBlock();
await page.keyboard.type('abc');
await page.waitForTimeout(200);
await page.keyboard.type('/');
await page.waitForTimeout(600);
L('MID_TRIGGER panel?', await page.evaluate(() => !!document.querySelector('#slash-panel')));
// 清空重来
await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); el.focus(); document.execCommand('selectAll', false, null); });
await page.keyboard.press('Backspace');
await page.waitForTimeout(300);

// ---------- 3. 搜索命中 ----------
for (const q of ['fgx', 'bt', 'yykp', 'tp', 'unordered', 'code_block', 'list', '图']) {
  await openSlash(q);
  const pi = await panelInfo();
  L('SEARCH', q, '->', pi.rows.map((r) => r.title).join('|') || ('EMPTY:' + pi.empty));
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
  // 删掉 /query
  await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); el.focus(); document.execCommand('selectAll', false, null); });
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(250);
}

// ---------- 4. 逐条命令应用 → 存储形状 ----------
const cases = [
  ['heading1', 'bt1'], ['heading2', 'bt2'], ['heading3', 'bt3'], ['paragraph', 'wb'],
  ['quote', 'yy'], ['todo', 'db'], ['divider', 'fgx'], ['codeBlock', 'dmk'],
  ['bulletList', 'wxl'], ['numberList', 'yxl'], ['callout', 'callout'],
  ['imgTextCard', 'twkp'], ['imageTextRow', 'twhp'], ['musicCard', 'yykp'],
];
for (const [act, py] of cases) {
  await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); if (el) { el.focus(); document.execCommand('selectAll', false, null); } });
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(150);
  await focusFirstBlock();
  await page.keyboard.type('内容文字');
  await page.waitForTimeout(200);
  await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); if (el) { el.focus(); document.execCommand('selectAll', false, null); document.getSelection().collapseToStart(); } });
  // 光标回块首打 /（Rust 触发要求块首）
  await page.keyboard.type('/' + py);
  await page.waitForSelector('#slash-panel', { timeout: 5000 });
  await page.waitForTimeout(300);
  await page.evaluate((a) => {
    const row = document.querySelector(`#slash-panel .slash-row[data-act="${a}"]`);
    if (row) row.click();
  }, act);
  await page.waitForTimeout(700);
  const memos = await curDoc();
  const mine = memos?.filter((m) => JSON.stringify(m.doc).includes('内容文字') || m.doc.length <= 3).pop();
  L('APPLY', act, JSON.stringify(mine ? mine.doc : null));
  // 恢复：全选删掉回到空段落（逐块删复杂，直接新建备忘继续）
  await backToList();
  await newMemo();
}

// ---------- 5. 图片/画廊（文件选择路径） ----------
for (const [act, py] of [['image', 'tp'], ['gallery', 'hl']]) {
  await openSlash(py);
  await page.waitForTimeout(300);
  const before = await page.evaluate(() => document.querySelectorAll('#editor-root [data-bid]').length);
  await page.evaluate((a) => document.querySelector(`#slash-panel .slash-row[data-act="${a}"]`)?.click(), act);
  await page.waitForTimeout(800);
  const after = await page.evaluate(() => ({
    blocks: document.querySelectorAll('#editor-root [data-bid]').length,
    placeholder: !!document.querySelector('#editor-root .atomic-placeholder'),
    panel: !!document.querySelector('#slash-panel'),
  }));
  L('MEDIA', act, 'before', before, 'after', JSON.stringify(after));
  await backToList();
  await newMemo();
}

// ---------- 6. 行内命令 ----------
async function inlineCase(act, py, withText) {
  await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); if (el) { el.focus(); document.execCommand('selectAll', false, null); } });
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(150);
  if (withText) {
    await focusFirstBlock();
    await page.keyboard.type('选中文字段落');
    await page.waitForTimeout(200);
    // 选中前四字
    await page.evaluate(() => {
      const el = document.querySelector('#editor-root [data-bid]');
      const tn = el.firstChild;
      const r = document.createRange(); r.setStart(tn, 0); r.setEnd(tn, 4);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
    });
    await page.waitForTimeout(150);
  }
  await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); if (el) { el.focus(); document.execCommand('selectAll', false, null); document.getSelection().collapseToStart(); } });
  if (withText) {
    // 重新选中（collapse 后选区丢失——记录 Rust 实际可达路径：块首 / 后 Enter 应用）
  }
  await page.keyboard.type('/' + py);
  await page.waitForSelector('#slash-panel', { timeout: 5000 });
  await page.waitForTimeout(300);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(600);
  const dom = await page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.innerHTML);
  const memos = await curDoc();
  const mine = memos?.filter((m) => JSON.stringify(m.doc).includes('选中') || JSON.stringify(m.doc).includes('文字')).pop();
  L('INLINE', act, 'sel=' + withText, 'DOM=', dom, 'DOC=', JSON.stringify(mine?.doc));
  await backToList();
  await newMemo();
}
await inlineCase('bold', 'jc', false);
await inlineCase('bold', 'jc', true);
await inlineCase('code', 'dm', true);
await inlineCase('highlight', 'gl', false);

// ---------- 7. 链接表单 ----------
await openSlash('lj');
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="link"]')?.click());
await page.waitForTimeout(500);
const linkForm = await page.evaluate(() => {
  const p = document.querySelector('#slash-panel');
  if (!p) return null;
  const input = p.querySelector('.slash-link-input');
  return {
    hasForm: !!p.querySelector('.slash-link-form'),
    placeholder: input?.getAttribute('placeholder'), value: input?.value,
    focused: document.activeElement === input,
    title: p.querySelector('.slash-link-title')?.textContent,
    btns: [...p.querySelectorAll('.slash-link-actions button')].map((b) => b.textContent),
  };
});
L('LINKFORM', JSON.stringify(linkForm));
// 取消 → 面板应回列表（原版）还是全关？
await page.evaluate(() => [...document.querySelectorAll('#slash-panel .slash-link-actions button')][0]?.click());
await page.waitForTimeout(400);
L('LINKCANCEL panel?', await page.evaluate(() => !!document.querySelector('#slash-panel')));

// ---------- 8. Esc / 点外关闭 ----------
await openSlash();
await page.keyboard.press('Escape');
await page.waitForTimeout(300);
L('ESC panel?', await page.evaluate(() => !!document.querySelector('#slash-panel')));
await openSlash();
await page.mouse.click(350, 700); // 点编辑区空白（面板外）
await page.waitForTimeout(500);
L('OUTCLICK panel?', await page.evaluate(() => !!document.querySelector('#slash-panel')));
await page.keyboard.press('Escape').catch(() => {});

// ---------- 9. 最近使用 ----------
await page.evaluate(() => { const el = document.querySelector('#editor-root [data-bid]'); if (el) { el.focus(); document.execCommand('selectAll', false, null); } });
await page.keyboard.press('Backspace');
await openSlash('fgx');
await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="divider"]')?.click());
await page.waitForTimeout(600);
await page.evaluate(() => { const els = document.querySelectorAll('#editor-root [data-bid]'); els[els.length - 1]?.focus(); });
await page.keyboard.type('/');
await page.waitForSelector('#slash-panel', { timeout: 5000 });
await page.waitForTimeout(300);
const rec = await panelInfo();
L('RECENT', JSON.stringify({ heads: rec.heads, firstRows: rec.rows.slice(0, 4) }));

L('ERRORS', JSON.stringify(errors));
await browser.close();
