// 链接→音乐卡生命周期量测 v2：拦截 /meta 延迟放行，确定性
// 量测「骨架出现期」与「完成时」的光标/样式。Rust 与原版同法。
// 用法: node probe_linkmusic_chain2.mjs <baseUrl> <rust|orig>
import { chromium } from 'playwright-core';

const base = process.argv[2];
const flavor = process.argv[3] || 'rust';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const MUSIC_URL = 'https://music.163.com/song?id=347230';
const META = { title: '海阔天空', subtitle: 'Beyond', source: '网易云音乐', cover: '', type: 'music' };

async function armMetaDelay(page, ms) {
  await page.route('**/meta?url=*', async (route) => {
    await new Promise((r) => setTimeout(r, ms));
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      headers: { 'Access-Control-Allow-Origin': '*' },
      body: JSON.stringify(META),
    }).catch(() => {});
  });
}

const caretInfo = () => {
  const s = getSelection();
  const ae = document.activeElement;
  const anc = s && s.rangeCount ? s.anchorNode : null;
  const ancEl = anc ? (anc.nodeType === 1 ? anc : anc.parentElement) : null;
  const bidEl = ancEl && ancEl.closest ? ancEl.closest('[data-bid],[data-blockid]') : null;
  return {
    rangeCount: s ? s.rangeCount : -1,
    active: ae ? ae.tagName + (ae.dataset && (ae.dataset.bid || ae.dataset.blockid) ? '#' + (ae.dataset.bid || ae.dataset.blockid) : '') : 'none',
    anchorBlock: bidEl ? (bidEl.dataset.bid || bidEl.dataset.blockid) : null,
    anchorOff: s && s.rangeCount ? s.anchorOffset : null,
    anchorText: bidEl ? (bidEl.textContent || '').slice(0, 20) : null,
  };
};

const skeletonInfo = () => {
  const sk = document.querySelector('.link-card-skeleton');
  if (!sk) return { exists: false };
  const cs = getComputedStyle(sk);
  const r = sk.getBoundingClientRect();
  const cover = sk.querySelector('.link-card-skeleton-cover');
  const cr = cover ? cover.getBoundingClientRect() : null;
  const ca = cover ? getComputedStyle(cover, '::after') : null;
  const anims = document.getAnimations ? document.getAnimations().filter((a) => a.animationName === 'mynoteSkeletonSpin').map((a) => a.playState) : [];
  const body = sk.querySelector('.link-card-skeleton-body');
  return {
    exists: true, bg: cs.backgroundColor, borderW: cs.borderTopWidth, borderStyle: cs.borderTopStyle,
    w: Math.round(r.width), h: Math.round(r.height), breakInside: cs.breakInside,
    coverH: cr ? Math.round(cr.height) : null, bodyDisplay: body ? getComputedStyle(body).display : null,
    spinName: ca ? ca.animationName : null, anims,
    parentCls: sk.parentElement ? String(sk.parentElement.className) : '',
    col: sk.closest('.editor-column')?.dataset?.editorColumn || null,
  };
};

async function pasteOn(page, selector, text) {
  return page.evaluate(({ sel, t }) => {
    const el = document.querySelector(sel);
    if (!el) return 'no-el';
    const dt = new DataTransfer();
    dt.setData('text/plain', t);
    el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
    return 'dispatched';
  }, { sel: selector, t: text });
}

