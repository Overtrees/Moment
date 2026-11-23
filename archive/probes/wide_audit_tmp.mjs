// 大屏编辑页适配审计探针（只读量测，生产站，Chromium 口径）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const URL = 'http://localhost:8931/';
const ZIP = '/tmp/fx/combined.zip';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
// 生产字节镜像走 localhost（wasm md5 与线上戳逐字一致）；
// Chromium 直连公网隧道不通，故清掉代理 env 只打本地。
for (const k of ['http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'all_proxy', 'ALL_PROXY']) delete process.env[k];
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
const R = {};

async function importZip(page) {
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', ZIP);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  let toast = null;
  for (let i = 0; i < 60 && !toast; i++) {
    toast = await page.evaluate(() => {
      const t = document.querySelector('.backup-toast');
      if (!t || !t.innerText.includes('已导入')) return null;
      const r = t.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height, text: t.innerText.slice(0, 30) };
    });
    if (!toast) await page.waitForTimeout(150);
  }
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page.waitForTimeout(400);
  return toast;
}

async function openMemo(page, title) {
  const pt = await page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt);
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, title);
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1600);
}

const layoutInfo = (page) => page.evaluate(() => {
  const q = (s) => document.querySelector(s);
  const rect = (el) => el ? { x: +el.getBoundingClientRect().x.toFixed(1), y: +el.getBoundingClientRect().y.toFixed(1), w: +el.getBoundingClientRect().width.toFixed(1), h: +el.getBoundingClientRect().height.toFixed(1) } : null;
  const detail = q('.detail');
  const spread = q('.editor-spread');
  const body = q('.editor-body');
  const bcs = body ? getComputedStyle(body) : null;
  // 72ch 实测：以正文字体量 '0' 字宽
  let chPx = null;
  if (body) {
    const sp = document.createElement('span');
    sp.style.cssText = 'position:absolute;visibility:hidden;font:inherit;white-space:nowrap';
    sp.textContent = '0000000000';
    body.appendChild(sp);
    chPx = +(sp.getBoundingClientRect().width / 10).toFixed(2);
    sp.remove();
  }
  const cols = [...document.querySelectorAll('.editor-body > .editor-column')].map((c) => {
    const cs = getComputedStyle(c);
    return {
      side: c.getAttribute('data-editor-column'), rect: rect(c),
      scrollH: c.scrollHeight, clientH: c.clientHeight, scrollTop: c.scrollTop,
      overflowY: cs.overflowY, padL: cs.paddingLeft, padR: cs.paddingRight, borderR: cs.borderRightWidth,
    };
  });
  const units = [];
  document.querySelectorAll('.editor-body > .editor-column').forEach((c) => {
    const side = c.getAttribute('data-editor-column');
    [...c.children].forEach((u) => {
      const ed = u.querySelector('.ed-line, [contenteditable="true"]') || u;
      const ecs = getComputedStyle(ed);
      units.push({
        bid: u.getAttribute('data-bid') || u.getAttribute('data-bids') || '?',
        cls: (u.className || '').toString().slice(0, 60), col: side, rect: rect(u),
        fs: ecs.fontSize, lh: ecs.lineHeight,
      });
    });
  });
  // 无栏容器时（单栏）直子
  if (!cols.length && body) {
    [...body.children].forEach((u) => units.push({ bid: u.getAttribute('data-bid') || '?', cls: (u.className || '').toString().slice(0, 60), col: 'single', rect: rect(u) }));
  }
  const dock = q('.editor-title-dock');
  const cap = q('.editor-title-capsule');
  const av = q('.editor-avatar-button');
  const fabs = [...document.querySelectorAll('.editor-fab')].map((f) => ({ cls: f.className, rect: rect(f), label: f.getAttribute('aria-label') }));
  const pad = q('.editor-pad');
  const bl = q('.wiki-backlinks');
  return {
    detailCls: detail ? detail.className : null,
    spreadRect: rect(spread), bodyCls: body ? body.className : null,
    bodyRect: rect(body),
    bodyStyle: bcs ? { display: bcs.display, colCount: bcs.columnCount, colGap: bcs.columnGap, lh: bcs.lineHeight } : null,
    padStyle: pad ? { pl: getComputedStyle(pad).paddingLeft, pr: getComputedStyle(pad).paddingRight, pt: getComputedStyle(pad).paddingTop } : null,
    chPx, ch72: chPx ? +(chPx * 72).toFixed(1) : null,
    cols, units, dockRect: rect(dock), capRect: rect(cap), avatarRect: rect(av), fabs,
    backlinksRect: rect(bl),
  };
});

