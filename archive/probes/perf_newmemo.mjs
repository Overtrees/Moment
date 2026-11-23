// 新备忘自动聚焦分段探针：点「新建笔记」→ 量 body/bridge/focus。
// 用法：node perf_newmemo.mjs <base> [rounds]
import { chromium } from 'playwright-core';

const base = process.argv[2];
const ROUNDS = parseInt(process.argv[3] || '4', 10);
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

const INSTRUMENT = () => {
  window.__seg = { marks: {} };
  const mo = new MutationObserver(() => {
    if (!window.__seg.marks.body && document.querySelector('.editor-body')) {
      window.__seg.marks.body = performance.now();
    }
  });
  mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
  const poll = () => {
    if (!window.__seg.marks.bridge && typeof window.__mnFocus === 'function') {
      window.__seg.marks.bridge = performance.now();
    }
    if (!window.__seg.marks.focus) {
      const ae = document.activeElement;
      if (ae && ae.isContentEditable && ae.closest && ae.closest('[data-bid]')) {
        window.__seg.marks.focus = performance.now();
      }
    }
    if (!window.__seg.marks.bridge || !window.__seg.marks.focus) setTimeout(poll, 2);
  };
  setTimeout(poll, 0);
};

async function newMemo(page) {
  await page.evaluate(INSTRUMENT);
  const t0 = await page.evaluate(() => {
    // NewCard：.list-item 且其标题文本恰为「新建笔记」
    const card = [...document.querySelectorAll('.list-item')]
      .find((e) => e.querySelector('.item-title-text')?.textContent.trim() === '新建笔记');
    if (!card) return -1;
    const t = performance.now();
    card.click();
    return t;
  });
  if (t0 < 0) return { error: 'new-note entry not found' };
  await page.waitForTimeout(3000);
  return page.evaluate((t0) => {
    const m = window.__seg.marks || {};
    const rel = (v) => (v == null ? null : Math.round(v - t0));
    return { body: rel(m.body), bridge: rel(m.bridge), focus: rel(m.focus) };
  }, t0);
}

async function backToList(page) {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(400);
}

const rows = [];
for (let r = 0; r < ROUNDS; r++) {
  const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const row = { round: r + 1 };
  try {
    await page.goto(base, { waitUntil: 'load' });
    await page.waitForSelector('.list-item', { timeout: 30000 });
    await page.waitForTimeout(600);
    row.cold = await newMemo(page);
    await backToList(page);
    row.warm = await newMemo(page);
  } catch (e) {
    row.error = String(e).slice(0, 160);
  }
  rows.push(row);
  console.log(JSON.stringify(row));
  await browser.close();
}
const med = (vals) => {
  const v = vals.filter((x) => x != null).sort((a, b) => a - b);
  return v.length ? v[Math.floor(v.length / 2)] : null;
};
for (const k of ['cold', 'warm']) {
  console.log(`MEDIAN ${k}: body=${med(rows.map((r) => r[k]?.body))} bridge=${med(rows.map((r) => r[k]?.bridge))} focus=${med(rows.map((r) => r[k]?.focus))}`);
}
