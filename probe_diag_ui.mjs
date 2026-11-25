// 专用探针：诊断页按钮排布 + 点击态/加载态（2026-11-25 UIUX）。
//  ① 排布：复制（.primary）与刷新（.secondary）在主组同行、
//     清空（.danger）在危险组单独成行（异容器、在主组之下）；
//     三钮高 ≥44（点击域口径）。
//  ② 点击态：样式表含 .diag-actions .backup-btn:active 规则；
//     实压刷新钮（mouse down 保持）computed transform 落到
//     scale(0.975)。
//  ③ 加载态：剪贴板替身（writeText 延迟 900ms resolve +
//     调用计数）下点复制 → 进行中复制钮 disabled、内嵌
//     .backup-toast-spinner、文案「复制中…」、三钮全 disabled；
//     期间强制连点，writeText 仍只调 1 次；完成后钮恢复、
//     toast「已复制」出现、Diag 有 copy ok 结果行、复制物
//     首行仍是 ENV 环境头。
//  ④ 结果行：刷新记 refresh lines=；清空后正文只剩 cleared
//     一行（结果行口径与改造前一致）。
// 用法：node probe_diag_ui.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
// 剪贴板替身：慢复制夹具（延迟 + 计数），装在页面脚本之前。
await ctx.addInitScript(() => {
  window.__copyCalls = 0;
  window.__lastCopy = '';
  const stub = {
    writeText: (t) => {
      window.__copyCalls++;
      window.__lastCopy = t;
      return new Promise((r) => setTimeout(r, 900));
    },
  };
  try {
    Object.defineProperty(navigator, 'clipboard', { value: stub, configurable: true });
  } catch (e) { /* 替身装不上则③的计数断言会如实判红 */ }
});
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

// 进诊断页：列表 → 点标题进设置 → 诊断日志行
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 15000 });
await page.waitForTimeout(900);
await page.locator('.set-row', { hasText: '诊断日志' }).first().click();
await page.waitForSelector('.diag-actions', { timeout: 15000 });
await page.waitForTimeout(600);

const diagLines = () => page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]'); } catch (e) { return []; }
});
const waitDiag = async (needle, tries = 24) => {
  let lines = [];
  for (let i = 0; i < tries; i++) {
    lines = await diagLines();
    if (lines.some((l) => String(l).includes(needle))) break;
    await page.waitForTimeout(500);
  }
  return lines;
};

// ① 排布
const layout = await page.evaluate(() => [...document.querySelectorAll('.diag-actions button')].map((b) => {
  const r = b.getBoundingClientRect();
  return { text: b.innerText.trim(), cls: b.className, parent: b.parentElement.className, top: r.top, height: r.height };
}));
L('  buttons:', JSON.stringify(layout));
const copyBtn = layout.find((b) => b.text.includes('复制'));
const refreshBtn = layout.find((b) => b.text.includes('刷新'));
const clearBtn = layout.find((b) => b.text.includes('清空'));
ok('① 三钮齐备（复制/刷新/清空）', !!copyBtn && !!refreshBtn && !!clearBtn);
ok('① 复制为 primary 主钮', !!copyBtn && copyBtn.cls.includes('primary'), copyBtn && copyBtn.cls);
ok('① 刷新为 secondary', !!refreshBtn && refreshBtn.cls.includes('secondary'), refreshBtn && refreshBtn.cls);
ok('① 清空为 danger', !!clearBtn && clearBtn.cls.includes('danger'), clearBtn && clearBtn.cls);
ok('① 复制与刷新同组（diag-actions-main）', !!copyBtn && !!refreshBtn && copyBtn.parent === 'diag-actions-main' && refreshBtn.parent === 'diag-actions-main', copyBtn && copyBtn.parent);
ok('① 清空单独成组（diag-actions-danger）', !!clearBtn && clearBtn.parent === 'diag-actions-danger', clearBtn && clearBtn.parent);
ok('① 危险组在主组之下', !!clearBtn && !!copyBtn && clearBtn.top > copyBtn.top + 40, `clear.top=${clearBtn && clearBtn.top} copy.top=${copyBtn && copyBtn.top}`);
ok('① 三钮高 ≥44', layout.every((b) => b.height >= 44), layout.map((b) => b.height).join(','));

