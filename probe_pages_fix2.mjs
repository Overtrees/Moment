// 每页审计 设置/备份/列表 剩余项专项探针（审计 S3/S5/S6/S7、
// L4/L5、S9）。用法: node probe_pages_fix2.mjs [baseUrl]
// 默认 http://localhost:8119/（需先起 serve_headers 服务于新 dist）。
// 每项断言同时打印实测值，便于修前/修后对照。
import { chromium } from 'playwright-core';
import { execSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const base = process.argv[2] || 'http://localhost:8119/';
let failures = 0;
const ok = (cond, name, extra = '') => {
  console.log((cond ? '✓' : '✗') + ' ' + name + (extra ? ' | ' + extra : ''));
  if (!cond) failures++;
};

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
async function newPage(lang = 'zh-CN') {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, locale: lang });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => { console.log('PAGEERROR', String(e)); failures++; });
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  return [ctx, page];
}
// 设置入口：JS dispatch 点 page-title（冒烟既有约定）
async function gotoSettings(page) {
  await page.evaluate(() => document.querySelector('h1.page-title, .page-title').dispatchEvent(new MouseEvent('click', { bubbles: true })));
  await page.waitForSelector('.backup-card', { timeout: 10000 });
}
async function gotoBackup(page) {
  await gotoSettings(page);
  await page.locator('.set-row').filter({ hasText: '备份与恢复' }).first().click();
  await page.waitForSelector('.backup-hero', { timeout: 10000 });
}
function makeZip(memos, atts = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pz-'));
  const files = { 'memos.json': JSON.stringify({ version: 2, exportedAt: '2026-11-21T00:00:00.000Z', memos, avatars: {} }), 'manifest.json': JSON.stringify({ version: 1, attachments: atts }) };
  for (const [k, v] of Object.entries(files)) fs.writeFileSync(path.join(dir, k), v);
  const out = path.join(dir, 'fixture.zip');
  execSync(`cd ${dir} && zip -q fixture.zip memos.json manifest.json`);
  return out;
}
const para = (id, text) => ({ id, type: 'paragraph', children: [{ text }] });
const attNode = (id, fid, name) => ({ id, type: 'attachment', fileId: fid, name });
const histCardText = (page) => page.evaluate(() => {
  const titles = [...document.querySelectorAll('.backup-section-title')];
  const t = titles.find((e) => e.innerText.includes('最近操作'));
  const card = t ? t.nextElementSibling : null;
  return card ? card.innerText : '';
});

