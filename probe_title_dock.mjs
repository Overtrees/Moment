// 专用探针：长标题上滚头部不收缩根治（坞 scrolled 翻转
// 重定宽 + blur 重播 ed_scroll）。
// 取证裁定（生产构建本地同字节服务 + Chromium 活体）：
// 翻转本身正常（坞 class 翻 scrolled、meta 隐藏、与标
// 题长度解耦），但 TitleController.sync_width 的触发集
// 不含坞类翻转，胶囊保留大态陈值宽（193.8px）超过行模
// 式可用宽（189 = 坞 269 − 头像 72 − gap 8），被
// flex-wrap 挤到第二行，视觉与大态无异；活体派发一次
// resize 即钳入行（充分性）。修法：观察者兼听坞 class
// 翻转即重定宽（Diag ph=dockflip）、行态剔除已隐藏
// meta 的宽项、标题会话结束按当刻 scrollY 重播
// ed_scroll（堵 S7 抑制期的 resync 缺口）。
// 守的行为：
//  ① 三档标题（短 6 字 / 14 字截断档 / 27 字）× 长正
//     文上滚：坞翻 scrolled、胶囊与头像同行（cy 差
//     ≤4px）、胶囊宽 ≤ 行态可用宽；回滚恢复大态（宽回
//     滚前值 ±2、恢复堆叠）；Diag 有 ph=dockflip 行。
//  ② 空正文长标题：不可滚、坞不翻、胶囊保持大态、
//     meta 可见（原版同场景亦不收缩、无分叉）。
//  ③ 会话期程序滚动被 S7 抑制（坞不翻）；标题失焦后
//     无新滚动事件、坞靠 blur 重播自行翻入行态且胶囊
//     同行，scrollY 不被重播改动。
// 用法: node probe_title_dock.mjs [baseURL]
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, zipfile
def para(bid, text):
    return {"id": bid, "type": "paragraph", "children": [{"text": text}]}
def memo(mid, title, doc):
    return {"id": mid, "title": title, "doc": doc, "pinned": False,
            "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00"}
def longdoc(prefix):
    return [para(f"{prefix}{i}", f"正文第{i}行填充内容用于撑高页面。") for i in range(1, 46)]
