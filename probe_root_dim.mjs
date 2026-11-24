// 专用探针：根色口径（备份模态不压暗 + 图片页根色脱钩）+ 图片卡点按 rider。
// 取证定案（真机量测）：备份确认底表打开时视口内压暗均匀，但
// 布局视口下缘以下一条带呈未压暗实心浅栏——条带 = 根色原值、
// 压暗面 = 根色 ×(1−0.28)、分界恰在布局视口下缘；根因 = 根色
// 派生链的触发集不含模态开关，视口外只能由浏览器以根（html）
// 背景绘制而根色没跟随压暗。其后裁定 C 撤备份压暗、恢复集
// (b) 摘除灯箱预压暗登记，根色派生收口为页面状态纯函数。
// 判据变更（2026-11-24，图片独立页面化——用户拍板）：灯箱
// 浮层整套退役、改与列表/编辑/设置同级的独立图片页：
// .lightbox 标记/CSS/滚动锁/E-15 链灯箱条目/LBX 打点/
// LightboxPresence 镜像/DimStack 压暗栈/derive 派生输入
// 全部删除（verify 第 11 节 (ii) 已改 src 全域零残留锁）。
// 本探针随之改段：② 改图片页进出与根色脱钩、⑥ 改图片页
// 返回后离页窗口、⑦ 改图片页内根色随 scheme 走根页面
// 色；⑧（浮层安全区 padding 公式）、⑨（浮层滚动锁）、
// ⑩（LBX 派生快照与普查）三段整段删除；图片页专项判据
// （标题/自然尺寸/可滚/滚动恢复）由 probe_lightbox_page
// 守。DimStack 删除后 dim push/pop 恒缺席，①② 的缺席断
// 言保留（恒成立、守删除不回潮）。
// 守的行为：
//  ① 备份模态打开（裁定 C 后）→ 根色不被改写：变量保持
//     未设、html 仍 rgb(242,242,247)（--primary-bg 原值）；
//     scrim 计算背景 rgba(0,0,0,0)（transparent）；Diag 全
//     程无 dim push/pop backup-modal；取消关闭 → 根色仍
//     未设、html 不变。
//  ② 编辑页点图文卡图 → 进图片页：.img-page 在场、
//     .lightbox 不在场；图片页根色 = 根页面色（未设 /
//     rgb(242,242,247)），与编辑 base（#FAFAFA）脱钩；
//     Diag IMGPAGE open 带文件名 name=a.png；点页内返
//     回钮回编辑页 → 根色恢复编辑 base；全程无 dim
//     push/pop。
//  ③ rider：图片卡左滑开启态点按无操作（保持 -168、不打开
//     编辑页、Diag 记 row open-state tap noop）；滑回收起后
//     点按仍正常打开。
//  ④ 分层对账（头部口径，断言落在 ①② 内）：压暗基础设
//     施已整删、无任何层登记；备份确认层 scrim 计算背景
//     transparent、备份页根计算背景 = --primary-bg 原
//     值；图片页根色同为根页面色原值——页面区与底部带
//     （根色原值）齐平的耦合由 ①② 的根色断言钉住；视
//     口内采样像素（截图采样）= rgb(242,242,247)。
//  ⑥ 图片页返回后再离页回列表：离页窗口内页面状态仍
//     为编辑器（selected 保留至卸载帧），根色恒为编辑
//     base #FAFAFA（10ms 页内采样锁）；提交帧后回落列
//     表默认；离页后 CENSUS 全 imgp=0（图片页无残留）。
//     派生仍是页面状态纯函数、输入无离页特例（分界见
//     main.rs 派生注）。
//  ⑦ 图片页根色随 scheme 走根页面色：带 bgColor
//     #ffffff 的备忘开图片页 → 根色为根页面色浅色值
//     （未设/rgb(242,242,247)）、非 BG base；切深色 →
//     根色 = 根页面色深色值 rgb(0,0,0)（--primary-bg
//     深色 #000000）；切回浅色 → 回 242；返回编辑页 →
//     根色恢复 BG base #ffffff。前提：编辑器 scheme 分
//     支在槽位隐藏时不写根色（可见性自守），本段兼守
//     该自守不回归。
// 判据边界：无头只断言网页层量（CSS 变量与 html 计算背景），
// iOS 视口外 chrome 带区本身测不到，终判待真机。已知残差
// （浮层时代真机定案，历史记录）：状态栏带因子律 M2 已
// 于 2026-11-24 §10 取证被证伪（根色恒 250 时带仍 =0
// 纯黑，带由浏览器按视口边缘全屏黑元素自身派生）；浮
// 层退役后该残差失去对象，图片页真机终判点改为页头位
// 置/标题与原尺寸大图滚动手感。
// 用法: node probe_root_dim.mjs [baseURL]
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import base64, json, zipfile
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAGklEQVR42mP8z8BQz0BEwMDAwMDEwMDAAAAASUVORK5CYII=')
memo = {"id": "dim-memo", "title": "压暗探针", "pinned": False,
        "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00",
        "doc": [
            {"id": "dim-p1", "type": "paragraph", "children": [{"text": "首段文字"}]},
            {"id": "dim-itc", "type": "imgTextCard", "attrs": {"fileId": "imgA"}, "children": [{"text": "图文说明"}]},
            {"id": "dim-img", "type": "image", "attrs": {"fileId": "imgB"}, "children": []},
        ]}
