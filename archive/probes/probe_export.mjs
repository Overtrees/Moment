// 导出面板双边度量探针：node probe_export.mjs <orig|rust> <width> <height>
// 打开 编辑器 → ••• 菜单 → 导出笔记，量 .editor-export-panel 全套 computed 度量
import { chromium } from 'playwright-core';

const [app, w, h] = [process.argv[2], +process.argv[3] || 393, +process.argv[4] || 852];
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const URL = app === 'orig' ? 'http://localhost:8109/Moment.html' : 'http://localhost:8108/';

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(URL, { waitUntil: 'networkidle' });
await page.waitForTimeout(1500);

// 打开第一条备忘
if (app === 'orig') {
  const card = page.locator('.memo-card, .list-item, .memo-item, [data-memo-id]').first();
  await card.click();
} else {
  const card = page.locator('.img-card, .list-item').first();
  await card.click();
}
await page.waitForSelector('.editor-fab.right', { timeout: 15000 });
await page.waitForTimeout(600);
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(400);
// 点导出入口（菜单里含「导出笔记」的按钮）
const entry = page.locator('.editor-menu-panel button', { hasText: '导出笔记' }).first();
await entry.click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(700); // 等进场动画落定

const data = await page.evaluate(() => {
  const R = (el) => {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) };
  };
  const CS = (el, props) => {
    if (!el) return null;
    const cs = getComputedStyle(el);
    const o = {};
    for (const p of props) o[p] = cs.getPropertyValue(p);
    return o;
  };
  const panel = document.querySelector('.editor-export-panel');
  const head = panel && (panel.querySelector('.export-head') || panel.children[0] && panel.children[0].children[0]);
  const back = panel && panel.querySelector('button');
  const choices = panel && [...panel.querySelectorAll('.editor-export-choice')];
  const first = choices && choices[0];
  const badge = first && first.querySelector('span');
  const copySpans = first && [...first.querySelectorAll('span')];
  const note = panel && [...panel.querySelectorAll('div')].find((d) => d.textContent.trim() === 'PDF 会打开浏览器打印窗口，可在其中存储为 PDF。');
  return {
    panelRect: R(panel),
    panel: CS(panel, ['position', 'top', 'right', 'width', 'max-width', 'max-height', 'border-radius', 'background-color', 'border-top-color', 'border-top-width', 'opacity', 'transform', 'transform-origin', 'z-index', 'overflow-y', 'display', 'flex-direction', 'backdrop-filter']),
    panelChildren: panel ? [...panel.children].map((c) => c.className || c.tagName) : null,
    headRect: R(head),
    head: CS(head, ['min-height', 'padding', 'border-bottom-color', 'border-bottom-width', 'gap']),
    backRect: R(back),
    back: CS(back, ['background-color', 'border-radius', 'border-top-width', 'border-top-color']),
    backSvg: back ? (back.querySelector('svg') ? { w: back.querySelector('svg').getAttribute('width'), sw: back.querySelector('svg').getAttribute('stroke-width') } : null) : null,
    titleText: panel ? (panel.textContent.includes('导出笔记') ? '导出笔记' : panel.textContent.slice(0, 40)) : null,
    choiceCount: choices ? choices.length : 0,
    choiceRects: choices ? choices.map((c) => R(c)) : [],
    choice: CS(first, ['min-height', 'padding', 'border-radius', 'gap', 'background-color']),
    badgeRect: R(badge),
    badge: CS(badge, ['background-color', 'border-radius', 'font-size', 'font-weight', 'font-family', 'color', 'letter-spacing']),
    badgeTexts: choices ? choices.map((c) => c.querySelector('span').textContent) : [],
    copySpanCount: copySpans ? copySpans.length : 0,
    choiceText: first ? first.textContent.replace(/\s+/g, ' ').trim() : null,
    lastSpanInChoice: first ? (() => { const s = [...first.querySelectorAll('span')]; const last = s[s.length - 1]; return { text: last.textContent, cls: last.className }; })() : null,
    noteExists: !!note,
    noteText: note ? note.textContent.trim() : null,
    noteStyle: CS(note, ['font-size', 'line-height', 'color', 'border-top-width', 'margin', 'padding']),
    activeElement: document.activeElement ? (document.activeElement.className || document.activeElement.tagName) : null,
  };
});
console.log(JSON.stringify({ app, viewport: `${w}x${h}`, errors: errors.slice(0, 2), ...data }, null, 1));
await browser.close();
