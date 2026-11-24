// 专用探针：安全区实心栏根治（根色压暗跟随）+ 图片卡点按 rider。
// 取证定案（真机量测）：备份确认底表打开时视口内压暗均匀，但
// 布局视口下缘以下一条带呈未压暗实心浅栏——条带 = 根色原值、
// 压暗面 = 根色 ×(1−0.28)、分界恰在布局视口下缘；根因 = 根色
// 派生链的触发集不含模态开关，视口外只能由浏览器以根（html）
// 背景绘制而根色没跟随压暗。修法：App 层 DimStack（context）
// 登记全站真压暗层（备份模态 α0.28 / 灯箱 α0.88，DimLayer +
// use_hook Drop 守卫同步入栈出栈），根色派生增读该输入，栈非
// 空时把 base 向黑按 max α 混合成等效实色经 apply_root_bg 单
// 点写入；压暗呈现本身不改。（其后两登记先后按裁定 C 与
// 恢复集 (b) 摘除，DimStack 现无注册者、派生恒基色，本
// 探针现锁「不压暗」口径，见下判据变更两注。）
// 判据变更（2026-11-23 用户裁定 C）：备份确认弹窗撤掉 0.28
// 压暗、对齐原版透明遮罩（fixedOverlay background:
// transparent）——备份 scrim 改 transparent、其 DimLayer 注
// 册注销。① 段期望随之改（见下）。被替换的旧期望（#13 口
// 径，留注可溯）：① 打开 → 根色 #aeaeb2 / html
// rgb(174,174,178)、Diag dim push/pop backup-modal 各 +1、
// 栈深恰 1、scrim rgba(0,0,0,0.28)、合成像素
// rgb(174,174,178)；关闭 → 变量撤除、html 回
// rgb(242,242,247)、Diag dim pop +1。
// 判据变更（2026-11-23 晚，恢复集 (b)）：灯箱的根色预压暗
// 登记亦摘除——开灯箱不再预压暗根色，视口外带区由浏览器
// 以根色（编辑页基色）叠灯箱遮罩因子单独作用（真机判读）。
// DimStack 基础设施保留、现无注册者，派生恒基色。②④⑥⑦
// 段期望随之翻转（见下）；被替换的旧期望（留注可溯）：
// ② 开灯箱根色 #1e1e1e + dim push/pop lightbox、⑥ 离页窗
// 口恒 #1e1e1e + 卸载 dim pop 恰 +1、⑦ 浅色压暗 #1f1f1f /
// 深色压暗 #0b0b0b。灯箱自身 0.88 遮罩样式、几何、滚动锁
// 诸段断言不变。
// 守的行为：
//  ① 备份模态打开（裁定 C 后）→ 根色不被改写：变量保持
//     未设、html 仍 rgb(242,242,247)（--primary-bg 原值）；
//     scrim 计算背景 rgba(0,0,0,0)（transparent）；Diag 全
//     程无 dim push/pop backup-modal；取消关闭 → 根色仍
//     未设、html 不变。
//  ② 编辑页开灯箱 → 根色保持编辑 base 不压暗（#FAFAFA、
//     html rgb(250,250,250)），Diag 无 dim push lightbox；
//     灯箱自身 scrim 仍 rgba(0,0,0,0.88)（其样式不变）；
//     关灯箱 → 根色不变、无 dim pop lightbox。
//  ③ rider：图片卡左滑开启态点按无操作（保持 -168、不打开
//     编辑页、Diag 记 row open-state tap noop）；滑回收起后
//     点按仍正常打开。
//  ④ 分层对账（2026-11-23 真机顶带色差取证补，备份侧随
//     裁定 C、灯箱侧随恢复集 (b) 更新）：灯箱与备份确认层
//     均不在 DimStack 登记（栈恒空）；灯箱 scrim 计算背景
//     为其自身样式 rgba(0,0,0,0.88)；备份确认层不登记、scrim 计算
//     背景为 transparent；备份页根的计算背景 =
//     --primary-bg 原值——它是透明 scrim 在视口内的底，
//     根色派生对非编辑页的 base 假设（primary_bg_value）
//     必须与之同值，页面区与底部带（根色原值）才齐平，此
//     断言把该耦合钉住；视口内采样像素（截图采样）=
//     rgb(242,242,247)，即用户实际看到的未压暗页色。
//  ⑤ 灯箱几何（2026-11-23 灯箱截图定案补）：灯箱层须四边
//     锚定（inset:0，与原版 src/app/editor.js 及备份 scrim
//     同口径）覆盖整个布局视口——此前 height:100lvh 定高
//     在真机量得盒底停在视口 735/754、末 19pt 无覆盖、图
//     心上偏 9.5pt。本断言锁 rect 与布局视口的覆盖关系；
//     无头 Chromium 无动态工具栏、100lvh 恰等于视口高，
//     对旧写法在无头口径下不具区分力，区分力在真机。
//  ⑥ 异常退出路径（2026-11-23 灯箱三面排查补，恢复集
//     (b) 后更新）：灯箱开着时离页（程序化点返回钮——UI
//     路径下灯箱罩全屏、返回钮点不到，此为网页层唯一可
//     达的「开着灯箱卸载编辑器」路径）→ 根色全程不压暗、
//     卸载后回落列表未设/rgb(242,242,247)，Diag 无 dim
//     pop lightbox（登记摘除后无出栈行；原断言「pop 恰
//     +1、缺失即粘 #1e1e1e」随预压暗摘除失去对象）。
//     离页窗口口径（同日晚白带根治终版，提交点后移）：离
//     页窗口内页面状态仍为编辑器（selected 保留至卸载
//     帧），根色恒为编辑 base #FAFAFA；提交帧状态翻转与
//     卸载同任务落定、其后回落列表默认。派生仍是页面状
//     态纯函数、输入无离页特例（分界见 main.rs 派生注）。
//     本段以 10ms 页内采样锁此口径。
//  ⑦ 灯箱开着切深浅色（同日排查补，恢复集 (b) 后翻
//     转）：带 bgColor #ffffff 的备忘开灯箱 → 根色保持
//     #ffffff 不压暗；emulateMedia 切深色 → 根色须为
//     scheme 深色 base #595959（darken #ffffff，rgb(89,
//     89,89)）——灯箱不再压暗后，编辑器 scheme 分支写未
//     压暗值即为正值（旧口径曾要求其写压暗同值 #0b0b0b、
//     停在 #595959 即红，现反转）；切回浅色 → 回
//     #ffffff；关灯箱 → 仍 #ffffff。
//  ⑧ 灯箱内容面安全区公式（同日用户浮层自适配口径补）：
//     .lightbox 计算 padding 四边在 env=0（无头/标签页形
//     态）下恒为 20px（与旧平值等价）；样式规则文本须含
//     max(20px, env(safe-area-inset-*)) 四边公式——env 非
//     0 的 standalone 形态无头测不到，公式在位 + env=0
//     等价两条即网页层可锁的全部，终判待真机 PWA 形态。
//  ⑨ 灯箱背景滚动锁（2026-11-23 用户裁定，偏离原版——
//     原版不锁）：长备忘（图 + 40 段）上先做无锁对照组
//     （CDP 合成触摸拖、滚轮、PageDown 三路在无灯箱时都
//     必须真滚——区分力自证），再开灯箱：程序化 scrollTo
//     设 300 基线（程序化滚动非手势、不在锁面内），三路
//     手势逐一试滚断言 scrollY 纹丝不动、灯箱仍在场；点
//     关后滚轮须恢复；异常路径（开着灯箱程序化离页、编
//     辑器卸载）后断言 .lightbox 不在场、重进编辑页滚轮
//     正常（无残留锁——锁判定源即节点在否，见 bridge.rs
//     总论）。无头区分力注记：触摸走 CDP
//     dispatchTouchEvent 合成事件链，其 touchmove 与默
//     认滚动在无头 Chromium 与真机同构（probe_canvas_
//     focus ⑤c 同路已证合成触摸驱动真滚动判定）；真机
//     橡皮筋与滚动链手感终判待真机。列表页在异常路径
//     后只有一条备忘、不可滚，滚动恢复以「重进编辑页
//     可滚」取证。
//  ⑩ 灯箱派生快照与普查（2026-11-24 灯箱颜色链重构笔 4
//     探针笔，design_lightbox_rootcolor.md §8/§9）：开灯箱
//     → LBX open 行含派生输入快照（inputs page/sel/
//     scheme/lbx/dim/bgc/base/target），快照口径 O1
//     （dim=0/a0.00、base=target=#FAFAFA）且同行实测
//     root=rgb(250,250,250) 与 target 同色、lbxbg 为遮罩
//     自身 0.88；open 后 300/1000/3000ms 延迟重采样三发
//     齐发，快照 lbx=1（三发为镜像 effect 与派生落定后
//     的稳态采样，diag.rs log_lbx_late 口径；open 行采样
//     在挂载提交内、镜像尚未落定，其 lbx 字段不作判
//     据），与 open 行除 lbx 外逐字段一致（root_inputs
//     单一静态同源），三发 root/body 恒编辑 base（无晚
//     到写暗）。关灯箱后正常离页的 CENSUS 全 lbx=0；开
//     着灯箱异常离页（同 ⑥ 指针派发路径）窗口内
//     CENSUS 抓到 lbx=1（提交点与清理普查时灯箱尚在
//     场），其后再离页 CENSUS 回全 lbx=0——异常路径无
//     灯箱残留。
// 判据边界：无头只断言网页层量（CSS 变量与 html 计算背景），
// iOS 视口外 chrome 带区本身测不到，终判待真机。已知残差
// （真机定案）：状态栏带因子律 = M2——带 = 根色 ×(1−α)，
// α 为当前模态压暗系数（备份旧态 α0.28 → ×0.72 实测 125；
// 灯箱 α0.88 → ×0.12 预测 ≈4、实测 ≈0；固定 ×0.72 的 M1
// 预测灯箱带 ≈22 已排除）。因子在浏览器侧、无应用杠杆；
// 底部带 = 根色精确（备份态实测）。恢复集 (b) 后灯箱态
// 根色 = 编辑 base 本值，带色预测 = base ×0.12 由浏览器
// 因子单独作用（不再叠应用侧预压暗的双重压暗），真机判
// 读。详见 main.rs DimStack 注释。
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
  // 依赖下 $eval 确定性找不到节点而崩（⑨ 段第二处调用曾因此从未执行）。
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

