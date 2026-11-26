// Rust Web W1 无头冒烟（复刻版 DOM）：种子渲染 → 设置/备份页导入
// 真实备份（确认弹窗）→ 详情图片 → 搜索面板 → 刷新持久 → 导出校验
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8096/';
const zip = process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const ok = (name, cond) => console.log((cond ? '✓ ' : '✗ ') + name);

// 1) 种子列表
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
const seedTitles = await page.$$eval('.item-title-text, .img-card-title-text', (els) => els.map((e) => e.innerText));
console.log('SEED TITLES:', JSON.stringify(seedTitles));
ok('seed renders', seedTitles.includes("周末看展记录") && seedTitles.includes("装修踩坑清单"));

// 2) 头像 → 设置 → 备份与恢复 → 导入（文件 → 确认弹窗 → 恢复）
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', zip);
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(
  () => document.querySelector('.backup-toast')?.innerText.includes('已导入'),
  { timeout: 15000 }
);
console.log('IMPORT STATUS:', await page.$eval('.backup-toast', (e) => e.innerText));
ok('import real_backup.zip', true);

// 3) 返回列表 → 打开「冬日」，附件图片真渲染
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 }); // .seg-row 为设置页独有：等它出现才证明备份页已关闭到位（出场 280ms；.page-content 在备份页自身已成立，不能作到位判据）
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 8000 }); // 列表独有标记：.list-item 在设置页（字号预览行）也存在，不能作回列表的到位判据；触发钮在列表滚动态表头下为 visibility:hidden，故只判在场（attached）
await page.click('.img-card:has-text("冬日")');
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForFunction(
  () => {
    const img = document.querySelector('.detail img.blk-media');
    return img && img.naturalWidth > 0;
  },
  { timeout: 10000 }
);
const imgW = await page.$eval('.detail img.blk-media', (e) => e.naturalWidth);
console.log('DETAIL IMG naturalWidth:', imgW);
ok('detail image renders', imgW === 886);

// 4) 返回 + 搜索（触发胶囊 → 面板输入）
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { timeout: 8000 });
await page.click('.glass-search-trigger');
await page.waitForSelector('.glass-search-input', { timeout: 8000 });
await page.fill('.glass-search-input', 'IP 检测');
await page.waitForTimeout(500);
const hits = await page.$$eval('.item-title-text, .img-card-title-text', (els) => els.map((e) => e.innerText));
console.log('SEARCH "IP 检测":', JSON.stringify(hits));
ok('search narrows', hits.includes('实用技巧') && !hits.includes('冬日'));
await page.keyboard.press('Escape');
await page.waitForTimeout(300);

// 5) 刷新：持久数据自动载入
await page.reload({ waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.waitForFunction(
  () => document.body.innerText.includes('冬日') && document.body.innerText.includes('实用技巧'),
  { timeout: 10000 }
);
ok('reload persists', true);

// 6) 导出：设置 → 备份 → 导出备份 → 确认 → 下载校验
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('.backup-row:has-text("导出备份")', { timeout: 8000 });
const dlPromise = page.waitForEvent('download', { timeout: 15000 });
await page.click('.backup-row:has-text("导出备份")');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
const dl = await dlPromise;
await dl.saveAs('/tmp/mynote-export.zip');
const listing = execSync('python3 -c "import zipfile; z=zipfile.ZipFile(\'/tmp/mynote-export.zip\'); print(len(z.namelist())); print(\' \'.join(sorted(z.namelist())[:5]))"').toString();
console.log('EXPORT ZIP:', listing.trim().replace(/\n/g, ' / '));
ok('export zip has 19 entries', listing.startsWith('19'));

console.log('ERRORS:', errors.length ? errors.join(' | ') : 'none');
await browser.close();
