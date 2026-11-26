// 专用探针：诊断页改版（2026-11-25 用户定案）。
//  ① 退役：旧三钮（刷新/复制全部/清空）与 .diag-actions
//     操作区零在场。
//  ② 自动删除行：标签 + 开关（默认关、aria-checked=false）
//     单独一行、行下说明原文在场且位于等级行之上；开启
//     后 31 天前归档被清、2 天前归档保留、偏好落盘、
//     Diag 落 autodel purged 1 结果行。
//  ③ 等级行：单独一行、现值「全部」；点开四档选项，选
//     「错误」后当天卡只剩 ERR 行（info/warn 行隐藏），
//     选「警告」后 warn+error 可见、info 隐藏，偏好落盘。
//  ④ 历史归档胶囊：文本格式 YYYY-MM-DD HH:mm，与种入
//     归档的冻结时刻一致。
//  ⑤ 视窗页（归档）：点胶囊进入——页头返回钮 + 标题
//     「<胶囊文本>.log」+ 导出钮三件套齐，正文终端卡
//     （绿字黑底 computed 实测）含归档行。
//  ⑥ 导出：share 替身下点导出 → share 调 1 次、文件名
//     = 标题、Diag 落 export ok 结果行。
//  ⑦ 当天卡：返回 Diag 页后点当天卡 → 视窗页标题为今
//     日日期 + HH:mm.log，正文含当天行；再返回回 Diag 页。
// 种入走 addInitScript（app 读取前落 localStorage）：
//  当天行 3 条（info / W 标记 warn / ERR error）、归档
//  2 份（31 天前、2 天前，冻结时刻 at 决定胶囊文本与
//  自动删除判定）；sessionStorage 旗防重复种入。
// 用法：node probe_diag_ui.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const DAY = 86400000;
const now = Date.now();
const at31 = now - 31 * DAY;
const at2 = now - 2 * DAY;
const pad = (n) => String(n).padStart(2, '0');
const dayStr = (ms) => { const d = new Date(ms); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
const stampStr = (ms) => { const d = new Date(ms); return `${dayStr(ms)} ${pad(d.getHours())}:${pad(d.getMinutes())}`; };
const todayStampPrefix = dayStr(now);

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
await ctx.addInitScript(({ at31, at2, day }) => {
  if (sessionStorage.getItem('__diagSeeded')) return;
  sessionStorage.setItem('__diagSeeded', '1');
  localStorage.setItem('moment_diag_day_v1', day);
  localStorage.setItem('moment_diag_v1', JSON.stringify([
    '[08:00:01] APP seeded info line',
    '[08:00:02 W] APP seeded warn line',
    '[08:00:03] ERR seeded error line',
  ]));
  localStorage.setItem('moment_diag_archives_v1', JSON.stringify([
    { at: at31, day: 'old-day', lines: ['[07:00:00] APP old archive line'] },
    { at: at2, day: 'recent-day', lines: ['[07:30:00] APP recent archive line', '[07:31:00] ERR recent archive error'] },
  ]));
  window.__shareCalls = 0;
  window.__shareNames = [];
  try {
    Object.defineProperty(navigator, 'share', {
      configurable: true,
      value: (data) => {
        window.__shareCalls++;
        if (data && data.files && data.files[0]) window.__shareNames.push(data.files[0].name);
        return Promise.resolve();
      },
    });
    Object.defineProperty(navigator, 'canShare', { configurable: true, value: () => true });
  } catch (e) { /* 替身装不上则⑥的计数断言会如实判红 */ }
}, { at31, at2, day: todayStampPrefix });
const page = await ctx.newPage();
await page.goto(base, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

// 进诊断页：列表 → 点标题进设置 → 诊断日志行
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 15000 });
await page.waitForTimeout(900);
// 圆角对照基准：设置页数据分组卡（.backup-card）的
// computed border-radius，进 Diag 页后与日志卡对照。
const settingsCardRadius = await page.evaluate(() => {
  const card = document.querySelector('.backup-card');
  return card ? getComputedStyle(card).borderRadius : '';
});
await page.locator('.set-row', { hasText: '诊断日志' }).first().click();
await page.waitForSelector('.diag-page', { timeout: 15000 });
await page.waitForTimeout(600);

