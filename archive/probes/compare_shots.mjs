// 原版 vs Rust 版同视口截图比对 v2：两边同为原版示例种子数据。
// 用法: node compare_shots.mjs <origBase> <rustBase> <outDir>
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const origBase = process.argv[2] || 'http://localhost:8097/Moment.html';
const rustBase = process.argv[3] || 'http://localhost:8096/';
const outDir = process.argv[4] || '/tmp/cmp-shots';
mkdirSync(outDir, { recursive: true });

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function newPage() {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 160)));
  return { ctx, page };
}
const shot = async (page, name) => { await page.screenshot({ path: `${outDir}/${name}.png` }); console.log('shot', name); };
const wait = (page, ms) => page.waitForTimeout(ms);

// ---------- 原版 ----------
{
  const { ctx, page } = await newPage();
  await page.goto(origBase, { waitUntil: 'load' });
  await wait(page, 5000);
  await shot(page, 'orig-list');
  await page.getByText('周末看展记录', { exact: true }).first().click().catch((e) => console.log('orig open fail', String(e).slice(0, 120)));
  await wait(page, 2500);
  await shot(page, 'orig-editor');
  // 返回列表
  await page.mouse.click(40, 40).catch(() => {});
  await wait(page, 1200);
  // 头像进设置（左上圆，中心约 70,108）
  await page.mouse.click(70, 108);
  await wait(page, 1800);
  await shot(page, 'orig-settings');
  await page.getByText('备份与恢复', { exact: true }).first().click().catch((e) => console.log('orig backup fail', String(e).slice(0, 120)));
  await wait(page, 1800);
  await shot(page, 'orig-backup');
  await ctx.close();
}

// ---------- Rust 版 ----------
{
  const { ctx, page } = await newPage();
  await page.goto(rustBase, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await wait(page, 800);
  await shot(page, 'rust-list');
  await page.click('.list-item:has-text("周末看展记录") .item-title-text');
  await page.waitForSelector('.detail .ed-line', { timeout: 8000 });
  await wait(page, 800);
  await shot(page, 'rust-editor');
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await wait(page, 600);
  await shot(page, 'rust-settings');
  await page.click('.set-row:has-text("备份与恢复")');
  await wait(page, 900);
  await shot(page, 'rust-backup');
  await ctx.close();
}

await browser.close();
console.log('DONE', outDir);
