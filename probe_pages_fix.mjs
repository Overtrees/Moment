// 每页审计修复验证探针（L1 折叠首卡 / S1 avatars 往返 / L2 置顶
// updatedAt / L3 24h 补零 / S2 导出文件名 / S4 上次备份口径）。
// 用法：node probe_pages_fix.mjs <baseUrl>
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const base = process.argv[2] || 'http://localhost:8117/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const REAL = process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip';
let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' | ' + val : ''));
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

async function newPage(locale) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, locale: locale || 'zh-CN' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('PAGEERROR', String(e)));
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.waitForTimeout(600);
  return [ctx, page];
}

async function gotoBackup(page) {
  // 标题点击偶发被初始化竞态吞掉：重试至设置页出现为止
  for (let i = 0; i < 4; i++) {
    await page.$eval('h1.page-title', (e) => e.click()).catch(() => {});
    try {
      await page.waitForSelector('.set-row', { timeout: 3000 });
      break;
    } catch { if (i === 3) throw new Error('settings page not reached'); }
  }
  await page.click('.set-row:has-text("备份与恢复")');
  await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
}

async function backToList(page) {
  await page.click('.editor-fab.left');
  await page.waitForSelector('.set-row', { timeout: 8000 }).catch(() => {});
  await page.click('.editor-fab.left');
  await page.waitForSelector('.list-item', { timeout: 8000 });
}

async function importZip(page, path) {
  await gotoBackup(page);
  await page.setInputFiles('#file-import', path);
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  await page.waitForFunction(() => document.querySelector('.status-toast')?.innerText.includes('已导入'), { timeout: 15000 });
  await backToList(page);
}

async function exportFromBackup(page) {
  await gotoBackup(page);
  const dlPromise = page.waitForEvent('download', { timeout: 20000 });
  await page.locator('.backup-card').first().locator('.backup-row').first().click();
  await page.waitForSelector('.backup-modal', { timeout: 8000 });
  await page.click('.backup-modal .backup-btn.primary');
  const dl = await dlPromise;
  return dl;
}

const readIdbMemos = (page) => page.evaluate(() => new Promise((res, rej) => {
  const req = indexedDB.open('mynote-web', 1);
  req.onsuccess = () => {
    const g = req.result.transaction('kv', 'readonly').objectStore('kv').get('memos_json');
    g.onsuccess = () => res(g.result);
    g.onerror = () => rej(String(g.error));
  };
  req.onerror = () => rej(String(req.error));
}));

// ---------- L1 折叠组首卡 ----------
try {
  const [ctx, page] = await newPage();
  await importZip(page, '/tmp/fixprobe/fold3.zip');
  const collapsed = await page.evaluate(() => !!document.querySelector('.card-expand-wrapper'));
  ok('L1 前置：组处于折叠态', collapsed);
  await page.$eval('.card-expand-wrapper .item-title-text', (e) => e.click());
  await page.waitForTimeout(700);
  const state = await page.evaluate(() => ({
    wrapper: !!document.querySelector('.card-expand-wrapper'),
    editor: !!document.querySelector('#editor-root'),
    cards: [...document.querySelectorAll('.list-item .item-title-text')].map((e) => e.innerText),
  }));
  ok('L1 点首卡展开该组（3 卡可见、未进编辑器）',
    !state.wrapper && !state.editor && ['折叠甲', '折叠乙', '折叠丙'].every((t) => state.cards.includes(t)),
    JSON.stringify(state));
  if (!state.wrapper && !state.editor) {
    await page.$eval('.list-item:has-text("折叠乙") .item-title-text', (e) => e.click());
    await page.waitForTimeout(700);
    const opened = await page.evaluate(() => !!document.querySelector('#editor-root'));
    ok('L1 展开后点卡打开备忘', opened);
  }
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR: ' + String(e).split('\n')[0]); }

// ---------- S1 avatars 往返 + S2 文件名 ----------
try {
  const [ctx, page] = await newPage();
  await importZip(page, REAL);
  const dl = await exportFromBackup(page);
  const name = dl.suggestedFilename();
  // 无头 Chromium 对非 ASCII 下载名回退 "download"（审计报告
  // 已知注记），故文件名以 S2b 的锚点 download 属性为准；
  // 这里只记录 suggestedFilename 供参考。
  console.log('  (info) suggestedFilename =', name);
  await dl.saveAs('/tmp/fixprobe/export_out.zip');
  const cmp = execSync('python3 - <<\'PY\'\nimport json, zipfile\nsrc = json.loads(zipfile.ZipFile("' + REAL + '").read("memos.json"))\nout = json.loads(zipfile.ZipFile("/tmp/fixprobe/export_out.zip").read("memos.json"))\nsa, oa = src.get("avatars"), out.get("avatars")\nprint(json.dumps({"src_keys": sorted(src.keys()), "out_keys": sorted(out.keys()), "src_n": len(sa) if isinstance(sa, dict) else -1, "out_n": len(oa) if isinstance(oa, dict) else -1, "equal": sa == oa}))\nPY').toString().trim();
  const r = JSON.parse(cmp);
  ok('S1 导出 memos.json 含 avatars 键', r.out_keys.includes('avatars'), JSON.stringify(r));
  ok('S1 avatars 7 个且内容与源一致', r.out_n === 7 && r.equal, JSON.stringify(r));
  await ctx.close();

  // S1b 空头像时导出仍恒带 avatars 键（原版 {} 形态）
  const [ctx2, page2] = await newPage();
  const dl2 = await exportFromBackup(page2);
  await dl2.saveAs('/tmp/fixprobe/export_empty.zip');
  const cmp2 = execSync('python3 -c "import json,zipfile; d=json.loads(zipfile.ZipFile(\'/tmp/fixprobe/export_empty.zip\').read(\'memos.json\')); print(json.dumps({\'keys\': sorted(d.keys()), \'avatars\': d.get(\'avatars\')}))"').toString().trim();
  const r2 = JSON.parse(cmp2);
  ok('S1b 无头像导出 avatars 键恒在且为 {}', r2.keys.includes('avatars') && r2.avatars && Object.keys(r2.avatars).length === 0, cmp2);
  await ctx2.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR: ' + String(e).split('\n')[0]); }

// ---------- S2b 导出文件名（锚点 download 属性实测） ----------
try {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, locale: 'zh-CN', acceptDownloads: true });
  await ctx.addInitScript(() => {
    window.__dlNames = [];
    const orig = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
      if (this.download) window.__dlNames.push(this.download);
      return orig.call(this);
    };
  });
  const page = await ctx.newPage();
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.waitForTimeout(600);
  await exportFromBackup(page);
  await page.waitForTimeout(500);
  const names = await page.evaluate(() => window.__dlNames);
  const expectName = `此刻备份_${new Date().toISOString().slice(0, 10)}.zip`;
  ok('S2 导出文件名=原版口径', names.includes(expectName), `got=${JSON.stringify(names)} want=${expectName}`);
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR: ' + String(e).split('\n')[0]); }