const diagLines = () => page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
});
const waitDiag = async (needle, tries = 24) => {
  let lines = [];
  for (let i = 0; i < tries; i++) {
    lines = await diagLines();
    if (lines.some((l) => String(l).includes(needle))) break;
    await page.waitForTimeout(500);
  }
  return lines;
};
const archivesStored = () => page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem('moment_diag_archives_v1') || '[]'); } catch (e) { return []; }
});

// ① 退役零在场
const retired = await page.evaluate(() => {
  const scope = document.querySelector('.diag-page');
  const btns = [...scope.querySelectorAll('button')].map((b) => b.innerText.trim());
  return {
    actions: !!scope.querySelector('.diag-actions'),
    copyBtn: btns.some((t) => t.includes('复制全部')),
    refreshBtn: btns.some((t) => t === '刷新'),
    clearBtn: btns.some((t) => t === '清空'),
  };
});
ok('① .diag-actions 操作区不在场', !retired.actions);
ok('① 复制全部/刷新/清空三钮不在场', !retired.copyBtn && !retired.refreshBtn && !retired.clearBtn, JSON.stringify(retired));

// ② 自动删除行 + 说明 + 顺序（等级行在其下）
const rows = await page.evaluate(() => {
  const grab = (sel) => { const e = document.querySelector(sel); if (!e) return null; const r = e.getBoundingClientRect(); return { top: r.top, text: e.innerText.trim() }; };
  const sw = document.querySelector('.diag-page .editor-column-toggle-track');
  const note = [...document.querySelectorAll('.diag-note')].map((e) => e.innerText.trim());
  return {
    autodelRow: grab('.diag-page .backup-card .set-row'),
    note,
    switchChecked: sw ? sw.getAttribute('aria-checked') : null,
    switchIsButton: sw ? sw.tagName : null,
  };
});
ok('② 自动删除行在场（首行含「自动删除日志」）', !!rows.autodelRow && rows.autodelRow.text.includes('自动删除日志'), rows.autodelRow && rows.autodelRow.text);
ok('② 开关为 button 且默认关（aria-checked=false）', rows.switchIsButton === 'BUTTON' && rows.switchChecked === 'false', `${rows.switchIsButton}/${rows.switchChecked}`);
ok('② 说明原文在场', rows.note.some((t) => t === '开启后日志超过30天自动删除'), JSON.stringify(rows.note));
const levelRowBox = await page.locator('.diag-page .set-row', { hasText: '日志等级' }).first().boundingBox();
const noteBox = await page.locator('.diag-note').first().boundingBox();
const autodelBox = await page.locator('.diag-page .set-row', { hasText: '自动删除日志' }).first().boundingBox();
ok('② 说明在自动删除行之下、等级行之上', !!autodelBox && !!noteBox && !!levelRowBox && noteBox.y > autodelBox.y && noteBox.y < levelRowBox.y,
  `autodel=${autodelBox && autodelBox.y} note=${noteBox && noteBox.y} level=${levelRowBox && levelRowBox.y}`);

// ④ 胶囊（先于自动删除开启验证：两份都在）
const capsules0 = await page.locator('.diag-capsule').allInnerTexts();
ok('④ 归档胶囊 2 枚', capsules0.length === 2, JSON.stringify(capsules0));
ok('④ 胶囊文本格式 YYYY-MM-DD HH:mm', capsules0.every((t) => /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(t.trim())), JSON.stringify(capsules0));
ok('④ 胶囊含 2 天前归档的冻结时刻', capsules0.map((t) => t.trim()).includes(stampStr(at2)), `want ${stampStr(at2)}`);