// ② 编辑页灯箱不压暗根色（恢复集 (b)）
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
  const dimPush0 = count(await diagText(), 'dim push lightbox');
  const dimPop0 = count(await diagText(), 'dim pop lightbox');
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  await page.waitForTimeout(300);
  ok('② 灯箱打开根色保持编辑 base #FAFAFA / rgb(250, 250, 250)（不预压暗）',
    await waitRoot({ varBg: ed0.varBg, htmlBg: 'rgb(250, 250, 250)' }, 'lightbox-open'));
  const lbBg = await page.evaluate(() => {
    const lb = document.querySelector('.lightbox');
    return lb ? getComputedStyle(lb).backgroundColor : '';
  });
  ok('② 灯箱 scrim 自身遮罩样式不变 rgba(0, 0, 0, 0.88)',
    lbBg === 'rgba(0, 0, 0, 0.88)', lbBg);
  const lbGeo = await page.evaluate(() => {
    const lb = document.querySelector('.lightbox');
    if (!lb) return null;
    const r = lb.getBoundingClientRect();
    const de = document.documentElement;
    return { top: r.top, bottom: r.bottom, width: r.width,
             vh: de.clientHeight, vw: de.clientWidth,
             pos: getComputedStyle(lb).position };
  });
  ok('② 灯箱几何四边锚定覆盖布局视口（inset:0，原版同口径）',
    !!lbGeo && lbGeo.pos === 'fixed' && Math.abs(lbGeo.top) < 0.6 &&
    Math.abs(lbGeo.bottom - lbGeo.vh) < 0.6 && Math.abs(lbGeo.width - lbGeo.vw) < 0.6,
    JSON.stringify(lbGeo));
  await waitDiagSettle();
  ok('② Diag 无 dim push lightbox（预压暗登记已摘除）',
    count(await diagText(), 'dim push lightbox') === dimPush0);
  await page.touchscreen.tap(200, 200);
  await page.waitForFunction(() => !document.querySelector('.lightbox'), null, { polling: 200, timeout: 8000 });
  ok('② 灯箱关闭根色仍为编辑 base（全程未压暗）',
    await waitRoot({ varBg: ed0.varBg, htmlBg: 'rgb(250, 250, 250)' }, 'lightbox-close'));
  await waitDiagSettle();
  ok('② Diag 无 dim pop lightbox',
    count(await diagText(), 'dim pop lightbox') === dimPop0);
}

