// 滚动监听审计探针：同一 fixture、同一视口，对比原版(8099)与 Rust(8098)
// 阶段一：生成 fixture zip 并导入 Rust；原版用 MynoteIdb 原子恢复 + localStorage 播种。
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const RUST = 'http://localhost:8098/';
const ORIG = 'http://localhost:8099/Moment.html';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, zipfile, datetime
now = datetime.datetime.now().astimezone()
def ts(days_ago, hour=10):
    return (now - datetime.timedelta(days=days_ago)).replace(hour=hour, minute=0, second=0, microsecond=0).isoformat()
def para(bid, text):
    return {"id": bid, "type": "paragraph", "children": [{"text": text}]}
memos = []
# 长文备忘：30 段（编辑页滚动/双栏用）
long_doc = [para(f"L{i}", f"长文段落 {i}：" + "滚动测试文字" * 10) for i in range(30)]
memos.append({"id": "scrlong", "title": "滚动长文", "pinned": True, "createdAt": ts(0, 9), "updatedAt": ts(0, 9), "doc": long_doc})
# 12 篇普通备忘（列表滚动用，分到不同日期组避免折叠吞卡）
for i in range(12):
    doc = [para(f"s{i}a", f"列表备忘 {i} 正文：" + "填充文字" * 30), para(f"s{i}b", "第二段" + "更多填充" * 20)]
    memos.append({"id": f"scr{i}", "title": f"列表备忘{i}", "pinned": False, "createdAt": ts(i % 6, 8), "updatedAt": ts(i % 6, 8), "doc": doc})
data = {"version": 2, "exportedAt": ts(0), "memos": memos, "avatars": {}}
man = {"version": 1, "attachments": {}}
z = zipfile.ZipFile('/tmp/scroll_test.zip', 'w')
z.writestr('memos.json', json.dumps(data, ensure_ascii=False))
z.writestr('manifest.json', json.dumps(man, ensure_ascii=False))
z.close()
import io
io.open('/tmp/scroll_memos.json', 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False))
print('fixture ok', len(memos))
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function newPage(url) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  // 统计 scroll 监听净注册数（包裹 add/removeEventListener）
  await page.addInitScript(() => {
    window.__scrollListeners = 0;
    const add = EventTarget.prototype.addEventListener;
    const rem = EventTarget.prototype.removeEventListener;
    EventTarget.prototype.addEventListener = function (t, f, o) {
      if (t === 'scroll' && (this === window || this === document)) window.__scrollListeners++;
      return add.call(this, t, f, o);
    };
    EventTarget.prototype.removeEventListener = function (t, f, o) {
      if (t === 'scroll' && (this === window || this === document)) window.__scrollListeners--;
      return rem.call(this, t, f, o);
    };
  });
  page.on('pageerror', (e) => console.log('PAGEERROR', url, String(e).slice(0, 120)));
  await page.goto(url, { waitUntil: 'load' });
  return { ctx, page };
}

const scrollTo = async (page, y) => {
  await page.evaluate((v) => window.scrollTo(0, v), y);
  await page.waitForTimeout(350);
};

