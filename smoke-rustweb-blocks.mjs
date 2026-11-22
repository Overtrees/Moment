// Rust Web 全块渲染冒烟：导入 fixtures/allblocks.zip（原版 canonical
// 形状：attrs.level/checked/items + md 源段落），逐项断言渲染度量。
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const ok = (name, cond) => console.log((cond ? '✓ ' : '✗ ') + name);

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForFunction(() => document.body.innerText.includes('全块渲染测试'), { timeout: 15000 });
await page.evaluate(() => {
  const t = document.querySelector('.img-card-title-text') || document.querySelector('.list-item .item-title-text');
  if (t) t.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(1200);

// 方向键跨块（分块架构补齐原版单宿主的天然跨块）：b02 标
// 题末 ArrowRight → b03 标题首；ArrowLeft → 回 b02 末；
// ArrowDown/Up 在单行块间上下跨块（b01 是 md 预览不入列）
const arrowRes = await page.evaluate(() => {
  const el = document.querySelector('[data-bid="b02"]');
  el.focus();
  const r = document.createRange();
  r.selectNodeContents(el);
  r.collapse(false);
  const s = getSelection();
  s.removeAllRanges();
  s.addRange(r);
  return { bid: document.activeElement?.dataset?.bid };
});
await page.keyboard.press('ArrowRight');
await page.waitForTimeout(250);
const arrowR = await page.evaluate(() => ({ bid: document.activeElement?.dataset?.bid, off: getSelection().focusOffset }));
ok('arrow right at block end crosses to next block start', arrowRes.bid === 'b02' && arrowR.bid === 'b03' && arrowR.off === 0);
await page.keyboard.press('ArrowLeft');
await page.waitForTimeout(250);
const arrowL = await page.evaluate(() => {
  const el = document.querySelector('[data-bid="b02"]');
  const s = getSelection();
  const pre = document.createRange();
  pre.selectNodeContents(el);
  pre.setEnd(s.focusNode, s.focusOffset);
  return { bid: document.activeElement?.dataset?.bid, off: pre.toString().length, len: (el.textContent || '').length };
});
ok('arrow left at block start crosses to prev block end', arrowL.bid === 'b02' && arrowL.off === arrowL.len);
await page.keyboard.press('ArrowDown');
await page.waitForTimeout(250);
const arrowD = await page.evaluate(() => document.activeElement?.dataset?.bid);
ok('arrow down on last line crosses to next block', arrowD === 'b03');
await page.keyboard.press('ArrowUp');
await page.waitForTimeout(250);
const arrowU = await page.evaluate(() => document.activeElement?.dataset?.bid);
ok('arrow up on first line crosses to prev block', arrowU === 'b02');

// 标题三级字号（原版实测 h1 28 / h2 23 / h3 20）
const hSizes = await page.evaluate(() => {
  const out = {};
  for (const lv of [1, 2, 3]) {
    const el = document.querySelector('.blk-h' + lv);
    out[lv] = el ? getComputedStyle(el).fontSize : null;
  }
  return out;
});
console.log('HEADING SIZES:', JSON.stringify(hSizes));
ok('heading levels from attrs (28/23/20)', hSizes[1] === '28px' && hSizes[2] === '23px' && hSizes[3] === '20px');

// 待办勾选（attrs.checked）
const todo = await page.evaluate(() => {
  const done = document.querySelector('.todo-row.done');
  return { doneText: done ? done.innerText : '', onBox: !!document.querySelector('.todo-checkbox.on') };
});
ok('todo checked from attrs', todo.doneText.includes('已完成待办') && todo.onBox);

// Callout 预览卡（md 源段落）
const callouts = await page.$$eval('.md-preview .callout .callout-title', (els) => els.map((e) => e.innerText));
console.log('CALLOUTS:', JSON.stringify(callouts));
ok('callout previews with orig titles', callouts.includes('笔记') && callouts.includes('注意') && callouts.includes('提示'));

// 代码预览
const code = await page.$eval('.md-preview pre code', (e) => e.innerText).catch(() => '');
ok('code preview renders inner code', code.includes('fn main()') && !code.includes('```'));

// 列表预览（无序 2 + 有序 3）
const lis = await page.$$eval('.md-preview li', (els) => els.map((e) => e.innerText));
console.log('LIST ITEMS:', JSON.stringify(lis));
ok('list previews render 5 items', lis.length === 5 && lis[4].includes('有序项三'));

// 图库（attrs.items 两张图）
await page.waitForFunction(() => {
  const g = document.querySelector('[data-type="gallery"]');
  return g && [...g.querySelectorAll('img')].filter((i) => i.naturalWidth > 0).length >= 2;
}, { timeout: 10000 }).catch(() => {});
const galImgs = await page.$$eval('[data-type="gallery"] img', (els) => els.filter((i) => i.naturalWidth > 0).length);
ok('gallery renders attrs.items images', galImgs >= 2);

// 链接卡 / 音乐卡
const lk = await page.evaluate(() => document.body.innerText.includes('示例文章标题'));
const mu = await page.evaluate(() => !!document.querySelector('.music-card-link'));
ok('link card + music card render', lk && mu);

// 附件块文件名（审计 E2）：b19 非图附件的文件名按原版
// renderAtomicHTML 口径来自 manifest（测试文档.pdf），
// 不该落「附件」兜底文案
const attNames = await page.$$eval('.attachment-file .att-name', (els) => els.map((e) => e.innerText));
console.log('ATT NAMES:', JSON.stringify(attNames));
ok('attachment block shows manifest filename (E2)', attNames.some((t) => t.includes('测试文档.pdf')));

// 点 Callout 预览 → 源码编辑态；失焦 → 回预览
await page.click('.md-preview .callout-note');
await page.waitForTimeout(600);
const srcOn = await page.evaluate(() => document.activeElement?.dataset?.btype || '');
ok('callout preview click enters source edit', srcOn === 'mdsrc');
// 撤销合并（原版 use-history 口径）：600ms 内连打三字只算
// 一步，Ctrl+Z 一次全撤（旧口径每键一步只会撤掉一个字）
await page.keyboard.type('XYZ');
await page.waitForTimeout(300);
await page.keyboard.press('Control+z');
await page.waitForTimeout(700);
const undoTxt = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.editor-body [data-bid], .editor-body .md-hit')]
    .map((e) => e.textContent || '')
    .find((t) => t.includes('注释类标注块正文'));
  return el || '';
});
ok('undo coalesces 600ms typing burst into one step', undoTxt.includes('注释类标注块正文') && !undoTxt.includes('XYZ'));
await page.click('.detail .ed-line >> nth=0');
await page.waitForTimeout(600);
const backPrev = await page.$$eval('.md-preview .callout', (els) => els.length);
ok('blur returns to callout preview', backPrev >= 3);