memos = [
    memo("dock-a", "短标题甲乙丙", longdoc("da")),
    memo("dock-b", "中档标题一二三四五六七八九十", longdoc("db")),
    memo("dock-c", "长标题一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑寅卯", longdoc("dc")),
    memo("dock-d", "空正文长题一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑", [para("dd1", "")]),
]
z = zipfile.ZipFile('/tmp/dock_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": memos}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {}}, ensure_ascii=False))
z.close()
print('dock_probe.zip ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

let pass = 0, fail = 0;
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ok', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}

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
async function openMemo(prefix) {
  await page.waitForFunction((t) => [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
    .some((e) => e.textContent.includes(t)), prefix, { timeout: 10000 });
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.evaluate((t) => {
      const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
        .find((e) => e.textContent.includes(t));
      if (el) el.click();
    }, prefix);
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

async function dockGeom() {
  return page.evaluate(() => {
    const dock = document.querySelector('.editor-title-dock');
    const cap = document.querySelector('.editor-title-capsule');
    const av = document.querySelector('.editor-avatar-button');
    const meta = document.querySelector('.editor-title-meta');
    const cr = cap.getBoundingClientRect();
    const ar = av.getBoundingClientRect();
    return {
      scrolled: dock.classList.contains('scrolled'),
      dockW: dock.clientWidth,
      capW: cr.width,
      capCy: cr.top + cr.height / 2,
      avCy: ar.top + ar.height / 2,
      avW: ar.width,
      scrollY: window.scrollY || 0,
      metaDisplay: getComputedStyle(meta).display,
    };
  });
}
// 等坞翻到目标态且胶囊宽稳定（width transition 0.2s 收敛）
async function waitDock(wantScrolled) {
  for (let i = 0; i < 50; i++) {
    const g = await dockGeom();
    if (g.scrolled === wantScrolled) {
      let last = -1, stable = 0;
      for (let j = 0; j < 30; j++) {
        const w = (await dockGeom()).capW;
        if (Math.abs(w - last) < 0.05) { stable++; if (stable >= 3) return dockGeom(); }
        else stable = 0;
        last = w;
        await page.waitForTimeout(60);
      }
      return dockGeom();
    }
    await page.waitForTimeout(80);
  }
  return dockGeom();
}
async function diagDockflips() {
  return page.evaluate(() => {
    try {
      const arr = JSON.parse(localStorage.getItem('mynote_diag_v1') || '[]');
      return arr.map((x) => x.line || String(x)).filter((l) => l.includes('titleGeom') && l.includes('ph=dockflip')).length;
    } catch { return 0; }
  });
}
const rowAvail = (g) => g.dockW - g.avW - 8;

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });
await importZip('/tmp/dock_probe.zip');

console.log('S1 三档标题 × 长正文：上滚入行 / 回滚恢复');
for (const [prefix, label] of [['短标题甲乙丙', '短 6 字'], ['中档标题', '14 字截断档'], ['长标题一二三四', '27 字']]) {
  await openMemo(prefix);
  const g0 = await dockGeom();
  ok(`${label}: 顶部坞为列态`, !g0.scrolled, JSON.stringify(g0));
  const flipsBefore = await diagDockflips();
  await page.evaluate(() => window.scrollTo(0, 600));
  const g1 = await waitDock(true);
  ok(`${label}: 上滚后坞翻行态`, g1.scrolled, JSON.stringify(g1));
  ok(`${label}: 胶囊与头像同行 (cy 差 ≤4)`, Math.abs(g1.capCy - g1.avCy) <= 4, `capCy=${g1.capCy.toFixed(1)} avCy=${g1.avCy.toFixed(1)}`);
  ok(`${label}: 胶囊宽 ≤ 行态可用宽`, g1.capW <= rowAvail(g1) + 1, `capW=${g1.capW.toFixed(1)} avail=${rowAvail(g1)}`);
  // Diag 落盘为 1s 节流合并写（批10 T-F）：几何轮询落定后即
  // 读会落在节流窗内假红，改轮询等 dockflip 行落盘（200ms
  // 步进、上限约 6s）后仍按原判据断言。只改读取时序。
  let flipsAfter = await diagDockflips();
  for (let i = 0; flipsAfter <= flipsBefore && i < 30; i++) {
    await page.waitForTimeout(200);
    flipsAfter = await diagDockflips();
  }
  ok(`${label}: 翻转记 Diag ph=dockflip`, flipsAfter > flipsBefore);
  await page.evaluate(() => window.scrollTo(0, 0));
  const g2 = await waitDock(false);
  ok(`${label}: 回滚后坞回列态`, !g2.scrolled, JSON.stringify(g2));
  ok(`${label}: 胶囊宽恢复大态 (±2)`, Math.abs(g2.capW - g0.capW) <= 2, `before=${g0.capW.toFixed(1)} after=${g2.capW.toFixed(1)}`);
  ok(`${label}: 胶囊恢复堆叠 (cy 差 >4)`, Math.abs(g2.capCy - g2.avCy) > 4, `diff=${Math.abs(g2.capCy - g2.avCy).toFixed(1)}`);
  await goBack();
}

console.log('S2 空正文长标题：保持大态');
{
  await openMemo('空正文长题');
  const g0 = await dockGeom();
  await page.evaluate(() => window.scrollTo(0, 600));
  await page.waitForTimeout(600);
  const g1 = await dockGeom();
  ok('空正文不可滚 (scrollY=0)', g1.scrollY === 0, `scrollY=${g1.scrollY}`);
  ok('坞不翻行态', !g1.scrolled);
  ok('胶囊保持大态宽 (±2)', Math.abs(g1.capW - g0.capW) <= 2, `before=${g0.capW.toFixed(1)} after=${g1.capW.toFixed(1)}`);
  ok('meta 仍可见', g1.metaDisplay !== 'none', g1.metaDisplay);
  await goBack();
}

console.log('S3 标题会话抑制 + blur 重播 resync');
{
  await openMemo('长标题一二三四');
  await page.click('#editor-title-text');
  await page.waitForTimeout(350);
  await page.evaluate(() => window.scrollTo(0, 600));
  await page.waitForTimeout(600);
  const gMid = await dockGeom();
  ok('会话期滚动已发生 (scrollY=600)', gMid.scrollY === 600, `scrollY=${gMid.scrollY}`);
  ok('会话期坞翻转被 S7 抑制', !gMid.scrolled);
  await page.evaluate(() => document.querySelector('#editor-title-text').blur());
  const g1 = await waitDock(true);
  ok('失焦后无新滚动、坞靠重播翻入行态', g1.scrolled, JSON.stringify(g1));
  ok('重播后胶囊与头像同行 (cy 差 ≤4)', Math.abs(g1.capCy - g1.avCy) <= 4, `diff=${Math.abs(g1.capCy - g1.avCy).toFixed(1)}`);
  ok('重播后胶囊宽 ≤ 行态可用宽', g1.capW <= rowAvail(g1) + 1, `capW=${g1.capW.toFixed(1)} avail=${rowAvail(g1)}`);
  ok('重播未改动 scrollY', g1.scrollY === 600, `scrollY=${g1.scrollY}`);
  await goBack();
}

console.log(`\nprobe_title_dock: ${pass} passed, ${fail} failed`);
await browser.close();
if (fail > 0) { console.log('PROBE FAILED'); process.exit(1); }
console.log('ALL PASS');
