// 链接→音乐卡生命周期量测探针（Chromium 口径）
// 用法: node probe_linkmusic_chain.mjs <baseUrl> [orig]
// 阶段：斜杠音乐胶囊形态/可编辑性/粘贴响应 → 段落粘贴 URL 的
// 骨架样式与动画 → 加载期间/完成后的光标落点。三模式各跑一遍
// 骨架量测（单栏 / 默认双栏 / 独立双栏）。
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8197/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const MUSIC_URL = 'https://music.163.com/song?id=347230';
const LINK_URL = 'https://example.com/some/article';

const caretInfo = () => {
  const s = getSelection();
  const ae = document.activeElement;
  const anc = s && s.rangeCount ? s.anchorNode : null;
  const ancEl = anc ? (anc.nodeType === 1 ? anc : anc.parentElement) : null;
  const bidEl = ancEl && ancEl.closest ? ancEl.closest('[data-bid]') : null;
  return {
    rangeCount: s ? s.rangeCount : -1,
    active: ae ? (ae.tagName + '.' + (ae.className && ae.className.baseVal !== undefined ? '' : String(ae.className).slice(0, 40)) + (ae.dataset && ae.dataset.bid ? '#' + ae.dataset.bid : '')) : 'none',
    anchorBid: bidEl ? bidEl.dataset.bid : null,
    anchorOff: s && s.rangeCount ? s.anchorOffset : null,
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
  const anims = document.getAnimations ? document.getAnimations().filter(a => a.animationName === 'mynoteSkeletonSpin').map(a => a.playState) : [];
  return {
    exists: true,
    bg: cs.backgroundColor, borderW: cs.borderTopWidth, borderStyle: cs.borderTopStyle,
    radius: cs.borderTopLeftRadius, w: Math.round(r.width), h: Math.round(r.height),
    breakInside: cs.breakInside, colSpan: cs.columnSpan,
    coverH: cr ? Math.round(cr.height) : null,
    spinName: ca ? ca.animationName : null, spinState: ca ? ca.animationPlayState : null,
    anims,
    parentCls: sk.parentElement ? sk.parentElement.className : '',
    inColumn: !!sk.closest('.editor-column'),
    colOf: sk.closest('.editor-column')?.dataset?.editorColumn || null,
  };
};

async function openMemo(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.click('.list-item:has-text("周末看展记录") .item-title-text');
  await page.waitForSelector('.detail .ed-line', { timeout: 10000 });
  await page.waitForTimeout(800);
}

async function pasteOn(page, selector, text) {
  return page.evaluate(({ sel, t }) => {
    const el = document.querySelector(sel);
    if (!el) return 'no-el';
    const dt = new DataTransfer();
    dt.setData('text/plain', t);
    const ev = new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true });
    el.dispatchEvent(ev);
    return 'dispatched';
  }, { sel: selector, t: text });
}

async function newParaAtEnd(page) {
  const n = await page.$$eval('.detail .ed-line', (els) => els.length);
  await page.click(`.detail .ed-line >> nth=${n - 1}`);
  await page.keyboard.press('End');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(400);
}

