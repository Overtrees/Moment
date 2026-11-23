// 重开备忘标题点按落点复现探针：
// 新建路径 vs 重开路径，中部点按后输入落点对照 + 全程选区快照。
// 用法：node probe_title_reopen.mjs [base]
import { chromium } from 'playwright-core';

const BASE = process.argv[2] || 'http://localhost:8231/';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const TITLE16 = '标题验收一二三四五六七八九十甲乙';

const SNAP = () => {
  const el = document.getElementById('editor-title-text');
  const sel = window.getSelection();
  const info = {
    text: el ? el.textContent : null,
    active: document.activeElement ? (document.activeElement.id || document.activeElement.className) : null,
    scrollLeft: el && el.parentElement ? el.parentElement.scrollLeft : null,
  };
  if (sel && sel.rangeCount) {
    info.anchorType = sel.anchorNode ? sel.anchorNode.nodeType : null;
    info.anchorOff = sel.anchorOffset;
    info.collapsed = sel.isCollapsed;
    if (el && sel.anchorNode && el.contains(sel.anchorNode)) {
      const r = document.createRange();
      r.selectNodeContents(el);
      r.setEnd(sel.anchorNode, sel.anchorOffset);
      info.charOff = r.toString().length;
    } else info.charOff = null;
  }
  return info;
};

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
const S = async (label) => console.log(label, JSON.stringify(await page.evaluate(SNAP)));

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });

// ---- 流程 A：新建 ----
await page.click('.list-item:has-text("新建") .item-title-text');
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(800);
const tapTitle = async (frac) => {
  const box = await page.locator('.editor-title-capsule').boundingBox();
  await page.touchscreen.tap(box.x + box.width * frac, box.y + box.height / 2);
};
await tapTitle(0.5);
await page.waitForTimeout(500);
await page.keyboard.type(TITLE16, { delay: 25 });
await page.waitForTimeout(500);
await S('A typed:');
await page.touchscreen.tap(196, 500); // 点正文失焦
await page.waitForTimeout(700);
await S('A after blur:');
await tapTitle(0.5);
await page.waitForTimeout(120);
await S('A tap+120ms:');
await page.waitForTimeout(800);
await S('A tap+920ms:');
await page.keyboard.type('X', { delay: 30 });
await page.waitForTimeout(400);
const aText = await page.evaluate(() => document.getElementById('editor-title-text').textContent);
console.log('A result text:', aText, '| X index:', aText.indexOf('X'), '/', aText.length);

// ---- 流程 B：重开 ----
await page.touchscreen.tap(196, 500);
await page.waitForTimeout(500);
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.waitForTimeout(600);
await page.click('.list-item:has-text("标题验收") .item-title-text');
await page.waitForSelector('#editor-title-text', { timeout: 10000 });
await page.waitForTimeout(900);
await S('B reopened:');
await tapTitle(0.3);
await page.waitForTimeout(120);
await S('B tap30+120ms:');
await page.waitForTimeout(800);
await S('B tap30+920ms:');
await page.keyboard.type('Y', { delay: 30 });
await page.waitForTimeout(400);
const bText = await page.evaluate(() => document.getElementById('editor-title-text').textContent);
console.log('B result text:', bText, '| Y index:', bText.indexOf('Y'), '/', bText.length);

const diag = await page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
console.log('DIAG title lines:', diag.split('\n').filter((l) => /title|EDIT/.test(l)).slice(-12).join(' | '));
console.log('pageerrors:', errors.slice(0, 3).join('; ') || 'none');
await browser.close();