memo_bg = {"id": "dim-memo-bg", "title": "深浅探针", "pinned": False, "bgColor": "#ffffff",
        "createdAt": "2026-11-21T10:00:00+08:00", "updatedAt": "2026-11-21T10:00:00+08:00",
        "doc": [
            {"id": "dim-p2", "type": "paragraph", "children": [{"text": "带背景色首段"}]},
            {"id": "dim-img2", "type": "image", "attrs": {"fileId": "imgB"}, "children": []},
        ]}
z = zipfile.ZipFile('/tmp/dim_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo, memo_bg]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {
    "imgA": {"name": "a.png", "type": "image/png"},
    "imgB": {"name": "b.png", "type": "image/png"}}}))
z.writestr('attachments/imgA', PNG)
z.writestr('attachments/imgB', PNG)
z.close()
print('dim_probe.zip ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

let pass = 0, fail = 0;
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ok', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}

const rootState = () => page.evaluate(() => {
  const cs = getComputedStyle(document.documentElement);
  return { varBg: cs.getPropertyValue('--mn-root-bg').trim(), htmlBg: cs.backgroundColor };
});
const diagText = () => page.evaluate(() => localStorage.getItem('mynote_diag_v1') || '');
const count = (s, sub) => s.split(sub).length - 1;
// Diag 落盘为 1s 节流合并写（批10 T-F）：动作后固定短等再读
// localStorage 会落在节流窗内假红/假过。正向断言改轮询等目标
// 行落盘后仍按原判据断言；缺席断言先等落盘静默（连续两次读
// 间隔 ≥1.2s 内容不变）再读。只改读取时序，不放宽判据。
async function waitDiag(pred, timeoutMs = 6000) {
  const t0 = Date.now();
  let txt = await diagText();
  while (!pred(txt) && Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(200);
    txt = await diagText();
  }
  return txt;
}
async function waitDiagSettle(timeoutMs = 6000) {
  const t0 = Date.now();
  let prev = await diagText();
  while (Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(1200);
    const cur = await diagText();
    if (cur === prev) return cur;
    prev = cur;
  }
  return prev;
}
async function waitRoot(want, label) {
  try {
    await page.waitForFunction((w) => {
      const cs = getComputedStyle(document.documentElement);
      return cs.getPropertyValue('--mn-root-bg').trim() === w.varBg && cs.backgroundColor === w.htmlBg;
    }, want, { polling: 150, timeout: 8000 });
    return true;
  } catch { console.log('  waitRoot timeout:', label, 'want', JSON.stringify(want), 'got', JSON.stringify(await rootState())); return false; }
}

async function importZip(zipPath) {
  await page.goto(url, { waitUntil: 'load' });
  // goto 的 load 只等文档加载，SPA 首帧未必已渲染出标题——先等节点
  // 出现再 $eval 取用（与本 helper 其余等待同口径 8000ms），否则状态
  // 依赖下 $eval 确定性找不到节点而崩。
  await page.waitForSelector('h1.page-title', { timeout: 8000 });
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', zipPath);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { polling: 200, timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
}

await importZip('/tmp/dim_probe.zip');

// ① 备份模态不压暗（裁定 C：透明遮罩、根色不改写）
{
  const base0 = await rootState();
  ok('① 列表基线：变量未设、html = rgb(242, 242, 247)', base0.varBg === '' && base0.htmlBg === 'rgb(242, 242, 247)', JSON.stringify(base0));
  const diag0 = await diagText();
  const push0 = count(diag0, 'dim push backup-modal'), pop0 = count(diag0, 'dim pop backup-modal');
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('.backup-row:has-text("导出备份")', { timeout: 8000 });
  await page.click('.backup-row:has-text("导出备份")');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  ok('① 模态打开根色不改写：变量未设、html 仍 rgb(242, 242, 247)',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'modal-open'));
  const diag1 = await diagText();
  ok('① Diag 无 dim push backup-modal（裁定 C 注销登记）', count(diag1, 'dim push backup-modal') === push0);
  ok('① DimStack 无备份层登记（push/pop 净差为 0）',
    (count(diag1, 'dim push backup-modal') - count(diag1, 'dim pop backup-modal')) - (push0 - pop0) === 0,
    `push=${count(diag1, 'dim push backup-modal')} pop=${count(diag1, 'dim pop backup-modal')}`);
  const layerInfo = await page.evaluate(() => {
    const scrim = document.querySelector('.backup-modal-scrim');
    const root = scrim ? scrim.parentElement : null;
    return {
      scrimBg: scrim ? getComputedStyle(scrim).backgroundColor : '',
      rootBg: root ? getComputedStyle(root).backgroundColor : '',
    };
  });
  ok('① scrim 计算背景 transparent rgba(0, 0, 0, 0)（原版 fixedOverlay 口径）',
    layerInfo.scrimBg === 'rgba(0, 0, 0, 0)', layerInfo.scrimBg);
  ok('① 备份页根底色 = --primary-bg rgb(242, 242, 247)（透明 scrim 视口内底，与派生 base 同值）',
    layerInfo.rootBg === 'rgb(242, 242, 247)', layerInfo.rootBg);
  // 采样像素：截图采样视口左缘（x=8 在 .page-content 20px
  // 内距之外、卡片不覆盖；y=300 为页面底色区）；scrim 已
  // 透明，采样到的即未压暗页色本身。
  await page.waitForTimeout(300);
  const shot = await page.screenshot();
  const px = await page.evaluate(async (b64) => {
    const img = new Image();
    img.src = 'data:image/png;base64,' + b64;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    const d = g.getImageData(8, 300, 1, 1).data;
    return [d[0], d[1], d[2]];
  }, shot.toString('base64'));
  ok('① 采样像素 = rgb(242, 242, 247)±2（未压暗页色）',
    Math.abs(px[0] - 242) <= 2 && Math.abs(px[1] - 242) <= 2 && Math.abs(px[2] - 247) <= 2,
    JSON.stringify(px));
  await page.click('.backup-modal .backup-btn.secondary');
  await page.waitForFunction(() => !document.querySelector('.backup-modal'), null, { polling: 200, timeout: 8000 });
  ok('① 模态关闭后根色仍未设、html 保持 rgb(242, 242, 247)',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'modal-close'));
  const diag2 = await diagText();
  ok('① Diag 无 dim pop backup-modal', count(diag2, 'dim pop backup-modal') === pop0);
  // 回列表
  await page.click('.editor-fab.left');
  await page.waitForSelector('.seg-row', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
}