// ---------- Rust ----------
{
  const { ctx, page } = await newPage(RUST);
  await page.waitForSelector('.list-item, .img-card', { timeout: 20000 });
  // 导入 fixture
  await page.$eval('h1.page-title', (e) => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
  await page.setInputFiles('#file-import', '/tmp/scroll_test.zip');
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 10000 });
  await page.waitForTimeout(500);
  console.log('RUST list height', await page.evaluate(() => document.documentElement.scrollHeight));

  // L1 标题联动 @15
  await scrollTo(page, 15);
  const l1 = await page.evaluate(() => {
    const h = document.querySelector('h1.page-title');
    const cs = getComputedStyle(h);
    return { tf: cs.transform, op: cs.opacity, y: window.scrollY };
  });
  console.log('RUST L1 @15', JSON.stringify(l1));
  // L2 紧凑翻转 @29/@31：紧凑胶囊 .page-title.compact 可见性
  for (const y of [29, 31]) {
    await scrollTo(page, y);
    const c = await page.evaluate(() => {
      const el = document.querySelector('.page-title.compact');
      const cs = getComputedStyle(el);
      return { vis: cs.visibility, op: cs.opacity, y: window.scrollY };
    });
    console.log('RUST L2 @' + y, JSON.stringify(c));
  }
  // L4 搜索/新建卡 @60 透明度
  await scrollTo(page, 60);
  const l4 = await page.evaluate(() => ({
    trig: getComputedStyle(document.querySelector('.glass-search-trigger')).opacity,
    newc: (() => { const e = [...document.querySelectorAll('.list-item')].find((x) => x.textContent.includes('新建')); return e ? getComputedStyle(e).opacity : 'nf'; })(),
  }));
  console.log('RUST L4 @60', JSON.stringify(l4));
  // L3 保存/恢复：滚到 400 → 开长文 → 读 editor scrollY → 返回 → 读 scrollY
  await scrollTo(page, 400);
  const yBefore = await page.evaluate(() => window.scrollY);
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
    if (el) el.click();
  });
  await page.waitForSelector('#editor-root', { timeout: 8000 });
  await page.waitForTimeout(600);
  const yEditor = await page.evaluate(() => window.scrollY);
  console.log('RUST L3 listY=', yBefore, 'editorY=', yEditor);
  // E2 标题坞三档：firstBlockTop @0/15/60 + dock class
  for (const y of [0, 15, 60]) {
    await scrollTo(page, y);
    const e2 = await page.evaluate(() => {
      const b = document.querySelector('#editor-root [data-bid]');
      const dock = document.querySelector('.editor-title-dock');
      return { top: b ? Math.round(b.getBoundingClientRect().top) : -1, dockCls: dock ? dock.className : 'nf', dockH: dock ? Math.round(dock.getBoundingClientRect().height) : -1 };
    });
    console.log('RUST E2 @' + y, JSON.stringify(e2));
  }
  // E1 背景渐变 @15/@45
  for (const y of [15, 45]) {
    await scrollTo(page, y);
    const g = await page.evaluate(() => document.getElementById('body-before-bg')?.textContent || 'none');
    console.log('RUST E1 @' + y, g.slice(0, 160));
  }
  // E3 菜单滚动态：开 ••• 菜单 → 滚动 200 → 菜单是否还在
  await scrollTo(page, 0);
  await page.evaluate(() => document.querySelector('.editor-fab.right')?.click());
  await page.waitForTimeout(600);
  const menuBefore = await page.evaluate(() => !!document.querySelector('.editor-menu-panel, .menu-panel'));
  await scrollTo(page, 200);
  const menuAfter = await page.evaluate(() => !!document.querySelector('.editor-menu-panel, .menu-panel'));
  console.log('RUST E3 menu before/after scroll', menuBefore, menuAfter);
  await page.evaluate(() => document.querySelector('.menu-scrim')?.click());
  await page.waitForTimeout(400);
  // E4 斜杠面板滚动跟随：聚焦首块打 / → 记录面板 top → 滚动 200 → 面板 top
  await scrollTo(page, 0);
  await page.evaluate(() => document.querySelector('#editor-root [data-bid]')?.focus());
  await page.keyboard.type('/');
  await page.waitForSelector('#slash-panel', { timeout: 5000 }).catch(() => null);
  await page.waitForTimeout(400);
  const sp1 = await page.evaluate(() => document.querySelector('#slash-panel')?.getBoundingClientRect().top ?? -1);
  await scrollTo(page, 200);
  const sp2 = await page.evaluate(() => document.querySelector('#slash-panel')?.getBoundingClientRect().top ?? -1);
  console.log('RUST E4 slash top before/after', Math.round(sp1), Math.round(sp2));
  await page.evaluate(() => document.querySelector('.menu-scrim')?.click());
  await page.waitForTimeout(300);
  // E5 监听泄漏：回列表→再进出编辑器 2 次，数 window scroll 监听净值
  const lis0 = await page.evaluate(() => window.__scrollListeners);
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
  const lisList = await page.evaluate(() => window.__scrollListeners);
  for (let i = 0; i < 2; i++) {
    await page.evaluate(() => {
      const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
      if (el) el.click();
    });
    await page.waitForSelector('#editor-root', { timeout: 8000 });
    await page.waitForTimeout(400);
    await page.click('.editor-fab.left');
    await page.waitForSelector('.list-item, .img-card', { timeout: 8000 });
    await page.waitForTimeout(300);
  }
  const lisAfter = await page.evaluate(() => window.__scrollListeners);
  console.log('RUST E5 scroll listeners editor/list/after2cycles', lis0, lisList, lisAfter);
  await ctx.close();
}

