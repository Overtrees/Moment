// 页面级副作用审计探针（Chromium 口径）：
// 插桩 addEventListener/removeEventListener/setInterval 净计数，
// 遍历 列表→编辑(带底色)→列表→设置→备份→诊断→列表→编辑(普通)
// →列表→编辑(带底色,第二轮) 全程量测根级状态残留：
// html/body inline style 与 class、计算背景、overflow、根字号、
// document.title、meta theme-color、window.__mn* 全局、
// #body-before-bg 样式元素、localStorage 键集。
// 用法: node probe_page_side_effects.mjs [baseUrl]
import { chromium } from 'playwright-core';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const BASE = process.argv[2] || 'http://localhost:8205/';
const ZIP = new URL('./fixtures/audit-bg.zip', import.meta.url).pathname;

const INIT = `
window.__probe = { net: {}, intervals: 0 };
window.__tgtName = (t) => {
  if (t === window) return 'window';
  if (t === document) return 'document';
  if (t === window.visualViewport) return 'visualViewport';
  if (typeof MediaQueryList !== 'undefined' && t instanceof MediaQueryList) return 'mql';
  if (t && t.nodeType === 1) return 'el';
  return 'other';
};
const __oAdd = EventTarget.prototype.addEventListener;
const __oRem = EventTarget.prototype.removeEventListener;
EventTarget.prototype.addEventListener = function (type, f, o) {
  const k = window.__tgtName(this) + ':' + type;
  window.__probe.net[k] = (window.__probe.net[k] || 0) + 1;
  return __oAdd.call(this, type, f, o);
};
EventTarget.prototype.removeEventListener = function (type, f, o) {
  const k = window.__tgtName(this) + ':' + type;
  window.__probe.net[k] = (window.__probe.net[k] || 0) - 1;
  return __oRem.call(this, type, f, o);
};
const __oSI = window.setInterval.bind(window);
const __oCI = window.clearInterval.bind(window);
window.setInterval = (...a) => { window.__probe.intervals++; return __oSI(...a); };
window.clearInterval = (id) => { window.__probe.intervals--; return __oCI(id); };
`;

