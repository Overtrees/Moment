// 列表页审计探针：原版(8101) vs Rust(8100)，同 zip 同视口。
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const RUST = 'http://localhost:8100/';
const ORIG = 'http://localhost:8101/Moment.html';
const REAL = '/home/hatch/workspace/mynote-zip-acceptance/real_backup.zip';
const SYNTH = '/tmp/synth.zip';
const ONE = '/tmp/one.zip';

const browser = await chromium.launch({
  executablePath: process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell',
  args: ['--no-sandbox'],
});
const out = [];
function log(side, item, data) { out.push({ side, item, data }); console.log(side, item, JSON.stringify(data)); }

async function newPage(locale) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, ...(locale ? { locale } : {}) });
  return ctx.newPage();
}

async function importRust(page, zip) {
  await page.goto(RUST, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.waitForTimeout(500);
  await page.$eval('h1.page-title', e => e.click());
  await page.waitForTimeout(700);
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForTimeout(700);
  await page.setInputFiles('#file-import', zip);
  await page.waitForTimeout(900);
  if (await page.locator('.backup-modal').count()) await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(500);
  await page.click('.editor-fab.left');
  await page.waitForTimeout(800);
  await page.click('.editor-fab.left');
  await page.waitForTimeout(1000);
}

async function importOrig(page, zip) {
  await page.goto(ORIG, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  const b64 = fs.readFileSync(zip).toString('base64');
  const r = await page.evaluate(async (b64) => {
    const bin = atob(b64); const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    const unzipped = await window.MynoteZip.checkedZip(bytes);
    const backup = JSON.parse(fflate.strFromU8(unzipped['memos.json']));
    const db = await window.MynoteIdb.getDB();
    const res = await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
    try { localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos)); } catch (e) {}
    return JSON.stringify(res);
  }, b64);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2500);
  return r;
}

// 通用 DOM 快照：分组/卡片/头部度量
async function snapshot(page) {
  return page.evaluate(() => {
    const q = s => document.querySelector(s);
    const qa = s => [...document.querySelectorAll(s)];
    const rect = el => el ? (() => { const r = el.getBoundingClientRect(); return { w: Math.round(r.width), h: Math.round(r.height), x: Math.round(r.x), y: Math.round(r.y) }; })() : null;
    const title = q('h1.page-title');
    const avatarEl = title ? (title.querySelector('img') || title.querySelector('div') || title.querySelector('svg')) : null;
    const trig = q('.glass-search-trigger');
    const groups = qa('.section-header').map(e => e.innerText.trim());
    const cards = qa('.swipe-wrapper').map(w => {
      const item = w.querySelector('.list-item, .img-card');
      const img = w.querySelector('img.img-cover');
      return {
        cls: item ? item.className : '',
        title: (w.querySelector('.item-title-text, .img-card-title-text') || {}).innerText || '',
        meta: (w.querySelector('.item-meta, .img-text .m') || {}).innerText || '',
        tags: [...w.querySelectorAll('.item-tag')].map(t => t.innerText.trim()),
        expand: (w.querySelector('.expand-btn') || {}).innerText || '',
        transform: item ? getComputedStyle(item).transform : '',
        imgNat: img ? img.naturalWidth : null,
        coverDiv: !!w.querySelector('div.img-cover'),
      };
    });
    return {
      avatarRect: rect(avatarEl), avatarTag: avatarEl ? avatarEl.tagName : null,
      titleText: title ? title.innerText.trim() : null,
      trigRect: rect(trig), trigText: trig ? trig.innerText.trim() : null,
      groups, cards,
      emptyTip: (q('.empty-tip') || {}).innerText || null,
      bodyTextLen: document.body.innerText.length,
      scrollH: document.documentElement.scrollHeight,
    };
  });
}

