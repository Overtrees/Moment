// Scratch probe: ORIGINAL app baseline — long title scroll shrink + empty body scrollability
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const BASE = 'http://localhost:8101/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function seedAndOpen(zipPath, titlePart) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 160)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(2500);
  const b64 = fs.readFileSync(zipPath).toString('base64');
  const res = await page.evaluate(async (b64) => {
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
  console.log('restore:', res.slice(0, 120));
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2500);
  // open memo by title text (list may need group expand: click twice)
  for (let i = 0; i < 3; i++) {
    const clicked = await page.evaluate((t) => {
      const el = [...document.querySelectorAll('*')].find(e => e.children.length === 0 && e.textContent && e.textContent.includes(t));
      if (el) { el.click(); return true; }
      return false;
    }, titlePart);
    await page.waitForTimeout(1200);
    const inEditor = await page.evaluate(() => !!document.querySelector('.editor-title-dock'));
    if (inEditor) break;
    if (!clicked) break;
  }
  await page.waitForTimeout(800);
  return { ctx, page };
}

function helpers(page, ctx) {
  async function state(label) {
    const s = await page.evaluate(() => {
      const dock = document.querySelector('.editor-title-dock');
      const av = document.querySelector('.editor-avatar-button');
      const cap = dock ? [...dock.children].find(c => !c.classList.contains('editor-avatar-button')) : null;
      const meta = document.querySelector('.editor-title-meta');
      const inp = document.querySelector('.editor-title-input');
      const r = (el) => { if (!el) return null; const b = el.getBoundingClientRect(); return { x: +b.x.toFixed(1), y: +b.y.toFixed(1), w: +b.width.toFixed(1), h: +b.height.toFixed(1), cy: +(b.y + b.height / 2).toFixed(1) }; };
      const se = document.scrollingElement;
      return {
        dir: dock ? getComputedStyle(dock).flexDirection : null,
        avatar: r(av), capsule: r(cap),
        metaPresent: !!meta,
        titleFs: inp ? getComputedStyle(inp).fontSize : null,
        titleText: inp ? inp.textContent : null,
        scrollY: window.scrollY, scrollable: se ? se.scrollHeight - window.innerHeight : null,
      };
    });
    const row = s.avatar && s.capsule ? Math.abs(s.avatar.cy - s.capsule.cy) < 4 : null;
    console.log(`[ORIG ${label}] dir=${s.dir} y=${s.scrollY} canScroll=${s.scrollable} row=${row} capW=${s.capsule?.w} capY=${s.capsule?.y} avY=${s.avatar?.y} meta=${s.metaPresent} fs=${s.titleFs} title="${s.titleText}"`);
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
  return { state, touchScroll };
}

// Original: long body + long title (t27)
{
  const { ctx, page } = await seedAndOpen('/tmp/hdrprobe/b1.zip', '好咯后公民明明明明模拟');
  const H = helpers(page, ctx);
  await H.state('t27 top');
  await H.touchScroll(400);
  await H.state('t27 scrolled');
  await ctx.close();
}
// Original: long body + short title (t03)
{
  const { ctx, page } = await seedAndOpen('/tmp/hdrprobe/b1.zip', '短题三');
  const H = helpers(page, ctx);
  await H.state('t03 top');
  await H.touchScroll(400);
  await H.state('t03 scrolled');
  await ctx.close();
}
// Original: empty body + long title (e27)
{
  const { ctx, page } = await seedAndOpen('/tmp/hdrprobe/b3.zip', '空体好咯后公民');
  const H = helpers(page, ctx);
  await H.state('e27 top');
  await H.touchScroll(400);
  await H.state('e27 touchScrolled');
  await ctx.close();
}
await browser.close();
console.log('DONE');