// ③ 等级行与过滤
const levelValue0 = await page.locator('.diag-level-value').innerText();
ok('③ 等级行现值为「全部」', levelValue0.trim() === '全部', levelValue0.trim());
const todayText = () => page.$eval('.diag-today', (e) => e.innerText);
const todayRadius = await page.evaluate(() => getComputedStyle(document.querySelector('.diag-today')).borderRadius);
ok('③ 圆角对齐：当天卡 computed border-radius == 设置数据卡', todayRadius === settingsCardRadius && settingsCardRadius !== '', `${todayRadius} vs ${settingsCardRadius}`);
let tt = await todayText();
ok('③ 全部档：info/warn/error 三行皆显', tt.includes('seeded info line') && tt.includes('seeded warn line') && tt.includes('seeded error line'));
await page.locator('.diag-page .set-row', { hasText: '日志等级' }).first().click();
await page.waitForSelector('.diag-level-opts .seg-btn', { timeout: 5000 });
const optTexts = await page.locator('.diag-level-opts .seg-btn').allInnerTexts();
ok('③ 点开四档选项（全部/信息/警告/错误）', optTexts.map((t) => t.trim()).join('/') === '全部/信息/警告/错误', JSON.stringify(optTexts));
await page.locator('.diag-level-opts .seg-btn', { hasText: '错误' }).click();
await page.waitForTimeout(400);
tt = await todayText();
ok('③ 错误档：只剩 error 行', tt.includes('seeded error line') && !tt.includes('seeded info line') && !tt.includes('seeded warn line'));
const levelPref1 = await page.evaluate(() => localStorage.getItem('moment_diag_level_v1'));
ok('③ 等级偏好落盘（error）', levelPref1 === 'error', String(levelPref1));
const levelValue1 = await page.locator('.diag-level-value').innerText();
ok('③ 等级行现值更新为「错误」', levelValue1.trim() === '错误', levelValue1.trim());
await page.locator('.diag-page .set-row', { hasText: '日志等级' }).first().click();
await page.waitForSelector('.diag-level-opts .seg-btn', { timeout: 5000 });
await page.locator('.diag-level-opts .seg-btn', { hasText: '警告' }).click();
await page.waitForTimeout(400);
tt = await todayText();
ok('③ 警告档：warn+error 可见、info 隐藏', tt.includes('seeded warn line') && tt.includes('seeded error line') && !tt.includes('seeded info line'));
await page.locator('.diag-page .set-row', { hasText: '日志等级' }).first().click();
await page.waitForSelector('.diag-level-opts .seg-btn', { timeout: 5000 });
await page.locator('.diag-level-opts .seg-btn', { hasText: '全部' }).click();
await page.waitForTimeout(400);
tt = await todayText();
ok('③ 复位全部档：三行皆显', tt.includes('seeded info line') && tt.includes('seeded warn line') && tt.includes('seeded error line'));

// ② 自动删除开启 → 清 31 天前、留 2 天前
await page.locator('.diag-page .editor-column-toggle-track').click();
await page.waitForTimeout(500);
const swAfter = await page.evaluate(() => document.querySelector('.diag-page .editor-column-toggle-track').getAttribute('aria-checked'));
ok('② 开启后开关 aria-checked=true', swAfter === 'true', String(swAfter));
const autodelPref = await page.evaluate(() => localStorage.getItem('moment_diag_autodel_v1'));
ok('② 自动删除偏好落盘（1）', autodelPref === '1', String(autodelPref));
const archAfter = await archivesStored();
ok('② 31 天前归档已清、2 天前保留', archAfter.length === 1 && archAfter[0].at === at2, JSON.stringify(archAfter.map((a) => a.at)));
const capsules1 = await page.locator('.diag-capsule').allInnerTexts();
ok('② 清后胶囊剩 1 枚（2 天前）', capsules1.length === 1 && capsules1[0].trim() === stampStr(at2), JSON.stringify(capsules1));
const purgeLines = await waitDiag('DIAG autodel purged 1');
ok('② Diag 落 autodel purged 1 结果行', purgeLines.some((l) => String(l).includes('DIAG autodel purged 1')));