// S7 标题编辑期 scrolled 翻转抑制：编辑标题时滚动不许切
// 紧凑坞；失焦后滚动照常翻转（对照）
await page.evaluate(() => window.scrollTo(0, 0));
await page.waitForTimeout(300);
await page.click('#editor-title-text');
await page.waitForTimeout(300);
await page.evaluate(() => window.scrollTo(0, 250));
await page.waitForTimeout(400);
const s7a = await page.evaluate(() => document.querySelector('.editor-title-dock')?.classList.contains('scrolled'));
ok('S7 no scrolled flip while editing title', s7a === false);
await page.click('.detail .ed-line >> nth=0');
await page.waitForTimeout(300);
await page.evaluate(() => window.scrollTo(0, 320));
await page.waitForTimeout(400);
const s7b = await page.evaluate(() => document.querySelector('.editor-title-dock')?.classList.contains('scrolled'));
ok('S7 scrolled flips normally after title blur', s7b === true);
// S8 失焦回顶：滚动态下程序化失焦（等指针守卫过期）→ 回
// 到顶部且坞回未滚动形态（原版 use-editor-dom 口径）
await page.waitForTimeout(600);
await page.evaluate(() => {
  const el = document.querySelector('[data-bid="b21"]');
  if (el) el.focus();
});
await page.waitForTimeout(150);
await page.evaluate(() => { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); });
await page.waitForTimeout(500);
const s8 = await page.evaluate(() => ({
  y: window.scrollY,
  scrolled: document.querySelector('.editor-title-dock')?.classList.contains('scrolled'),
}));
ok('S8 blur forces scroll top + unscrolled dock', s8.y === 0 && s8.scrolled === false);