// ---------- 阶段 1：单栏，斜杠音乐胶囊 ----------
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
  await openMemo(page);
  await newParaAtEnd(page);
  await page.keyboard.type('/');
  await page.waitForSelector('#slash-panel', { timeout: 6000 }).catch(() => console.log('NO SLASH PANEL'));
  await page.evaluate(() => document.querySelector('#slash-panel .slash-row[data-act="musicCard"]')?.click());
  await page.waitForTimeout(900);
  const pill = await page.evaluate(() => {
    const p = document.querySelector('.music-input-pill');
    if (!p) return { exists: false, bodyHas: document.body.innerText.includes('粘贴音乐链接') };
    const cs = getComputedStyle(p);
    return {
      exists: true, editable: p.isContentEditable, ceAttr: p.getAttribute('contenteditable'),
      text: p.textContent, radius: cs.borderTopLeftRadius,
      w: Math.round(p.getBoundingClientRect().width), h: Math.round(p.getBoundingClientRect().height),
    };
  });
  console.log('PILL:', JSON.stringify(pill));
  console.log('CARET after slash-music:', JSON.stringify(await page.evaluate(caretInfo)));
  // 点胶囊后粘贴音乐 URL 到胶囊
  if (pill.exists) {
    await page.click('.music-input-pill');
    await page.waitForTimeout(400);
    console.log('paste on pill ->', await pasteOn(page, '.music-input-pill', MUSIC_URL));
    await page.waitForTimeout(1200);
    const after = await page.evaluate(() => ({
      pill: !!document.querySelector('.music-input-pill'),
      skeleton: !!document.querySelector('.link-card-skeleton'),
      cardLink: !!document.querySelector('.music-card-link'),
      promptBtn: !!document.querySelector('.blk-wrap.sel'),
    }));
    console.log('AFTER PILL PASTE:', JSON.stringify(after));
  }
  await ctx.close();
}

// ---------- 阶段 2：单栏，段落粘贴 URL → 骨架/光标 ----------
async function pasteFlow(mode) {
  const wide = mode !== 'single';
  const ctx = await browser.newContext({ viewport: wide ? { width: 1280, height: 800 } : { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
  await openMemo(page);
  if (mode === 'independent') {
    await page.click('.editor-fab.right');
    await page.waitForSelector('.editor-menu-panel', { timeout: 10000 });
    await page.click('.menu-item.twopane-row');
    await page.waitForSelector('.editor-body.is-independent-scroll', { timeout: 8000 });
    await page.click('.menu-scrim').catch(() => {});
    await page.waitForSelector('.editor-menu-panel', { state: 'detached', timeout: 6000 }).catch(() => {});
    await page.waitForTimeout(600);
  }
  await newParaAtEnd(page);
  const bid = await page.evaluate(() => document.activeElement?.dataset?.bid || null);
  console.log(`[${mode}] focused bid before paste:`, bid);
  console.log(`[${mode}] paste ->`, await pasteOn(page, '.detail .ed-line:last-of-type', MUSIC_URL).catch((e) => String(e)));
  // 粘贴目标修正：桥按事件 target 的最近 [data-bid] 定位，取当前聚焦块
  await page.waitForTimeout(700);
  let sk = await page.evaluate(skeletonInfo);
  if (!sk.exists && bid) {
    console.log(`[${mode}] retry paste on focused bid`);
    await pasteOn(page, `[data-bid="${bid}"]`, MUSIC_URL);
    await page.waitForTimeout(700);
    sk = await page.evaluate(skeletonInfo);
  }
  console.log(`[${mode}] SKELETON:`, JSON.stringify(sk));
  console.log(`[${mode}] CARET during load:`, JSON.stringify(await page.evaluate(caretInfo)));
  // 等解析完成（骨架消失或出现成品/错误卡）
  const done = await page.waitForFunction(() => !document.querySelector('.link-card-skeleton'), { timeout: 20000 }).then(() => true).catch(() => false);
  await page.waitForTimeout(600);
  const fin = await page.evaluate(() => ({
    cardLink: !!document.querySelector('.music-card-link'),
    cardErr: !!document.querySelector('.music-card-error'),
    pill: !!document.querySelector('.music-input-pill'),
  }));
  console.log(`[${mode}] RESOLVED skeletonGone=${done}`, JSON.stringify(fin));
  console.log(`[${mode}] CARET after resolve:`, JSON.stringify(await page.evaluate(caretInfo)));
  const diag = await page.evaluate(() => {
    try {
      const raw = localStorage.getItem('mynote_diag_v1') || '';
      return raw.split('\n').filter((l) => /CARD|pasteCard|music/.test(l)).slice(-8);
    } catch (e) { return ['diag-read-fail']; }
  });
  console.log(`[${mode}] DIAG:`, JSON.stringify(diag));
  await ctx.close();
}

await pasteFlow('single');
await pasteFlow('spread');
await pasteFlow('independent');

await browser.close();
console.log('DONE');