// ⑥ 异常退出路径：灯箱开着时离页（编辑器卸载）→ 根色
// 全程不压暗、回落列表默认（恢复集 (b)：无出栈行可查）
{
  const zone = await page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="dim-itc"]');
    const el = w ? w.querySelector('.itc-img-wrap img') : null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  ok('⑥ 图文卡图片区可定位', !!zone);
  const edBase6 = await rootState();
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  await page.waitForTimeout(300);
  ok('⑥ 灯箱重开根色保持编辑 base（不压暗）',
    await waitRoot({ varBg: edBase6.varBg, htmlBg: 'rgb(250, 250, 250)' }, 'lb-reopen'));
  const popBefore = count(await diagText(), 'dim pop lightbox');
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
  // 灯箱罩全屏、真实点按到不了返回钮；对钮元素直接派发
  // 指针事件离页是网页层唯一可达的「开着灯箱卸载编辑
  // 器」路径。fab 已改 onpointerdown 触发（批 6 E-9），
  // e.click() 不再触发，改真实指针派发（与
  // probe_pages_editor_rust 同法）。
  await page.$eval('.editor-fab.left', (e) => {
    const r = e.getBoundingClientRect();
    const opts = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 };
    e.dispatchEvent(new PointerEvent('pointerdown', opts));
    e.dispatchEvent(new PointerEvent('pointerup', opts));
  });
  await page.waitForFunction(() => !document.querySelector('#editor-root'), null, { polling: 200, timeout: 10000 });
  const lbSamples = await page.evaluate(() => {
    clearInterval(window.__lbTimer);
    return window.__lbSamples || [];
  });
  const lvSamples = lbSamples.filter((s) => s.lv);
  ok('⑥ 离页窗口内根色恒为编辑 base #FAFAFA（提交点后移：状态仍为编辑器；灯箱不压暗）',
    lvSamples.length > 0 && lvSamples.every((s) => s.v.toLowerCase() === '#fafafa'),
    `n=${lvSamples.length} vals=${[...new Set(lvSamples.map((s) => s.v))].join(',') || '无'}`);
  ok('⑥ 编辑器卸载后根色回落列表默认（未设 / rgb(242, 242, 247)）',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'leave-with-lightbox'));
  await waitDiagSettle();
  const popAfter = count(await diagText(), 'dim pop lightbox');
  ok('⑥ Diag 无 dim pop lightbox（登记摘除后无出栈行）',
    popAfter === popBefore, `before=${popBefore} after=${popAfter}`);
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
}