// ③ rider：图片卡左滑开启态点按无操作
{
  const row = page.locator('.img-card', { hasText: '压暗探针' }).first();
  await row.waitFor({ timeout: 8000 });
  const box = await row.boundingBox();
  const cx = box.x + box.width / 2, cy = box.y + box.height / 2;
  const txOf = () => row.evaluate((el) => {
    const m = getComputedStyle(el).transform.match(/matrix\(([^)]+)\)/);
    return m ? parseFloat(m[1].split(',')[4]) : 0;
  });
  await page.mouse.move(cx, cy);
  await page.mouse.down();
  for (let i = 1; i <= 6; i++) { await page.mouse.move(cx - 22 * i, cy); await page.waitForTimeout(30); }
  await page.mouse.up();
  await page.waitForTimeout(500);
  const txOpen = await txOf();
  ok('③ 左滑开启（tx = -168）', Math.abs(txOpen + 168) < 1.5, `tx=${txOpen}`);
  // 手势坐标按元素当前位置重取（根因修正，断言不变）：卡已
  // 平移 −168px，closed 态单次捕获的中心点对开启态卡只剩尾缘
  // ~12px 余量，且本段紧接页面交接进场动画、单次捕获易过期
  // ——点按会落进 actions 死区不达卡（Diag 红），右滑首步
  // （+22px）即越出未动的卡面、元素级 pointer 处理收不到
  // 后续 move（右滑红）。改从开启态实测中心点按/起滑。
  const openBox = await row.boundingBox();
  const ocx = openBox.x + openBox.width / 2, ocy = openBox.y + openBox.height / 2;
  const diag0 = await diagText();
  await page.mouse.click(ocx, ocy);
  await page.waitForTimeout(600);
  const txAfterTap = await txOf();
  ok('③ 开启态点按无操作：仍 -168', Math.abs(txAfterTap + 168) < 1.5, `tx=${txAfterTap}`);
  ok('③ 开启态点按不打开编辑页', (await page.$('.detail')) === null);
  const diagTap = await waitDiag((t) => count(t, 'row open-state tap noop') > count(diag0, 'row open-state tap noop'));
  ok('③ Diag 记 row open-state tap noop', diagTap.includes('row open-state tap noop') && count(diagTap, 'row open-state tap noop') > count(diag0, 'row open-state tap noop'));
  // 滑回收起
  await page.mouse.move(ocx, ocy);
  await page.mouse.down();
  for (let i = 1; i <= 6; i++) { await page.mouse.move(ocx + 22 * i, ocy); await page.waitForTimeout(30); }
  await page.mouse.up();
  await page.waitForTimeout(500);
  const txClosed = await txOf();
  ok('③ 右滑收起（tx = 0）', Math.abs(txClosed) < 1.5, `tx=${txClosed}`);
}