// ② 点击态
const hasActiveRule = await page.evaluate(() => {
  let txt = '';
  for (const sh of document.styleSheets) {
    try { for (const r of sh.cssRules) txt += r.cssText + '\n'; } catch (e) { /* 跨源表跳过 */ }
  }
  return /\.diag-actions \.backup-btn:active/.test(txt);
});
ok('② :active 规则在场（.diag-actions .backup-btn:active）', hasActiveRule);
const rBox = await page.locator('.diag-actions-main .backup-btn.secondary').boundingBox();
await page.mouse.move(rBox.x + rBox.width / 2, rBox.y + rBox.height / 2);
await page.mouse.down();
await page.waitForTimeout(350); // 等 180ms 过渡落定（量落定值口径）
const pressed = await page.evaluate(() => {
  const b = document.querySelector('.diag-actions-main .backup-btn.secondary');
  const cs = getComputedStyle(b);
  return { transform: cs.transform, bg: cs.backgroundColor };
});
await page.mouse.up();
const m = /matrix\(([\d.]+)/.exec(pressed.transform || '');
ok('② 实压 transform 落到 scale(0.975)', !!m && Math.abs(parseFloat(m[1]) - 0.975) < 0.01, pressed.transform);

// ③ 加载态（慢复制）
await page.locator('.diag-actions-main .backup-btn.primary').click();
await page.waitForSelector('.diag-actions .backup-btn.primary .backup-toast-spinner', { timeout: 5000 });
const during = await page.evaluate(() => {
  const btns = [...document.querySelectorAll('.diag-actions button')];
  const copy = document.querySelector('.diag-actions .backup-btn.primary');
  return {
    allDisabled: btns.every((b) => b.disabled),
    copyText: copy.innerText.trim(),
    spinnerInCopy: !!copy.querySelector('.backup-toast-spinner'),
  };
});
ok('③ 进行中三钮全 disabled（防连点/防交叉）', during.allDisabled);
ok('③ 复制钮进行中文案', during.copyText.includes('复制中'), during.copyText);
ok('③ 复制钮内嵌 spinner', during.spinnerInCopy);
// 期间强制连点（绕过 actionability 的程序化点击 + 真实坐标再点一次）
await page.evaluate(() => document.querySelector('.diag-actions .backup-btn.primary').click());
await page.locator('.diag-actions-main .backup-btn.primary').click({ force: true }).catch(() => {});
await page.waitForSelector('.backup-toast', { timeout: 8000 });
const toastText = await page.locator('.backup-toast .backup-toast-text').innerText();
ok('③ 完成 toast 为「已复制」', toastText.includes('已复制'), toastText.trim());
const copyCalls = await page.evaluate(() => window.__copyCalls);
ok('③ writeText 只调 1 次（防连点成立）', copyCalls === 1, `calls=${copyCalls}`);
const lastCopy = await page.evaluate(() => window.__lastCopy);
ok('③ 复制物首行仍是 ENV 环境头', lastCopy.startsWith('ENV build='));
const restored = await page.evaluate(() => {
  const copy = document.querySelector('.diag-actions .backup-btn.primary');
  return { disabled: copy.disabled, spinner: !!copy.querySelector('.backup-toast-spinner'), text: copy.innerText.trim() };
});
ok('③ 完成后复制钮恢复（启用、无 spinner、原文案）', !restored.disabled && !restored.spinner && restored.text.includes('复制全部'), JSON.stringify(restored));
const linesAfterCopy = await waitDiag('DIAG copy ok');
ok('③ Diag 有 copy ok 结果行', linesAfterCopy.some((l) => String(l).includes('DIAG copy ok')));

// ④ 刷新/清空结果行
await page.locator('.diag-actions-main .backup-btn.secondary').click();
const linesAfterRefresh = await waitDiag('DIAG refresh lines=');
ok('④ Diag 有 refresh lines= 结果行', linesAfterRefresh.some((l) => String(l).includes('DIAG refresh lines=')));
await page.locator('.diag-actions-danger .backup-btn.danger').click();
await page.waitForTimeout(400);
const bodyText = await page.$eval('.diag-body', (e) => e.innerText);
const bodyLines = bodyText.split('\n').filter((s) => s.trim().length > 0);
ok('④ 清空后正文只剩 cleared 行', bodyLines.length === 1 && bodyLines[0].includes('DIAG cleared'), JSON.stringify(bodyLines));

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
