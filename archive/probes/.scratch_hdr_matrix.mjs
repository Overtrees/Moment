// Scratch probe v2: batched contexts. Title length x body x scroll — header shrink matrix (Rust prod dist 82da190a4f)
import { chromium } from 'playwright-core';

const url = 'http://localhost:8246/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function newPageWith(zip) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  return { ctx, page };
}

function helpers(page, ctx) {
  async function openMemo(titlePart) {
    await page.waitForFunction((t) => [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .some((e) => e.textContent.includes(t)), titlePart, { timeout: 10000 });
    for (let attempt = 0; attempt < 3; attempt++) {
      await page.evaluate((t) => {
        const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
          .find((e) => e.textContent.includes(t));
        if (el) el.click();
      }, titlePart);
      try { await page.waitForSelector('.detail', { timeout: 3000 }); break; } catch (e) { /* folded group expand, retry */ }
    }
    await page.waitForSelector('.detail', { timeout: 8000 });
    await page.waitForTimeout(600);
  }
  async function headState(label) {
    const s = await page.evaluate(() => {
      const dock = document.querySelector('.editor-title-dock');
      const av = document.querySelector('.editor-avatar-button');
      const cap = document.querySelector('.editor-title-capsule');
      const meta = document.querySelector('.editor-title-meta');
      const inp = document.querySelector('.editor-title-input');
      const r = (el) => { if (!el) return null; const b = el.getBoundingClientRect(); return { x: +b.x.toFixed(1), y: +b.y.toFixed(1), w: +b.width.toFixed(1), h: +b.height.toFixed(1), cy: +(b.y + b.height / 2).toFixed(1) }; };
      const se = document.scrollingElement;
      return {
        dockClass: dock ? dock.className : null,
        avatar: r(av), capsule: r(cap),
        metaDisplay: meta ? getComputedStyle(meta).display : null,
        inputVal: inp ? inp.value : null,
        scrollY: window.scrollY,
        scrollable: se ? se.scrollHeight - window.innerHeight : null,
        activeId: document.activeElement ? (document.activeElement.id || document.activeElement.className) : null,
      };
    });
    const row = s.avatar && s.capsule ? Math.abs(s.avatar.cy - s.capsule.cy) < 4 : null;
    console.log(`[${label}] cls="${s.dockClass}" y=${s.scrollY} canScroll=${s.scrollable} row=${row} meta=${s.metaDisplay} capW=${s.capsule?.w} capY=${s.capsule?.y} avY=${s.avatar?.y} active=${s.activeId} val="${s.inputVal}"`);
    return s;
  }
  async function touchScroll(dy) {
    const cdp = await ctx.newCDPSession(page);
    const x = 196, y0 = 620, y1 = 620 - dy;
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: y0, id: 1 }] });
    for (let i = 1; i <= 10; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 + (y1 - y0) * i / 10, id: 1 }] });
      await page.waitForTimeout(16);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForTimeout(500);
    await cdp.detach();
  }
  async function backToList() {
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.click('.editor-fab.left');
    await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
    await page.waitForTimeout(400);
  }
  return { openMemo, headState, touchScroll, backToList };
}

// ---------- Batch 1: t03 / t11 / t27 long body + C + D on t27 ----------
{
  const { ctx, page } = await newPageWith('/tmp/hdrprobe/b1.zip');
  const H = helpers(page, ctx);
  for (const [part, label] of [['短题三', 'A t03'], ['十一个字的标题正好踩线', 'A t11'], ['好咯后公民明明明明模拟继续', 'A t27']]) {
    await H.openMemo(part);
    await H.headState(label + ' top');
    await H.touchScroll(400);
    await H.headState(label + ' touchScrolled');
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(400);
    await H.headState(label + ' backTop');
    await H.backToList();
  }
  // C: edit title then scroll
  await H.openMemo('好咯后公民明明明明模拟继续');
  await page.click('.editor-title-capsule');
  await page.waitForTimeout(500);
  await H.headState('C after title tap');
  await page.keyboard.type('加字');
  await page.waitForTimeout(300);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(600);
  await H.headState('C after Enter');
  await H.touchScroll(400);
  await H.headState('C scrolled after edit');
  await H.backToList();
  // D: resync gap — compact, tap title, scrollTo top in session, end session via body tap, no more scroll
  await H.openMemo('好咯后公民明明明明模拟继续');
  await H.touchScroll(400);
  await H.headState('D compact pre-edit');
  await page.click('.editor-title-capsule');
  await page.waitForTimeout(500);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(400);
  await H.headState('D to-top in session');
  await page.evaluate(() => { const el = document.querySelector('.editor-body [data-bid]'); if (el) el.click(); });
  await page.waitForTimeout(700);
  await H.headState('D after body tap (session end?)');
  await page.evaluate(() => window.scrollTo(0, 500));
  await page.waitForTimeout(400);
  await H.headState('D scrollTo500 after');
  await H.backToList();
  await ctx.close();
}

// ---------- Batch 2: t08 / t09 / t23 long body ----------
{
  const { ctx, page } = await newPageWith('/tmp/hdrprobe/b2.zip');
  const H = helpers(page, ctx);
  for (const [part, label] of [['八个字的标题在此', 'A t08'], ['十个字的标题正好十', 'A t09'], ['二十字长标题', 'A t23']]) {
    await H.openMemo(part);
    await H.headState(label + ' top');
    await H.touchScroll(400);
    await H.headState(label + ' touchScrolled');
    await H.backToList();
  }
  await ctx.close();
}

// ---------- Batch 3: empty body e03 / e11 / e27 ----------
{
  const { ctx, page } = await newPageWith('/tmp/hdrprobe/b3.zip');
  const H = helpers(page, ctx);
  for (const [part, label] of [['空短三', 'B e03'], ['空体十一字标题踩线一二', 'B e11'], ['空体好咯后公民', 'B e27']]) {
    await H.openMemo(part);
    await H.headState(label + ' top');
    await H.touchScroll(400);
    await H.headState(label + ' touchScrolled');
    await page.evaluate(() => { window.scrollTo(0, 9999); });
    await page.waitForTimeout(400);
    await H.headState(label + ' scrollToBottom');
    await H.backToList();
  }
  await ctx.close();
}

await browser.close();
console.log('DONE');
