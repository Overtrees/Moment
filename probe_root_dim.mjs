// 专用探针：安全区实心栏根治（根色压暗跟随）+ 图片卡点按 rider。
// 取证定案（真机量测）：备份确认底表打开时视口内压暗均匀，但
// 布局视口下缘以下一条带呈未压暗实心浅栏——条带 = 根色原值、
// 压暗面 = 根色 ×(1−0.28)、分界恰在布局视口下缘；根因 = 根色
// 派生链的触发集不含模态开关，视口外只能由浏览器以根（html）
// 背景绘制而根色没跟随压暗。修法：App 层 DimStack（context）
// 登记全站真压暗层（备份模态 α0.28 / 灯箱 α0.88，DimLayer +
// use_hook Drop 守卫同步入栈出栈），根色派生增读该输入，栈非
// 空时把 base 向黑按 max α 混合成等效实色经 apply_root_bg 单
// 点写入；压暗呈现本身不改。
// 守的行为：
//  ① 备份模态打开 → --mn-root-bg = #aeaeb2（--primary-bg
//     #f2f2f7 ×0.72）、html 计算背景 rgb(174,174,178)、Diag
//     dim push +1；取消关闭 → 变量撤除、html 回
//     rgb(242,242,247)、Diag dim pop +1。
//  ② 编辑页开灯箱 → 根色按 0.88 混合（编辑 base #FAFAFA →
//     #1e1e1e、html rgb(30,30,30)）、Diag dim push；关灯箱
//     → 恢复编辑 base、Diag dim pop。
//  ③ rider：图片卡左滑开启态点按无操作（保持 -168、不打开
//     编辑页、Diag 记 row open-state tap noop）；滑回收起后
//     点按仍正常打开。
// 判据边界：无头只断言网页层量（CSS 变量与 html 计算背景），
// iOS 视口外 chrome 带区本身测不到，终判待真机。
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
z = zipfile.ZipFile('/tmp/dim_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo]}, ensure_ascii=False))
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

// ① 备份模态压暗跟随
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
  ok('① 模态打开根色压成等效实色 #aeaeb2 / rgb(174, 174, 178)',
    await waitRoot({ varBg: '#aeaeb2', htmlBg: 'rgb(174, 174, 178)' }, 'modal-open'));
  const diag1 = await diagText();
  ok('① Diag dim push backup-modal +1', count(diag1, 'dim push backup-modal') === push0 + 1);
  await page.click('.backup-modal .backup-btn.secondary');
  await page.waitForFunction(() => !document.querySelector('.backup-modal'), null, { polling: 200, timeout: 8000 });
  ok('① 模态关闭根色撤除、html 回 rgb(242, 242, 247)',
    await waitRoot({ varBg: '', htmlBg: 'rgb(242, 242, 247)' }, 'modal-close'));
  const diag2 = await diagText();
  ok('① Diag dim pop backup-modal +1', count(diag2, 'dim pop backup-modal') === pop0 + 1);
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
  ok('③ Diag 记 row open-state tap noop', (await diagText()).includes('row open-state tap noop') && count(await diagText(), 'row open-state tap noop') > count(diag0, 'row open-state tap noop'));
  // 滑回收起
  await page.mouse.move(ocx, ocy);
  await page.mouse.down();
  for (let i = 1; i <= 6; i++) { await page.mouse.move(ocx + 22 * i, ocy); await page.waitForTimeout(30); }
  await page.mouse.up();
  await page.waitForTimeout(500);
  const txClosed = await txOf();
  ok('③ 右滑收起（tx = 0）', Math.abs(txClosed) < 1.5, `tx=${txClosed}`);
}

// ② 编辑页灯箱压暗跟随
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
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.lightbox', { timeout: 8000 });
  ok('② 灯箱打开根色按 0.88 混合 #1e1e1e / rgb(30, 30, 30)',
    await waitRoot({ varBg: '#1e1e1e', htmlBg: 'rgb(30, 30, 30)' }, 'lightbox-open'));
  ok('② Diag 记 dim push lightbox', (await diagText()).includes('dim push lightbox'));
  await page.touchscreen.tap(200, 200);
  await page.waitForFunction(() => !document.querySelector('.lightbox'), null, { polling: 200, timeout: 8000 });
  ok('② 灯箱关闭根色恢复编辑 base',
    await waitRoot({ varBg: ed0.varBg, htmlBg: 'rgb(250, 250, 250)' }, 'lightbox-close'));
  ok('② Diag 记 dim pop lightbox', (await diagText()).includes('dim pop lightbox'));
}

await browser.close();
console.log(`\nprobe_root_dim: ${pass} pass, ${fail} fail`);
if (fail === 0) console.log('ALL PASS');
process.exit(fail === 0 ? 0 : 1);
