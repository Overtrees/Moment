// S12 导出 toast 文案对齐实测：备份页导出（下载回退分支）后
// toast 文案应为「本地备份已下载 (.zip)」（原版 BackupView.js:207
// showStatus('✅ 本地备份已下载 (.zip)')，渲染时 ✅ 由 toast 图标
// 呈现、正文剥前缀），历史条目应为「备份已下载」（原版 :208）。
// 注：目标文案只存在于下载回退分支，故 init script 摘掉
// navigator.share 强制走回退（无 Web Share 的设备即此分支）。
import { chromium } from 'playwright-core';

const url = process.argv[2] || 'http://localhost:8206/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
await ctx.addInitScript(() => {
  try { delete Navigator.prototype.share; } catch (_) {}
  try { delete Navigator.prototype.canShare; } catch (_) {}
  try { Object.defineProperty(navigator, 'share', { value: undefined }); } catch (_) {}
  try { Object.defineProperty(navigator, 'canShare', { value: undefined }); } catch (_) {}
});
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const ok = (name, cond) => console.log((cond ? '✓ ' : '✗ ') + name);

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('.backup-hero', { timeout: 8000 });

// 导出：行 → 确认弹窗 → 主按钮
const dlPromise = page.waitForEvent('download', { timeout: 20000 }).catch(() => null);
await page.click('.backup-row:has-text("导出备份")');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');

// toast 文案（图标 + 正文分开取，合并即原版可见串）
await page.waitForFunction(
  () => document.querySelector('.backup-toast')?.innerText.includes('本地备份已下载'),
  { timeout: 20000 },
);
const toast = await page.evaluate(() => {
  const t = document.querySelector('.backup-toast');
  return {
    full: t?.innerText.replace(/\s+/g, ' ').trim(),
    icon: t?.querySelector('.backup-toast-icon')?.innerText.trim(),
    text: t?.querySelector('.backup-toast-text')?.innerText.trim(),
  };
});
console.log('TOAST:', JSON.stringify(toast));
ok('toast text == 本地备份已下载 (.zip)', toast.text === '本地备份已下载 (.zip)');
ok('toast icon == ✅', toast.icon === '✅');
await page.screenshot({ path: 'screenshots/s12_toast_zh.png' });

const dl = await dlPromise;
// 注：headless shell 对 blob: 锚点下载的 suggestedFilename 恒为
// 'download'（不传播 download 属性，与原版同机制下同表现），
// 文件名口径以应用自记的历史 detail 为准（下方断言）。
console.log('DOWNLOAD fired:', !!dl);
ok('zip download fired', !!dl);

// 历史条目（localStorage 口径）
await page.waitForFunction(
  () => (localStorage.getItem('mynote_backup_history') || '[]').includes('备份已下载'),
  { timeout: 8000 },
);
const hist = await page.evaluate(() => JSON.parse(localStorage.getItem('mynote_backup_history') || '[]'));
console.log('HISTORY[0]:', JSON.stringify(hist[0]));
ok('history[0].title == 备份已下载', hist[0]?.title === '备份已下载');
ok('history[0] is export/success with filename detail', hist[0]?.type === 'export' && hist[0]?.ok === true && /\.zip$/.test(hist[0]?.detail || ''));

// 历史条目 DOM 渲染（返回设置再进备份页，迫使重读渲染）
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('.backup-hero', { timeout: 8000 });
await page.waitForFunction(() => document.body.innerText.includes('备份已下载'), { timeout: 8000 });
const histDom = await page.evaluate(() => {
  const els = [...document.querySelectorAll('.backup-card')];
  const card = els.find((e) => e.innerText.includes('备份已下载'));
  return card ? card.innerText.replace(/\s+/g, ' ').trim() : '(not found)';
});
console.log('HISTORY DOM:', histDom);
ok('history entry rendered with 备份已下载', histDom.includes('备份已下载'));
await page.screenshot({ path: 'screenshots/s12_history_zh.png' });

console.log('PAGEERRORS:', errors.length ? errors.join(' | ') : 'none');
console.log(errors.length ? 'ERRORS: ' + errors.join('; ') : 'ERRORS: none');
await browser.close();