// ---------- S3/S6: 导出确认表（标题/文案/按钮序） ----------
try {
  const [ctx, page] = await newPage();
  await gotoBackup(page);
  await page.locator('.backup-row').filter({ hasText: '导出备份' }).first().click();
  await page.waitForSelector('.backup-modal', { timeout: 5000 });
  const title = await page.$eval('.backup-modal-title', (e) => e.innerText);
  ok(title === '确认导出备份', 'S3 导出确认表标题=确认导出备份', title);
  const msg = await page.$eval('.backup-modal-msg', (e) => e.innerText);
  ok(msg.includes('头像') && msg.includes('分享面板'), 'S6 导出确认文案含头像+分享面板', msg);
  const btns = await page.$$eval('.backup-modal-actions .backup-btn', (els) => els.map((e) => ({ t: e.innerText, cls: e.className, y: e.getBoundingClientRect().y })));
  ok(btns.length === 2 && btns[0].cls.includes('primary') && btns[0].y < btns[1].y, 'S3 按钮序：确认（primary）在上、取消在下', JSON.stringify(btns));
  await page.locator('.backup-modal-actions .backup-btn.secondary').click();
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR S3/S6: ' + String(e).split('\n')[0]); }

// ---------- S5: 历史条目（导出成功 detail / 只渲染 6 条 / 状态点）+ S7 坏 zip ----------
try {
  const [ctx, page] = await newPage();
  await gotoBackup(page);
  await page.locator('.backup-row').filter({ hasText: '导出备份' }).first().click();
  await page.waitForSelector('.backup-modal', { timeout: 5000 });
  await page.locator('.backup-modal-actions .backup-btn.primary').click();
  await page.waitForSelector('.status-toast', { timeout: 10000 });
  await page.waitForTimeout(600);
  const histText1 = await histCardText(page);
  ok(histText1.includes('备份已下载'), 'S5 导出成功条目标题=备份已下载', histText1.replace(/\n/g, ' / ').slice(0, 120));
  ok(/此刻备份_\d{4}-\d{2}-\d{2}\.zip/.test(histText1), 'S5 导出条目 detail=文件名', histText1.replace(/\n/g, ' / ').slice(0, 120));
  ok(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(histText1), 'S5 条目时间戳为 YYYY-MM-DD HH:MM', histText1.replace(/\n/g, ' / ').slice(0, 120));
  const badPath = path.join(os.tmpdir(), 'bad-fixture.zip');
  fs.writeFileSync(badPath, 'this is not a zip at all');
  await page.setInputFiles('#file-import', badPath);
  await page.waitForSelector('.status-toast', { timeout: 10000 });
  const toast = await page.$eval('.status-toast', (e) => e.innerText);
  ok(!/EOCD|invalid Zip|zip:/i.test(toast), 'S7 坏 zip toast 无英文内部原文', toast);
  ok(toast.includes('不是有效的备份'), 'S7 坏 zip toast 为本地化文案', toast);
  await page.waitForTimeout(600);
  const histText2 = await histCardText(page);
  ok(histText2.includes('导入失败'), 'S5 失败也记历史（导入失败条目）', histText2.replace(/\n/g, ' / ').slice(0, 120));
  await page.evaluate(() => {
    const arr = [];
    for (let i = 0; i < 8; i++) arr.push({ type: 'export', ok: true, title: '条目' + i, detail: 'd' + i, at: '2026-11-21T0' + i + ':00:00.000Z' });
    localStorage.setItem('mynote_backup_history', JSON.stringify(arr));
  });
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await gotoBackup(page);
  const rowCount = await page.evaluate(() => {
    const titles = [...document.querySelectorAll('.backup-section-title')];
    const t = titles.find((e) => e.innerText.includes('最近操作'));
    const card = t ? t.nextElementSibling : null;
    return card ? card.children.length : -1;
  });
  ok(rowCount === 6, 'S5 历史只渲染前 6 条', 'rows=' + rowCount);
  const dotBg = await page.evaluate(() => {
    const titles = [...document.querySelectorAll('.backup-section-title')];
    const t = titles.find((e) => e.innerText.includes('最近操作'));
    const card = t ? t.nextElementSibling : null;
    const dot = card ? card.querySelector('span') : null;
    return dot ? getComputedStyle(dot).backgroundColor : '';
  });
  ok(dotBg && dotBg !== 'rgba(0, 0, 0, 0)', 'S5 条目带状态色点', dotBg);
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR S5/S7: ' + String(e).split('\n')[0]); }

// ---------- S9: 附件计数（孤儿附件不计）+ S3 导入表标题 + S5 恢复条目 ----------
try {
  const [ctx, page] = await newPage();
  const zip = makeZip(
    [{ id: 's9a', title: '计数备忘', pinned: false, createdAt: '2026-11-20T00:00:00.000Z', updatedAt: '2026-11-20T00:00:00.000Z', doc: [attNode('n1', 'fid-used', 'used.pdf')] }],
    { 'fid-used': { name: 'used.pdf' }, 'fid-orphan': { name: 'orphan.pdf' } },
  );
  await gotoBackup(page);
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 5000 });
  const ititle = await page.$eval('.backup-modal-title', (e) => e.innerText);
  ok(ititle === '确认恢复备份', 'S3 导入确认表标题=确认恢复备份', ititle);
  await page.locator('.backup-modal-actions .backup-btn.primary').click();
  await page.waitForSelector('.status-toast', { timeout: 10000 });
  await page.waitForTimeout(600);
  const hero = await page.$eval('.backup-desc', (e) => e.innerText);
  ok(hero.includes('1 个附件') && !hero.includes('2 个附件'), 'S9 附件计数=doc 引用去重（孤儿不计）', hero);
  const histText3 = await histCardText(page);
  ok(histText3.includes('从本地文件恢复') && histText3.includes('fixture.zip'), 'S5 恢复条目 message+detail=文件名', histText3.replace(/\n/g, ' / ').slice(0, 140));
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR S9: ' + String(e).split('\n')[0]); }

// ---------- L4/L5: 列表（收起 ▲ / 置顶按钮「取消」） ----------
try {
  const [ctx, page] = await newPage();
  const memos = [];
  for (let i = 0; i < 4; i++) {
    memos.push({ id: 'lx' + i, title: '折叠目标' + i, pinned: false, createdAt: '2026-11-21T0' + i + ':00:00.000Z', updatedAt: '2026-11-21T0' + i + ':00:00.000Z', doc: [para('p' + i, '正文' + i)] });
  }
  memos.push({ id: 'lxpin', title: '已置顶备忘', pinned: true, createdAt: '2026-11-19T00:00:00.000Z', updatedAt: '2026-11-19T00:00:00.000Z', doc: [para('pp', '置顶正文')] });
  const zip = makeZip(memos);
  await gotoBackup(page);
  await page.setInputFiles('#file-import', zip);
  await page.waitForSelector('.backup-modal', { timeout: 5000 });
  await page.locator('.backup-modal-actions .backup-btn.primary').click();
  await page.waitForSelector('.status-toast', { timeout: 10000 });
  await page.locator('.editor-fab.left').click();
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.locator('.editor-fab.left').click().catch(() => {});
  await page.waitForSelector('.list-item', { timeout: 10000 });
  await page.waitForTimeout(500);
  const expandPill = page.locator('text=/▼ 展开/').first();
  if (await expandPill.count()) { await expandPill.click(); await page.waitForTimeout(400); }
  const bodyText = await page.evaluate(() => document.body.innerText);
  ok(bodyText.includes('▲ 收起'), 'L4 展开后末卡文案=▲ 收起', bodyText.includes('收起') ? 'has 收起 without ▲' : 'no 收起');
  const row = page.locator('.list-item:has-text("已置顶备忘")').first();
  const box = await row.boundingBox();
  if (box) {
    await page.mouse.move(box.x + box.width - 20, box.y + box.height / 2);
    await page.mouse.down();
    for (let dx = 0; dx <= 120; dx += 20) await page.mouse.move(box.x + box.width - 20 - dx, box.y + box.height / 2);
    await page.mouse.up();
    await page.waitForTimeout(500);
  }
  const swipeText = await page.evaluate(() => {
    const btns = [...document.querySelectorAll('.swipe-action-btn span')];
    return btns.map((b) => b.innerText).join('|');
  });
  ok(swipeText.split('|').includes('取消'), 'L5 已置顶滑动按钮文案=取消', swipeText);
  ok(!swipeText.includes('取消置顶'), 'L5 无「取消置顶」残留', swipeText);
  await ctx.close();
} catch (e) { failures++; console.log('✗ SECTION ERROR L4/L5: ' + String(e).split('\n')[0]); }

await browser.close();
console.log(failures === 0 ? 'PROBE ALL PASS' : 'PROBE FAILURES: ' + failures);
process.exit(failures === 0 ? 0 : 1);