const blockDetail = (page) => page.evaluate(() => {
  const out = {};
  const rect = (el) => el ? { x: +el.getBoundingClientRect().x.toFixed(1), y: +el.getBoundingClientRect().y.toFixed(1), w: +el.getBoundingClientRect().width.toFixed(1), h: +el.getBoundingClientRect().height.toFixed(1) } : null;
  const gal = document.querySelector('.gallery-grid');
  if (gal) {
    const cs = getComputedStyle(gal);
    const imgs = [...gal.querySelectorAll('img')];
    out.gallery = { rect: rect(gal), cols: cs.gridTemplateColumns, gap: cs.gap, margin: cs.margin, n: imgs.length, tile: imgs[0] ? rect(imgs[0]) : null, tileRadius: imgs[0] ? getComputedStyle(imgs[0]).borderRadius : null };
  }
  const atomImg = document.querySelector('.atomic-img, .atomic[data-type="image"]');
  if (atomImg) {
    const img = atomImg.querySelector('img');
    const cs = getComputedStyle(atomImg);
    out.image = { wrapRect: rect(atomImg), wrapCls: atomImg.className, margin: cs.margin, imgRect: img ? rect(img) : null, imgMargin: img ? getComputedStyle(img).margin : null, imgRadius: img ? getComputedStyle(img).borderRadius : null };
  }
  const att = document.querySelector('.attachment-file');
  if (att) { const cs = getComputedStyle(att); out.attFile = { rect: rect(att), padding: cs.padding, radius: cs.borderRadius, gap: cs.gap }; }
  const music = document.querySelector('.blk-music, [data-type="musicCard"]');
  if (music) out.music = { rect: rect(music), cls: (music.className || '').toString().slice(0, 50) };
  const link = document.querySelector('.link-card-block');
  if (link) { const t = link.querySelector('.lkc-title'); out.link = { rect: rect(link), titleFs: t ? getComputedStyle(t).fontSize : null, cover: rect(link.querySelector('.lkc-cover')) }; }
  const todo = document.querySelector('.todo-row, [data-type="todo"]');
  if (todo) { const cb = todo.querySelector('.todo-checkbox'); out.todo = { rect: rect(todo), cb: cb ? rect(cb) : null, minH: getComputedStyle(todo).minHeight }; }
  const itc = document.querySelector('.img-text-card');
  if (itc) out.itc = { rect: rect(itc) };
  const itr = document.querySelector('.img-text-row');
  if (itr) out.itr = { rect: rect(itr) };
  const quote = document.querySelector('.blk-quote, blockquote');
  if (quote) { const cs = getComputedStyle(quote); out.quote = { rect: rect(quote), padding: cs.padding, fs: cs.fontSize }; }
  const pre = document.querySelector('.blk-code, .md-preview.block pre, .editor-body pre');
  if (pre) out.pre = { rect: rect(pre), padding: getComputedStyle(pre).padding };
  const tbl = document.querySelector('.editor-body table');
  if (tbl) { const td = tbl.querySelector('td, th'); out.table = { rect: rect(tbl), cellPad: td ? getComputedStyle(td).padding : null, cellMinW: td ? getComputedStyle(td).minWidth : null }; }
  return out;
});