// ===== 第二阶段：md 边缘语料 e01–e17（fixtures/md-edge.zip，
// 与 audit_slash_md_report.md §二 的双边实测语料同构） =====
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', process.env.HOME + '/workspace/Mynote/fixtures/md-edge.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForFunction(() => document.body.innerText.includes('md边缘'), { timeout: 15000 });
await page.evaluate(() => {
  const t = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('md边缘'));
  if (t) t.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(1200);

const eFacts = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const hits = [...body.querySelectorAll('.md-hit')];
  const hitWith = (fn) => hits.find(fn);
  const txt = (el) => (el ? el.textContent || '' : '');
  const e13 = hitWith((h) => h.textContent.includes('公式'));
  const merged = hits.filter((h) => h.textContent.includes('未完任务'));
  const mg = merged[0];
  return {
    e01: !!body.querySelector('.md-preview pre code.language-js'),
    e02: [...body.querySelectorAll('.md-preview pre code')].some((c) => c.textContent.includes('let y = 2;')),
    e03: [...body.querySelectorAll('.md-preview pre code')].some((c) => c.textContent.includes('plain code')),
    e04title: txt(body.querySelector('details.callout.callout-tip .callout-title')),
    e05: !!hitWith((h) => h.querySelector('h1') && h.textContent.includes('后面一行正文')),
    e06: !!hitWith((h) => h.textContent.includes('前一行') && h.querySelectorAll('ul li').length === 2),
    e07: !!hitWith((h) => h.querySelector('li strong') && h.querySelector('li code') && h.querySelector('li a')),
    e08: !!hitWith((h) => h.querySelector('td strong') && h.querySelector('td code')),
    e09: (() => { const p = body.querySelector('p.md-preview-inline'); return !!p && !!p.querySelector('strong') && !!p.querySelector('em') && !!p.querySelector('del') && !!p.querySelector('code') && !!p.querySelector('a'); })(),
    e10e11count: merged.length,
    e10box: mg ? mg.querySelectorAll('ul li input[type="checkbox"]').length : 0,
    e10checked: mg ? mg.querySelectorAll('ul li input[type="checkbox"]:checked').length : 0,
    e11start: mg ? mg.querySelector('ol')?.getAttribute('start') : null,
    e11items: mg ? mg.querySelectorAll('ol li').length : 0,
    e12: !!body.querySelector('sup.footnote-ref') && [...body.querySelectorAll('section.footnotes li')].some((li) => li.textContent.includes('脚注内容')),
    e13: !!e13 && !!e13.querySelector('sup') && !!e13.querySelector('sub'),
    e14: (() => { const a = body.querySelector('a.mynote-wiki-link'); return !!a && a.dataset.noteTitle === '目标笔记' && a.textContent.includes('显示名'); })(),
    e15: [...body.querySelectorAll('.ed-line')].some((e) => (e.textContent || '').trim() === '***') && body.querySelectorAll('.md-preview hr').length === 0,
    e16: !!hitWith((h) => h.querySelector('h2') && h.textContent.includes('文字下')),
    e17: [...body.querySelectorAll('.md-preview pre code')].some((c) => c.textContent.includes('未闭合代码')),
  };
});
console.log('E-FACTS:', JSON.stringify(eFacts));
ok('e01 fenced code keeps language class', eFacts.e01);
ok('e02 tilde fence renders code', eFacts.e02);
ok('e03 plain fence renders code', eFacts.e03);
ok('e04 folding callout shows default title not dash', eFacts.e04title === '提示');
ok('e05 mixed heading+para renders both', eFacts.e05);
ok('e06 para+list mixed renders p and ul', eFacts.e06);
ok('e07 list items parse inline md', eFacts.e07);
ok('e08 table cells parse inline md', eFacts.e08);
ok('e09 pure inline md becomes inline preview', eFacts.e09);
ok('e10+e11 adjacent list blocks merge into one preview (M6)', eFacts.e10e11count === 1);
ok('e10 task list renders checkboxes with checked state', eFacts.e10box === 2 && eFacts.e10checked === 1);
ok('e11 ordered list keeps start=2 in merged preview', eFacts.e11start === '2' && eFacts.e11items === 2);
ok('e12 footnotes render ref + section', eFacts.e12);
ok('e13 sup/sub render', eFacts.e13);
ok('e14 wiki link with alias renders', eFacts.e14);
ok('e15 *** alone stays plain text (no hr)', eFacts.e15);
ok('e16 setext renders h2 + p', eFacts.e16);
ok('e17 unclosed fence renders code', eFacts.e17);

