// 编辑页外壳审计探针（原版 8101）：与 Rust 探针同口径度量。
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const BASE = 'http://localhost:8101/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR ::', String(e).slice(0, 200)));
const R = (name, val) => console.log(name + ' :: ' + (typeof val === 'string' ? val : JSON.stringify(val)));

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForTimeout(2500);
// API 播种 real_backup
const b64 = fs.readFileSync(process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip').toString('base64');
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
R('ORIG_RESTORE', restoreRes);
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2500);
await page.click('text=冬日');
await page.waitForTimeout(1800);

R('FABS_DOCK', await page.evaluate(() => {
  const g = (el) => { if (!el) return null; const r = el.getBoundingClientRect(); return { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) }; };
  const dock = document.querySelector('.editor-title-dock');
  const capsule = dock ? [...dock.children].find((c) => !c.classList.contains('editor-avatar-button')) : null;
  const titleEl = document.querySelector('.editor-title-input');
  const meta = document.querySelector('.editor-title-meta');
  return {
    fabL: g(document.querySelector('.editor-fab.left')), fabR: g(document.querySelector('.editor-fab.right')),
    dock: g(dock), avatar: g(document.querySelector('.editor-avatar-button')), capsule: g(capsule),
    titleText: titleEl ? titleEl.textContent : null,
    titleFs: titleEl ? getComputedStyle(titleEl).fontSize : null,
    meta: meta ? meta.textContent : null,
    avatarHasImg: !!document.querySelector('.editor-avatar-button img'),
  };
}));

// 菜单
await page.click('.editor-fab.right');
await page.waitForTimeout(900);
R('MENU', await page.evaluate(() => {
  const p = document.querySelector('.editor-menu-panel');
  if (!p) return { open: false };
  const r = p.getBoundingClientRect();
  const btns = [...p.querySelectorAll('button')].map((b) => ({
    text: b.innerText.replace(/\n/g, '|'), op: getComputedStyle(b).opacity,
    cls: b.className, checked: b.getAttribute('aria-checked'),
  }));
  return { open: true, w: Math.round(r.width), x: Math.round(r.x), y: Math.round(r.y), btns };
}));
// 导出面板
await page.click('.editor-export-entry');
await page.waitForTimeout(900);
R('EXPORT_PANEL', await page.evaluate(() => {
  const p = document.querySelector('.editor-export-panel');
  if (!p) return { open: false };
  const r = p.getBoundingClientRect();
  const back = p.querySelector('.editor-export-back');
  const br = back ? back.getBoundingClientRect() : null;
  return {
    open: true, w: Math.round(r.width),
    text: p.innerText.replace(/\n/g, '|'),
    backSize: br ? Math.round(br.width) + 'x' + Math.round(br.height) : null,
    formats: [...p.querySelectorAll('[data-export-format]')].map((c) => c.getAttribute('data-export-format')),
  };
}));
await page.click('.editor-export-back');
await page.waitForTimeout(900);
R('EXPORT_BACK_TO_MENU', await page.evaluate(() => !!document.querySelector('.editor-menu-panel')));
// 背景表
await page.evaluate(() => {
  const b = [...document.querySelectorAll('.editor-menu-panel button')].find((x) => x.innerText.includes('更换背景色'));
  if (b) b.click();
});
await page.waitForTimeout(900);
R('BGSHEET', await page.evaluate(() => {
  const btns = [...document.querySelectorAll('button[aria-label]')].filter((b) => ['冷雾', '暖沙', '浅绿', '浅蓝', '浅粉', '米橙', '淡紫', '浅杏'].includes(b.getAttribute('aria-label')));
  const f = btns[0]?.getBoundingClientRect(); const s = btns[1]?.getBoundingClientRect(); const fifth = btns[4]?.getBoundingClientRect();
  return {
    n: btns.length,
    labels: btns.map((b) => b.getAttribute('aria-label')),
    dotSize: f ? Math.round(f.width) + 'x' + Math.round(f.height) : null,
    rowGapX: f && s ? Math.round(s.x - f.x) : null,
    secondRowDy: f && fifth ? Math.round(fifth.y - f.y) : null,
    colors: btns.map((b) => getComputedStyle(b).backgroundColor),
    bodyText: document.body.innerText.includes('为当前笔记设置底色'),
    removeVisible: document.body.innerText.includes('移除背景'),
  };
}));
// 选暖沙
await page.evaluate(() => {
  const b = [...document.querySelectorAll('button[aria-label]')].find((x) => x.getAttribute('aria-label') === '暖沙');
  if (b) b.click();
});
await page.waitForTimeout(1000);
R('BG_AFTER_SELECT', await page.evaluate(() => {
  // 编辑根容器背景：editor-spread 的祖先链上找 inline backgroundColor
  let el = document.querySelector('.editor-spread');
  const chain = [];
  while (el && chain.length < 5) { chain.push({ cls: String(el.className).slice(0, 30), bg: el.style.backgroundColor || getComputedStyle(el).backgroundColor }); el = el.parentElement; }
  return { sheetGone: ![...document.querySelectorAll('button[aria-label]')].some((b) => b.getAttribute('aria-label') === '暖沙'), chain };
}));
// 长标题截断：改标题为 12 字
await page.evaluate(() => { document.querySelector('.editor-title-input')?.focus(); document.execCommand('selectAll', false, null); });
await page.keyboard.type('一二三四五六七八九十甲乙');
await page.waitForTimeout(300);
await page.evaluate(() => document.querySelector('.editor-title-input')?.blur());
await page.waitForTimeout(500);
R('LONG_TITLE', await page.evaluate(() => {
  const t = document.querySelector('.editor-title-input');
  return { text: t ? t.textContent : null, fs: t ? getComputedStyle(t).fontSize : null };
}));
// 恢复短标题
await page.evaluate(() => { const t = document.querySelector('.editor-title-input'); t?.focus(); document.execCommand('selectAll', false, null); });
await page.keyboard.type('冬日');
await page.evaluate(() => document.querySelector('.editor-title-input')?.blur());
await page.waitForTimeout(400);
// 滚动态：meta 消失 + 横排
await page.evaluate(() => window.scrollTo(0, 400));
await page.waitForTimeout(700);
R('SCROLLED', await page.evaluate(() => {
  const dock = document.querySelector('.editor-title-dock');
  const meta = document.querySelector('.editor-title-meta');
  return {
    scrollY: window.scrollY,
    dockDir: dock ? getComputedStyle(dock).flexDirection : null,
    metaPresent: !!meta, metaText: meta ? meta.textContent : null,
  };
}));
await browser.close();
console.log('DONE');