async function runViewport(w, h, opts = {}) {
  const key = `${w}x${h}`;
  L(`\n===== ${key} =====`);
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => L('PAGEERROR', String(e).slice(0, 160)));
  const res = { viewport: key };
  try {
    res.toast = await importZip(page);
    await openMemo(page, '双栏混排');
    res.flow = await layoutInfo(page);
    await page.screenshot({ path: `/tmp/wide_flow_${w}.png` });
    // 斜杠面板：右栏找一段落输入 /
    if (opts.slash !== false) {
      try {
        const pt = await page.evaluate(() => {
          const cols = document.querySelectorAll('.editor-body > .editor-column');
          const scope = cols.length > 1 ? cols[1] : document.querySelector('.editor-body');
          const u = [...scope.children].find((c) => (c.className || '').includes('blk-p')) || [...scope.children][1];
          const ed = u.querySelector('.ed-line') || u;
          ed.scrollIntoView({ block: 'center' });
          const r = ed.getBoundingClientRect();
          return { x: r.x + 30, y: r.y + r.height / 2 };
        });
        await page.mouse.click(pt.x, pt.y);
        await page.keyboard.type('/');
        await page.waitForSelector('#slash-panel', { timeout: 5000 });
        await page.waitForTimeout(400);
        res.slash = await page.evaluate(() => {
          const p = document.getElementById('slash-panel');
          const r = p.getBoundingClientRect();
          const sel = window.getSelection();
          let caret = null;
          if (sel && sel.rangeCount) { const cr = sel.getRangeAt(0).getBoundingClientRect(); caret = { x: cr.x, y: cr.y, b: cr.bottom, h: cr.height }; }
          return { rect: { x: r.x, y: r.y, w: r.width, h: r.height }, caret, rows: p.querySelectorAll('.slash-row').length, z: getComputedStyle(p).zIndex };
        });
        await page.screenshot({ path: `/tmp/wide_slash_${w}.png` });
        await page.keyboard.press('Escape');
        await page.waitForTimeout(300);
        // 清掉斜杠字符避免污染落盘（退格删 /）
        await page.keyboard.press('Backspace');
        await page.waitForTimeout(300);
      } catch (e) { res.slash = 'ERR ' + String(e).slice(0, 120); }
    }
    // 菜单 + 独立双栏切换
    if (opts.menu !== false) {
      try {
        const fab = await page.evaluate(() => {
          const f = [...document.querySelectorAll('.editor-fab')].find((b) => (b.getAttribute('aria-label') || '').includes('菜单') || b.className.includes('right'));
          if (!f) return null; const r = f.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
        });
        await page.mouse.click(fab.x, fab.y);
        await page.waitForSelector('.editor-menu-panel', { timeout: 5000 });
        await page.waitForTimeout(500);
        res.menu = await page.evaluate(() => {
          const p = document.querySelector('.editor-menu-panel');
          const r = p.getBoundingClientRect();
          const tg = document.querySelector('.editor-column-mode-toggle');
          return {
            rect: { x: r.x, y: r.y, w: r.width, h: r.height }, origin: getComputedStyle(p).transformOrigin,
            toggleDisplay: tg ? getComputedStyle(tg).display : 'ABSENT',
            items: [...p.querySelectorAll('.menu-title, .editor-column-mode-title')].map((e) => e.textContent.trim()),
          };
        });
        // 背景底表（若菜单有背景项）
        const bgPt = await page.evaluate(() => {
          const b = [...document.querySelectorAll('.editor-menu-panel button')].find((e) => e.textContent.includes('背景'));
          if (!b) return null; const r = b.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
        });
        if (bgPt) {
          await page.mouse.click(bgPt.x, bgPt.y);
          await page.waitForSelector('.bg-sheet', { timeout: 5000 }).catch(() => null);
          await page.waitForTimeout(500);
          res.bgsheet = await page.evaluate(() => {
            const s = document.querySelector('.bg-sheet');
            if (!s) return null; const r = s.getBoundingClientRect();
            return { x: r.x, y: r.y, w: r.width, h: r.height };
          });
          await page.mouse.click(10, 10);
          await page.waitForTimeout(400);
          // 底表点外关闭后菜单可能已关，重新打开
          await page.mouse.click(fab.x, fab.y);
          await page.waitForSelector('.editor-menu-panel', { timeout: 5000 }).catch(() => null);
          await page.waitForTimeout(400);
        }
        const tgPt = await page.evaluate(() => {
          const tg = document.querySelector('.editor-column-mode-toggle');
          if (!tg || getComputedStyle(tg).display === 'none') return null;
          const r = tg.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
        });
        if (tgPt) {
          await page.mouse.click(tgPt.x, tgPt.y);
          await page.waitForTimeout(900);
          res.indep = await layoutInfo(page);
          // 独立滚动：左栏滚动不带动右栏
          res.indepScroll = await page.evaluate(() => {
            const cols = document.querySelectorAll('.editor-body > .editor-column');
            if (cols.length < 2) return 'no-cols';
            cols[0].scrollTop = 120;
            return { leftTop: cols[0].scrollTop, rightTop: cols[1].scrollTop, leftCanScroll: cols[0].scrollHeight > cols[0].clientHeight };
          });
          await page.screenshot({ path: `/tmp/wide_indep_${w}.png` });
        }
      } catch (e) { res.menu = 'ERR ' + String(e).slice(0, 120); }
    }
    // 重进不跳栏：回列表再进，比对分栏归属
    try {
      const before = (res.indep || res.flow).units.map((u) => `${u.bid}@${u.col}`).join(',');
      const back = await page.evaluate(() => {
        const f = [...document.querySelectorAll('.editor-fab')].find((b) => b.className.includes('left'));
        if (!f) return null; const r = f.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      });
      await page.mouse.click(back.x, back.y);
      await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
      await page.waitForTimeout(500);
      await openMemo(page, '双栏混排');
      const after = await layoutInfo(page);
      const afterMap = after.units.map((u) => `${u.bid}@${u.col}`).join(',');
      res.reentry = { stable: before === afterMap, mode: after.bodyCls, before: before.slice(0, 200), after: afterMap.slice(0, 200) };
    } catch (e) { res.reentry = 'ERR ' + String(e).slice(0, 120); }
    // 全块备忘
    try {
      const back2 = await page.evaluate(() => {
        const f = [...document.querySelectorAll('.editor-fab')].find((b) => b.className.includes('left'));
        if (!f) return null; const r = f.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
      });
      await page.mouse.click(back2.x, back2.y);
      await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
      await page.waitForTimeout(400);
      await openMemo(page, '全块渲染测试');
      res.allblocks = await blockDetail(page);
      res.allblocksLayout = await layoutInfo(page);
      await page.screenshot({ path: `/tmp/wide_allblocks_${w}.png` });
    } catch (e) { res.allblocks = 'ERR ' + String(e).slice(0, 120); }
  } catch (e) {
    res.fatal = String(e).slice(0, 200);
  }
  R[key] = res;
  await ctx.close();
  return res;
}