// ② 编辑页点图进图片页：根色与编辑 base 脱钩（页面口径）
{
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes('压暗探针'));
    if (el) el.click();
  });
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(800);
  const ed0 = await rootState();
  ok('② 编辑基线：--mn-root-bg = #FAFAFA、html = rgb(250, 250, 250)',
    ed0.varBg.toLowerCase() === '#fafafa' && ed0.htmlBg === 'rgb(250, 250, 250)', JSON.stringify(ed0));
  const zone = await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="dim-itc"]');
    const el = w ? w.querySelector('.itc-img-wrap img') : null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  ok('② 图文卡图片区可定位', !!zone);
  const dimPush0 = count(await diagText(), 'dim push');
  const dimPop0 = count(await diagText(), 'dim pop');
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(300);
  ok('② 进图片页：.img-page 在场、.lightbox 不在场（浮层已退役）',
    (await page.$('.img-page')) !== null && (await page.$('.lightbox')) === null);
  ok('② 图片页根色 = 根页面色（未设 / rgb(242, 242, 247)），与编辑 base 脱钩',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'imgpage-open'));
  const diagImg = await waitDiag((t) => t.includes('IMGPAGE open'));
  ok('② Diag IMGPAGE open 带文件名 name=a.png（图文卡附件名）',
    /IMGPAGE open name=a\.png/.test(diagImg), diagImg.slice(-200));
  await page.click('.img-page .editor-fab.left');
  await page.waitForSelector('.detail', { timeout: 8000 });
  ok('② 返回编辑页根色恢复编辑 base #FAFAFA',
    await waitRoot({ varBg: ed0.varBg, htmlBg: 'rgb(250, 250, 250)' }, 'imgpage-back'));
  await waitDiagSettle();
  const diagEnd = await diagText();
  ok('② 全程无 dim push/pop（压暗栈已整删、恒缺席）',
    count(diagEnd, 'dim push') === dimPush0 && count(diagEnd, 'dim pop') === dimPop0);
}

