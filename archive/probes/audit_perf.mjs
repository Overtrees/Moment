// 性能 A/B：300 条备忘数据集，两版测 加载/搜索/打开/输入。
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const [origBase, rustBase] = process.argv.slice(2);
const ZIP = '/tmp/big300.zip';
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});

async function measure(label, base, isOrig) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  const out = { label };
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForTimeout(2500);

  // 导入大数据集
  if (isOrig) {
    const b64 = fs.readFileSync(ZIP).toString('base64');
    await page.evaluate(async (b64) => {
      const bin = atob(b64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      const unzipped = await window.MynoteZip.checkedZip(bytes);
      const backup = JSON.parse(fflate.strFromU8(unzipped['memos.json']));
      const db = await window.MynoteIdb.getDB();
      await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
      try { localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos)); } catch (e) {}
    }, b64);
  } else {
    await page.waitForSelector('.list-item', { timeout: 20000 });
    await page.$eval('h1.page-title', (e) => e.click());
    await page.waitForTimeout(700);
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForTimeout(700);
    await page.setInputFiles('#file-import', ZIP);
    await page.waitForTimeout(800);
    await page.click('.backup-modal .backup-btn.primary');
    await page.waitForTimeout(1500);
  }

  // 冷加载到列表渲染完成
  const t0 = Date.now();
  await page.reload({ waitUntil: 'load' });
  if (isOrig) {
    await page.waitForFunction(() => document.body.innerText.includes('压测笔记 000'), { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(800);
  } else {
    await page.waitForSelector('.list-item', { timeout: 30000 });
    await page.waitForTimeout(800);
  }
  out.loadMs = Date.now() - t0;
  out.cards = await page.evaluate(() => document.querySelectorAll('.list-item, .img-card').length);

  // 搜索响应：打开搜索、输入 ZEBRA、计时到结果收敛
  if (isOrig) {
    await page.mouse.click(330, 108); // 搜索胶囊（原版右上）
  } else {
    await page.evaluate(() => document.querySelector('.glass-search-trigger')?.click());
  }
  await page.waitForTimeout(700);
  const ts0 = Date.now();
  await page.keyboard.type('ZEBRA', { delay: 30 });
  await page.waitForFunction(() => document.body.innerText.includes('独特关键词'), { timeout: 15000 }).catch(() => {});
  out.searchMs = Date.now() - ts0;
  await page.keyboard.press('Escape');
  await page.evaluate(() => { const i = document.querySelector('input'); if (i) { i.value = ''; i.dispatchEvent(new Event('input', { bubbles: true })); } });
  await page.waitForTimeout(600);

  // 打开首条备忘
  const to0 = Date.now();
  if (isOrig) await page.click('text=压测笔记 000');
  else await page.evaluate(() => document.querySelector('.list-item .item-title-text')?.click());
  await page.waitForFunction(() => !!document.querySelector('.editor-body'), { timeout: 20000 }).catch(() => {});
  out.openMs = Date.now() - to0;

  // 输入延迟：聚焦首块，键入 12 字，测 DOM 出现耗时
  await page.evaluate(() => {
    const el = document.querySelector('.editor-body [data-bid], .editor-body [data-blockid], .editor-body p');
    if (el) { el.focus(); const r = document.createRange(); r.selectNodeContents(el); r.collapse(false); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
  });
  const tt0 = Date.now();
  await page.keyboard.type('延迟测试文字输入', { delay: 20 });
  await page.waitForFunction(() => document.body.innerText.includes('延迟测试文字输入'), { timeout: 10000 }).catch(() => {});
  out.typeMs = Date.now() - tt0;

  console.log(JSON.stringify(out));
  await ctx.close();
}

await measure('ORIG', origBase, true);
await measure('RUST', rustBase, false);
await browser.close();