for (const [w, h] of [[1024, 768], [1280, 800], [1440, 900], [1920, 1080]]) {
  await runViewport(w, h);
}
await runViewport(1024, 500, { slash: false });
await runViewport(1280, 500, { slash: false });

// 拖拽拾起 @1440 flow
try {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, hasTouch: true });
  const page = await ctx.newPage();
  await importZip(page);
  await openMemo(page, '双栏混排');
  const drag = { viewport: '1440x900' };
  const pt = await page.evaluate(() => {
    const col = document.querySelector('.editor-body > .editor-column');
    const u = [...col.children].find((c) => (c.className || '').includes('blk-p')) || col.children[0];
    const r = u.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2, bid: u.getAttribute('data-bid') };
  });
  await page.mouse.move(pt.x, pt.y);
  await page.mouse.down();
  await page.waitForTimeout(420); // 文本块 hold 280ms 拾起
  drag.atPickup = await page.evaluate((bid) => {
    const u = document.querySelector(`[data-bid="${bid}"]`);
    const lifted = document.querySelector('.mn-lifted');
    const cs = lifted ? getComputedStyle(lifted) : null;
    const sib = [...document.querySelectorAll('.mn-shift')].map((s) => ({ bid: s.getAttribute('data-bid'), tf: getComputedStyle(s).transform }));
    return { liftedFound: !!lifted, sameEl: lifted === u, transform: cs ? cs.transform : null, shifts: sib.slice(0, 4) };
  }, pt.bid);
  await page.mouse.move(pt.x, pt.y + 110, { steps: 8 });
  await page.waitForTimeout(250);
  drag.follow = await page.evaluate((bid) => {
    const u = document.querySelector(`[data-bid="${bid}"]`);
    const r = u.getBoundingClientRect();
    return { cx: r.x + r.width / 2, cy: r.y + r.height / 2 };
  }, pt.bid);
  drag.followExpect = { cx: pt.x, cy: pt.y + 110 };
  await page.screenshot({ path: '/tmp/wide_drag_1440.png' });
  await page.mouse.up();
  await page.waitForTimeout(800);
  drag.afterDrop = await page.evaluate(() => ({ lifted: !!document.querySelector('.mn-lifted'), shifts: document.querySelectorAll('.mn-shift').length }));
  R.drag1440 = drag;
  await ctx.close();
} catch (e) { R.drag1440 = 'ERR ' + String(e).slice(0, 200); }

fs.writeFileSync('/tmp/wide_results.json', JSON.stringify(R, null, 1));
L('\nDONE failsafe');
await browser.close();
