// 非 iOS 形状一致性量测 v2：胶囊/圆形元素在 390/768/1280 三档宽度
// 下的实际渲染几何（宽高 + 计算 border-radius）。Rust 版与原版同测。
// 用法: node probe_shapes.mjs [rust|orig]
import { chromium } from 'playwright-core';

const app = process.argv[2] || 'rust';
const BASE = app === 'rust' ? 'http://localhost:8198/' : 'http://localhost:8199/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const MEASURE = `function measure(sel, pseudo) {
  const el = document.querySelector(sel);
  if (!el) return null;
  const r = el.getBoundingClientRect();
  const cs = getComputedStyle(el, pseudo || undefined);
  const out = { w: +r.width.toFixed(2), h: +r.height.toFixed(2), br: cs.borderTopLeftRadius, disp: cs.display };
  if (pseudo) { out.pw = cs.width; out.ph = cs.height; }
  return out;
}
function measureStyled(re) {
  const el = [...document.querySelectorAll('span')].find((s) => re.test(s.getAttribute('style') || ''));
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { w: +r.width.toFixed(2), h: +r.height.toFixed(2), br: getComputedStyle(el).borderTopLeftRadius };
}`;

async function measureAll(page, targets) {
  return page.evaluate(`(() => { ${MEASURE}; const out = {}; const T = ${JSON.stringify(targets)};
    for (const [name, sel] of T) out[name] = measure(sel);
    return out; })()`);
}
const clickSel = (page, sel) => page.evaluate((s) => { const el = document.querySelector(s); if (el) { el.click(); return true; } return false; }, sel);

const results = {};
for (const width of [390, 768, 1280]) {
  const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width, height: width === 390 ? 852 : 900 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
  const R = { list: {}, editor: {}, menu: {}, export: {}, bg: {}, settings: {}, backup: {} };
  try {
    await page.goto(BASE, { waitUntil: 'load' });
    await page.waitForSelector('.list-item', { timeout: 20000 });
    await page.waitForTimeout(600);
    R.list = await measureAll(page, [
      ['search-trigger', '.glass-search-trigger'],
      ['avatar-in-title', 'h1.page-title > *'],
      ['item-tag', '.item-tag'],
      ['pin-dot', '.pin-dot'],
      ['swipe-action-btn', '.swipe-action-btn'],
      ['expand-btn', '.expand-btn'],
      ['img-card', '.img-card'],
    ]);
    await page.evaluate(() => window.scrollTo(0, 800));
    await page.waitForTimeout(500);
    const compact = await measureAll(page, [['compact-title', '.page-title.compact']]);
    if (compact['compact-title'] && compact['compact-title'].h > 0) R.list['compact-title'] = compact['compact-title'];
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(300);

    if (app === 'rust') {
      await page.$eval('h1.page-title', (e) => e.click());
      await page.waitForSelector('.page-content', { timeout: 8000 });
      R.settings = await measureAll(page, [
        ['fab-left', '.editor-fab.left'],
        ['compact-title', '.page-title.compact'],
        ['seg-btn', '.seg-btn'],
      ]);
      await page.click('.set-row:has-text("备份与恢复")');
      await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
      await page.setInputFiles('#file-import', process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip');
      await page.waitForSelector('.backup-modal', { timeout: 8000 });
      await page.click('.backup-modal .backup-btn.primary');
      await page.waitForSelector('.backup-toast', { timeout: 10000 });
      await page.waitForTimeout(400);
      R.backup = await measureAll(page, [
        ['backup-btn', '.backup-btn'],
        ['backup-hero-badge', '.backup-hero-badge'],
        ['backup-state', '.backup-state'],
      ]);
      R.backup['history-dot'] = await page.evaluate(`(() => { ${MEASURE}; return measureStyled(/width:\\s*8px/); })()`);
      R.backup['history-badge'] = await page.evaluate(`(() => { ${MEASURE}; return measureStyled(/font-9|font-size:\\s*9px/); })()`);
      // 备份页返回先到设置页，需点两次才回列表
      for (let i = 0; i < 3; i++) {
        await page.click('.editor-fab.left');
        await page.waitForTimeout(900);
        if (await page.$('.container .list-item')) break;
      }
      await page.waitForTimeout(600);
      const after = await measureAll(page, [['expand-btn', '.expand-btn'], ['item-tag', '.item-tag'], ['img-card', '.img-card']]);
      Object.assign(R.list, after);
    }

    // 第二轮导入 allblocks 全块型夹具（待办/附件/音乐卡/md 预览语料）
    if (app === 'rust') {
      await page.$eval('h1.page-title', (e) => e.click());
      await page.waitForSelector('.page-content', { timeout: 8000 });
      await page.click('.set-row:has-text("备份与恢复")');
      await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
      await page.setInputFiles('#file-import', process.env.HOME + '/workspace/Mynote/fixtures/allblocks.zip');
      await page.waitForSelector('.backup-modal', { timeout: 8000 });
      await page.click('.backup-modal .backup-btn.primary');
      await page.waitForSelector('.backup-toast', { timeout: 10000 });
      await page.waitForTimeout(400);
      for (let i = 0; i < 3; i++) {
        await page.click('.editor-fab.left');
        await page.waitForTimeout(900);
        if (await page.$('.container .list-item')) break;
      }
      await page.waitForTimeout(500);
      const ab = await measureAll(page, [['item-tag', '.item-tag']]);
      if (ab['item-tag']) R.list['item-tag'] = ab['item-tag'];
    }

    // 编辑页：打开指定语料备忘（rust 用 allblocks「全块渲染测试」；原版用种子第二篇）
    const openMemo = async (text) => {
      await page.waitForSelector('.list-item', { timeout: 10000 });
      const clicked = await page.evaluate((t) => {
        const items = [...document.querySelectorAll('.list-item, .img-card')];
        const el = t ? items.find((e) => (e.innerText || '').includes(t)) : items[1];
        if (el) { el.click(); return true; }
        return false;
      }, text);
      if (!clicked) throw new Error('openMemo: target not found: ' + text);
      await page.waitForSelector(app === 'rust' ? '.editor-title-capsule' : '.editor-title-dock', { timeout: 15000 });
      await page.waitForTimeout(700);
    };
    if (app === 'rust') {
      await openMemo('全块渲染测试');
    } else {
      await openMemo(null);
    }
    R.editor = await measureAll(page, [
      ['fab-left', '.editor-fab.left'],
      ['fab-right', '.editor-fab.right'],
      ['avatar-button', '.editor-avatar-button'],
      ['title-capsule', '.editor-title-capsule'],
      ['title-capsule-alt', '.editor-title-dock > div'],
      ['todo-checkbox', '.editor-body .todo-checkbox'],
      ['md-preview-pill', '.editor-body .md-preview:not(.block)'],
      ['att-hint', '.att-hint'],
      ['music-retry', '.music-card-retry'],
      ['slash-pill', '.slash-recent-pill'],
    ]);
    R.editor['todo-ring'] = await page.evaluate(`(() => { ${MEASURE}; return measure('.editor-body .todo-checkbox', '::before'); })()`);
    const atomic = await page.$('.editor-body .atomic');
    if (atomic) {
      await atomic.click();
      await page.waitForTimeout(400);
      const bd = await measureAll(page, [['blk-del', '.blk-del']]);
      if (bd['blk-del']) R.editor['blk-del'] = bd['blk-del'];
    }

    // 菜单（DOM 直点：Playwright 可点性检查会被块选中浮层挡住）
    await clickSel(page, '.editor-fab.right');
    await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
    await page.waitForTimeout(500);
    R.menu = await measureAll(page, [
      ['switch', '.switch'],
      ['switch-knob', '.switch .knob'],
      ['col-toggle-track', '.editor-column-toggle-track'],
      ['col-toggle-knob', '.editor-column-toggle-knob'],
      ['menu-icon', '.menu-icon'],
    ]);
    // 导出面板
    if (await clickSel(page, '.menu-section .menu-item')) {
      await page.waitForSelector('.editor-export-panel', { timeout: 8000 }).catch(() => {});
      await page.waitForTimeout(500);
      R.export = await measureAll(page, [
        ['export-back', '.export-back'],
        ['export-badge', '.export-badge'],
      ]);
      await clickSel(page, '.export-back');
      await page.waitForTimeout(600);
    }
    // 背景底表（菜单最后一项）
    if (!(await page.$('.editor-menu-panel'))) { await clickSel(page, '.editor-fab.right'); await page.waitForSelector('.editor-menu-panel', { timeout: 8000 }); await page.waitForTimeout(400); }
    await page.evaluate(() => { const items = document.querySelectorAll('.editor-menu-panel > .menu-item, .editor-menu-panel .menu-item'); if (items.length) items[items.length - 1].click(); });
    await page.waitForSelector('.bg-sheet', { timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(500);
    R.bg = await measureAll(page, [['bg-dot', '.bg-dot']]);
  } catch (e) {
    console.log('FLOW ERROR @', width, String(e).slice(0, 300));
  }
  results[width] = R;
  await browser.close();
}
console.log(JSON.stringify(results, null, 1));
