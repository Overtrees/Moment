// 复现：标题 Enter 提交后点正文点不出光标（竞态量化）
// 循环：聚焦标题 → 改标题 → Enter → （不同延时）点正文段落 →
// 断言选区落在段落内 + 打字落字。失败抓全套现场。
import { chromium } from 'playwright-core';

const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = process.argv[2] || 'http://localhost:8196/';
const ROUNDS = parseInt(process.argv[3] || '30', 10);

const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 393, height: 852 }, hasTouch: true });
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.new-card-title', { timeout: 15000 });
await page.click('.new-card-title');
await page.waitForSelector('#editor-title-text', { timeout: 8000 });
await page.waitForTimeout(900);

// 给正文先放一个有字的段落（新备忘自动聚焦首块）
await page.keyboard.type('正文段落甲乙丙丁');
await page.waitForTimeout(300);

// 给标题 input 与首段各打身份标记（节点是否被换）
await page.evaluate(() => {
  const inp = document.querySelector('#editor-title-text');
  if (inp) inp.__mark = 'title-node-1';
  const p = document.querySelector('.editor-body [data-bid]');
  if (p) p.__mark = 'para-node-1';
});

async function bodyState() {
  return page.evaluate(() => {
    const ae = document.activeElement;
    const sel = window.getSelection();
    let anchorBid = null, anchorInBody = false;
    if (sel && sel.rangeCount) {
      let n = sel.anchorNode;
      anchorInBody = !!(n && document.querySelector('.editor-body') && document.querySelector('.editor-body').contains(n.nodeType === 3 ? n.parentNode : n));
      let el = n && (n.nodeType === 3 ? n.parentElement : n);
      const bidEl = el && el.closest ? el.closest('[data-bid]') : null;
      anchorBid = bidEl ? bidEl.getAttribute('data-bid') : null;
    }
    const inp = document.querySelector('#editor-title-text');
    const firstPara = document.querySelector('.editor-body [data-bid]');
    return {
      aeTag: ae ? ae.tagName + '#' + (ae.id || '') + '.' + (ae.className || '') : 'none',
      aeIsTitle: ae === inp,
      anchorBid, anchorInBody,
      selCollapsed: sel ? sel.isCollapsed : null,
      titleSameNode: inp ? inp.__mark === 'title-node-1' : null,
      titleExists: !!inp,
      paraSameNode: firstPara ? firstPara.__mark === 'para-node-1' : null,
      paraCE: firstPara ? firstPara.isContentEditable : null,
      paraText: firstPara ? (firstPara.innerText || '').slice(0, 40) : null,
      foreign: window.__mnTitleGeomForeign,
    };
  });
}

async function diagTail() {
  return page.evaluate(() => {
    try {
      const arr = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
      return arr.slice(-30).map((x) => x.line || String(x));
    } catch { return []; }
  });
}

let fails = 0;
const failRounds = [];
for (let r = 1; r <= ROUNDS; r++) {
  // —— 聚焦标题（触屏点按）——
  const tBox = await page.evaluate(() => {
    const inp = document.querySelector('#editor-title-text');
    const b = inp.getBoundingClientRect();
    return { x: b.left + b.width / 2, y: b.top + b.height / 2 };
  });
  await page.touchscreen.tap(tBox.x, tBox.y);
  await page.waitForTimeout(200);
  const focused = await page.evaluate(() => document.activeElement === document.querySelector('#editor-title-text'));
  if (!focused) {
    console.log(`R${r}: TITLE TAP DID NOT FOCUS (pre-failure)`);
    fails++; failRounds.push(r + ':titlefocus');
    continue;
  }
  await page.keyboard.press('Control+a');
  await page.keyboard.type('标题' + r);
  await page.waitForTimeout(80);
  await page.keyboard.press('Enter');
  // 延时三档轮换：0 / 120 / 500 ms
  const delay = [0, 120, 500][r % 3];
  if (delay) await page.waitForTimeout(delay);

  // —— 点正文首段（触屏点按段内文字处）——
  const pBox = await page.evaluate(() => {
    const p = document.querySelector('.editor-body [data-bid]');
    const b = p.getBoundingClientRect();
    return { x: b.left + 30, y: b.top + Math.min(14, b.height / 2) };
  });
  const hit = await page.evaluate(({ x, y }) => {
    const el = document.elementFromPoint(x, y);
    const chain = [];
    let n = el;
    while (n && chain.length < 6) { chain.push(n.tagName + '.' + (n.className || '') + (n.getAttribute && n.getAttribute('data-bid') ? '[bid=' + n.getAttribute('data-bid') + ']' : '')); n = n.parentElement; }
    return chain.join(' < ');
  }, pBox);
  await page.touchscreen.tap(pBox.x, pBox.y);
  await page.waitForTimeout(150);
  let st = await bodyState();
  let okSel = st.anchorInBody && !st.aeIsTitle;
  let typed = false;
  if (okSel) {
    const before = st.paraText || '';
    await page.keyboard.type('X');
    await page.waitForTimeout(150);
    const after = await page.evaluate(() => {
      const p = document.querySelector('.editor-body [data-bid]');
      return p ? (p.innerText || '') : '';
    });
    typed = after.includes('X') && after.length >= before.length;
  }
  if (okSel && typed) {
    console.log(`R${r}: ok (delay=${delay})`);
  } else {
    fails++; failRounds.push(r);
    console.log(`R${r}: FAIL delay=${delay} okSel=${okSel} typed=${typed}`);
    console.log('  state:', JSON.stringify(st));
    console.log('  hitChain:', hit);
    const d = await diagTail();
    console.log('  diag tail:\n    ' + d.join('\n    '));
    // 失败后再点一次：看是否持续失败（用户口径：持续到退出重进）
    await page.touchscreen.tap(pBox.x, pBox.y);
    await page.waitForTimeout(200);
    const st2 = await bodyState();
    console.log('  second tap state:', JSON.stringify({ aeIsTitle: st2.aeIsTitle, anchorInBody: st2.anchorInBody, aeTag: st2.aeTag }));
  }
}
console.log(`\n== FAILS: ${fails}/${ROUNDS} rounds: ${JSON.stringify(failRounds)}`);
await browser.close();