const SNAP = () => {
  const de = document.documentElement, b = document.body;
  const bb = document.getElementById('body-before-bg');
  return {
    htmlInline: de.getAttribute('style') || '',
    bodyInline: b ? (b.getAttribute('style') || '') : '',
    htmlClass: String(de.className || ''), bodyClass: b ? String(b.className || '') : '',
    htmlBg: getComputedStyle(de).backgroundColor,
    bodyBg: b ? getComputedStyle(b).backgroundColor : '',
    htmlOverflow: getComputedStyle(de).overflow,
    bodyOverflow: b ? getComputedStyle(b).overflow : '',
    rootFontSize: de.style.fontSize || '',
    title: document.title,
    theme: [...document.querySelectorAll('meta[name="theme-color"]')].map(m => m.getAttribute('content')),
    mn: {
      esc: typeof window.__mnEsc, edScroll: typeof window.__mnEdScroll,
      typed: typeof window.__mnTypedMark, typedSent: window.__mnTypedSent,
      bgCleanup: typeof window.__mnBgCleanup, bgUpdate: typeof window.__mnBgUpdate,
      exportKeys: typeof window.__mnExportKeys, inline: typeof window.__mnInline,
      listCleanup: typeof window.__mnListScrollCleanup,
    },
    bodyBeforeEl: !!bb,
    bodyBeforeCss: bb ? bb.textContent : null,
    lsKeys: Object.keys(localStorage).sort(),
    net: { ...window.__probe.net },
    intervals: window.__probe.intervals,
    editorOpen: !!document.getElementById('editor-root'),
    scrimCount: document.querySelectorAll('.menu-scrim,.sheet-scrim,.backup-modal-scrim').length,
  };
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const out = [];
const errors = [];
function rec(label, s) {
  out.push({ label, ...s });
  console.log('---', label);
  console.log(JSON.stringify(s, null, 1));
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({
  viewport: { width: 1280, height: 800 },
  hasTouch: true,
});
await ctx.addInitScript(INIT);
const page = await ctx.newPage();
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await sleep(600);
rec('S0 list-initial', await page.evaluate(SNAP));

// 导入夹具（设置→备份→#file-import→确认→等 toast→返回×2）
await page.evaluate(() => document.querySelector('h1.page-title').dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForSelector('.set-row', { timeout: 10000 });
await page.locator('.set-row').first().click();
await page.waitForSelector('#file-import', { state: 'attached', timeout: 10000 });
await page.setInputFiles('#file-import', ZIP);
await page.waitForSelector('.backup-modal .backup-btn.primary', { timeout: 10000 });
await page.locator('.backup-modal .backup-btn.primary').click();
await page.waitForFunction(() => {
  const t = document.querySelector('.backup-toast');
  return t && t.textContent.includes('已导入');
}, null, { timeout: 20000, polling: 300 });
await page.locator('.editor-fab.left').click();
await sleep(300);
await page.locator('.editor-fab.left').click();
await page.waitForSelector('.list-item', { timeout: 10000 });
await sleep(500);
rec('S1 list-after-import', await page.evaluate(SNAP));

// 打开带底色备忘
await page.locator('.list-item', { hasText: '底色备忘' }).first().click();
await page.waitForSelector('#editor-root', { timeout: 10000 });
await sleep(800);
rec('S2 editor-colored', await page.evaluate(SNAP));
// 编辑器内滚动，触发 body::before 渐变写入
await page.evaluate(() => window.scrollTo(0, 120));
await sleep(500);
rec('S3 editor-colored-scrolled', await page.evaluate(SNAP));
// 关闭编辑器 → 列表（用户实报泄漏点 1）
await page.locator('.editor-fab.left').click();
await page.waitForSelector('.list-item', { timeout: 10000 });
await sleep(800);
rec('S4 list-after-editor', await page.evaluate(SNAP));
// 设置页（用户实报泄漏点 2）
await page.evaluate(() => document.querySelector('h1.page-title').dispatchEvent(new MouseEvent('click', { bubbles: true })));
await page.waitForSelector('.set-row', { timeout: 10000 });
await sleep(400);
rec('S5 settings-after-editor', await page.evaluate(SNAP));
// 备份页
await page.locator('.set-row').first().click();
await page.waitForSelector('.backup-hero', { timeout: 10000 });
await sleep(400);
rec('S6 backup', await page.evaluate(SNAP));
await page.locator('.editor-fab.left').click();
await sleep(300);
// 诊断页
await page.locator('.set-row').nth(2).click();
await page.waitForSelector('.diag-body', { timeout: 10000 });
await sleep(400);
rec('S7 diag', await page.evaluate(SNAP));
await page.locator('.editor-fab.left').click();
await sleep(300);
await page.locator('.editor-fab.left').click();
await page.waitForSelector('.list-item', { timeout: 10000 });
await sleep(500);
rec('S8 list-after-settings-tour', await page.evaluate(SNAP));

// 普通备忘往返
await page.locator('.list-item', { hasText: '普通备忘' }).first().click();
await page.waitForSelector('#editor-root', { timeout: 10000 });
await sleep(800);
rec('S9 editor-plain', await page.evaluate(SNAP));
await page.locator('.editor-fab.left').click();
await page.waitForSelector('.list-item', { timeout: 10000 });
await sleep(800);
rec('S10 list-after-plain', await page.evaluate(SNAP));

// 带底色备忘第二轮往返（量监听/定时器增量）
await page.locator('.list-item', { hasText: '底色备忘' }).first().click();
await page.waitForSelector('#editor-root', { timeout: 10000 });
await sleep(800);
rec('S11 editor-colored-2nd', await page.evaluate(SNAP));
// 导出面板：开菜单 → 导出 → 面板开 → 记录 __mnExportKeys → Esc 关 → 再按一键看自摘
await page.locator('.editor-fab.right').click();
await sleep(400);
await page.evaluate(() => {
  const btns = [...document.querySelectorAll('.menu-item, .editor-menu button, [class*=menu] button')];
  const t = btns.find((b) => b.textContent.includes('导出'));
  if (t) t.click();
});
await sleep(900);
rec('S12 export-panel-open', await page.evaluate(SNAP));
await page.keyboard.press('Escape');
await sleep(600);
rec('S13 export-panel-esc-closed', await page.evaluate(SNAP));
await page.keyboard.press('a');
await sleep(300);
rec('S14 after-stray-key', await page.evaluate(SNAP));
await page.locator('.editor-fab.left').click();
await page.waitForSelector('.list-item', { timeout: 10000 });
await sleep(800);
rec('S15 list-after-editor-2nd', await page.evaluate(SNAP));

// 戳残留监听：切深色（scheme mq）+ 改视口宽（wide mq / vv / resize）
await page.emulateMedia({ colorScheme: 'dark' });
await sleep(500);
await page.setViewportSize({ width: 900, height: 800 });
await sleep(500);
await page.emulateMedia({ colorScheme: 'light' });
await page.setViewportSize({ width: 1280, height: 800 });
await sleep(500);
rec('S16 list-after-media-pokes', await page.evaluate(SNAP));

console.log('=== pageerrors/console errors ===');
console.log(errors.length ? errors.join('\n') : '(none)');
await browser.close();
