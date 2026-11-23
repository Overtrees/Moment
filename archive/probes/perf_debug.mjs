// 一次性调试：导入后重载，dump 列表状态与 Diag。
import { chromium } from 'playwright-core';
const base = process.argv[2];
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
console.log('boot ok');
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 15000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 15000 });
await page.setInputFiles('#file-import', '/tmp/big300.zip');
await page.waitForSelector('.backup-modal', { timeout: 15000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 30000 });
console.log('import ok');
await page.reload({ waitUntil: 'load' });
for (let i = 0; i < 6; i++) {
  await page.waitForTimeout(5000);
  const st = await page.evaluate(() => ({
    items: document.querySelectorAll('.list-item, .img-card').length,
    hasPerf: document.body.innerText.includes('压测笔记 000'),
    titles: [...document.querySelectorAll('.list-item .item-title-text, .img-card-title-text')].map((e) => e.textContent.slice(0, 20)),
    textHead: document.body.innerText.slice(0, 120).replace(/\n/g, ' | '),
  }));
  console.log(`t+${(i + 1) * 5}s`, JSON.stringify(st));
  if (st.hasPerf) break;
}
const diag = await page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]').slice(-12); } catch { return []; }
});
console.log('DIAG:', JSON.stringify(diag, null, 1));
// 点击行为实验：标题文本 vs 卡片本体
const clickRes = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
    .find((e) => e.textContent.includes('压测笔记'));
  if (!el) return 'no-el';
  el.click();
  return 'clicked title: ' + el.textContent.slice(0, 20) + ' cls=' + el.className;
});
console.log('CLICK1:', clickRes);
await page.waitForTimeout(2500);
console.log('after title click:', await page.evaluate(() => ({
  detail: !!document.querySelector('.detail'),
  editorBody: !!document.querySelector('.editor-body'),
  title: document.querySelector('#editor-title-text')?.textContent || '',
})));
if (!(await page.evaluate(() => !!document.querySelector('.editor-body')))) {
  const click2 = await page.evaluate(() => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => e.textContent.includes('压测笔记'));
    if (!card) return 'no-card';
    card.click();
    return 'clicked card cls=' + card.className;
  });
  console.log('CLICK2:', click2);
  await page.waitForTimeout(2500);
  console.log('after card click:', await page.evaluate(() => ({
    detail: !!document.querySelector('.detail'),
    editorBody: !!document.querySelector('.editor-body'),
    title: document.querySelector('#editor-title-text')?.textContent || '',
  })));
}
await browser.close();
