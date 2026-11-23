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
//     顶边之上）不被劫持到文末。
//  ⑥ 落焦区域扩展（用户 2026-11-23 新规，覆盖原先与原版
//     一致的盒边界——原 ③「点 body 盒外（.detail）不落焦」
//     断言就此作废）：空备忘点旧盒外 y≈500/700（.detail 背
//     景区）→ 落焦首段 + Diag (detailbg) +1 + 落字可入
//     （鼠标与 CDP 触摸各验）；有内容备忘点末块下方背景
//     区 → 落文末块末尾；点头部带（坞穿透区、坞下缘之
//     上）→ 不落焦正文、Diag +0。新点位先以
//     elementFromPoint 自检落点确为 .detail 背景，防布局
//     变化下断言测错对象。
//  ④ Diag 落一行 canvas focus。
//  ⑤ 手势主路（触发前移到 pointerup 手势内同步落焦，真机
//     定案：合成 click 非可信手势、click 阶段落焦不带键
//     盘）：CDP 触摸点按落焦且 Diag 恰 +1（主路 + click
//     去重）、合成 PointerEvent 单独驱动主路落焦、CDP 触
//     摸滚动 60px 不落焦（位移判据）。Chromium 口径仅验接
//     线/判别/去重，键盘与光标终判不在此口径内。
// 原版对照实测（同夹具同点位，Chromium 口径）：body 本体
// 点按 A1/A2/B1 皆落焦（空备忘落唯一空段、内容备忘落末块
// 末尾）——盒内判据与之同构；盒外区域原版无反应，本版按
// 用户 2026-11-23 新规扩展落焦（有意偏离，同标题胶囊的
// 用户规格豁免口径），见 ⑥。
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
// 块上点按基线：点首行本身仍落焦（盒外区域断言移入 ⑥：
// 原「body 盒外不落焦」已被用户 2026-11-23 新规覆盖）
{
  const g = await geom();
  const cx = g.body.left + g.body.width / 2;
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

// ── ⑤ 手势主路：pointerup 同步落焦 + click 去重 + 位移判据 ──
await openMemoByTitle('画布空白甲');
{
  const diagCount = () => page.evaluate(() => {
    try {
      const raw = localStorage.getItem('mynote_diag_v1') || '';
      return (raw.match(/canvas focus ->/g) || []).length;
    } catch (e) { return -1; }
  });
  const g = await geom();
  const first = g.units[0];
  const cx = g.body.left + g.body.width / 2;
  const ty = first.bottom + 60;
  const cdp = await ctx.newCDPSession(page);
  // ⑤a CDP 触摸点按：主路落焦、Diag 恰 +1、打字落字
  await blurAll();
  await page.waitForTimeout(200);
  const d0 = await diagCount();
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: cx, y: ty, id: 1 }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await page.waitForTimeout(400);
  ok('⑤a 触摸点按尾部空白落首段（pointerup 主路）', (await selBid()) === first.bid, await selBid());
  const dA = (await diagCount()) - d0;
  ok('⑤a Diag canvas focus 恰 +1（合成 click 已去重）', dA === 1, String(dA));
  await page.keyboard.insertText('Z');
  await page.waitForTimeout(250);
  const txtA = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', first.bid);
  ok('⑤a 触摸点按后打字落字', txtA.includes('Z'), txtA);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(200);
  // ⑤b 合成 PointerEvent 单独驱动（不派 click）：主路不依赖 click
  await blurAll();
  await page.waitForTimeout(200);
  const d1 = await diagCount();
  await page.evaluate(([x, y]) => {
    const body = document.querySelector('.editor-body');
    const opts = { bubbles: true, composed: true, pointerId: 9, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y };
    body.dispatchEvent(new PointerEvent('pointerdown', opts));
    body.dispatchEvent(new PointerEvent('pointerup', opts));
  }, [cx, ty]);
  await page.waitForTimeout(300);
  ok('⑤b 合成 PointerEvent 单独驱动主路落焦', (await selBid()) === first.bid, await selBid());
  const dB = (await diagCount()) - d1;
  ok('⑤b Diag canvas focus +1', dB === 1, String(dB));
  // ⑤c CDP 触摸纵向滚动 60px：位移判据拦下、不落焦
  await blurAll();
  await page.waitForTimeout(200);
  const d2 = await diagCount();
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: cx, y: ty, id: 1 }] });
  for (let i = 1; i <= 4; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: cx, y: ty - i * 15, id: 1 }] });
    await page.waitForTimeout(40);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await page.waitForTimeout(400);
  ok('⑤c 触摸滚动 60px 不落焦', (await selBid()) === '', await selBid());
  const dC = (await diagCount()) - d2;
  ok('⑤c Diag canvas focus +0', dC === 0, String(dC));
  await cdp.detach();
}