// ⑦ 灯箱开着切深浅色（不压暗口径：scheme 写 base 本值）+ ⑧ 内距公式
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
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  await page.waitForTimeout(300);
  ok('⑦ 灯箱打开根色保持 BG base #ffffff（不压暗）',
    await waitRoot({ varBg: '#ffffff', htmlBg: 'rgb(255, 255, 255)' }, 'bg-lb-open'));
  // ⑧ 内距：env=0 下四边恒 20px（与旧平值等价）+ 规则含 env 公式
  const padInfo = await page.evaluate(() => {
    const lb = document.querySelector('.lightbox');
    if (!lb) return null;
    const cs = getComputedStyle(lb);
    let ruleText = '';
    for (const sh of document.styleSheets) {
      let rules;
      try { rules = sh.cssRules; } catch { continue; }
      if (!rules) continue;
      for (const r of rules) {
        if (r.selectorText === '.lightbox') ruleText += r.cssText + '\n';
      }
    }
    return { t: cs.paddingTop, r: cs.paddingRight, b: cs.paddingBottom, l: cs.paddingLeft, ruleText };
  });
  ok('⑧ 灯箱计算 padding 四边 20px（env=0 等价旧平值）',
    !!padInfo && padInfo.t === '20px' && padInfo.r === '20px' && padInfo.b === '20px' && padInfo.l === '20px',
    JSON.stringify(padInfo && { t: padInfo.t, r: padInfo.r, b: padInfo.b, l: padInfo.l }));
  ok('⑧ .lightbox 规则含 max(20px, env(safe-area-inset-*)) 自适配公式',
    !!padInfo && padInfo.ruleText.includes('max(20px, env(safe-area-inset-top)')
      && padInfo.ruleText.includes('max(20px, env(safe-area-inset-bottom)')
      && padInfo.ruleText.includes('max(20px, env(safe-area-inset-left)')
      && padInfo.ruleText.includes('max(20px, env(safe-area-inset-right)'),
    (padInfo && padInfo.ruleText.slice(0, 200)) || 'no rule');
  // 切深色：灯箱不压暗后，根色须落 scheme 深色 base
  // #595959 本值（旧口径要求压暗值 #0b0b0b、现反转）
  await page.emulateMedia({ colorScheme: 'dark' });
  ok('⑦ 深色下根色 = scheme 深色 base #595959 / rgb(89, 89, 89)（未压暗本值）',
    await waitRoot({ varBg: '#595959', htmlBg: 'rgb(89, 89, 89)' }, 'lb-scheme-dark'));
  await page.emulateMedia({ colorScheme: 'light' });
  ok('⑦ 切回浅色根色回 #ffffff',
    await waitRoot({ varBg: '#ffffff', htmlBg: 'rgb(255, 255, 255)' }, 'lb-scheme-light'));
  await page.touchscreen.tap(200, 200);
  await page.waitForFunction(() => !document.querySelector('.lightbox'), null, { polling: 200, timeout: 8000 });
  ok('⑦ 关灯箱根色仍为 BG base #ffffff',
    await waitRoot({ varBg: '#ffffff', htmlBg: 'rgb(255, 255, 255)' }, 'bg-lb-close'));
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
}

