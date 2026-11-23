// 标题坞对比探针：同数据（allblocks.zip）下两版编辑页在
// scrollY 0 / 50 / 150 时的坞几何（头像/胶囊/元行/首行内容）。
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const [origBase, rustBase] = process.argv.slice(2);
const ZIP = process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip';
const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});

async function probe(label, base, isOrig) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForTimeout(2600);
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
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(2200);
    await page.click('text=全块渲染测试');
  } else {
    await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
    await page.$eval('h1.page-title', (e) => e.click());
    await page.waitForTimeout(700);
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForTimeout(700);
    await page.setInputFiles('#file-import', ZIP);
    await page.waitForTimeout(800);
    await page.click('.backup-modal .backup-btn.primary');
    await page.waitForTimeout(1200);
    await page.evaluate(() => document.querySelectorAll('.editor-fab.left')[0]?.click());
    await page.waitForTimeout(700);
    await page.evaluate(() => document.querySelectorAll('.editor-fab.left')[0]?.click());
    await page.waitForTimeout(900);
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('.img-card-title-text, .item-title-text')].find((e) => e.textContent.includes('全块渲染测试'));
      if (t) t.click();
    });
  }
  await page.waitForTimeout(1500);
  const out = { label, states: [] };
  for (const y of [0, 50, 150]) {
    const m = await page.evaluate(async (yy) => {
      window.scrollTo(0, yy);
      await new Promise((r) => setTimeout(r, 450));
      const q = (sel) => document.querySelector(sel);
      const rect = (el) => el ? { t: Math.round(el.getBoundingClientRect().top), w: Math.round(el.getBoundingClientRect().width), h: Math.round(el.getBoundingClientRect().height) } : null;
      const dock = q('.editor-title-dock');
      const avatar = q('.editor-avatar-button');
      const capsule = avatar && avatar.parentElement ? [...avatar.parentElement.children].find((c) => c !== avatar && !c.classList.contains('editor-title-meta')) : null;
      const meta = q('.editor-title-meta');
      const firstBlock = q('.editor-body > *');
      const titleEl = document.getElementById('editor-title-text') || (capsule && capsule.querySelector('[contenteditable]'));
      const extra = {
        capPad: capsule ? getComputedStyle(capsule).padding : null,
        capGap: capsule ? getComputedStyle(capsule).gap : null,
        titleW: titleEl ? Math.round(titleEl.getBoundingClientRect().width) : null,
        titleFont: titleEl ? getComputedStyle(titleEl).fontSize : null,
        titleLS: titleEl ? getComputedStyle(titleEl).letterSpacing : null,
        scrollerW: titleEl && titleEl.parentElement ? Math.round(titleEl.parentElement.getBoundingClientRect().width) : null,
        metaW: meta ? Math.round(meta.getBoundingClientRect().width) : null,
        metaFont: meta ? getComputedStyle(meta).fontSize : null,
      };
      return {
        ...extra,
        scrollY: Math.round(window.scrollY),
        dockDir: dock ? getComputedStyle(dock).flexDirection : null,
        avatar: rect(avatar),
        capsule: rect(capsule),
        metaVisible: meta ? getComputedStyle(meta).display !== 'none' && meta.offsetParent !== null : null,
        metaText: meta ? meta.textContent : null,
        bodyBg: getComputedStyle(document.body).backgroundColor,
        beforeBg: (() => { const b = getComputedStyle(document.body, '::before'); return b.backgroundImage.slice(0, 60); })(),
        firstBlockTop: firstBlock ? Math.round(firstBlock.getBoundingClientRect().top) : null,
      };
    }, y);
    out.states.push(m);
  }
  console.log(JSON.stringify(out));
  await page.screenshot({ path: `/tmp/dock-${label}.png` });
  await ctx.close();
}

await probe('ORIG', origBase, true);
await probe('RUST', rustBase, false);
await browser.close();