// Rust: PointerEvent 横拖；Orig: TouchEvent 横拖（其手势钩子只听 touch）
async function swipe(page, cardIndex, dx, kind) {
  return page.evaluate(({ cardIndex, dx, kind }) => {
    const rows = [...document.querySelectorAll('.swipe-wrapper')];
    const w = rows[cardIndex];
    const row = w.querySelector('.list-item, .img-card');
    const r = row.getBoundingClientRect();
    const y = r.top + r.height / 2, x0 = r.left + r.width * 0.7;
    const steps = 6;
    if (kind === 'pointer') {
      const opts = (x) => ({ bubbles: true, cancelable: true, composed: true, pointerId: 7, pointerType: 'touch', clientX: x, clientY: y, isPrimary: true });
      row.dispatchEvent(new PointerEvent('pointerdown', opts(x0)));
      for (let i = 1; i <= steps; i++) row.dispatchEvent(new PointerEvent('pointermove', opts(x0 + dx * i / steps)));
      row.dispatchEvent(new PointerEvent('pointerup', opts(x0 + dx)));
      row.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: x0 + dx, clientY: y }));
    } else {
      const mk = (x) => new Touch({ identifier: 7, target: row, clientX: x, clientY: y });
      const ev = (type, x) => new TouchEvent(type, { bubbles: true, cancelable: true, composed: true, touches: type === 'touchend' ? [] : [mk(x)], changedTouches: [mk(x)] });
      row.dispatchEvent(ev('touchstart', x0));
      for (let i = 1; i <= steps; i++) row.dispatchEvent(ev('touchmove', x0 + dx * i / steps));
      row.dispatchEvent(ev('touchend', x0 + dx));
      // 原版 touchmove 在 swiping 时 preventDefault（非 passive 监听），
      // 真机上拖动后的 click 被浏览器抑制；仅小位移时才补发 click。
      if (Math.abs(dx) < 10) row.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: x0 + dx, clientY: y }));
    }
    return true;
  }, { cardIndex, dx, kind });
}

async function rowTransform(page, cardIndex) {
  return page.evaluate((i) => {
    const w = [...document.querySelectorAll('.swipe-wrapper')][i];
    const row = w && w.querySelector('.list-item, .img-card');
    if (!row) return null;
    const m = getComputedStyle(row).transform;
    const btns = [...w.querySelectorAll('.swipe-action-btn')].map(b => ({ text: b.innerText.trim(), pe: getComputedStyle(b).pointerEvents, op: getComputedStyle(b).opacity }));
    return { transform: m, btns };
  }, cardIndex);
}

// ============ Phase A: real_backup 基础 ============
for (const side of ['rust', 'orig']) {
  const page = await newPage();
  if (side === 'rust') await importRust(page, REAL); else await importOrig(page, REAL);
  await page.waitForTimeout(1200);
  log(side, 'A-snapshot', await snapshot(page));
  // 封面图加载等待
  await page.waitForTimeout(1500);
  log(side, 'A-cover-after', await page.evaluate(() => {
    const img = document.querySelector('img.img-cover');
    return { exists: !!img, naturalWidth: img ? img.naturalWidth : null, coverDiv: !!document.querySelector('div.img-cover') };
  }));
  // 头像点击进设置
  await page.$eval('h1.page-title', e => e.click()).catch(e => log(side, 'A-avatar-click-err', String(e)));
  await page.waitForTimeout(900);
  log(side, 'A-avatar-to-settings', await page.evaluate(() => ({
    hasSetRow: !!document.querySelector('.set-row'),
    bodyHead: document.body.innerText.slice(0, 80).replace(/\n/g, '|'),
  })));
  await page.click('.editor-fab.left').catch(() => {});
  await page.waitForTimeout(900);
  await page.close();
}