async function openMemo(page) {
  await page.goto(base, { waitUntil: 'load' });
  if (flavor === 'rust') {
    await page.waitForSelector('.list-item', { timeout: 20000 });
    await page.click('.list-item:has-text("周末看展记录") .item-title-text');
    await page.waitForSelector('.detail .ed-line', { timeout: 10000 });
  } else {
    await page.waitForSelector('.list-item, .memo-card, [class*=memo]', { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(1500);
    const clicked = await page.evaluate(() => {
      const els = [...document.querySelectorAll('*')].filter((e) => e.children.length === 0 || e.classList.contains('item-title-text'));
      const t = [...document.querySelectorAll('.item-title-text, .memo-title, h3, .title')].find((e) => e.textContent.includes('周末看展记录'));
      if (t) { t.click(); return true; }
      return false;
    });
    console.log('orig open memo clicked:', clicked);
    await page.waitForSelector('.editor-body', { timeout: 10000 });
  }
  await page.waitForTimeout(900);
}

async function flowA(page) {
  // 斜杠 → 音乐卡 → 胶囊 → 粘贴
  if (flavor === 'rust') {
    const n = await page.$$eval('.detail .ed-line', (els) => els.length);
    await page.click(`.detail .ed-line >> nth=${n - 1}`);
    await page.keyboard.press('End');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(400);
    await page.keyboard.type('/');
    await page.waitForSelector('#slash-panel', { timeout: 6000 });
    await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="musicCard"]')?.click());
  } else {
    await page.evaluate(() => {
      const body = document.querySelector('.editor-body');
      const last = body.lastElementChild;
      const r = document.createRange();
      r.selectNodeContents(last); r.collapse(false);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
      last.focus && last.focus();
    });
    await page.keyboard.press('End');
    await page.keyboard.press('Enter');
    await page.keyboard.type('/');
    await page.waitForTimeout(1200);
    await page.evaluate(() => document.querySelector('[data-slash-id="musicCard"]')?.click());
  }
  await page.waitForTimeout(900);
  const pillSel = flavor === 'rust' ? '.music-input-pill' : '[data-music-url="pending"]';
  const pill = await page.evaluate((sel) => {
    const p = document.querySelector(sel);
    if (!p) return { exists: false };
    return { exists: true, editable: p.isContentEditable, text: (p.textContent || '').slice(0, 30) };
  }, pillSel);
  console.log('A PILL:', JSON.stringify(pill));
  console.log('A CARET at pill:', JSON.stringify(await page.evaluate(caretInfo)));
  if (!pill.exists) return;
  await page.click(pillSel).catch(() => {});
  await page.waitForTimeout(300);
  console.log('A paste ->', await pasteOn(page, pillSel, MUSIC_URL));
  await page.waitForTimeout(1500); // 骨架期（meta 被延迟 5s）
  const mid = await page.evaluate(() => ({
    pill: !!document.querySelector('.music-input-pill,[data-music-url="pending"]'),
  }));
  console.log('A MID pillGone:', JSON.stringify(mid), 'SKELETON:', JSON.stringify(await page.evaluate(skeletonInfo)));
  console.log('A CARET during load:', JSON.stringify(await page.evaluate(caretInfo)));
  await page.waitForFunction(() => !document.querySelector('.link-card-skeleton'), { timeout: 20000 }).catch(() => console.log('A skeleton never left'));
  await page.waitForTimeout(700);
  const fin = await page.evaluate(() => ({
    pill: !!document.querySelector('.music-input-pill,[data-music-url="pending"]'),
    card: !!document.querySelector('.music-card-link'),
    err: !!document.querySelector('.music-card-error'),
  }));
  console.log('A FINAL:', JSON.stringify(fin));
  console.log('A CARET after load:', JSON.stringify(await page.evaluate(caretInfo)));
}

async function flowB(page, mode) {
  if (flavor === 'rust') {
    const n = await page.$$eval('.detail .ed-line', (els) => els.length);
    await page.click(`.detail .ed-line >> nth=${n - 1}`);
    await page.keyboard.press('End');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(400);
    const bid = await page.evaluate(() => document.activeElement?.dataset?.bid);
    console.log(`B[${mode}] paste ->`, await pasteOn(page, `[data-bid="${bid}"]`, MUSIC_URL));
  } else {
    await page.evaluate(() => {
      const body = document.querySelector('.editor-body');
      const last = body.lastElementChild;
      const r = document.createRange();
      r.selectNodeContents(last); r.collapse(false);
      const s = getSelection(); s.removeAllRanges(); s.addRange(r);
    });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(300);
    const sel = '.editor-body > p:last-child';
    console.log('B paste ->', await pasteOn(page, sel, MUSIC_URL));
  }
  await page.waitForTimeout(1500);
  console.log(`B[${mode}] SKELETON:`, JSON.stringify(await page.evaluate(skeletonInfo)));
  console.log(`B[${mode}] CARET during load:`, JSON.stringify(await page.evaluate(caretInfo)));
  await page.waitForFunction(() => !document.querySelector('.link-card-skeleton'), { timeout: 20000 }).catch(() => console.log('B skeleton never left'));
  await page.waitForTimeout(700);
  console.log(`B[${mode}] CARET after load:`, JSON.stringify(await page.evaluate(caretInfo)));
}

// ---- 主流程 ----
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
  await armMetaDelay(page, 5000);
  await openMemo(page);
  await flowA(page);
  await ctx.close();
}
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
  await armMetaDelay(page, 5000);
  await openMemo(page);
  await flowB(page, 'single');
  await ctx.close();
}
if (flavor === 'rust') {
  for (const mode of ['spread', 'independent']) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
    await armMetaDelay(page, 5000);
    await openMemo(page);
    if (mode === 'independent') {
      await page.click('.editor-fab.right');
      await page.waitForSelector('.editor-menu-panel', { timeout: 10000 });
      await page.click('.editor-column-mode-toggle');
      await page.waitForSelector('.editor-body.is-independent-scroll', { timeout: 8000 });
      await page.click('.menu-scrim').catch(() => {});
      await page.waitForTimeout(500);
    }
    await flowB(page, mode);
    await ctx.close();
  }
}
await browser.close();
console.log('DONE');
