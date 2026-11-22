// 探针（原版）：尾随空段的真实数据形态——DOM 形态、点击输入、
// 落盘后的 memos doc 结构、文末原子块的 trail_ 推入、退格行为。
import { chromium } from 'playwright-core';
const url = 'http://localhost:8207/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
const L = (...a) => console.log(...a);

await page.goto(url, { waitUntil: 'load' });
await page.waitForTimeout(2500);
const seeded = await page.evaluate(async () => {
  const resp = await fetch('trail_probe.zip');
  const buf = await resp.arrayBuffer();
  const unzipped = await window.MynoteZip.checkedZip(new Uint8Array(buf));
  const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
  const db = await window.MynoteIdb.getDB();
  await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
  localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
  return backup.memos.length;
});
L('SEEDED', seeded);
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(2000);

const dumpBody = () => page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  if (!body) return [];
  const walk = (root, depth) => [...root.children].flatMap((el) => {
    const row = {
      depth, tag: el.tagName, cls: (el.className || '').slice(0, 40),
      bid: el.dataset?.blockid || '', type: el.dataset?.type || '',
      ce: el.contentEditable, text: (el.textContent || '').replace(/\s+/g, ' ').slice(0, 26),
    };
    return el.classList?.contains('editor-column') ? [row, ...walk(el, depth + 1)] : [row];
  });
  return walk(body, 0);
});
const openMemo = async (title) => {
  const titlePt = (t) => page.evaluate((tt) => {
    const card = [...document.querySelectorAll('.list-item, .img-card')]
      .find((e) => (e.querySelector('.item-title-text, .img-card-title-text')?.textContent || '').trim() === tt
        && !e.querySelector('.expand-btn'));
    if (!card) return null;
    const el = card.querySelector('.item-title-text, .img-card-title-text') || card;
    el.scrollIntoView({ block: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, t);
  // 折叠组先展开（代表卡点标题不打开，必须先点 .expand-btn）
  let pt = null;
  for (let attempt = 0; attempt < 4 && !pt; attempt++) {
    pt = await titlePt(title);
    if (pt) break;
    const ex = await page.evaluate(() => {
      const b = document.querySelector('.expand-btn');
      if (!b) return null;
      b.scrollIntoView({ block: 'center' });
      const r = b.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    if (ex) { await page.mouse.click(ex.x, ex.y); await page.waitForTimeout(900); }
    else await page.waitForTimeout(500);
  }
  if (!pt) throw new Error('card not found: ' + title);
  await page.mouse.click(pt.x, pt.y);
  await page.waitForSelector('.editor-body', { timeout: 10000 });
  await page.waitForTimeout(1800);
};
const goBack = async () => {
  await page.click('.editor-fab.left');
  await page.waitForTimeout(1500);
};
const readStored = (title) => page.evaluate(async (t) => {
  const out = {};
  try {
    const arr = JSON.parse(localStorage.getItem('memos_app_v2') || '[]');
    const m = arr.find((x) => x.title === t);
    out.ls = m ? m.doc : null;
  } catch (e) { out.lsErr = String(e).slice(0, 80); }
  try {
    const db = await window.MynoteIdb.getDB();
    out.stores = [...db.objectStoreNames];
    for (const sn of out.stores) {
      const all = await new Promise((res, rej) => {
        const rq = db.transaction(sn, 'readonly').objectStore(sn).getAll();
        rq.onsuccess = () => res(rq.result); rq.onerror = () => rej(rq.error);
      });
      const m = (all || []).find((x) => x && x.title === t && Array.isArray(x.doc));
      if (m) { out.idb = m.doc; out.idbStore = sn; break; }
    }
  } catch (e) { out.idbErr = String(e).slice(0, 120); }
  return out;
}, title);
const selInfo = () => page.evaluate(() => {
  const s = getSelection();
  const el = s.anchorNode?.nodeType === 1 ? s.anchorNode : s.anchorNode?.parentElement;
  const blk = el?.closest?.('[data-blockid]');
  return { bid: blk?.dataset?.blockid || '', off: s.focusOffset, text: (s.anchorNode?.textContent || '').slice(0, 20) };
});

// ---- 甲：文末预览 → 尾随段形态 + 点击输入 + 落盘 ----
await openMemo('尾随甲');
let rows = await dumpBody();
L('ORIG A body', JSON.stringify(rows));
const trailA = rows[rows.length - 1];
if (trailA && trailA.tag === 'P' && !trailA.bid.startsWith('ta')) {
  const pt = await page.evaluate(() => {
    const body = document.querySelector('.editor-body');
    const p = body.querySelector(`[data-blockid="${document.querySelector('.editor-body [data-blockid]:last-of-type')?.dataset.blockid}"]`);
    const last = [...body.querySelectorAll('[data-blockid]')].pop();
    const r = last.getBoundingClientRect();
    return { x: r.x + 20, y: r.y + r.height / 2, bid: last.dataset.blockid };
  });
  await page.mouse.click(pt.x, pt.y);
  await page.waitForTimeout(400);
  L('ORIG A click-trail sel', JSON.stringify(await selInfo()));
  await page.keyboard.insertText('尾巴文字甲');
  await page.waitForTimeout(900);
  L('ORIG A after-type sel', JSON.stringify(await selInfo()));
}
await goBack();
const storedA = await readStored('尾随甲');
L('ORIG A stored ls', JSON.stringify(storedA.ls));
L('ORIG A stored idb', JSON.stringify(storedA.idb));

// ---- 丙：文末分割线 → init trail_ 推入；不编辑直接返回，看落盘 ----
await openMemo('尾随丙');
rows = await dumpBody();
L('ORIG C body', JSON.stringify(rows));
await goBack();
const storedC = await readStored('尾随丙');
L('ORIG C stored ls', JSON.stringify(storedC.ls));
L('ORIG C stored idb', JSON.stringify(storedC.idb));

// ---- 戊：相邻预览之间不补、文末补 ----
await openMemo('尾随戊');
rows = await dumpBody();
L('ORIG E body', JSON.stringify(rows));
await goBack();

// ---- 乙：预览→图片之间的尾随段；退格行为 + 输入落盘 ----
await openMemo('尾随乙');
rows = await dumpBody();
L('ORIG B body', JSON.stringify(rows));
const trailPt = await page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const kids = [...body.querySelectorAll('[data-blockid]')];
  const img = kids.find((e) => e.dataset.type === 'image');
  const prev = img?.previousElementSibling;
  const cand = prev && prev.tagName === 'P' && !['tb1', 'tb2', 'tb3'].includes(prev.dataset.blockid) ? prev : null;
  if (!cand) return null;
  const r = cand.getBoundingClientRect();
  return { x: r.x + 20, y: r.y + r.height / 2, bid: cand.dataset.blockid };
});
L('ORIG B trail pt', JSON.stringify(trailPt));
if (trailPt) {
  await page.mouse.click(trailPt.x, trailPt.y);
  await page.waitForTimeout(400);
  L('ORIG B click-trail sel', JSON.stringify(await selInfo()));
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(600);
  rows = await dumpBody();
  L('ORIG B after-backspace body', JSON.stringify(rows));
  L('ORIG B after-backspace sel', JSON.stringify(await selInfo()));
  await page.keyboard.insertText('乙尾巴');
  await page.waitForTimeout(900);
  L('ORIG B after-type sel', JSON.stringify(await selInfo()));
}
await goBack();
const storedB = await readStored('尾随乙');
L('ORIG B stored ls', JSON.stringify(storedB.ls));
L('ORIG B stored idb', JSON.stringify(storedB.idb));

// ---- 丁：表格预览 → 列表组之间 ----
await openMemo('尾随丁');
rows = await dumpBody();
L('ORIG D body', JSON.stringify(rows));
await goBack();

// ---- 己：对照（预览 → 普通段，不补） ----
await openMemo('尾随己');
rows = await dumpBody();
L('ORIG F body', JSON.stringify(rows));
await goBack();

await browser.close();
L('DONE');