// ⑩ 灯箱派生快照与普查（灯箱颜色链重构笔 4 探针笔）
{
  const diagLines = async () => {
    const raw = await diagText();
    try { const a = JSON.parse(raw); if (Array.isArray(a)) return a; } catch {}
    return raw.split('\n');
  };
  const lastLine = (lines, sub) => {
    const hits = lines.filter((l) => l.includes(sub));
    return hits.length ? hits[hits.length - 1] : '';
  };
  const inputsOf = (line) => {
    const i = line.indexOf(' inputs ');
    return i >= 0 ? line.slice(i + 1) : '';
  };
  const censusLines = async () => (await diagLines()).filter((l) => l.includes('CENSUS'));
  const openDimMemo = async () => {
    await page.evaluate(() => {
      const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
        .find((e) => e.textContent.includes('压暗探针'));
      if (el) el.click();
    });
    await page.waitForSelector('.detail', { timeout: 8000 });
    await page.waitForTimeout(800);
  };
  const itcZone = () => page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="dim-itc"]');
    const el = w ? w.querySelector('.itc-img-wrap img') : null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  const fabPointerLeave = async () => {
    // 同 ⑥/⑨：灯箱罩全屏，fab 改 onpointerdown（批 6 E-9），
    // 对钮元素派发真实指针事件离页。
    await page.$eval('.editor-fab.left', (e) => {
      const r = e.getBoundingClientRect();
      const opts = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 };
      e.dispatchEvent(new PointerEvent('pointerdown', opts));
      e.dispatchEvent(new PointerEvent('pointerup', opts));
    });
    await page.waitForFunction(() => !document.querySelector('#editor-root'), null, { polling: 200, timeout: 10000 });
    await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  };

  // —— 快照面：开灯箱 → open 行快照 + 三发重采样稳态 ——
  await openDimMemo();
  const zone = await itcZone();
  ok('⑩ 图文卡图片区可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  // 等本轮 late3000 落盘（open +3s、Diag 节流 1s）：以「最
  // 后一行 late3000 已是本轮在场稳态行（el 链在场、快照
  // lbx=1）」为落点，前段迟到的三发行（⑦ 关灯箱后补发、
  // el=none/lbx=0）不串扰。
  let lines = [];
  {
    const t0 = Date.now();
    for (;;) {
      lines = await diagLines();
      const last = lastLine(lines, 'LBX late3000 ');
      if (last.includes('el=DIV.lightbox') && last.includes('lbx=1')) break;
      if (Date.now() - t0 > 15000) break;
      await page.waitForTimeout(300);
    }
  }
  const openLine = lastLine(lines, 'LBX open');
  const late300 = lastLine(lines, 'LBX late300 ');
  const late1000 = lastLine(lines, 'LBX late1000 ');
  const late3000 = lastLine(lines, 'LBX late3000 ');
  const openInputs = inputsOf(openLine);
  ok('⑩ LBX open 行含派生输入快照（page=editor sel=dim-memo）',
    openInputs.startsWith('inputs page=editor sel=dim-memo '), openLine.slice(-170));
  ok('⑩ LBX open 快照口径 O1：dim=0/a0.00、base=#FAFAFA、target=#FAFAFA（在场不改值）',
    openInputs.includes('dim=0/a0.00') && openInputs.includes('base=#FAFAFA') && openInputs.includes('target=#FAFAFA'),
    openInputs);
  ok('⑩ LBX open 行实值与快照一致：root=rgb(250,250,250)（= target #FAFAFA）、lbxbg=rgba(0,0,0,0.88)',
    openLine.includes('root=rgb(250,250,250)') && openLine.includes('lbxbg=rgba(0,0,0,0.88)'),
    openLine.slice(0, 170));
  const trio = [['late300', late300], ['late1000', late1000], ['late3000', late3000]];
  ok('⑩ open 后延迟重采样三发齐发（late300/1000/3000 均在场行）',
    trio.every(([, l]) => l.includes('el=DIV.lightbox')),
    trio.map(([k, l]) => `${k}:${l ? '有' : '缺'}`).join(' '));
  ok('⑩ 三发快照 lbx=1（镜像+派生落定的稳态采样）',
    trio.every(([, l]) => inputsOf(l).includes('lbx=1')),
    trio.map(([, l]) => inputsOf(l)).join(' | ').slice(0, 220));
  const normInputs = (s) => s.replace(/lbx=[01]/, 'lbx=#');
  ok('⑩ 三发与 open 行快照同源一致（除 lbx 翻转外逐字段相同，root_inputs 单一静态）',
    openInputs !== '' && trio.every(([, l]) => inputsOf(l) !== '' && normInputs(inputsOf(l)) === normInputs(openInputs)),
    `open=[${openInputs}] late3000=[${inputsOf(late3000)}]`);
  ok('⑩ 三发根色恒编辑 base（root/body 均 rgb(250,250,250)，无晚到写暗）',
    trio.every(([, l]) => l.includes('root=rgb(250,250,250)') && l.includes('body=rgb(250,250,250)')),
    trio.map(([, l]) => l.slice(0, 60)).join(' | '));

  // —— 普查面一：关灯箱 → 正常离页，CENSUS 全 lbx=0 ——
  await page.touchscreen.tap(200, 200);
  await page.waitForFunction(() => !document.querySelector('.lightbox'), null, { polling: 200, timeout: 8000 });
  const censN0 = (await censusLines()).length;
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await waitDiagSettle();
  const censClosed = (await censusLines()).slice(censN0);
  ok('⑩ 关灯箱后离页有 CENSUS 落盘', censClosed.length > 0, `n=${censClosed.length}`);
  ok('⑩ 关灯箱后 CENSUS 全 lbx=0（灯箱无残留）',
    censClosed.length > 0 && censClosed.every((l) => l.includes('lbx=0')),
    censClosed.join(' | ').slice(0, 220));

  // —— 普查面二：开着灯箱异常离页，窗口内抓 lbx=1 ——
  await openDimMemo();
  const zone2 = await itcZone();
  ok('⑩ 图文卡图片区可定位（异常路径）', !!zone2);
  await page.touchscreen.tap(zone2.x, zone2.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  await page.waitForTimeout(300);
  const censN1 = (await censusLines()).length;
  await fabPointerLeave();
  await waitDiagSettle();
  const censLeave = (await censusLines()).slice(censN1);
  ok('⑩ 异常离页窗口 CENSUS 抓到 lbx=1（提交点/清理普查时灯箱尚在场）',
    censLeave.some((l) => l.includes('lbx=1')),
    censLeave.join(' | ').slice(0, 220));
  // 其后再正常离页一周：CENSUS 回全 lbx=0（异常路径无残留）
  await openDimMemo();
  const censN2 = (await censusLines()).length;
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await waitDiagSettle();
  const censFinal = (await censusLines()).slice(censN2);
  ok('⑩ 异常离页后无灯箱残留：再离页 CENSUS 全 lbx=0',
    censFinal.length > 0 && censFinal.every((l) => l.includes('lbx=0')),
    censFinal.join(' | ').slice(0, 220));
}

// ⑨ 灯箱背景滚动锁（裁定：开灯箱锁背景滚动，偏离原版）
{
  execSync(`python3 - <<'PYEOF'
import base64, json, zipfile
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAGklEQVR42mP8z8BQz0BEwMDAwMDEwMDAAAAASUVORK5CYII=')
doc = [{"id": "lock-p0", "type": "paragraph", "children": [{"text": "首段文字"}]},
       {"id": "lock-img", "type": "image", "attrs": {"fileId": "imgB"}, "children": []}]
for i in range(1, 41):
    doc.append({"id": f"lock-f{i}", "type": "paragraph", "children": [{"text": f"填充段落 {i:02d}，用于撑起可滚动的长文档。"}]})
memo = {"id": "lock-memo", "title": "滚动锁探针", "pinned": False,
        "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00",
        "doc": doc}
z = zipfile.ZipFile('/tmp/dim_probe_tall.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {
    "imgB": {"name": "b.png", "type": "image/png"}}}))
z.writestr('attachments/imgB', PNG)
z.close()
print('dim_probe_tall.zip ready')
PYEOF`);
  await importZip('/tmp/dim_probe_tall.zip');
  const cdp = await ctx.newCDPSession(page);
  const scrollY = () => page.evaluate(() => window.scrollY);
  const setScroll = (y) => page.evaluate((v) => window.scrollTo(0, v), y);
  const touchDragUp = async (x, y, dy = 60) => {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y, id: 1 }] });
    for (let i = 1; i <= 4; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y - (dy / 4) * i, id: 1 }] });
      await page.waitForTimeout(40);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForTimeout(400);
  };
  const wheelDown = async (dy) => {
    await page.mouse.move(196, 400);
    await page.mouse.wheel(0, dy);
    await page.waitForTimeout(350);
  };
  const openLockMemo = async () => {
    await page.evaluate(() => {
      const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
        .find((e) => e.textContent.includes('滚动锁探针'));
      if (el) el.click();
    });
    await page.waitForSelector('.detail', { timeout: 8000 });
    await page.waitForTimeout(800);
  };
  const imgZone = () => page.evaluate(() => {
    const w = document.querySelector('[data-wrapbid="lock-img"]');
    const el = w ? w.querySelector('img') : null;
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });

  await openLockMemo();
  // 对照组（无灯箱）：三路输入都必须真滚（区分力自证）
  await setScroll(300);
  ok('⑨ 对照基线：长文档可滚、scrollY = 300', (await scrollY()) === 300, String(await scrollY()));
  await touchDragUp(196, 500);
  const yTouch = await scrollY();
  ok('⑨ 对照：无灯箱触摸拖动真滚（scrollY > 330）', yTouch > 330, String(yTouch));
  await setScroll(300);
  await wheelDown(300);
  const yWheel = await scrollY();
  ok('⑨ 对照：无灯箱滚轮真滚（scrollY > 400）', yWheel > 400, String(yWheel));
  await setScroll(300);
  await page.keyboard.press('PageDown');
  await page.waitForTimeout(350);
  const yKey = await scrollY();
  ok('⑨ 对照：无灯箱 PageDown 真滚（scrollY > 400）', yKey > 400, String(yKey));

  // 开灯箱 → 程序化设 300 基线 → 三路手势逐一试滚
  await setScroll(0);
  const zone = await imgZone();
  ok('⑨ 长备忘图片可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  const ob = await page.evaluate(() => {
    const lb = document.querySelector('.lightbox');
    return lb ? getComputedStyle(lb).overscrollBehavior : '';
  });
  ok('⑨ .lightbox overscroll-behavior: none（CSS 兜底在位）', ob === 'none', ob);
  await setScroll(300);
  const y0 = await scrollY();
  ok('⑨ 灯箱基线：程序化 scrollTo 设 300（非手势、不在锁面）', y0 === 300, String(y0));
  await touchDragUp(196, 500);
  ok('⑨ 灯箱态触摸拖动不滚（scrollY 仍 300）', (await scrollY()) === 300, String(await scrollY()));
  ok('⑨ 灯箱拖后仍在场', (await page.$('.lightbox')) !== null);
  await wheelDown(600);
  ok('⑨ 灯箱态滚轮不滚（scrollY 仍 300）', (await scrollY()) === 300, String(await scrollY()));
  await page.keyboard.press('PageDown');
  await page.keyboard.press('Space');
  await page.keyboard.press('ArrowDown');
  await page.waitForTimeout(350);
  ok('⑨ 灯箱态滚动键不滚（scrollY 仍 300）', (await scrollY()) === 300, String(await scrollY()));
  ok('⑨ 灯箱按键后仍在场', (await page.$('.lightbox')) !== null);

  // 点关 → 滚动恢复（tap 不被锁误伤、关后能滚）
  await page.touchscreen.tap(200, 200);
  await page.waitForFunction(() => !document.querySelector('.lightbox'), null, { polling: 200, timeout: 8000 });
  ok('⑨ 点关灯箱成功（tap 未被滚动锁误伤）', true);
  await wheelDown(600);
  const yBack = await scrollY();
  ok('⑨ 关灯箱后滚轮恢复（scrollY > 400）', yBack > 400, String(yBack));

  // 异常路径：开着灯箱离页卸载 → 无残留锁
  await setScroll(0);
  const zone2 = await imgZone();
  ok('⑨ 图片可定位（异常路径）', !!zone2);
  await page.touchscreen.tap(zone2.x, zone2.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  // 同 ⑥：fab 已改 onpointerdown（批 6 E-9），改真实指针派发
  await page.$eval('.editor-fab.left', (e) => {
    const r = e.getBoundingClientRect();
    const opts = { bubbles: true, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 };
    e.dispatchEvent(new PointerEvent('pointerdown', opts));
    e.dispatchEvent(new PointerEvent('pointerup', opts));
  });
  await page.waitForFunction(() => !document.querySelector('#editor-root'), null, { polling: 200, timeout: 10000 });
  ok('⑨ 异常离页后 .lightbox 不在场（锁判定源已消失）',
    (await page.evaluate(() => document.querySelector('.lightbox') === null)));
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await openLockMemo();
  await wheelDown(600);
  const yRe = await scrollY();
  ok('⑨ 异常路径后重进编辑页滚轮正常（scrollY > 100，无残留锁）', yRe > 100, String(yRe));
  await page.click('.editor-fab.left');
  await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });
  await cdp.detach();
}

await browser.close();
console.log(`\nprobe_root_dim: ${pass} pass, ${fail} fail`);
if (fail === 0) console.log('ALL PASS');
process.exit(fail === 0 ? 0 : 1);