// ── ⑥ 落焦区域扩展（用户 2026-11-23 新规）：头部以下全屏 ──
// ⑥a 空备忘旧盒外背景区落首段（鼠标 y=500/700 + 触摸 y=600）
{
  const diagBg = () => page.evaluate(() => {
    try {
      const raw = localStorage.getItem('mynote_diag_v1') || '';
      // bg 逐条计数：Diag 是单行 JSON 串，对原文用带 .* 的 /g 正则会被
      // 贪婪匹配把 N 次出现吞成 1 个，故解析数组后逐条 test（all 的无 .*
      // 子串计数无此病、保持原文计数）。
      const lines = JSON.parse(raw || '[]');
      return {
        all: (raw.match(/canvas focus ->/g) || []).length,
        bg: lines.filter((l) => /canvas focus -> .*\(detailbg\)/.test(l)).length,
      };
    } catch (e) { return { all: -1, bg: -1 }; }
  });
  const g = await geom();
  const first = g.units[0];
  const cx = g.body.left + g.body.width / 2;
  const hitBg = (y) => page.evaluate((yy) => {
    const el = document.elementFromPoint(innerWidth / 2, yy);
    return !!el && !!el.closest('.detail') && !el.closest('.editor-body') && !el.closest('[data-bid]');
  }, y);
  ok('⑥a 前提 y=500 落点为 detail 背景（body 盒外）', await hitBg(500));
  ok('⑥a 前提 y=700 落点为 detail 背景（body 盒外）', await hitBg(700));
  for (const y of [500, 700]) {
    await blurAll();
    await page.waitForTimeout(200);
    const d0 = await diagBg();
    await page.mouse.click(cx, y);
    await page.waitForTimeout(300);
    ok(`⑥a 空备忘 背景区 y=${y} 落首段`, (await selBid()) === first.bid, await selBid());
    const d1 = await diagBg();
    ok(`⑥a y=${y} Diag detailbg +1（且总行 +1）`, d1.bg - d0.bg === 1 && d1.all - d0.all === 1, `${d0.bg}->${d1.bg}`);
    await page.keyboard.insertText('Z');
    await page.waitForTimeout(250);
    const txt = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', first.bid);
    ok(`⑥a y=${y} 打字落字`, txt.includes('Z'), txt);
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(200);
  }
  // CDP 触摸点背景区：pointerup 主路 + 回声纪律（Diag 恰 +1）
  const cdp = await ctx.newCDPSession(page);
  await blurAll();
  await page.waitForTimeout(200);
  const d0 = await diagBg();
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: cx, y: 600, id: 1 }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await page.waitForTimeout(400);
  ok('⑥a 触摸 背景区 y=600 落首段（pointerup 主路）', (await selBid()) === first.bid, await selBid());
  const d1 = await diagBg();
  ok('⑥a 触摸 Diag detailbg 恰 +1', d1.bg - d0.bg === 1 && d1.all - d0.all === 1, `${d0.bg}->${d1.bg}`);
  await cdp.detach();
  // ⑥c 头部带（坞穿透区、坞下缘之上）不落焦正文：坞
  // pointer-events:none，落点穿透到 .editor-pad——须由几
  // 何边界（坞下缘）拦下。点位取坞水平范围内左侧（避开
  // 居中头像与左 fab），前提自检落点确为 detail 背景。
  const dock = await page.evaluate(() => {
    const r = document.querySelector('.editor-title-dock').getBoundingClientRect();
    return { left: Math.round(r.left), top: Math.round(r.top), bottom: Math.round(r.bottom) };
  });
  const hx = dock.left + 30;
  const hy = dock.top + 15;
  const hitHead = await page.evaluate(([x, y]) => {
    const el = document.elementFromPoint(x, y);
    return !!el && !!el.closest('.detail') && !el.closest('.editor-body') && !el.closest('[data-bid]')
      && !el.closest('button, a, input, label');
  }, [hx, hy]);
  ok('⑥c 前提 头部带落点为 detail 背景（坞穿透区）', hitHead, `${hx},${hy} dockBottom=${dock.bottom}`);
  await blurAll();
  await page.waitForTimeout(200);
  const h0 = await diagBg();
  await page.mouse.click(hx, hy);
  await page.waitForTimeout(300);
  ok('⑥c 头部带点按不落焦正文', (await selBid()) === '', await selBid());
  const h1 = await diagBg();
  ok('⑥c Diag canvas focus +0', h1.all - h0.all === 0, `${h0.all}->${h1.all}`);
}
await goBack();