// ---------- L2 置顶刷新 updatedAt ----------
try {
  const [ctx, page] = await newPage();
  await importZip(page, '/tmp/fixprobe/pin1.zip');
  const before = JSON.parse(await readIdbMemos(page)).memos.find((m) => String(m.id) === 'pin_a');
  const row = page.locator('.list-item:has-text("置顶目标")');
  const box = await row.boundingBox();
  await page.mouse.move(box.x + box.width - 30, box.y + box.height / 2);
  await page.mouse.down();
  for (let i = 1; i <= 6; i++) await page.mouse.move(box.x + box.width - 30 - i * 25, box.y + box.height / 2);
  await page.mouse.up();
  await page.waitForTimeout(500);
  await page.locator('.swipe-wrapper', { has: row }).locator('.swipe-action-btn').first().click({ timeout: 5000 })
    .catch(async () => { await page.$eval('.swipe-action-btn', (e) => e.click()); });
  await page.waitForTimeout(700);
  const after = JSON.parse(await readIdbMemos(page)).memos.find((m) => String(m.id) === 'pin_a');
  ok('L2 置顶后 pinned=true', after.pinned === true, JSON.stringify(after.pinned));
  ok('L2 置顶同时刷新 updatedAt', after.updatedAt !== before.updatedAt, `before=${before.updatedAt} after=${after.updatedAt}`);
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR: ' + String(e).split('\n')[0]); }

// ---------- L3 24h 今日时间补零 ----------
try {
  const [ctx, page] = await newPage('zh-CN');
  await importZip(page, '/tmp/fixprobe/time1.zip');
  const meta = await page.$eval('.list-item:has-text("时间目标") .item-meta', (e) => e.innerText);
  // 夹具时刻带 Z 后缀，显示小时随时区变；断言只锁「24h 两位补零」本身
  ok('L3 今日时间 24h 补零（HH:MM 两位）', /^\d{2}:\d{2}/.test(meta), meta.slice(0, 12));
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR: ' + String(e).split('\n')[0]); }

// ---------- S4 上次备份：格式化 + 仅 upload 成功更新 ----------
try {
  // (a) 历史里有 upload 成功条目 → 显示「今天 HH:MM」格式化
  const ctxA = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, locale: 'zh-CN' });
  const at = new Date(); at.setHours(9, 5, 0, 0);
  await ctxA.addInitScript((iso) => {
    localStorage.setItem('mynote_backup_history', JSON.stringify([{ type: 'upload', ok: true, title: '云端备份', at: iso }]));
  }, at.toISOString());
  const pageA = await ctxA.newPage();
  await pageA.goto(base, { waitUntil: 'load' });
  await pageA.waitForSelector('.list-item', { timeout: 20000 });
  await pageA.waitForTimeout(600);
  await gotoBackup(pageA);
  const heroA = await pageA.$eval('.backup-desc', (e) => e.innerText);
  ok('S4a 上次备份显示格式化「今天 09:05」', heroA.includes('今天 09:05'), heroA.replace(/\n/g, ' '));
  await ctxA.close();

  // (b) 无 upload 条目时本地导出后仍显示暂无（不被本地导出更新）
  const [ctx, page] = await newPage();
  await exportFromBackup(page);
  await page.waitForTimeout(800);
  const heroB = await page.$eval('.backup-desc', (e) => e.innerText);
  ok('S4b 本地导出后上次备份仍为暂无', heroB.includes('暂无') && !/T\d{2}:\d{2}:\d{2}/.test(heroB), heroB.replace(/\n/g, ' '));
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR: ' + String(e).split('\n')[0]); }

await browser.close();
console.log(failures === 0 ? 'PROBE ALL PASS' : `PROBE FAILURES: ${failures}`);
process.exit(failures === 0 ? 0 : 1);
