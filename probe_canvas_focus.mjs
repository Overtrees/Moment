// 专用探针：画布空白点按落焦（原版 .editor-body 单宿主原生
// 落焦的分块等价路由，桥 canvasFocusRoute）。
// 守的行为：
//  ① 新建空备忘（单空段）：点 body 盒内任意尾部空白（首行
//     下方 40/100px、body 底边）→ 选区落首段、打字落字；
//     多点位 × 两轮全过。
//  ② 有内容备忘：点文末末块下方 body 内空白 → 选区落文末
//     块末尾、打字落文末位（原版同点位实测落末块末尾、追
//     加落字，同口径）；文末为图片等原子块时尾随空段恒物
//     化、落其 0 位（②b 图片结尾备忘另测）。
//  ③ 不回归：点已有块仍原生落焦该块；点块间空隙（末单元
//     顶边之上）不被劫持到文末；点 body 盒外（.detail）不
//     落焦（与原版 spread 区点按无反应同口径）。
//  ④ Diag 落一行 canvas focus。
// 原版对照实测（同夹具同点位，Chromium 口径）：body 本体
// 点按 A1/A2/B1 皆落焦（空备忘落唯一空段、内容备忘落末块
// 末尾），body 盒外点按无反应——本探针判据与之同构。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import base64, json, zipfile
def para(bid, text):
    return {"id": bid, "type": "paragraph", "children": [{"text": text}]}
def memo(mid, title, doc):
    return {"id": mid, "title": title, "doc": doc, "pinned": False,
            "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00"}
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=")
memos = [
    memo("canvas-a", "画布空白甲", [para("ca1", "")]),
    memo("canvas-b", "画布内容乙", [para("cb1", "第一段文字。"), para("cb2", "第二段文字。"), para("cb3", "第三段文字。")]),
    memo("canvas-c", "画布尾随丙", [para("cc1", "首段文字。"),
        {"id": "cc2", "type": "image", "attrs": {"fileId": "attimg1"}, "children": [{"text": ""}]}]),
]
z = zipfile.ZipFile('/tmp/canvas_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": memos}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {"attimg1": {"name": "dot.png", "type": "image/png", "size": len(PNG)}}}, ensure_ascii=False))
z.writestr('attachments/attimg1', PNG)
z.close()
print('canvas_probe.zip ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
let fails = 0;
const ok = (name, cond, val) => { if (!cond) fails++; console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : '')); };

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
  await page.waitForFunction((t) => [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
    .some((e) => e.textContent.includes(t)), title, { timeout: 10000 });
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.evaluate((t) => {
      const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
        .find((e) => e.textContent.includes(t));
      if (el) el.click();
    }, title);
    try {
      await page.waitForSelector('.detail', { timeout: 6000 });
      break;
    } catch (e) {
      if (attempt === 1) throw e;
    }
  }
  await page.waitForTimeout(1000);
}
const goBack = async () => { await page.click('.editor-fab.left'); await page.waitForTimeout(900); };
const geom = () => page.evaluate(() => {
  const body = document.querySelector('.editor-body');
  const br = body.getBoundingClientRect();
  const units = [...body.querySelectorAll('[data-bid]')].map((el) => {
    const r = el.getBoundingClientRect();
    return { bid: el.dataset.bid, top: Math.round(r.top), bottom: Math.round(r.bottom), h: Math.round(r.height), text: (el.innerText || '').replace(/\n/g, '') };
  });
  return { body: { top: Math.round(br.top), bottom: Math.round(br.bottom), left: Math.round(br.left), width: Math.round(br.width) }, units };
});
const selBid = () => page.evaluate(() => {
  const s = getSelection();
  const el = s.anchorNode?.nodeType === 1 ? s.anchorNode : s.anchorNode?.parentElement;
  return el?.closest?.('[data-bid]')?.dataset?.bid || '';
});
const blurAll = () => page.evaluate(() => {
  getSelection().removeAllRanges();
  if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
});

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await importZip('/tmp/canvas_probe.zip');