// ============ Phase B: synthetic 分组/折叠/搜索/滑动/滚动 ============
for (const side of ['rust', 'orig']) {
  const kind = side === 'rust' ? 'pointer' : 'touch';
  const page = await newPage();
  if (side === 'rust') await importRust(page, SYNTH); else await importOrig(page, SYNTH);
  await page.waitForTimeout(1200);
  log(side, 'B-snapshot-collapsed', await snapshot(page));

  // 折叠：点首卡（今日甲）——用 evaluate 派发 click，避免 Playwright 自动滚动干扰
  const snap = await snapshot(page);
  const idx甲 = snap.cards.findIndex(c => c.title === '今日甲');
  log(side, 'B-idx-jia', { idx甲 });
  if (idx甲 >= 0) {
    await page.evaluate((i) => {
      const w = [...document.querySelectorAll('.swipe-wrapper')][i];
      const row = w.querySelector('.list-item, .img-card');
      row.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    }, idx甲);
    await page.waitForTimeout(800);
    const after = await snapshot(page);
    log(side, 'B-after-fold-click', {
      editorOpen: await page.evaluate(() => !!document.querySelector('.editor-body')),
      titles: after.cards.map(c => c.title),
      expands: after.cards.map(c => c.expand).filter(Boolean),
    });
    // 点末卡「收起」
    const snap2 = after;
    const idx丁 = snap2.cards.findIndex(c => c.title === '今日丁');
    if (idx丁 >= 0) {
      const expBtn = page.locator('.swipe-wrapper').nth(idx丁).locator('.expand-btn');
      if (await expBtn.count()) { await expBtn.first().click(); await page.waitForTimeout(700); }
      const after2 = await snapshot(page);
      log(side, 'B-after-collapse', { titles: after2.cards.map(c => c.title), expands: after2.cards.map(c => c.expand).filter(Boolean) });
    }
    // 若卡片点击未展开，单独测「展开 N 条」按钮
    const chk = await snapshot(page);
    if (!chk.cards.some(c => c.title === '今日乙')) {
      const idx2 = chk.cards.findIndex(c => c.title === '今日甲');
      if (idx2 >= 0) {
        await page.evaluate((i) => {
          const b = [...document.querySelectorAll('.swipe-wrapper')][i].querySelector('.expand-btn');
          if (b) b.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        }, idx2);
        await page.waitForTimeout(800);
        const after3 = await snapshot(page);
        log(side, 'B-expand-via-btn', { titles: after3.cards.map(c => c.title), expands: after3.cards.map(c => c.expand).filter(Boolean), editorOpen: await page.evaluate(() => !!document.querySelector('.editor-body')) });
        // 收起回去，保持后续步骤初始态一致
        const idxD = after3.cards.findIndex(c => c.title === '今日丁');
        if (idxD >= 0) await page.evaluate((i) => {
          const b = [...document.querySelectorAll('.swipe-wrapper')][i].querySelector('.expand-btn');
          if (b) b.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        }, idxD);
        await page.waitForTimeout(700);
      }
    }
  }

  // 搜索：触发→面板度量→过滤→无结果→Esc→清空
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(600);
  await page.$eval('.glass-search-trigger', e => e.click());
  await page.waitForTimeout(700);
  log(side, 'B-search-panel', await page.evaluate(() => {
    const inp = document.querySelector('.glass-search-input');
    const panel = document.querySelector('.glass-search-panel');
    const r = panel ? panel.getBoundingClientRect() : null;
    return { panel: r ? { w: Math.round(r.width), h: Math.round(r.height) } : null, inputW: inp ? Math.round(inp.getBoundingClientRect().width) : null, focused: document.activeElement === inp, placeholder: inp ? inp.placeholder : null };
  }));
  const inp = page.locator('.glass-search-input');
  await inp.fill('粗体词');
  await page.waitForTimeout(700);
  let s = await snapshot(page);
  log(side, 'B-search-body-hit', { titles: s.cards.map(c => c.title), groups: s.groups, emptyTip: s.emptyTip });
  await inp.fill('今日乙');
  await page.waitForTimeout(700);
  s = await snapshot(page);
  log(side, 'B-search-title-hit', { titles: s.cards.map(c => c.title) });
  await inp.fill('不存在xyz');
  await page.waitForTimeout(700);
  s = await snapshot(page);
  log(side, 'B-search-noresult', { titles: s.cards.map(c => c.title), groups: s.groups, emptyTip: s.emptyTip, text: await page.evaluate(() => document.body.innerText.slice(0, 200).replace(/\n/g, '|')) });
  await page.keyboard.press('Escape');
  await page.waitForTimeout(600);
  log(side, 'B-search-esc', await page.evaluate(() => ({ panelGone: !document.querySelector('.glass-search-panel'), trigBack: !!document.querySelector('.glass-search-trigger') })));
  // 重新打开，清空查询应恢复（先填再删）
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(500);
  await page.$eval('.glass-search-trigger', e => e.click()).catch(() => {});
  await page.waitForTimeout(500);
  const inp2 = page.locator('.glass-search-input');
  if (await inp2.count()) {
    log(side, 'B-search-reopen-value', { value: await inp2.inputValue() });
    await inp2.fill('');
    await page.waitForTimeout(600);
    s = await snapshot(page);
    log(side, 'B-search-cleared', { count: s.cards.length, titles: s.cards.map(c => c.title) });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
  }

  // 滑动：对「上周记」行（文本行）做 -120 拖（过阈值）与 -30 拖（未过）
  s = await snapshot(page);
  const idxW = s.cards.findIndex(c => c.title === '上周记');
  log(side, 'B-idx-week', { idxW });
  if (idxW >= 0) {
    await swipe(page, idxW, -30, kind);
    await page.waitForTimeout(500);
    log(side, 'B-swipe-30', await rowTransform(page, idxW));
    await swipe(page, idxW, -120, kind);
    await page.waitForTimeout(600);
    log(side, 'B-swipe-120-open', await rowTransform(page, idxW));
    // 打开状态点卡片：只关闭
    await page.evaluate((i) => {
      const w = [...document.querySelectorAll('.swipe-wrapper')][i];
      const row = w.querySelector('.list-item, .img-card');
      row.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
    }, idxW);
    await page.waitForTimeout(600);
    log(side, 'B-open-click-close', { t: await rowTransform(page, idxW), editorOpen: await page.evaluate(() => !!document.querySelector('.editor-body')) });
    // 再次滑开 → 点置顶
    await swipe(page, idxW, -120, kind);
    await page.waitForTimeout(600);
    const btns = page.locator('.swipe-wrapper').nth(idxW).locator('.swipe-action-btn');
    await btns.first().click({ force: true }).catch(e => log(side, 'B-pin-click-err', String(e).slice(0, 100)));
    await page.waitForTimeout(800);
    s = await snapshot(page);
    log(side, 'B-after-pin', { groups: s.groups, titles: s.cards.map(c => c.title) });
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(side === 'rust' ? 1500 : 2500);
    s = await snapshot(page);
    log(side, 'B-after-pin-reload', { groups: s.groups, titles: s.cards.map(c => c.title) });
    // 取消置顶（此时上周记在置顶组）
    const idxW2 = s.cards.findIndex(c => c.title === '上周记');
    if (idxW2 >= 0) {
      await swipe(page, idxW2, -120, kind);
      await page.waitForTimeout(600);
      await page.locator('.swipe-wrapper').nth(idxW2).locator('.swipe-action-btn').first().click({ force: true }).catch(() => {});
      await page.waitForTimeout(800);
      s = await snapshot(page);
      log(side, 'B-after-unpin', { groups: s.groups, titles: s.cards.map(c => c.title) });
    }
    // 删除「三月记」+ reload 验证落库
    const idxY = s.cards.findIndex(c => c.title === '三月记');
    if (idxY >= 0) {
      await swipe(page, idxY, -120, kind);
      await page.waitForTimeout(600);
      log(side, 'B-del-open-state', await rowTransform(page, idxY));
      await page.locator('.swipe-wrapper').nth(idxY).locator('.swipe-action-btn').nth(1).click({ force: true }).catch(e => log(side, 'B-del-click-err', String(e).slice(0, 100)));
      await page.waitForTimeout(800);
      s = await snapshot(page);
      log(side, 'B-after-delete', { titles: s.cards.map(c => c.title) });
      await page.reload({ waitUntil: 'load' });
      await page.waitForTimeout(side === 'rust' ? 1500 : 2500);
      s = await snapshot(page);
      log(side, 'B-after-delete-reload', { titles: s.cards.map(c => c.title) });
    }
  }

  // 滚动联动：scrollY 0 / 15 / 30 / 100 时标题 transform/opacity 与紧凑标题可见性
  for (const y of [0, 15, 30, 120]) {
    await page.evaluate((yy) => window.scrollTo(0, yy), y);
    await page.waitForTimeout(450);
    log(side, 'B-scroll-' + y, await page.evaluate(() => {
      const t = document.querySelector('h1.page-title');
      const compact = document.querySelector('.page-title.compact');
      const trig = document.querySelector('.glass-search-trigger');
      const cs = t ? getComputedStyle(t) : null;
      return { scrollY: window.scrollY, transform: cs ? cs.transform : null, opacity: cs ? cs.opacity : null, visibility: cs ? cs.visibility : null, compactVis: compact ? getComputedStyle(compact).visibility : null, compactOp: compact ? getComputedStyle(compact).opacity : null, trigOp: trig ? getComputedStyle(trig).opacity : null };
    }));
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(400);

  // 新建卡：点击 → 编辑器 → reload 后列表变化
  const before = await snapshot(page);
  const idxNew = before.cards.findIndex(c => c.title === '新建笔记');
  if (idxNew >= 0) {
    await page.locator('.swipe-wrapper').nth(idxNew).locator('.list-item').first().click();
    await page.waitForTimeout(1200);
    log(side, 'B-new-open-editor', await page.evaluate(() => ({ editorBody: !!document.querySelector('.editor-body'), hasFab: !!document.querySelector('.editor-fab'), bodyHead: document.body.innerText.slice(0, 60).replace(/\n/g, '|') })));
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(side === 'rust' ? 1500 : 2500);
    const afterNew = await snapshot(page);
    log(side, 'B-new-after-reload', { countBefore: before.cards.length, countAfter: afterNew.cards.length, titles: afterNew.cards.map(c => c.title) });
  }
  await page.close();
}

// ============ Phase C: 12h(en-US) / 24h(zh-CN) 制 ============
for (const loc of ['en-US', 'zh-CN']) {
  for (const side of ['rust', 'orig']) {
    const page = await newPage(loc);
    if (side === 'rust') await importRust(page, SYNTH); else await importOrig(page, SYNTH);
    await page.waitForTimeout(1000);
    const s = await snapshot(page);
    log(side, 'C-' + loc, { hasDayPeriod: await page.evaluate(() => new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).formatToParts(new Date(2024, 0, 1, 13)).some(p => p.type === 'dayPeriod')), metas: s.cards.filter(c => c.title).map(c => c.title + ' :: ' + c.meta.split('\n')[0]) });
    await page.close();
  }
}

