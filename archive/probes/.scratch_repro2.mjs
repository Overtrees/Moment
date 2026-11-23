// 复现 2：导入含 md 源段的备忘，逐块循环「标题 Enter → 点该块」
// 目标块：b2 普通段 / b3 md 源段（预览→编辑） / b4 空段 / b5 末段 / b1 标题块
// CPU 节流 4x 放大竞态窗口；每 3 轮标题走 CDP 组字输入。
import { chromium } from 'playwright-core';

const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = process.argv[2] || 'http://localhost:8196/';
const ROUNDS = parseInt(process.argv[3] || '6', 10);

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 393, height: 852 }, hasTouch: true });
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });

async function importZip(zipPath) {
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zipPath);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
}
async function openMemoByTitle(title) {
  await page.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes(t));
    if (el) el.click();
  }, title);
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(600);
}

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.new-card-title', { timeout: 15000 });
// 先去设置页导入（列表页点头像/标题进设置：沿用 gaps 的 importZip 前置动作）
await importZip('/tmp/titlebug.zip');
await openMemoByTitle('标题后点正文');

const TARGETS = ['b2', 'b3', 'b4', 'b5', 'b1'];
async function snap(bid) {
  return page.evaluate((bid) => {
    const el = document.querySelector('[data-bid="' + bid + '"]') || document.querySelector('[data-bids="' + bid + '"]');
    const ae = document.activeElement;
    const sel = window.getSelection();
    let anchorBid = null;
    if (sel && sel.rangeCount) {
      let n = sel.anchorNode;
      let el2 = n && (n.nodeType === 3 ? n.parentElement : n);
      const b = el2 && el2.closest ? el2.closest('[data-bid]') : null;
      anchorBid = b ? b.getAttribute('data-bid') : null;
    }
    return {
      exists: !!el,
      cls: el ? el.className : null,
      ce: el ? el.isContentEditable : null,
      btype: el ? el.getAttribute('data-btype') : null,
      aeIsTitle: ae === document.querySelector('#editor-title-text'),
      aeTag: ae ? ae.tagName + '.' + (ae.className || '') : 'none',
      anchorBid,
      text: el ? (el.innerText || '') : null,
    };
  }, bid);
}
async function tapCenterOf(bid) {
  const box = await page.evaluate((bid) => {
    const el = document.querySelector('[data-bid="' + bid + '"]') || document.querySelector('[data-bids="' + bid + '"]');
    if (!el) return null;
    el.scrollIntoView({ block: 'center' });
    const b = el.getBoundingClientRect();
    return { x: b.left + Math.min(40, b.width / 3), y: b.top + b.height / 2 };
  }, bid);
  if (!box) return false;
  await page.touchscreen.tap(box.x, box.y);
  return true;
}
async function tapTitle() {
  const box = await page.evaluate(() => {
    const inp = document.querySelector('#editor-title-text');
    const b = inp.getBoundingClientRect();
    return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
  });
  await page.touchscreen.tap(box.x, box.y);
  await page.waitForTimeout(200);
  return page.evaluate(() => document.activeElement === document.querySelector('#editor-title-text'));
}
async function diagTail(n = 25) {
  return page.evaluate((n) => {
    try {
      const arr = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
      return arr.slice(-n).map((x) => x.line || String(x));
    } catch { return []; }
  }, n);
}

let fails = 0;
for (let r = 1; r <= ROUNDS; r++) {
  for (const bid of TARGETS) {
    const useComp = r % 3 === 0;
    if (!(await tapTitle())) { console.log(`R${r}/${bid}: title tap no focus`); fails++; continue; }
    if (useComp) {
      await cdp.send('Input.imeSetComposition', { text: 'biaoti', selectionStart: 6, selectionEnd: 6 });
      await page.waitForTimeout(60);
      await cdp.send('Input.insertText', { text: '标题组字' + r });
      await page.waitForTimeout(60);
    } else {
      await page.keyboard.press('Control+a');
      await page.keyboard.type('标题' + r + bid);
    }
    await page.keyboard.press('Enter');
    // 不等：立即点目标块（与提交重渲染竞速）
    const pre = await snap(bid);
    await tapCenterOf(bid);
    await page.waitForTimeout(250);
    let st = await snap(bid);
    // 判定：可编辑且选区在本块内
    let ok = st.ce && st.anchorBid === bid;
    let typed = false;
    if (ok) {
      const beforeLen = (st.text || '').length;
      await page.keyboard.type('Z');
      await page.waitForTimeout(150);
      const st2 = await snap(bid);
      typed = (st2.text || '').length === beforeLen + 1 && (st2.text || '').includes('Z');
    }
    if (ok && typed) {
      console.log(`R${r}/${bid}: ok (comp=${useComp}, was=${pre.cls}/${pre.btype})`);
    } else {
      fails++;
      console.log(`R${r}/${bid}: FAIL comp=${useComp} ok=${ok} typed=${typed}`);
      console.log('  pre :', JSON.stringify(pre));
      console.log('  post:', JSON.stringify(st));
      const hit = await page.evaluate((bid) => {
        const el = document.querySelector('[data-bid="' + bid + '"]') || document.querySelector('[data-bids="' + bid + '"]');
        if (!el) return 'no-el';
        const b = el.getBoundingClientRect();
        const h = document.elementFromPoint(b.left + 40, b.top + b.height / 2);
        return h ? h.tagName + '.' + (h.className || '') : 'null';
      }, bid);
      console.log('  hitNow:', hit);
      console.log('  diag:\n    ' + (await diagTail()).join('\n    '));
      // 再点一次看是否持续
      await tapCenterOf(bid);
      await page.waitForTimeout(250);
      const st3 = await snap(bid);
      console.log('  second tap:', JSON.stringify({ ce: st3.ce, anchorBid: st3.anchorBid, aeIsTitle: st3.aeIsTitle }));
    }
  }
}
console.log(`\n== FAILS: ${fails}`);
await browser.close();
