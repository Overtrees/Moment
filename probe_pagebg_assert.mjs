// 页面色泄漏根治断言探针（修复后口径）：
// 根背景 = App 按页面状态派生——编辑页=备忘有效背景，其他页=根页面色
// （内联清空、计算值回落 --primary-bg）；离开编辑页后 #body-before-bg
// 与具名全局监听必须被同步清理摘除；Diag 须有 root bg 派生记录。
// 用法: node probe_pagebg_assert.mjs <url>
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8206/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' | ' + extra : '')); if (!cond) fails++; };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function measure(page) {
  return page.evaluate(() => {
    const de = document.documentElement, b = document.body;
    const root = document.getElementById('editor-root');
    return {
      htmlInline: de.style.backgroundColor || '',
      bodyInline: b.style.backgroundColor || '',
      bodyComputed: getComputedStyle(b).backgroundColor,
      gradPresent: !!document.getElementById('body-before-bg'),
      mnEscFn: typeof window.__mnEsc === 'function',
      mnTypedFn: typeof window.__mnTypedMark === 'function',
      mnBgCleanupFn: typeof window.__mnBgCleanup === 'function',
      mnBgActive: window.__mnBgActive,
      editorRootBg: root ? getComputedStyle(root).backgroundColor : null,
    };
  });
}
const rootClean = (m) => m.htmlInline === '' && m.bodyInline === '' && !m.gradPresent && !m.mnEscFn && !m.mnTypedFn && !m.mnBgCleanupFn && m.mnBgActive !== true;

async function importFixture(page) {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/pagebg/fixture.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });
}
async function openMemo(page, title) {
  await page.click(`.list-item:has-text("${title}")`);
  await page.waitForSelector('#editor-root', { timeout: 10000 });
  await page.waitForTimeout(500);
}
async function backToList(page) {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(500);
}

// ---------- 浅色轮 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, colorScheme: 'light' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importFixture(page);
  let m = await measure(page);
  ok('L0 列表(导入后) 根内联空、计算=根色', m.htmlInline === '' && m.bodyInline === '' && m.bodyComputed === 'rgb(242, 242, 247)', JSON.stringify(m));

  await openMemo(page, '醒目背景备忘');
  m = await measure(page);
  ok('L1 编辑页(醒目) 根背景=备忘色', m.htmlInline === 'rgb(255, 87, 34)' && m.bodyInline === 'rgb(255, 87, 34)', JSON.stringify(m));
  ok('L1 编辑器根元素背景=备忘色(不回归)', m.editorRootBg === 'rgb(255, 87, 34)', m.editorRootBg);

  // 编辑页内换色 → 根背景跟随（App 派生的数据通路）
  await page.click('.editor-fab.right');
  await page.waitForSelector('.menu-item', { timeout: 8000 });
  await page.click('.menu-item:has-text("更换背景色")');
  await page.waitForSelector('.bg-dot', { timeout: 8000 });
  await page.click('.bg-dot[style*="d4e8d0"]');
  await page.waitForTimeout(600);
  m = await measure(page);
  ok('L2 编辑页内换色 根背景跟随新色', m.bodyInline === 'rgb(212, 232, 208)' && m.editorRootBg === 'rgb(212, 232, 208)', JSON.stringify(m));

  await backToList(page);
  m = await measure(page);
  ok('L3 返回列表 根已清+监听全摘+无渐变残留', rootClean(m) && m.bodyComputed === 'rgb(242, 242, 247)', JSON.stringify(m));

  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.waitForTimeout(400);
  m = await measure(page);
  ok('L4 设置页 根色干净', rootClean(m) && m.bodyComputed === 'rgb(242, 242, 247)', JSON.stringify(m));

  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.waitForTimeout(400);
  m = await measure(page);
  ok('L5 备份页 根色干净', rootClean(m), JSON.stringify(m));
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });

  // 列表→设置（未再进编辑页）
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.waitForTimeout(300);
  m = await measure(page);
  ok('L6 列表→设置(未进编辑) 根色干净', rootClean(m), JSON.stringify(m));
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });

  // 默认背景备忘
  await openMemo(page, '默认背景备忘');
  m = await measure(page);
  ok('L7 编辑页(默认) 根背景=#FAFAFA', m.bodyInline === 'rgb(250, 250, 250)', JSON.stringify(m));
  await backToList(page);
  m = await measure(page);
  ok('L8 默认备忘返回列表 根已清', rootClean(m) && m.bodyComputed === 'rgb(242, 242, 247)', JSON.stringify(m));

  // Diag 派生记录
  const diag = await page.evaluate(() => (JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]')).join('\n'));
  ok('L9 Diag 有 root bg 派生记录', diag.includes('root bg -> #FF5722') && diag.includes('root bg -> (root default)') && diag.includes('root bg -> #d4e8d0'), '');
  ok('L9 Diag 有 editor cleanup sync 记录', diag.includes('editor cleanup sync done'), '');

  // 重载 → 再进编辑（换色已落库 #d4e8d0）→ 返回
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await openMemo(page, '醒目背景备忘');
  m = await measure(page);
  ok('L10 重载后进编辑 根背景=已存色', m.bodyInline === 'rgb(212, 232, 208)', JSON.stringify(m));
  await backToList(page);
  m = await measure(page);
  ok('L11 重载轮返回列表 根已清', rootClean(m), JSON.stringify(m));
  ok('浅色轮无 pageerror', errors.length === 0, errors.join(';'));
  await ctx.close();
}

// ---------- 深色轮 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, colorScheme: 'dark' });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importFixture(page);
  let m = await measure(page);
  ok('D0 深色列表 根内联空、计算=黑', m.htmlInline === '' && m.bodyComputed === 'rgb(0, 0, 0)', JSON.stringify(m));
  await openMemo(page, '醒目背景备忘');
  m = await measure(page);
  ok('D1 深色编辑(醒目) 根背景=压暗色', m.bodyInline === 'rgb(89, 30, 12)', JSON.stringify(m));
  await backToList(page);
  m = await measure(page);
  ok('D2 深色返回列表 根已清', rootClean(m) && m.bodyComputed === 'rgb(0, 0, 0)', JSON.stringify(m));
  await openMemo(page, '默认背景备忘');
  m = await measure(page);
  ok('D3 深色编辑(默认) 根背景=#000', m.bodyInline === 'rgb(0, 0, 0)', JSON.stringify(m));
  await backToList(page);
  m = await measure(page);
  ok('D4 深色默认返回 根已清', rootClean(m), JSON.stringify(m));
  ok('深色轮无 pageerror', errors.length === 0, errors.join(';'));
  await ctx.close();
}

await browser.close();
console.log(fails === 0 ? 'PROBE ALL PASS' : `PROBE FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
