// 外围波验证探针：备份页 toast 根治（G1/G2/G3）+ 诊断页
// overscroll（S9）+ 灯箱数值对齐（E6）。Rust 构建 @8197。
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = process.argv[2] || 'http://localhost:8197/';
const REAL = process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip';
fs.writeFileSync('/tmp/notabackup.zip', 'this is not a zip at all');
let fails = 0;
const ok = (name, cond, extra = '') => { console.log(`${cond ? '✓' : '✗'} ${name} ${extra}`); if (!cond) fails++; };

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 150)));
await page.goto(BASE, { waitUntil: 'load' });
await page.waitForSelector('.list-item, .img-card, .new-card', { timeout: 20000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });

// ---- info toast（Drive 连接 → 待定提示，spinner） ----
await page.click('.backup-btn.primary:has-text("Google")').catch(() => page.click('.backup-card .backup-btn.primary'));
await page.waitForSelector('.backup-toast', { timeout: 8000 });
await page.waitForTimeout(500); // 等入场动画（scale .94→1）结束再量几何
const info = await page.evaluate(() => {
  const t = document.querySelector('.backup-toast');
  const r = t.getBoundingClientRect();
  const cs = getComputedStyle(t);
  return {
    x: Math.round(r.x), w: Math.round(r.width), radius: cs.borderRadius,
    spinner: !!t.querySelector('.backup-toast-spinner'),
    text: t.innerText,
  };
});
console.log('INFO-TOAST', JSON.stringify(info));
ok('info toast 全宽条 x=16 w=vw-32', info.x === 16 && info.w === 393 - 32, `x=${info.x} w=${info.w}`);
ok('info toast radius 28px', info.radius === '28px', info.radius);
ok('info toast 带 spinner', info.spinner);
// info toast 6s 到期卸载后再进导入流程，避免 waitForSelector 误匹配
await page.waitForFunction(() => !document.querySelector('.backup-toast'), null, { timeout: 9000 });
ok('info toast 6s 后卸载', true);

// ---- 成功 toast 第一次：导入真实备份 ----
await page.setInputFiles('#file-import', REAL);
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForSelector('.backup-toast', { timeout: 15000 });
const s1 = await page.evaluate(() => {
  const t = document.querySelector('.backup-toast');
  return { text: t.innerText, icon: t.querySelector('.backup-toast-icon')?.textContent || '', cls: t.className };
});
console.log('SUCCESS-TOAST-1', JSON.stringify(s1));
ok('success toast 文案含已导入', s1.text.includes('已导入'), s1.text);
ok('success toast 带 ✅ 图标', s1.icon === '✅', s1.icon);
// G3：3s 后应被计时器卸载（非 CSS 淡出残留）
await page.waitForFunction(() => !document.querySelector('.backup-toast'), null, { timeout: 6000 });
ok('success toast 3s 后 DOM 已卸载 (G3)', true);

// ---- G1：同文案第二次触发必须可见 ----
await page.setInputFiles('#file-import', REAL);
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForSelector('.backup-toast', { timeout: 15000 });
await page.waitForTimeout(450); // 入场动画结束
const s2 = await page.evaluate(() => {
  const t = document.querySelector('.backup-toast');
  const cs = getComputedStyle(t);
  return { text: t.innerText, opacity: cs.opacity, visibility: cs.visibility };
});
console.log('SUCCESS-TOAST-2', JSON.stringify(s2));
ok('同文案第二次 toast 可见 (G1)', s2.text.includes('已导入') && s2.opacity === '1' && s2.visibility === 'visible', JSON.stringify(s2));
await page.waitForFunction(() => !document.querySelector('.backup-toast'), null, { timeout: 6000 });
ok('第二次 toast 同样按时卸载', true);

// ---- 错误 toast：坏 zip 两连发，第二次重置计时 ----
await page.setInputFiles('#file-import', '/tmp/notabackup.zip');
await page.waitForSelector('.backup-toast', { timeout: 8000 });
await page.waitForTimeout(1200);
await page.setInputFiles('#file-import', '/tmp/notabackup.zip');
await page.waitForTimeout(300);
const e2 = await page.evaluate(() => {
  const t = document.querySelector('.backup-toast');
  return t ? { text: t.innerText, icon: t.querySelector('.backup-toast-icon')?.textContent || '' } : null;
});
console.log('ERROR-TOAST-2', JSON.stringify(e2));
ok('error toast 带 ❌ 且文案本地化', !!e2 && e2.icon === '❌' && e2.text.includes('导入失败'), JSON.stringify(e2));
await page.waitForTimeout(4500); // 距第二次触发约 4.8s < 6s：应仍在
ok('error toast 6s 内仍在（计时被第二次重置）', await page.$('.backup-toast') !== null);
await page.waitForFunction(() => !document.querySelector('.backup-toast'), null, { timeout: 5000 });
ok('error toast 6s 后卸载', true);

// ---- S9：诊断页 .diag-body overscroll ----
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("诊断")');
await page.waitForSelector('.diag-body', { timeout: 8000 });
const ob = await page.evaluate(() => getComputedStyle(document.querySelector('.diag-body')).overscrollBehavior);
console.log('DIAG-OVERSCROLL', ob);
ok('.diag-body overscroll-behavior: contain (S9)', ob === 'contain', ob);
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.img-card', { timeout: 10000 });

// ---- E6：灯箱数值 ----
await page.click('.img-card:has-text("冬日")');
await page.waitForSelector('.detail img.blk-media', { timeout: 8000 });
await page.waitForFunction(() => document.querySelector('.detail img.blk-media')?.naturalWidth > 0, { timeout: 10000 });
await page.click('.detail img.blk-media');
await page.waitForSelector('.lightbox', { timeout: 8000 });
const lb = await page.evaluate(() => {
  const t = document.querySelector('.lightbox');
  const cs = getComputedStyle(t);
  const img = t.querySelector('img');
  return { z: cs.zIndex, bg: cs.backgroundColor, cursor: cs.cursor, imgRadius: img ? getComputedStyle(img).borderRadius : '' };
});
console.log('LIGHTBOX', JSON.stringify(lb));
ok('灯箱 z-index 10000 (E6)', lb.z === '10000', lb.z);
ok('灯箱底色 rgba(0,0,0,0.88) (E6)', lb.bg === 'rgba(0, 0, 0, 0.88)', lb.bg);
ok('灯箱 cursor zoom-out + 图片圆角 12px', lb.cursor === 'zoom-out' && lb.imgRadius === '12px', `${lb.cursor}/${lb.imgRadius}`);
await page.click('.lightbox');
await page.waitForTimeout(400);
ok('灯箱点按关闭', await page.$('.lightbox') === null);

await browser.close();
console.log(fails === 0 ? 'PROBE-PERIPHERY ALL PASS' : `PROBE-PERIPHERY ${fails} FAILED`);
process.exit(fails === 0 ? 0 : 1);
