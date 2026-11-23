// 探针（Rust）：尾随空段模型化验收——尾随位置是真实可编辑
// 段落块（有 data-bid）、点击落光标、输入落盘、重开不增不
// 减、退格/回车/撤销行为、Diag 物化记录、MD 导出无多余空段。
import { chromium } from 'playwright-core';
const url = process.argv[2] || 'http://localhost:8208/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

async function importZip(zip) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 }).catch(() => {});
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.waitForTimeout(400);
}
async function openMemo(title) {
  // 折叠组先展开（代表卡点标题是展开不是打开，与原版同）；
  // 列表按最近编辑重排，展开态/位置每轮都可能变，循环尝试。
  const titlePt = (t) => page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt
        && !e.querySelector('.expand-btn'));
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, t);
  let pt = null;
  for (let attempt = 0; attempt < 4 && !pt; attempt++) {
    pt = await titlePt(title);
    if (pt) break;
    const ex = await page.evaluate(() => {
      const b = document.querySelector('.expand-btn');
      if (!b) return null;
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (ex) { await page.mouse.click(ex.x, ex.y); await page.waitForTimeout(700); }
    else await page.waitForTimeout(500);
  }
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(800);
}
const goBack = async () => {
  await page.click('#editor-root .editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
  await page.waitForTimeout(400);
};
// 编辑器块流（拍平双栏容器）：cls/bid/btype/可编辑/文本
const dumpBlocks = () => page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  if (!body) return [];
  const out = [];
  const walk = (root) => [...root.children].forEach((el) => {
    if (el.classList?.contains('editor-column')) { walk(el); return; }
    out.push({
      cls: (el.className || '').slice(0, 44),
      bid: el.dataset?.bid || el.querySelector?.('[data-bid]')?.dataset?.bid || '',
      btype: el.dataset?.btype || el.querySelector?.('[data-bid]')?.dataset?.btype || '',
      ce: el.isContentEditable || !!el.querySelector?.('[contenteditable="true"]'),
      text: (el.textContent || '').replace(/\s+/g, ' ').slice(0, 24),
    });
  });
  walk(body);
  return out;
});
const readDoc = (title) => page.evaluate(async (t) => {
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('mynote-web', 1);
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const raw = await new Promise((res, rej) => {
    const rq = db.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error);
  });
  const data = JSON.parse(raw);
  const memos = Array.isArray(data) ? data : data.memos;
  const m = (memos || []).find((x) => x.title === t);
  return m ? m.doc : null;
}, title);
const selInfo = () => page.evaluate(() => {
  const s = getSelection();
  const el = s.anchorNode?.nodeType === 1 ? s.anchorNode : s.anchorNode?.parentElement;
  const blk = el?.closest?.('[data-bid]');
  return { bid: blk?.dataset?.bid || '', off: s.focusOffset, inTrailText: (blk?.textContent || '').slice(0, 20) };
});
const clickBlock = async (pred, label) => {
  const pt = await page.evaluate((p) => {
    const body = document.querySelector('.editor-body');
    const els = [];
    const walk = (root) => [...root.children].forEach((el) => {
      if (el.classList?.contains('editor-column')) { walk(el); return; }
      els.push(el);
    });
    walk(body);
    const el = els[p.index] || null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + Math.min(30, r.width / 2), y: r.y + r.height / 2 };
  }, pred);
  if (!pt) { ok(label + ' 可点击', false, 'element not found'); return false; }
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(450);
  return true;
};

await importZip('fixtures/trail.zip');

// ---------- 甲：文末预览 → 真实尾随段 ----------
await openMemo('尾随甲');
let blocks = await dumpBlocks();
L('A blocks', JSON.stringify(blocks));
ok('A 无 .md-trail 视图占位', !blocks.some((b) => b.cls.includes('md-trail')));
const lastA = blocks[blocks.length - 1];
ok('A 末块是带 bid 的可编辑段落', !!lastA.bid && lastA.ce && lastA.text === '', JSON.stringify(lastA));
await clickBlock({ index: blocks.length - 1 }, 'A 尾随段');
let sel = await selInfo();
ok('A 点击尾随段光标落入', sel.bid === lastA.bid, JSON.stringify(sel));
await page.keyboard.insertText('尾巴文字甲');
await page.waitForTimeout(800);
blocks = await dumpBlocks();
ok('A 输入进入尾随段', blocks[blocks.length - 1].text.includes('尾巴文字甲'), JSON.stringify(blocks[blocks.length - 1]));
// 撤销：文字消、段落留
await page.keyboard.press('Control+z');
await page.waitForTimeout(700);
blocks = await dumpBlocks();
const lastAfterUndo = blocks[blocks.length - 1];
ok('A 撤销后文字消但尾随段仍在', !!lastAfterUndo.bid && lastAfterUndo.text === '', JSON.stringify(lastAfterUndo));
await page.keyboard.insertText('尾巴文字甲');
await page.waitForTimeout(600);
await goBack();
const docA = await readDoc('尾随甲');
L('A stored', JSON.stringify(docA));
ok('A 落盘 doc 末块为真实段落且含输入文字',
  !!docA && docA[docA.length - 1].type === 'paragraph'
  && (docA[docA.length - 1].children?.[0]?.text || '') === '尾巴文字甲');
await openMemo('尾随甲');
blocks = await dumpBlocks();
ok('A 重开尾随段恰一块不多生', blocks.length === 3 && blocks[2].text.includes('尾巴文字甲'), `blocks=${blocks.length}`);
await goBack();

