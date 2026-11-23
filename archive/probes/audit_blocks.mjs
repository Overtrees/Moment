// 全块渲染同数据比对：向原版与 Rust 版分别导入 allblocks.zip，
// 打开「全块渲染测试」，分段截图 + 逐块度量（高度/字号/边距）。
// 用法: node audit_blocks.mjs <origBase> <rustBase> <outDir>
import { chromium } from 'playwright-core';

const [origBase, rustBase, outDir] = process.argv.slice(2);
const ZIP = '/tmp/allblocks.zip';
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});

async function newPage() {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  return ctx.newPage();
}

async function shootSegments(page, tag) {
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(500);
  for (let i = 0; i < 4; i++) {
    await page.screenshot({ path: `${outDir}/${tag}-${i}.png` });
    await page.evaluate(() => window.scrollBy(0, 700));
    await page.waitForTimeout(450);
  }
}

async function blockMetrics(page) {
  return page.evaluate(() => {
    const body = document.querySelector('.editor-body');
    if (!body) return { error: 'no editor-body' };
    const out = [];
    for (const el of body.querySelectorAll(':scope > *')) {
      const cs = getComputedStyle(el);
      const r = el.getBoundingClientRect();
      out.push({
        cls: el.className && el.className.baseVal !== undefined ? '' : String(el.className).slice(0, 40),
        tag: el.tagName.toLowerCase(),
        dtype: el.getAttribute('data-type') || '',
        h: Math.round(r.height),
        mt: cs.marginTop, mb: cs.marginBottom,
        fs: cs.fontSize, lh: cs.lineHeight,
        text: (el.innerText || '').slice(0, 24).replace(/\n/g, ' '),
      });
    }
    return out;
  });
}

// ---------- 原版 ----------
// 导入走原版自己的 restoreFromZipAtomic API（与 UI 确认按钮同一条链；
// 无头下 sheet 的确认点击不稳定，API 结果已单独验证 staged=4/failed=0）。
{
  const page = await newPage();
  await page.goto(origBase, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  const fs = await import('node:fs');
  const b64 = fs.readFileSync(ZIP).toString('base64');
  const restoreRes = await page.evaluate(async (b64) => {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const unzipped = await window.MynoteZip.checkedZip(bytes);
    const backup = JSON.parse(fflate.strFromU8(unzipped['memos.json']));
    const db = await window.MynoteIdb.getDB();
    const r = await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
    try { localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos)); } catch (e) {}
    return JSON.stringify(r);
  }, b64);
  console.log('ORIG RESTORE:', restoreRes);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.click('text=全块渲染测试');
  await page.waitForTimeout(1500);
  await shootSegments(page, 'orig-blocks');
  console.log('ORIG METRICS:', JSON.stringify(await blockMetrics(page), null, 0));
  await page.close();
}

// ---------- Rust 版 ----------
{
  const page = await newPage();
  await page.goto(rustBase, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.waitForTimeout(600);
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForTimeout(700);
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForTimeout(700);
  await page.setInputFiles('#file-import', ZIP);
  await page.waitForTimeout(900);
  if (await page.locator('.backup-modal').count()) {
    await page.click('.backup-modal .backup-btn.primary');
  } else {
    console.log('RUST IMPORT: no modal; body:', await page.evaluate(() => document.body.innerText.slice(0, 200)));
  }
  await page.waitForTimeout(1800);
  await page.click('.editor-fab.left'); // 备份 → 设置
  await page.waitForTimeout(900);
  await page.click('.editor-fab.left'); // 设置 → 列表
  await page.waitForFunction(() => document.body.innerText.includes('全块渲染测试'), { timeout: 15000 });
  await page.evaluate(() => {
    const t = document.querySelector('.img-card-title-text') || document.querySelector('.list-item .item-title-text');
    if (t) t.click();
  });
  await page.waitForTimeout(1500);
  await shootSegments(page, 'rust-blocks');
  console.log('RUST METRICS:', JSON.stringify(await blockMetrics(page), null, 0));
  await page.close();
}

await browser.close();
console.log('DONE', outDir);
