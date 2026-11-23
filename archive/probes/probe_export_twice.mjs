// 连续两次 PDF 导出 + 首个弹窗留开时再导出：验证 __mnPrintWin
// 句柄与流程可重复（用户在真机上重试是常见路径）。
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8120/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
let failures = 0;
const ok = (name, cond, val) => { if (!cond) failures++; console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : '')); };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
await ctx.addInitScript(() => {
  window.__prints = 0;
  window.print = () => { window.__prints++; window.dispatchEvent(new Event('afterprint')); };
});
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

// 用种子数据直接开一篇（避免导入夹具的长流程）
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await page.locator('.list-item').first().click();
await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
await page.waitForTimeout(900);

async function exportPdf(label) {
  const popP = ctx.waitForEvent('page', { timeout: 15000 }).catch(() => null);
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(350);
  await page.click('[data-export-format="pdf"]');
  const pop = await popP;
  ok(`${label} 弹窗打开`, !!pop);
  if (!pop) return null;
  await pop.waitForTimeout(1200);
  const info = await pop.evaluate(() => ({ shell: !!document.querySelector('.mynote-export-shell'), prints: window.__prints || 0 })).catch(() => ({ shell: false, prints: -1 }));
  ok(`${label} 弹窗为导出文档且 print 已调`, info.shell && info.prints >= 1, JSON.stringify(info));
  // 面板应已关闭
  const panelGone = await page.evaluate(() => !document.querySelector('.editor-export-panel') && !document.querySelector('.menu-scrim'));
  ok(`${label} opener 面板/遮罩已收`, panelGone);
  return pop;
}

const p1 = await exportPdf('第一次');
if (p1) await p1.close().catch(() => {});
await page.waitForTimeout(600);
const p2 = await exportPdf('第二次（首窗已关）');
if (p2) { /* 留开 */ }
await page.waitForTimeout(400);
const p3 = await exportPdf('第三次（第二窗留开）');
if (p3) await p3.close().catch(() => {});
if (p2) await p2.close().catch(() => {});
await page.waitForTimeout(500);
const alive = await page.evaluate(() => {
  // 命中点取首个块中心（固定 y 在短备忘上会落到正文区外）
  const el = document.querySelector('.editor-body [data-bid]');
  if (!el) return { hitBody: false, overlays: -1 };
  const r = el.getBoundingClientRect();
  const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
  return { hitBody: !!(hit && hit.closest && hit.closest('.editor-body')), overlays: document.querySelectorAll('.menu-scrim,.editor-export-panel').length };
});
ok('三次往返后正文可命中且无残留层', alive.hitBody && alive.overlays === 0, JSON.stringify(alive));
ok('全程无 pageerror', errors.length === 0, errors.join(' | ').slice(0, 200));
await browser.close();
console.log(failures ? `PROBE FAILURES: ${failures}` : 'PROBE ALL PASS');
process.exit(failures ? 1 : 0);