// ── ① 空备忘：多点位 × 两轮 ──
await openMemoByTitle('画布空白甲');
for (let round = 1; round <= 2; round++) {
  const g = await geom();
  const first = g.units[0];
  const cx = g.body.left + g.body.width / 2;
  const points = [
    { name: `R${round} 首行下方40px`, y: first.bottom + 40 },
    { name: `R${round} 首行下方100px`, y: first.bottom + 100 },
    { name: `R${round} body底边`, y: g.body.bottom - 8 },
  ];
  for (const p of points) {
    await blurAll();
    await page.waitForTimeout(200);
    await page.mouse.click(cx, p.y);
    await page.waitForTimeout(300);
    ok(`空备忘 ${p.name} 落首段`, (await selBid()) === first.bid, await selBid());
    await page.keyboard.insertText('Z');
    await page.waitForTimeout(250);
    const txt = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', first.bid);
    ok(`空备忘 ${p.name} 打字落字`, txt.includes('Z'), txt);
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(200);
  }
}
// body 盒外（原版同口径：无反应）
{
  const g = await geom();
  const cx = g.body.left + g.body.width / 2;
  await blurAll();
  await page.waitForTimeout(200);
  await page.mouse.click(cx, g.body.bottom + 100);
  await page.waitForTimeout(300);
  ok('空备忘 body盒外点按不落焦（原版同口径）', (await selBid()) === '', await selBid());
  // 块上点按基线：点首行本身仍落焦
  const first = g.units[0];
  await page.mouse.click(cx, first.top + Math.max(2, first.h / 2));
  await page.waitForTimeout(300);
  ok('空备忘 点首行本身落焦（基线）', (await selBid()) === first.bid, await selBid());
}
await goBack();

// ── ② 内容备忘：文末空白落文末块末尾（原版同口径） ──
await openMemoByTitle('画布内容乙');
{
  const g = await geom();
  const cx = g.body.left + g.body.width / 2;
  const last = g.units[g.units.length - 1];
  await blurAll();
  await page.waitForTimeout(200);
  await page.mouse.click(cx, Math.min(last.bottom + 40, g.body.bottom - 6));
  await page.waitForTimeout(300);
  ok('内容备忘 文末空白落文末块', (await selBid()) === last.bid, await selBid());
  await page.keyboard.insertText('Z');
  await page.waitForTimeout(250);
  const txt = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', last.bid);
  ok('内容备忘 文末打字追末尾', txt === (last.text + 'Z'), txt);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(200);
  const txtBack = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', last.bid);
  ok('内容备忘 退格后文末块复原', txtBack === last.text, txtBack);
  // ③ 块间空隙不劫持：点第一/二段之间空隙，选区不得落尾随段
  const g2 = await geom();
  const u1 = g2.units[0], u2 = g2.units[1];
  await blurAll();
  await page.waitForTimeout(200);
  await page.mouse.click(cx, Math.round((u1.bottom + u2.top) / 2));
  await page.waitForTimeout(300);
  const gapSel = await selBid();
  ok('内容备忘 块间空隙不劫持到文末', gapSel !== last.bid, gapSel);
  // ③ 点已有块仍落该块
  await page.mouse.click(cx, u2.top + Math.max(2, u2.h / 2));
  await page.waitForTimeout(300);
  ok('内容备忘 点第二段落该段（基线）', (await selBid()) === u2.bid, await selBid());
  // ③ 跨块拖拽选区不被画布路由拽塌：拖拽收尾的 click
  // target 是共同祖先 body，与空白点按同形——守卫（手势
  // 起点在块内 + xsel 在场）必须拦下，选区锚点与虚拟选
  // 区高亮保持（B-8 同源回归）。
  const pt = async (bid, off) => page.evaluate(([b, o]) => {
    const el = document.querySelector(`[data-bid="${b}"]`);
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let n = walker.nextNode(); let acc = 0;
    while (n) { const len = n.textContent.length; if (acc + len >= o) {
      const r = document.createRange(); r.setStart(n, o - acc); r.collapse(true);
      const rect = r.getBoundingClientRect(); return { x: rect.left + 1, y: rect.top + rect.height / 2 };
    } acc += len; n = walker.nextNode(); }
    return null;
  }, [bid, off]);
  const p0 = await pt(u1.bid, 2); const p1 = await pt(last.bid, 2);
  await page.mouse.move(p0.x, p0.y); await page.mouse.down();
  await page.mouse.move(p1.x, p1.y, { steps: 12 }); await page.waitForTimeout(150); await page.mouse.up();
  await page.waitForTimeout(350);
  const dragState = await page.evaluate(() => {
    const s = getSelection();
    const el = s.anchorNode?.nodeType === 1 ? s.anchorNode : s.anchorNode?.parentElement;
    const hl = window.CSS && CSS.highlights && CSS.highlights.get('mn-xsel');
    return { anchor: el?.closest?.('[data-bid]')?.dataset?.bid || '', hl: hl ? hl.size : -1 };
  });
  ok('内容备忘 跨块拖拽选区不被画布路由拽塌', dragState.anchor === u1.bid && dragState.hl > 0, JSON.stringify(dragState));
}
await goBack();