// ============ Phase D: 空状态（单条 zip 删光） ============
for (const side of ['rust', 'orig']) {
  const kind = side === 'rust' ? 'pointer' : 'touch';
  const page = await newPage();
  if (side === 'rust') await importRust(page, ONE); else await importOrig(page, ONE);
  await page.waitForTimeout(1000);
  let s = await snapshot(page);
  log(side, 'D-before', { titles: s.cards.map(c => c.title), emptyTip: s.emptyTip });
  const idx = s.cards.findIndex(c => c.title === '唯一备忘');
  if (idx >= 0) {
    await swipe(page, idx, -120, kind);
    await page.waitForTimeout(600);
    await page.locator('.swipe-wrapper').nth(idx).locator('.swipe-action-btn').nth(1).click({ force: true }).catch(e => log(side, 'D-del-err', String(e).slice(0, 100)));
    await page.waitForTimeout(900);
    s = await snapshot(page);
    log(side, 'D-empty', { titles: s.cards.map(c => c.title), emptyTip: s.emptyTip, bodyText: await page.evaluate(() => document.body.innerText.slice(0, 160).replace(/\n/g, '|')) });
  }
  await page.close();
}

fs.writeFileSync('/tmp/audit_pages_list_raw.json', JSON.stringify(out, null, 1));
await browser.close();
console.log('DONE');
