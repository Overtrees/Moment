// 专用探针：备份新鲜度常驻呈现（批 12 P-U8）。
// 数据全取现成 moment_backup_history（不加新存储）：
//  ① 无成功导出史 → 设置行副文案 =「尚未导出过备份」；
//  ② 2 天前成功导出 → 副文案含上次备份时间 +「2 天前」，
//     无警示段；
//  ③ 10 天前成功导出 + 期间有编辑（种子备忘 updatedAt 为
//     当前时刻）→ 副文案追加警示段；进备份页有超期横幅；
//     Diag 有 freshness stale shown 结果行。
// 用法：node probe_backup_fresh.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

const DAY = 86400000;
const setHistory = (daysAgo) => page.evaluate((d) => {
  const entry = {
    type: 'export', ok: true, title: '备份已下载', detail: 'x.zip',
    at: new Date(Date.now() - d * 86400000).toISOString(),
  };
  localStorage.setItem('moment_backup_history', JSON.stringify([entry]));
}, daysAgo);
const openSettings = async () => {
  await page.click('h1.page-title');
  await page.waitForSelector('.page-content', { timeout: 15000 });
  await page.waitForTimeout(900);
};
const backToList = async () => {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-current .page-enter', { timeout: 15000 });
  await page.waitForTimeout(900);
};
const backupMeta = () => page.locator('.backup-card .set-row').first().locator('.item-meta').innerText();

// ① 无历史
await openSettings();
const metaA = await backupMeta();
ok('① 无导出史副文案', metaA.includes('尚未导出过备份'), metaA.trim());
await backToList();

// ② 2 天前导出
await setHistory(2);
await openSettings();
const metaB = await backupMeta();
ok('② 副文案含上次备份', metaB.includes('上次备份'), metaB.trim());
ok('② 副文案含距今天数', metaB.includes('2 天前'), metaB.trim());
ok('② 无警示段', !metaB.includes('建议重新备份'), '');
await backToList();

// ③ 10 天前导出 + 期间有编辑
await setHistory(10);
await openSettings();
const metaC = await backupMeta();
ok('③ 副文案追加警示段', metaC.includes('已超 7 天') && metaC.includes('建议重新备份'), metaC.trim());
await page.click('.backup-card .set-row >> nth=0');
await page.waitForSelector('.backup-hero', { timeout: 15000 });
await page.waitForTimeout(600);
const banner = page.locator('.backup-stale-banner');
ok('③ 备份页超期横幅', (await banner.count()) === 1 && (await banner.innerText()).includes('超过 7 天'));
let diag = [];
for (let i = 0; i < 20; i++) {
  diag = await page.evaluate(() => {
    try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
  });
  if (diag.some((l) => String(l).includes('freshness stale shown'))) break;
  await page.waitForTimeout(500);
}
ok('③ Diag 有 freshness stale shown 行', diag.some((l) => String(l).includes('freshness stale shown')));

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