// ── ②b 原子块结尾备忘：文末空白落物化的尾随空段 ──
await openMemoByTitle('画布尾随丙');
{
  const g = await geom();
  const cx = g.body.left + g.body.width / 2;
  const last = g.units[g.units.length - 1];
  ok('尾随丙 文末已物化尾随空段', last.bid !== 'cc1' && last.bid !== 'cc2' && last.text === '', last.bid);
  await blurAll();
  await page.waitForTimeout(200);
  await page.mouse.click(cx, Math.min(last.bottom + 40, g.body.bottom - 6));
  await page.waitForTimeout(300);
  ok('尾随丙 文末空白落尾随空段', (await selBid()) === last.bid, await selBid());
  await page.keyboard.insertText('Z');
  await page.waitForTimeout(250);
  const txt = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', last.bid);
  ok('尾随丙 打字落尾随空段', txt.includes('Z'), txt);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(200);
}
await goBack();

// ── ③b 宽屏双栏：栏解析与空栏回退 ──
{
  const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
  const page2 = await ctx2.newPage();
  page2.on('pageerror', (e) => errors.push(String(e)));
  await page2.goto(url, { waitUntil: 'load' });
  await page2.waitForSelector('.list-item', { timeout: 20000 });
  await page2.$eval('h1.page-title', (e) => e.click());
  await page2.waitForSelector('.page-content', { timeout: 8000 });
  await page2.click('.set-row:has-text("备份与恢复")');
  await page2.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page2.setInputFiles('#file-import', '/tmp/canvas_probe.zip');
  await page2.waitForSelector('.backup-modal', { timeout: 8000 });
  await page2.click('.backup-modal .backup-btn.primary');
  await page2.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page2.click('.editor-fab.left');
  await page2.waitForSelector('.seg-row', { timeout: 8000 });
  await page2.click('.editor-fab.left');
  await page2.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await page2.evaluate((t) => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes(t));
    if (el) el.click();
  }, '画布空白甲');
  await page2.waitForSelector('.detail', { timeout: 10000 });
  await page2.waitForTimeout(1000);
  const w = await page2.evaluate(() => {
    const body = document.querySelector('.editor-body');
    const cols = [...body.querySelectorAll(':scope > .editor-column')].map((c) => {
      const r = c.getBoundingClientRect();
      return { name: c.getAttribute('data-editor-column'), left: Math.round(r.left), right: Math.round(r.right), top: Math.round(r.top), bottom: Math.round(r.bottom) };
    });
    const first = body.querySelector('[data-bid]');
    const fr = first?.getBoundingClientRect();
    return { cols, firstBid: first?.dataset?.bid || '', firstBottom: fr ? Math.round(fr.bottom) : 0 };
  });
  ok('宽屏 双栏在场', w.cols.length === 2, JSON.stringify(w.cols.map((c) => c.name)));
  const selBid2 = () => page2.evaluate(() => {
    const s = getSelection();
    const el = s.anchorNode?.nodeType === 1 ? s.anchorNode : s.anchorNode?.parentElement;
    return el?.closest?.('[data-bid]')?.dataset?.bid || '';
  });
  const blur2 = () => page2.evaluate(() => {
    getSelection().removeAllRanges();
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
  });
  if (w.cols.length === 2) {
    const [lc, rc] = w.cols;
    await blur2();
    await page2.waitForTimeout(200);
    await page2.mouse.click((lc.left + lc.right) / 2, w.firstBottom + 80);
    await page2.waitForTimeout(300);
    ok('宽屏 左栏首段下方空白落首段', (await selBid2()) === w.firstBid, await selBid2());
    await blur2();
    await page2.waitForTimeout(200);
    await page2.mouse.click((rc.left + rc.right) / 2, rc.top + 120);
    await page2.waitForTimeout(300);
    ok('宽屏 空右栏点按回退落首段', (await selBid2()) === w.firstBid, await selBid2());
  }
  await ctx2.close();
}

// ── ④ Diag ──
const diagHas = await page.evaluate(() => {
  try {
    const raw = localStorage.getItem('mynote_diag_v1') || '';
    return raw.includes('canvas focus ->');
  } catch (e) { return false; }
});
ok('Diag 落 canvas focus 行', diagHas);
ok('无 pageerror', errors.length === 0, errors[0] || '');

await browser.close();
console.log(fails === 0 ? 'ALL PASS' : `FAILURES: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