// ---------- 乙：预览 → 图片之间的尾随段 ----------
await openMemo('尾随乙');
blocks = await dumpBlocks();
L('B blocks', JSON.stringify(blocks));
const imgIdx = blocks.findIndex((b) => b.cls.startsWith('blk-wrap'));
const midB = imgIdx > 0 ? blocks[imgIdx - 1] : null;
ok('B 预览与图片之间是带 bid 的可编辑空段', !!midB && !!midB.bid && midB.ce && midB.text === '', JSON.stringify(midB));
if (midB) {
  await clickBlock({ index: imgIdx - 1 }, 'B 中间尾随段');
  sel = await selInfo();
  ok('B 点击中间尾随段光标落入', sel.bid === midB.bid, JSON.stringify(sel));
  await page.keyboard.insertText('乙尾巴');
  await page.waitForTimeout(700);
}
await goBack();
const docB = await readDoc('尾随乙');
ok('B 落盘 doc[1] 为段落且含输入文字',
  !!docB && docB[1].type === 'paragraph' && (docB[1].children?.[0]?.text || '') === '乙尾巴', JSON.stringify(docB?.map((d) => d.type)));

// ---------- 丙：文末分割线 → 原版口径不补（裸 hr 无 data-type） ----------
await openMemo('尾随丙');
blocks = await dumpBlocks();
L('C blocks', JSON.stringify(blocks));
ok('C 文末分割线打开时不补尾随段（与原版活体一致，共 2 块）', blocks.length === 2, `blocks=${blocks.length}`);
await goBack();
const docC = await readDoc('尾随丙');
ok('C 落盘 doc 仍为 [段落, 分割线]', !!docC && docC.length === 2 && docC[1].type === 'divider', JSON.stringify(docC?.map((d) => d.type)));

// ---------- 庚：文末图片（带 data-type） → 真实尾随段 ----------
await openMemo('尾随庚');
blocks = await dumpBlocks();
L('G blocks', JSON.stringify(blocks));
const lastG = blocks[blocks.length - 1];
ok('G 图片后是带 bid 的可编辑空段', !!lastG.bid && lastG.ce && lastG.text === '', JSON.stringify(lastG));
await clickBlock({ index: blocks.length - 1 }, 'G 尾随段');
await page.keyboard.insertText('庚尾巴');
await page.waitForTimeout(700);
await goBack();
const docG = await readDoc('尾随庚');
ok('G 落盘 doc 末块为含字段落', !!docG && docG[docG.length - 1].type === 'paragraph'
  && (docG[docG.length - 1].children?.[0]?.text || '') === '庚尾巴', JSON.stringify(docG?.map((d) => d.type)));

// ---------- 丁：表格预览 → 列表组之间的尾随段 + 回车 ----------
await openMemo('尾随丁');
blocks = await dumpBlocks();
L('D blocks', JSON.stringify(blocks));
const midD = blocks[1];
ok('D 表格预览与列表之间是可编辑空段', !!midD && !!midD.bid && midD.ce && midD.text === '', JSON.stringify(midD));
if (midD && midD.bid) {
  await clickBlock({ index: 1 }, 'D 尾随段');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(600);
  blocks = await dumpBlocks();
  ok('D 尾随段回车分出新段', blocks.length >= 4, `blocks=${blocks.length}`);
}
await goBack();

// ---------- 戊：相邻预览（原版活体：之间与文末各一段） ----------
await openMemo('尾随戊');
blocks = await dumpBlocks();
L('E blocks', JSON.stringify(blocks));
ok('E 相邻预览之间也有尾随段（共 4 块）', blocks.length === 4, `blocks=${blocks.length}`);
const midE = blocks[1];
ok('E 两预览之间是可编辑空段', !!midE && !!midE.bid && midE.ce && midE.text === '', JSON.stringify(midE));
const lastE = blocks[blocks.length - 1];
ok('E 文末是可编辑空段', !!lastE.bid && lastE.ce && lastE.text === '', JSON.stringify(lastE));
// 空尾随段段首退格（记录行为，不断言具体形态——与原版对照在报告中说明）
await clickBlock({ index: blocks.length - 1 }, 'E 尾随段');
await page.keyboard.press('Backspace');
await page.waitForTimeout(700);
blocks = await dumpBlocks();
sel = await selInfo();
L('E backspace-at-trail-start', JSON.stringify({ blocks: blocks.map((b) => b.cls.split(' ')[0] + ':' + b.text), sel }));
await goBack();

// ---------- 己：对照组不补 ----------
await openMemo('尾随己');
blocks = await dumpBlocks();
L('F blocks', JSON.stringify(blocks));
ok('F 预览后接普通段不补（共 2 块）', blocks.length === 2, `blocks=${blocks.length}`);
await goBack();

// ---------- Diag 物化记录 ----------
const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
ok('Diag 有 trail materialized 记录', diag.includes('trail materialized'), '');

// ---------- MD 导出：尾随段文字成段、无多余空段 ----------
await openMemo('尾随甲');
await page.locator('.editor-fab.right').click();
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
const dlPromise = page.waitForEvent('download', { timeout: 15000 });
await page.click('[data-export-format="markdown"]');
const dl = await dlPromise;
const mdPath = '/tmp/trail_export.md';
await dl.saveAs(mdPath);
const { execSync } = await import('node:child_process');
const md = execSync(`cat ${mdPath}`).toString();
L('MD export tail', JSON.stringify(md.slice(-80)));
ok('MD 导出含尾随段文字', md.includes('尾巴文字甲'));
ok('MD 导出不以多余空行收尾', md.endsWith('\n') && !md.endsWith('\n\n\n'));
await page.waitForTimeout(500);

await browser.close();
L(fails === 0 ? 'TRAIL ALL PASS' : `TRAIL FAILS=${fails}`);
process.exit(fails === 0 ? 0 : 1);