// M9 预览→源码光标落点：点 e01 代码预览左上 → 转源码后光
// 标在块尾（原版 use-editor-dom 两条还原路径均为
// selectNodeContents + collapse(false)；审计的 focusOffset 1
// 是元素节点子数偏移，与块尾同一位置）
await page.evaluate(() => {
  const hit = [...document.querySelectorAll('.md-hit')].find((h) => h.querySelector('code.language-js'));
  if (hit) hit.click();
});
await page.waitForTimeout(700);
const m9 = await page.evaluate(() => {
  const el = document.querySelector('[data-btype="mdsrc"]');
  if (!el) return { on: false };
  const s = getSelection();
  // 与桥 caretInfo 同口径（range toString；<br> 不计字符，
  // 两端同口径才可比）
  const pre = document.createRange();
  pre.selectNodeContents(el);
  if (s.rangeCount) pre.setEnd(s.focusNode, s.focusOffset);
  const full = document.createRange();
  full.selectNodeContents(el);
  return {
    on: document.activeElement === el,
    charOff: pre.toString().length,
    len: full.toString().length,
  };
});
console.log('M9:', JSON.stringify(m9));
ok('M9 preview->source caret lands at block end (orig behavior)', m9.on && m9.charOff === m9.len);
await page.evaluate(() => { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); });
await page.waitForTimeout(500);

// M6 点击合并预览 → 模型合并为单个源码段（其余块删除），
// 失焦后仍是单个合并预览；重开备忘保持合并形态
await page.evaluate(() => {
  const hit = [...document.querySelectorAll('.md-hit')].find((h) => h.textContent.includes('未完任务'));
  if (hit) hit.click();
});
await page.waitForTimeout(700);
const m6edit = await page.evaluate(() => {
  const el = document.querySelector('[data-btype="mdsrc"]');
  return el ? (el.innerText || '') : '';
});
ok('M6 merged preview click restores one merged source block', m6edit.includes('- [ ] 未完任务') && m6edit.includes('2. 第二项'));
await page.evaluate(() => { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); });
await page.waitForTimeout(600);
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
await page.waitForTimeout(400);
await page.evaluate(() => {
  const t = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('md边缘'));
  if (t) t.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(900);
const m6re = await page.evaluate(() => {
  const hits = [...document.querySelectorAll('.editor-body .md-hit')].filter((h) => h.textContent.includes('未完任务'));
  return { n: hits.length, hasOl: hits.length === 1 && !!hits[0].querySelector('ol[start="2"]') };
});
ok('M6 merge persists across reopen as single preview', m6re.n === 1 && m6re.hasOl);

console.log('ERRORS:', errors.length ? errors.join(' | ') : 'none');
await browser.close();
