// 形状压力测试：长标题溢出胶囊 / 滚动坞态 / 标签 / 展开按钮 +
// 字体度量压力（换平台字体栈后文本驱动型胶囊的几何是否仍成立）。
// 用法: node probe_shapes2.mjs
import { chromium } from 'playwright-core';

const BASE = 'http://localhost:8198/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const MEASURE = `function measure(sel, pseudo) {
  const el = document.querySelector(sel);
  if (!el) return null;
  const r = el.getBoundingClientRect();
  const cs = getComputedStyle(el, pseudo || undefined);
  return { w: +r.width.toFixed(2), h: +r.height.toFixed(2), br: cs.borderTopLeftRadius, cls: el.className };
}`;
async function measureAll(page, targets) {
  return page.evaluate(`(() => { ${MEASURE}; const out = {}; const T = ${JSON.stringify(targets)};
    for (const [name, sel] of T) out[name] = measure(sel);
    return out; })()`);
}
const clickSel = (page, sel) => page.evaluate((s) => { const el = document.querySelector(s); if (el) { el.click(); return true; } return false; }, sel);

async function importZip(page, path) {
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', path);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForSelector('.backup-toast', { timeout: 10000 });
  await page.waitForTimeout(400);
}
async function goHome(page) {
  for (let i = 0; i < 3; i++) {
    if (await page.$('.container .list-item')) return;
    await page.click('.editor-fab.left').catch(() => {});
    await page.waitForTimeout(900);
  }
}

const out = {};
for (const width of [390, 768, 1280]) {
  const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width, height: width === 390 ? 852 : 900 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
  const R = { list: {}, capsuleTop: {}, capsuleScrolled: {}, fonts: {} };
  try {
    await page.goto(BASE, { waitUntil: 'load' });
    await page.waitForSelector('.list-item', { timeout: 20000 });
    await importZip(page, '/tmp/stress.zip');
    await goHome(page);
    await page.waitForTimeout(500);
    R.list = await measureAll(page, [
      ['item-tag', '.item-tag'],
      ['expand-btn', '.expand-btn'],
      ['search-trigger', '.glass-search-trigger'],
    ]);
    // 折叠组先展开，长标题/标签卡才进 DOM
    if (await page.$('.expand-btn')) {
      await clickSel(page, '.expand-btn');
      await page.waitForTimeout(700);
      const ex = await measureAll(page, [['item-tag', '.item-tag']]);
      if (ex['item-tag']) R.list['item-tag'] = ex['item-tag'];
    }
    // 打开长标题备忘
    await page.evaluate(() => {
      const items = [...document.querySelectorAll('.list-item, .img-card')];
      const el = items.find((e) => (e.innerText || '').includes('长标题'));
      if (el) el.click();
    });
    await page.waitForSelector('.editor-title-capsule', { timeout: 15000 });
    await page.waitForTimeout(700);
    R.capsuleTop = await measureAll(page, [
      ['capsule', '.editor-title-capsule'],
      ['avatar-button', '.editor-avatar-button'],
      ['fab-left', '.editor-fab.left'],
      ['fab-right', '.editor-fab.right'],
    ]);
    // 滚动 → 坞进入 scrolled 横排态
    await page.evaluate(() => window.scrollTo(0, 700));
    await page.waitForTimeout(700);
    R.capsuleScrolled = await measureAll(page, [
      ['capsule', '.editor-title-capsule'],
      ['avatar-button', '.editor-avatar-button'],
    ]);
    await page.evaluate(() => window.scrollTo(0, 0));
    // 字体压力：回列表与备份页量文本驱动胶囊
    await clickSel(page, '.editor-fab.left');
    await goHome(page);
    const fontTargets = [
      ['search-trigger', '.glass-search-trigger'],
      ['item-tag', '.item-tag'],
      ['expand-btn', '.expand-btn'],
    ];
    R.fonts.default = await measureAll(page, fontTargets);
    for (const font of ['DejaVu Sans', 'Noto Sans CJK SC', 'Liberation Sans']) {
      await page.addStyleTag({ content: `body, button, input { font-family: '${font}', sans-serif !important; }` }).then((h) => h.evaluate((el) => { el.id = 'font-stress'; }));
      await page.waitForTimeout(300);
      R.fonts[font] = await measureAll(page, fontTargets);
      // 备份页徽章（文本驱动、无 line-height 锁定）
      await page.$eval('h1.page-title', (e) => e.click());
      await page.waitForSelector('.page-content', { timeout: 8000 });
      await page.click('.set-row:has-text("备份与恢复")');
      await page.waitForTimeout(600);
      R.fonts[font + ' @backup'] = await measureAll(page, [
        ['backup-hero-badge', '.backup-hero-badge'],
        ['backup-btn', '.backup-btn'],
        ['seg-btn', '.seg-btn'],
      ]);
      await page.click('.editor-fab.left');
      await page.waitForTimeout(600);
      await goHome(page);
      // 撤掉注入样式
      await page.evaluate(() => { const s = document.getElementById('font-stress'); if (s) s.remove(); });
      await page.waitForTimeout(300);
    }
  } catch (e) {
    console.log('FLOW ERROR @', width, String(e).slice(0, 260));
  }
  out[width] = R;
  await browser.close();
}
console.log(JSON.stringify(out, null, 1));
