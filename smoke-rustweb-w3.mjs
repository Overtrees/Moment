// Rust Web W3 冒烟：加粗快捷键 → 富文本/多行粘贴 → 列表转换/退出/
// 提出 → 代码块 → 高亮渲染 → 删块持久
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
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 8000 });

// 1) 加粗快捷键：选中首段前 2 字按 Cmd+B
await page.click('.detail .ed-line >> nth=0');
await page.keyboard.press('Home');
await page.keyboard.down('Shift');
await page.keyboard.press('ArrowRight');
await page.keyboard.press('ArrowRight');
await page.keyboard.up('Shift');
await page.keyboard.press('ControlOrMeta+b');
await page.waitForTimeout(300);
const boldHtml = await page.$eval('.detail .ed-line', (e) => e.innerHTML);
console.log('BOLD HTML:', boldHtml.slice(0, 80));
ok('cmd+B bolds selection', /<(b|strong)>/.test(boldHtml));

// 2) 富文本粘贴：在末尾分块后粘贴 HTML
await page.keyboard.press('End');
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await page.evaluate(() => {
  const el = document.activeElement;
  const dt = new DataTransfer();
  dt.setData('text/html', '<p>粘贴的<b>富文本</b>段落</p>');
  dt.setData('text/plain', '粘贴的富文本段落');
  el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
});
await page.waitForTimeout(400);
ok('paste html lands', await page.evaluate(() => document.body.innerText.includes('粘贴的富文本段落')));

// 3) 多行纯文本粘贴
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await page.evaluate(() => {
  const el = document.activeElement;
  const dt = new DataTransfer();
  dt.setData('text/plain', '第一行\n第二行\n第三行');
  el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
});
await page.waitForTimeout(400);
const allText = await page.evaluate(() => document.body.innerText);
ok('paste text lines split', allText.includes('第一行') && allText.includes('第二行') && allText.includes('第三行'));

// 4) 斜杠转无序列表（原版模型：md 源段落）→ 进源码编辑态 →
// 失焦回预览列表 → 点预览回源码
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await page.keyboard.type('/');
await page.waitForSelector('.slash-panel .slash-row', { timeout: 8000 });
await page.click('.slash-panel .slash-row[data-act="bulletList"]');
await page.waitForTimeout(400);
const srcType = await page.evaluate(() => document.activeElement?.dataset?.btype || '');
ok('slash list enters md source edit', srcType === 'mdsrc');
await page.keyboard.press('ControlOrMeta+a');
await page.keyboard.type('- 列表项一\n- 列表项二');
await page.waitForTimeout(300);
await page.click('.detail .ed-line >> nth=0'); // 失焦 → 回预览
await page.waitForSelector('.md-preview li', { timeout: 8000 });
const liTexts = await page.$$eval('.md-preview li', (els) => els.map((e) => e.innerText));
console.log('LIST ITEMS:', JSON.stringify(liTexts));
ok('md preview renders 2 list items', liTexts.length === 2 && liTexts[1].includes('列表项二'));
await page.click('.md-preview'); // 点预览 → 回源码编辑
await page.waitForTimeout(500);
const backSrc = await page.evaluate(() => document.activeElement?.innerText || '');
ok('preview click returns to source', backSrc.includes('- 列表项二'));
await page.click('.detail .ed-line >> nth=0');
await page.waitForTimeout(400);

// 5) 代码块：斜杠转 md 源（围栏）→ 源码编辑 → 失焦回代码预览
await page.keyboard.press('Enter');
await page.waitForTimeout(300);
await page.keyboard.type('/');
await page.waitForSelector('.slash-panel .slash-row', { timeout: 8000 });
await page.click('.slash-panel .slash-row[data-act="codeBlock"]');
await page.waitForTimeout(400);
await page.keyboard.press('ControlOrMeta+a');
await page.keyboard.type('```\nlet a = 1;\nlet b = 2;\n```');
await page.waitForTimeout(300);
await page.click('.detail .ed-line >> nth=0');
await page.waitForSelector('.md-preview pre code', { timeout: 8000 });
const codeText = await page.$eval('.md-preview pre code', (e) => e.innerText).catch(() => '');
console.log('CODE TEXT:', JSON.stringify(codeText));
ok('code preview renders fenced source', codeText.includes('let a = 1;') && codeText.includes('let b = 2;'));

// 返回 → 刷新 → 持久校验（含加粗 HTML）
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.click('.list-item:has-text("周末看展记录") .item-title-text');
await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
await page.waitForFunction(() => document.body.innerText.includes('列表项二'), { timeout: 8000 });
// S3 口径：加粗经回收归一为字面 ** 标记，重载后该段按统一
// 分类渲染为 md 预览（strong 呈现），不再是带 <b> 的可编辑
// div；断言改为查正文首块内的 strong 文本，意图不变。
const boldOk = await page.evaluate(() => {
  const first = document.querySelector('.editor-body')?.querySelector(':scope > *');
  return !!first && [...first.querySelectorAll('strong, b')].some((e) => e.textContent.includes('克力'));
});
ok('bold persists after reload', boldOk);
ok('list persists after reload', true);

// 6) 删块：先导入真实备份（种子无图片备忘），再打开「冬日」删图片块
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 }); // .seg-row 为设置页独有：等它出现才证明备份页已关闭到位（出场 280ms；.page-content 在备份页自身已成立，不能作到位判据）
await page.click('.editor-fab.left');
await page.waitForSelector('.img-card', { timeout: 8000 });
await page.click('.img-card:has-text("冬日")');
await page.waitForSelector('.detail', { timeout: 8000 });
const wraps0 = await page.$$eval('.detail .blk-wrap', (els) => els.length);
// 删块机制（卡片交互专项）：常驻悬浮删除钮已整体移除，
// 删除走浮层菜单——先点块体中央选中（桥的边缘区语义），
// 再右键出菜单点「删除」。
const delHidden0 = await page.$$eval('.detail .blk-wrap .blk-del', (els) => els.length);
ok('delete button not resident', delHidden0 === 0);
await page.click('.detail .blk-wrap >> nth=0');
// 图片块点击会同时开灯箱（既有行为），先关掉再走菜单
if (await page.$('.lightbox')) {
  await page.click('.lightbox');
  await page.waitForTimeout(300);
}
await page.click('.detail .blk-wrap >> nth=0', { button: 'right' });
await page.waitForSelector('.card-menu-panel .menu-item.danger', { timeout: 5000 });
await page.click('.card-menu-panel .menu-item.danger');
await page.waitForTimeout(500);
const wraps1 = await page.$$eval('.detail .blk-wrap', (els) => els.length);
console.log('WRAPS:', wraps0, '->', wraps1);
ok('delete block', wraps1 === wraps0 - 1);
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
// 唯一图片块已删，「冬日」不再是图片卡，退化为文本行
await page.click('.list-item:has-text("冬日") .item-title-text');
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(600);
const wraps2 = await page.$$eval('.detail .blk-wrap', (els) => els.length);
ok('delete persists after reload', wraps2 === wraps1);

console.log('ERRORS:', errors.length ? errors.join(' | ') : 'none');
await browser.close();
