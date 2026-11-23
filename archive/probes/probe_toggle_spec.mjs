// 集成量测：编辑菜单双栏开关行按原版专属结构
// (.editor-column-mode-toggle + .editor-column-toggle-track/-knob)
// 实例化后，与原版同控件逐值对照（轨道/钮/行程/开态色/文案/图标
// 槽/可见性门槛），并验开关往返行为（独立滚动形态切换不坏）。
// 用法：node probe_toggle_spec.mjs [rustBase] [origBase]
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8201/';
const origBase = process.argv[3] || 'http://localhost:8097/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let fails = 0;
const ok = (name, cond, extra = '') => { console.log((cond ? '✓ ' : '✗ ') + name + (extra ? ' — ' + extra : '')); if (!cond) fails++; };
const near = (a, b, tol = 0.6) => Math.abs(a - b) <= tol;

const MEASURE = () => {
  const row = document.querySelector('.editor-column-mode-toggle');
  if (!row) return null;
  const track = row.querySelector('.editor-column-toggle-track');
  const knob = row.querySelector('.editor-column-toggle-knob');
  const icon = row.querySelector('.editor-column-mode-icon');
  const iconSvg = icon ? icon.querySelector('svg') : null;
  const title = row.querySelector('.editor-column-mode-title');
  const sub = row.querySelector('.editor-column-mode-subtitle');
  const cs = (e) => (e ? getComputedStyle(e) : null);
  const rect = (e) => (e ? e.getBoundingClientRect() : null);
  return {
    display: cs(row).display,
    role: row.getAttribute('role'),
    ariaChecked: row.getAttribute('aria-checked'),
    ariaLabel: row.getAttribute('aria-label'),
    minHeight: cs(row).minHeight,
    trackChecked: track ? track.getAttribute('aria-checked') : null,
    track: track ? { w: rect(track).width, h: rect(track).height, bg: cs(track).backgroundColor, radius: cs(track).borderRadius } : null,
    knob: knob ? { w: rect(knob).width, h: rect(knob).height, x: rect(knob).x, bg: cs(knob).backgroundColor } : null,
    icon: icon ? { w: rect(icon).width, h: rect(icon).height, color: cs(icon).color } : null,
    iconSvg: iconSvg ? { w: iconSvg.getAttribute('width'), sw: iconSvg.querySelector('path') ? iconSvg.querySelector('path').getAttribute('stroke-width') : null } : null,
    title: title ? { text: title.textContent, fs: cs(title).fontSize, fw: cs(title).fontWeight } : null,
    sub: sub ? { text: sub.textContent, fs: cs(sub).fontSize } : null,
  };
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

// ---------- Rust ----------
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR:', String(e).slice(0, 200)));
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.evaluate(() => {
  const t = Array.from(document.querySelectorAll('.img-card-title-text, .item-title-text')).find((e) => e.textContent.includes('周末看展记录'));
  if (t) t.click(); else document.querySelector('.list-item')?.click();
});
await page.waitForSelector('.editor-body', { timeout: 15000 });
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-column-mode-toggle', { timeout: 8000 });
await page.waitForTimeout(400);
const r0 = await page.evaluate(MEASURE);
console.log('RUST off:', JSON.stringify(r0));
ok('rust row visible at 1280x800', r0 && r0.display === 'flex');
ok('rust role=switch + aria-checked=false', r0.role === 'switch' && r0.ariaChecked === 'false');
ok('rust track aria-checked=false', r0.trackChecked === 'false');
ok('rust track 42x26', near(r0.track.w, 42) && near(r0.track.h, 26), `${r0.track.w}x${r0.track.h}`);
ok('rust track off bg #d1d1d6', r0.track.bg === 'rgb(209, 209, 214)', r0.track.bg);
ok('rust knob 20x20', near(r0.knob.w, 20) && near(r0.knob.h, 20), `${r0.knob.w}x${r0.knob.h}`);
ok('rust row min-height 56', r0.minHeight === '56px', r0.minHeight);
ok('rust icon slot 24x24 + svg 20 sw1.8', near(r0.icon.w, 24) && near(r0.icon.h, 24) && r0.iconSvg.w === '20' && r0.iconSvg.sw === '1.8', JSON.stringify(r0.iconSvg));
ok('rust title/sub text', r0.title.text === '双栏独立滚动' && r0.sub.text === '平板与 PC 可分别滚动两栏', `${r0.title.text} / ${r0.sub.text}`);
ok('rust title 14px/650, sub 11px', r0.title.fs === '14px' && r0.title.fw === '650' && r0.sub.fs === '11px', `${r0.title.fs}/${r0.title.fw}/${r0.sub.fs}`);

await page.click('.editor-column-mode-toggle');
await page.waitForTimeout(450);
const r1 = await page.evaluate(MEASURE);
const indep = await page.evaluate(() => !!document.querySelector('.editor-body.is-independent-scroll'));
console.log('RUST on:', JSON.stringify(r1), 'independent-scroll:', indep);
ok('rust on: aria-checked=true (row+track)', r1.ariaChecked === 'true' && r1.trackChecked === 'true');
ok('rust on: track bg accent #007aff', r1.track.bg === 'rgb(0, 122, 255)', r1.track.bg);
ok('rust on: knob travel 16px', near(r1.knob.x - r0.knob.x, 16, 1), `dx=${(r1.knob.x - r0.knob.x).toFixed(2)}`);
ok('rust on: body enters independent-scroll', indep);

await page.click('.editor-column-mode-toggle');
await page.waitForTimeout(450);
const r2 = await page.evaluate(MEASURE);
const indep2 = await page.evaluate(() => !!document.querySelector('.editor-body.is-independent-scroll'));
ok('rust off again: aria false + knob back + flow restored', r2.ariaChecked === 'false' && near(r2.knob.x - r0.knob.x, 0, 1) && !indep2);
await ctx.close();

// narrow: hidden below the gate
const nctx = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
const npage = await nctx.newPage();
await npage.goto(base, { waitUntil: 'load' });
await npage.waitForSelector('.list-item', { timeout: 20000 });
await npage.evaluate(() => {
  const t = Array.from(document.querySelectorAll('.img-card-title-text, .item-title-text')).find((e) => e.textContent.includes('周末看展记录'));
  if (t) t.click(); else document.querySelector('.list-item')?.click();
});
await npage.waitForSelector('.editor-body', { timeout: 15000 });
await npage.click('.editor-fab.right');
await npage.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await npage.waitForTimeout(300);
const nDisp = await npage.evaluate(() => {
  const e = document.querySelector('.editor-column-mode-toggle');
  return e ? getComputedStyle(e).display : 'MISSING';
});
ok('rust row hidden on narrow 390px', nDisp === 'none', nDisp);
await nctx.close();

// ---------- Original ----------
const octx = await browser.newContext({ viewport: { width: 1280, height: 800 }, hasTouch: true });
const opage = await octx.newPage();
opage.on('pageerror', (e) => console.log('ORIG PAGEERROR:', String(e).slice(0, 200)));
await opage.goto(origBase + 'Moment.html', { waitUntil: 'load' });
await opage.waitForFunction(() => document.body && document.body.textContent.includes('周末看展记录'), null, { timeout: 20000 });
await opage.evaluate(() => {
  const els = Array.from(document.querySelectorAll('body *')).filter((e) => e.children.length === 0 && e.textContent.trim() === '周末看展记录');
  if (els.length) els[0].click();
});
await opage.waitForSelector('button[aria-label="打开更多菜单"]', { timeout: 15000 });
await opage.click('button[aria-label="打开更多菜单"]');
await opage.waitForSelector('.editor-column-mode-toggle', { timeout: 8000 });
await opage.waitForTimeout(400);
const o0 = await opage.evaluate(MEASURE);
console.log('ORIG off:', JSON.stringify(o0));
await opage.click('.editor-column-mode-toggle');
await opage.waitForTimeout(450);
const o1 = await opage.evaluate(MEASURE);
console.log('ORIG on:', JSON.stringify(o1));
await octx.close();

// ---------- Cross-checks ----------
ok('orig track 42x26', o0 && near(o0.track.w, 42) && near(o0.track.h, 26), o0 ? `${o0.track.w}x${o0.track.h}` : 'missing');
ok('track size rust==orig', near(r0.track.w, o0.track.w) && near(r0.track.h, o0.track.h));
ok('knob size rust==orig', near(r0.knob.w, o0.knob.w) && near(r0.knob.h, o0.knob.h));
ok('off bg rust==orig', r0.track.bg === o0.track.bg, `${r0.track.bg} vs ${o0.track.bg}`);
ok('on bg rust==orig', r1.track.bg === o1.track.bg, `${r1.track.bg} vs ${o1.track.bg}`);
ok('travel rust==orig', near((r1.knob.x - r0.knob.x) - (o1.knob.x - o0.knob.x), 0, 1), `rust ${(r1.knob.x - r0.knob.x).toFixed(2)} vs orig ${(o1.knob.x - o0.knob.x).toFixed(2)}`);
ok('icon slot rust==orig', near(r0.icon.w, o0.icon.w) && near(r0.icon.h, o0.icon.h));
ok('title/sub rust==orig', r0.title.text === o0.title.text && r0.sub.text === o0.sub.text);
ok('min-height rust==orig', r0.minHeight === o0.minHeight, `${r0.minHeight} vs ${o0.minHeight}`);

await browser.close();
console.log(fails === 0 ? 'TOGGLE SPEC ALL PASS' : `TOGGLE SPEC ${fails} FAIL`);
process.exit(fails === 0 ? 0 : 1);
