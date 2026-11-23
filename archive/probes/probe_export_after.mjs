// 修复后模拟验证：现成 dist（修复前构建）+ 注入新 panels.css +
// JS 模拟 rsx 结构变化（.export-inner 包裹 / › / 尾注 / PDF 徽章 sm），
// 量出修复后应有的几何与字号，和原版实测对照。
import { chromium } from 'playwright-core';

const [w, h] = [+process.argv[2] || 393, +process.argv[3] || 852];
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: w, height: h }, hasTouch: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto('http://localhost:8108/', { waitUntil: 'networkidle' });
await page.waitForTimeout(1500);
await page.locator('.img-card, .list-item').first().click();
await page.waitForSelector('.editor-fab.right', { timeout: 15000 });
await page.waitForTimeout(600);
await page.click('.editor-fab.right');
await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
await page.waitForTimeout(400);
await page.locator('.editor-menu-panel button', { hasText: '导出笔记' }).first().click();
await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
await page.waitForTimeout(500);

// 注入新 panels.css（整文件，与应用内已拼接的旧 panels 规则同值重复无副作用）
await page.addStyleTag({ path: process.env.HOME + '/workspace/Mynote/rust/apps/web/styles/panels.css' });
// 模拟 rsx 结构变化
await page.evaluate(() => {
  const panel = document.querySelector('.editor-export-panel');
  const head = panel.querySelector('.export-head');
  const choices = panel.querySelector('.export-choices');
  const inner = document.createElement('div');
  inner.className = 'export-inner';
  panel.appendChild(inner);
  inner.appendChild(head);
  inner.appendChild(choices);
  panel.querySelectorAll('.editor-export-choice').forEach((c) => {
    const s = document.createElement('span');
    s.className = 'export-chevron';
    s.textContent = '›';
    c.appendChild(s);
  });
  const badges = panel.querySelectorAll('.export-badge');
  badges[2].classList.add('sm');
  const note = document.createElement('div');
  note.className = 'export-note';
  note.textContent = 'PDF 会打开浏览器打印窗口，可在其中存储为 PDF。';
  inner.appendChild(note);
});
await page.waitForTimeout(300);

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
  const head = panel.querySelector('.export-head');
  const choices = [...panel.querySelectorAll('.editor-export-choice')];
  const first = choices[0];
  const badge = first.querySelector('.export-badge');
  const pdfBadge = choices[2].querySelector('.export-badge');
  const label = first.querySelector('.export-label');
  const detail = first.querySelector('.export-detail');
  const chev = first.querySelector('.export-chevron');
  const note = panel.querySelector('.export-note');
  return {
    panelRect: R(panel),
    panel: CS(panel, ['max-width', 'overflow-y', 'display', 'flex-direction']),
    panelChildren: [...panel.children].map((c) => c.className),
    headRect: R(head),
    head: CS(head, ['border-bottom-color']),
    choiceRects: choices.map((c) => R(c)),
    choice: CS(first, ['min-height', 'padding', 'border-radius']),
    badgeRect: R(badge),
    badge: CS(badge, ['background-color', 'border-radius', 'font-size', 'font-family', 'letter-spacing']),
    pdfBadge: CS(pdfBadge, ['font-size']),
    label: CS(label, ['font-size', 'font-weight', 'display']),
    detail: CS(detail, ['font-size', 'color', 'margin-top', 'display']),
    chevron: CS(chev, ['font-size', 'color', 'padding-left']),
    noteRect: R(note),
    noteStyle: CS(note, ['font-size', 'line-height', 'color', 'border-top-width', 'margin', 'padding']),
  };
});
console.log(JSON.stringify({ viewport: `${w}x${h}`, errors: errors.slice(0, 2), ...data }, null, 1));
await browser.close();
