// 审计探针：Rust 版 md 预览渲染（导入边缘 ZIP 后逐块转储编辑器 DOM）
import { chromium } from 'playwright-core';
const url = 'http://localhost:8102/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);

async function importZip(zip) {
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.waitForTimeout(400);
}
async function openMemo(title) {
  await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes(t));
    if (el) el.click();
  }, title);
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(700);
}
const dumpBlocks = () => page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  if (!body) return [];
  return [...body.children].map((el, i) => {
    const html = el.innerHTML.replace(/\s+/g, ' ').slice(0, 170);
    return { i, cls: el.className, tag: el.tagName, bid: el.dataset?.bid || el.querySelector?.('[data-bid]')?.dataset?.bid || '', html };
  });
});

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card', { timeout: 15000 });
await importZip('/tmp/md_edge.zip');
await openMemo('md边缘');
const blocks = await dumpBlocks();
for (const b of blocks) L('RUST-MD', JSON.stringify(b));

// 预览→源码切换：点击第一个 md 预览（代码围栏 e01）看光标
await page.evaluate(() => document.querySelector('.md-hit')?.click());
await page.waitForTimeout(500);
const afterClick = await page.evaluate(() => {
  const s = getSelection();
  const el = document.querySelector('#editor-root [data-bid][data-btype="mdsrc"]');
  return { mdsrc: !!el, activeIsMdsrc: document.activeElement === el, caretOffset: s.rangeCount ? s.focusOffset : -1, anchorText: s.anchorNode?.textContent?.slice(0, 20) };
});
L('RUST-MD click-preview->source', JSON.stringify(afterClick));

// 列表预览剥 md（回列表看 md边缘 卡片预览文本）
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
await page.waitForTimeout(400);
const cardText = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('md边缘'));
  return el ? el.innerText.replace(/\s+/g, ' ').slice(0, 300) : 'not found';
});
L('RUST-LIST-PREVIEW', cardText);

// 深色模式：面板与代码块度量
const ctx2 = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'dark' });
const p2 = await ctx2.newPage();
await p2.goto(url, { waitUntil: 'load' });
await p2.waitForSelector('.list-item, .img-card', { timeout: 15000 });
await p2.evaluate(() => [...document.querySelectorAll('.list-item')].find((e) => e.textContent.includes('新建'))?.click());
await p2.waitForSelector('#editor-root', { timeout: 8000 });
await p2.waitForTimeout(500);
await p2.evaluate(() => document.querySelector('#editor-root [data-bid]')?.focus());
await p2.keyboard.type('/');
await p2.waitForSelector('#slash-panel', { timeout: 5000 });
const dark = await p2.evaluate(() => {
  const p = document.querySelector('#slash-panel');
  const cs = getComputedStyle(p);
  const row = p.querySelector('.slash-row');
  return { panelBg: cs.backgroundColor, panelColor: cs.color, rowColor: getComputedStyle(row).color, backdrop: cs.backdropFilter };
});
L('RUST-DARK', JSON.stringify(dark));
await browser.close();