// ⑤ 点胶囊进视窗页（归档）
await page.locator('.diag-capsule').first().click();
await page.waitForSelector('.diag-log-page', { timeout: 15000 });
await page.waitForTimeout(700);
const viewer = await page.evaluate(() => {
  const title = document.querySelector('.diag-log-page .page-title');
  const bodyEl = document.querySelector('.diag-log-page .diag-body');
  const cs = bodyEl ? getComputedStyle(bodyEl) : null;
  return {
    title: title ? title.innerText.trim() : '',
    hasBack: !!document.querySelector('.diag-log-page .editor-fab.left'),
    exportText: (document.querySelector('.diag-export-btn') || {}).innerText || '',
    body: bodyEl ? bodyEl.innerText : '',
    color: cs ? cs.color : '',
    bg: cs ? cs.backgroundColor : '',
    radius: cs ? cs.borderRadius : '',
  };
});
ok('⑤ 视窗页标题 = 胶囊文本 + .log', viewer.title === `${stampStr(at2)}.log`, viewer.title);
ok('⑤ 页头三件套：返回钮 + 导出钮（导出）', viewer.hasBack && viewer.exportText.trim() === '导出', JSON.stringify({ back: viewer.hasBack, exp: viewer.exportText }));
ok('⑤ 正文含归档行（info+error）', viewer.body.includes('recent archive line') && viewer.body.includes('recent archive error'));
ok('⑤ 正文终端卡绿字黑底（computed）', viewer.color === 'rgb(124, 252, 154)' && viewer.bg === 'rgb(17, 17, 17)', `${viewer.color}/${viewer.bg}`);
ok('⑤ 圆角对齐：视窗正文卡 computed border-radius == 设置数据卡', viewer.radius === settingsCardRadius && settingsCardRadius !== '', `${viewer.radius} vs ${settingsCardRadius}`);

// ⑥ 导出走 share 替身
await page.locator('.diag-export-btn').click();
await page.waitForTimeout(600);
const shareInfo = await page.evaluate(() => ({ calls: window.__shareCalls, names: window.__shareNames }));
ok('⑥ share 调 1 次', shareInfo.calls === 1, `calls=${shareInfo.calls}`);
ok('⑥ 分享文件名 = 视窗标题', shareInfo.names.length === 1 && shareInfo.names[0] === `${stampStr(at2)}.log`, JSON.stringify(shareInfo.names));
const exportLinesResult = await waitDiag('DIAG export ok');
ok('⑥ Diag 落 export ok 结果行', exportLinesResult.some((l) => String(l).includes('DIAG export ok')));

// ⑦ 返回 → 当天卡进视窗页 → 再返回
await page.locator('.diag-log-page .editor-fab.left').click();
await page.waitForSelector('.diag-page', { timeout: 15000 });
await page.waitForTimeout(800);
await page.locator('.diag-today').click();
await page.waitForSelector('.diag-log-page', { timeout: 15000 });
await page.waitForTimeout(700);
const todayViewer = await page.evaluate(() => {
  const title = document.querySelector('.diag-log-page .page-title');
  const bodyEl = document.querySelector('.diag-log-page .diag-body');
  return { title: title ? title.innerText.trim() : '', body: bodyEl ? bodyEl.innerText : '' };
});
ok('⑦ 当天视窗标题为今日日期 + HH:mm.log', todayViewer.title.startsWith(todayStampPrefix) && / \d{2}:\d{2}\.log$/.test(todayViewer.title), todayViewer.title);
ok('⑦ 当天视窗正文含当天行', todayViewer.body.includes('seeded info line') && todayViewer.body.includes('seeded error line'));
await page.locator('.diag-log-page .editor-fab.left').click();
await page.waitForSelector('.diag-page', { timeout: 15000 });
await page.waitForTimeout(500);
ok('⑦ 返回落回 Diag 页', await page.evaluate(() => !!document.querySelector('.diag-page .diag-today')));

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