// ⑥ 图片页返回后再离页回列表：离页窗口根色恒编辑 base、
// 提交后回落列表默认；离页后 CENSUS 全 imgp=0
{
  const zone = await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="dim-itc"]');
    const el = w ? w.querySelector('.itc-img-wrap img') : null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  ok('⑥ 图文卡图片区可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(300);
  await page.click('.img-page .editor-fab.left');
  await page.waitForSelector('.detail', { timeout: 8000 });
  const edBase6 = await rootState();
  ok('⑥ 图片页返回编辑页、根色恢复编辑 base',
    await waitRoot({ varBg: edBase6.varBg, htmlBg: 'rgb(250, 250, 250)' }, 'img-back-editor'));
  // 离页窗口采样（10ms 页内轮询，硬顶 600 样本防泄漏到
  // 后段）：记录 (离页层在场, 根色变量) 序列，锁瞬态口径。
  await page.evaluate(() => {
    window.__lbSamples = [];
    const timer = setInterval(() => {
      window.__lbSamples.push({
        lv: !!document.querySelector('.editor-stage.leaving'),
        v: document.documentElement.style.getPropertyValue('--mn-root-bg').trim(),
      });
      if (window.__lbSamples.length >= 600) clearInterval(timer);
    }, 10);
    window.__lbTimer = timer;
  });
  await page.click('.editor-fab.left');
  await page.waitForFunction(() => !document.querySelector('#editor-root'), null, { polling: 200, timeout: 10000 });
  const lbSamples = await page.evaluate(() => {
    clearInterval(window.__lbTimer);
    return window.__lbSamples || [];
  });
  const lvSamples = lbSamples.filter((s) => s.lv);
  ok('⑥ 离页窗口内根色恒为编辑 base #FAFAFA（提交点后移：状态仍为编辑器）',
    lvSamples.length > 0 && lvSamples.every((s) => s.v.toLowerCase() === '#fafafa'),
    `n=${lvSamples.length} vals=${[...new Set(lvSamples.map((s) => s.v))].join(',') || '无'}`);
  ok('⑥ 编辑器卸载后根色回落列表默认（未设 / rgb(242, 242, 247)）',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'leave-after-imgpage'));
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await waitDiagSettle();
  const rawDiag = await diagText();
  let diagLines;
  try { const a = JSON.parse(rawDiag); diagLines = Array.isArray(a) ? a : rawDiag.split('\n'); }
  catch { diagLines = rawDiag.split('\n'); }
  const cens = diagLines.filter((l) => l.includes('CENSUS'));
  const lastCens = cens.length ? cens[cens.length - 1] : '';
  ok('⑥ 离页后 CENSUS 图片页无残留（imgp=0）',
    lastCens.includes('imgp=0'), lastCens.slice(-180));
}

// ⑦ 图片页根色随 scheme 走根页面色（与编辑 base 无关）
{
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
      .find((e) => e.textContent.includes('深浅探针'));
    if (el) el.click();
  });
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(800);
  ok('⑦ BG 备忘编辑基线：根色 #ffffff / rgb(255, 255, 255)',
    await waitRoot({ varBg: '#ffffff', htmlBg: 'rgb(255, 255, 255)' }, 'bg-editor-base'));
  const zone = await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="dim-img2"]');
    const el = w ? w.querySelector('img') : null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  ok('⑦ BG 备忘图片可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 });
  await page.waitForTimeout(300);
  ok('⑦ 图片页根色 = 根页面色浅色值（未设 / rgb(242, 242, 247)），非 BG base #ffffff',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'imgpage-root-light'));
  await page.emulateMedia({ colorScheme: 'dark' });
  ok('⑦ 深色下图片页根色 = 根页面色深色值 rgb(0, 0, 0)（--primary-bg 深色）',
    await waitRoot({ varBg: '', htmlBg: 'rgb(0, 0, 0)' }, 'imgpage-root-dark'));
  await page.emulateMedia({ colorScheme: 'light' });
  ok('⑦ 切回浅色图片页根色回 rgb(242, 242, 247)',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'imgpage-root-light2'));
  await page.click('.img-page .editor-fab.left');
  await page.waitForSelector('.detail', { timeout: 8000 });
  ok('⑦ 返回编辑页根色恢复 BG base #ffffff',
    await waitRoot({ varBg: '#ffffff', htmlBg: 'rgb(255, 255, 255)' }, 'bg-editor-back'));
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
}

await browser.close();
console.log(`\nprobe_root_dim: ${pass} pass, ${fail} fail`);
if (fail === 0) console.log('ALL PASS');
process.exit(fail === 0 ? 0 : 1);