// ---------- 原版 ----------
{
  const { ctx, page } = await newPage(ORIG);
  await page.waitForSelector('.list-item, .img-card, .memo-card, [class*=card]', { timeout: 20000 }).catch(() => null);
  await page.waitForTimeout(1500);
  // 播种：优先 MynoteIdb 原子恢复；兜底 localStorage
  const seeded = await page.evaluate(async () => {
    try {
      const resp = await fetch('/tmp-nonexistent').catch(() => null);
      return 'skip';
    } catch (e) { return 'err'; }
  });
  // 用 zip 字节经 MynoteZip 恢复（与主线 tails 批次同法）
  const fs = await import('node:fs');
  const bytes = fs.readFileSync('/tmp/scroll_test.zip');
  const b64 = bytes.toString('base64');
  const r = await page.evaluate(async (b64s) => {
    try {
      const bin = atob(b64s);
      const arr = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      const unzipped = await window.MynoteZip.checkedZip(arr);
      const backup = JSON.parse(new TextDecoder().decode(unzipped['memos.json']));
      const db = await window.MynoteIdb.getDB();
      await window.MynoteIdb.restoreFromZipAtomic(db, unzipped, backup, {});
      localStorage.setItem('memos_app_v2', JSON.stringify(backup.memos));
      return 'ok memos=' + backup.memos.length;
    } catch (e) { return 'fail ' + e.message; }
  }, b64);
  console.log('ORIG seed', r);
  await page.reload({ waitUntil: 'load' });
  await page.waitForTimeout(2500);
  console.log('ORIG list height', await page.evaluate(() => document.documentElement.scrollHeight),
    'cards', await page.evaluate(() => document.querySelectorAll('.list-item, .img-card').length));

  await scrollTo(page, 15);
  const l1 = await page.evaluate(() => {
    const h = document.querySelector('h1.page-title, .page-title');
    const cs = getComputedStyle(h);
    return { tf: cs.transform, op: cs.opacity, y: window.scrollY, cls: h.className };
  });
  console.log('ORIG L1 @15', JSON.stringify(l1));
  for (const y of [29, 31]) {
    await scrollTo(page, y);
    const c = await page.evaluate(() => {
      const el = document.querySelector('.page-title.compact');
      if (!el) return { nf: true };
      const cs = getComputedStyle(el);
      return { vis: cs.visibility, op: cs.opacity, y: window.scrollY };
    });
    console.log('ORIG L2 @' + y, JSON.stringify(c));
  }
  await scrollTo(page, 60);
  const l4 = await page.evaluate(() => {
    const trig = document.querySelector('.glass-search-trigger, .search-trigger');
    const items = [...document.querySelectorAll('.list-item')];
    const nc = items.find((x) => x.textContent.includes('新建'));
    return { trig: trig ? getComputedStyle(trig).opacity : 'nf', newc: nc ? getComputedStyle(nc).opacity : 'nf' };
  });
  console.log('ORIG L4 @60', JSON.stringify(l4));
  // L3
  await scrollTo(page, 400);
  const yBefore = await page.evaluate(() => window.scrollY);
  await page.evaluate(() => {
    const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text, .item-title-text')].find((e) => e.textContent.includes('滚动长文'));
    if (el) el.click();
  });
  await page.waitForTimeout(1500);
  const inEditor = await page.evaluate(() => !!document.querySelector('.editor-body, #editor-root, .detail'));
  const yEditor = await page.evaluate(() => window.scrollY);
  console.log('ORIG L3 listY=', yBefore, 'inEditor=', inEditor, 'editorY=', yEditor);
  // E2
  for (const y of [0, 15, 60]) {
    await scrollTo(page, y);
    const e2 = await page.evaluate(() => {
      const b = document.querySelector('.editor-body [data-type="paragraph"], .editor-body .ed-line, .editor-body > *');
      const dock = document.querySelector('.editor-title-dock');
      return { top: b ? Math.round(b.getBoundingClientRect().top) : -1, dockH: dock ? Math.round(dock.getBoundingClientRect().height) : -1 };
    });
    console.log('ORIG E2 @' + y, JSON.stringify(e2));
  }
  for (const y of [15, 45]) {
    await scrollTo(page, y);
    const g = await page.evaluate(() => document.getElementById('body-before-bg')?.textContent || 'none');
    console.log('ORIG E1 @' + y, g.slice(0, 160));
  }
  // E3 菜单
  await scrollTo(page, 0);
  await page.evaluate(() => document.querySelector('.editor-fab.right')?.click());
  await page.waitForTimeout(600);
  const menuBefore = await page.evaluate(() => !!document.querySelector('.editor-menu-panel, .menu-panel'));
  await scrollTo(page, 200);
  const menuAfter = await page.evaluate(() => !!document.querySelector('.editor-menu-panel, .menu-panel'));
  console.log('ORIG E3 menu before/after scroll', menuBefore, menuAfter);
  await page.keyboard.press('Escape');
  // E5 监听计数
  const lisEd = await page.evaluate(() => window.__scrollListeners);
  await page.evaluate(() => document.querySelector('.editor-fab.left')?.click());
  await page.waitForTimeout(1500);
  const lisList = await page.evaluate(() => window.__scrollListeners);
  console.log('ORIG E5 scroll listeners editor/list', lisEd, lisList, 'backY=', await page.evaluate(() => window.scrollY));
  await ctx.close();
}

await browser.close();
console.log('PROBE DONE');