// ⑥b 有内容备忘：末块下方背景区落文末块末尾
await openMemoByTitle('画布内容乙');
{
  const diagBg = () => page.evaluate(() => {
    try {
      const raw = localStorage.getItem('mynote_diag_v1') || '';
      // bg 逐条计数：Diag 是单行 JSON 串，对原文用带 .* 的 /g 正则会被
      // 贪婪匹配把 N 次出现吞成 1 个，故解析数组后逐条 test（all 的无 .*
      // 子串计数无此病、保持原文计数）。
      const lines = JSON.parse(raw || '[]');
      return {
        all: (raw.match(/canvas focus ->/g) || []).length,
        bg: lines.filter((l) => /canvas focus -> .*\(detailbg\)/.test(l)).length,
      };
    } catch (e) { return { all: -1, bg: -1 }; }
  });
  const g = await geom();
  const cx = g.body.left + g.body.width / 2;
  const last = g.units[g.units.length - 1];
  const y = Math.min(last.bottom + 160, 820);
  const hitBg = await page.evaluate((yy) => {
    const el = document.elementFromPoint(innerWidth / 2, yy);
    return !!el && !!el.closest('.detail') && !el.closest('.editor-body') && !el.closest('[data-bid]');
  }, y);
  ok('⑥b 前提 落点为 detail 背景（末块下方）', hitBg, `y=${y}`);
  await blurAll();
  await page.waitForTimeout(200);
  const d0 = await diagBg();
  await page.mouse.click(cx, y);
  await page.waitForTimeout(300);
  ok('⑥b 内容备忘 末块下方背景区落文末块', (await selBid()) === last.bid, await selBid());
  const atEnd = await page.evaluate((bid) => {
    const s = getSelection();
    const el = document.querySelector(`[data-bid="${bid}"]`);
    if (!s.anchorNode || !el || !el.contains(s.anchorNode)) return false;
    if (s.anchorNode === el) return s.anchorOffset === el.childNodes.length;
    return s.anchorOffset === (s.anchorNode.textContent || '').length;
  }, last.bid);
  ok('⑥b 光标落文末块末尾', atEnd);
  const d1 = await diagBg();
  ok('⑥b Diag detailbg +1', d1.bg - d0.bg === 1 && d1.all - d0.all === 1, `${d0.bg}->${d1.bg}`);
  await page.keyboard.insertText('Z');
  await page.waitForTimeout(250);
  const txt = await page.evaluate((bid) => document.querySelector(`[data-bid="${bid}"]`)?.innerText || '', last.bid);
  ok('⑥b 打字追文末尾', txt === last.text + 'Z', txt);
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
