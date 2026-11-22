// 审计探针：设置/备份/诊断 —— Rust(8100) vs 原版(8101)，只读审计用
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const RUST = 'http://localhost:8100/', ORIG = 'http://localhost:8101/Moment.html';
const REAL = process.env.HOME + '/workspace/mynote-zip-acceptance/real_backup.zip';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const R = {};
const log = (k, v) => { R[k] = v; console.log(k + ':', typeof v === 'string' ? v : JSON.stringify(v)); };
async function newPage(url) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGEERROR', url, String(e).slice(0, 200)));
  await page.goto(url, { waitUntil: 'load' });
  return [ctx, page];
}
const txt = page => page.evaluate(() => document.body.innerText);

// ============ RUST ============
{
  const [ctx, page] = await newPage(RUST);
  await page.waitForSelector('.list-item', { timeout: 20000 });
  await page.waitForTimeout(800);
  log('rust.seedListText', (await txt(page)).slice(0, 300).replace(/\n/g, ' | '));
  await page.$eval('h1.page-title', e => e.click());
  await page.waitForSelector('.page-content', { timeout: 8000 });
  await page.waitForTimeout(400);
  log('rust.settings', await page.evaluate(() => ({
    title: document.querySelector('.page-title')?.innerText,
    sections: [...document.querySelectorAll('.section-header')].map(e => e.innerText),
    rows: [...document.querySelectorAll('.set-row,.list-item')].map(e => e.innerText.replace(/\n/g, ' / ')),
    seg: [...document.querySelectorAll('.seg-btn')].map(e => e.innerText + (e.classList.contains('sel') ? '(sel)' : '')),
    about: [...document.querySelectorAll('.about-row')].map(e => e.innerText.replace(/\n/g, ' / ')),
    body: document.body.innerText.replace(/\n/g, ' | '),
    rootFs: document.documentElement.style.fontSize || getComputedStyle(document.documentElement).fontSize,
  })));
  // 字号 大
  await page.click('.seg-btn:has-text("大")'); await page.waitForTimeout(350);
  log('rust.fontLarge', await page.evaluate(() => ({ rootStyle: document.documentElement.style.fontSize, computed: getComputedStyle(document.documentElement).fontSize, ls: localStorage.getItem('sj_fontsize'), titleFs: getComputedStyle(document.querySelector('.page-title')).fontSize })));
  // reload 持久
  await page.reload({ waitUntil: 'load' }); await page.waitForSelector('.list-item', { timeout: 20000 }); await page.waitForTimeout(500);
  log('rust.fontAfterReloadList', await page.evaluate(() => ({ rootStyle: document.documentElement.style.fontSize, computed: getComputedStyle(document.documentElement).fontSize, ls: localStorage.getItem('sj_fontsize'), itemTitleFs: getComputedStyle(document.querySelector('.item-title-text')).fontSize })));
  await page.$eval('h1.page-title', e => e.click()); await page.waitForSelector('.page-content'); await page.waitForTimeout(300);
  log('rust.fontSelAfterReload', await page.evaluate(() => [...document.querySelectorAll('.seg-btn')].map(e => e.innerText + (e.classList.contains('sel') ? '(sel)' : '')).join(',')));
  await page.click('.seg-btn:has-text("中")'); await page.waitForTimeout(300);
  log('rust.fontMedium', await page.evaluate(() => document.documentElement.style.fontSize + '/' + localStorage.getItem('sj_fontsize')));
  // 语言页
  await page.click('.set-row:has-text("语言")'); await page.waitForTimeout(600);
  log('rust.langInitial', await page.evaluate(() => [...document.querySelectorAll('.list-item')].map(e => e.innerText.replace(/\n/g, ' / '))));
  const dlP = page.waitForResponse(r => r.url().includes('lang/en-US.json'), { timeout: 10000 }).catch(() => null);
  await page.click('.list-item:has-text("English")'); 
  const dl = await dlP; log('rust.langFetch', dl ? dl.status() + ' ' + dl.url() : 'no fetch observed');
  await page.waitForTimeout(1200);
  log('rust.langAfterEn', await page.evaluate(() => ({ title: document.querySelector('.page-title')?.innerText, ls_lang: localStorage.getItem('mynote_lang'), pack: !!localStorage.getItem('mynote_pack_en-US'), rows: [...document.querySelectorAll('.list-item')].map(e => e.innerText.replace(/\n/g, ' / ')) })));
  await page.click('.editor-fab.left'); await page.waitForTimeout(500);
  log('rust.settingsAfterEn', (await txt(page)).slice(0, 400).replace(/\n/g, ' | '));
  await page.reload({ waitUntil: 'load' }); await page.waitForSelector('.list-item', { timeout: 20000 }); await page.waitForTimeout(600);
  await page.$eval('h1.page-title', e => e.click()); await page.waitForTimeout(500);
  log('rust.langPersistReload', await page.evaluate(() => document.querySelector('.page-title')?.innerText + ' / lang=' + localStorage.getItem('mynote_lang')));
  // 切回 zh-CN
  await page.evaluate(() => { const rows = [...document.querySelectorAll('.set-row')]; const r = rows.find(e => /Language|语言/.test(e.innerText)); r && r.click(); });
  await page.waitForTimeout(600);
  await page.click('.list-item:has-text("简体中文")'); await page.waitForTimeout(800);
  log('rust.langBackZh', await page.evaluate(() => document.querySelector('.page-title')?.innerText + ' / ' + localStorage.getItem('mynote_lang')));
  // 备份页
  await page.click('.editor-fab.left'); await page.waitForTimeout(400);
  await page.click('.set-row:has-text("备份与恢复")'); await page.waitForSelector('.backup-hero', { timeout: 8000 }); await page.waitForTimeout(400);
  log('rust.backupInitial', await page.evaluate(() => ({ hero: document.querySelector('.backup-hero')?.innerText.replace(/\n/g, ' / '), rows: [...document.querySelectorAll('.backup-row')].map(e => e.innerText.replace(/\n/g, ' / ')), body: document.body.innerText.replace(/\n/g, ' | ').slice(0, 600) })));
  // Drive 连接按钮
  await page.click('.backup-action-bar .backup-btn.primary'); await page.waitForTimeout(500);
  log('rust.driveToast', await page.evaluate(() => document.querySelector('.status-toast')?.innerText || 'NO TOAST'));
  // 导出：确认弹窗形态 + 下载
  const dlEvent = page.waitForEvent('download', { timeout: 15000 }).catch(() => null);
  await page.click('.backup-row:has-text("导出备份")'); await page.waitForTimeout(500);
  log('rust.exportModal', await page.evaluate(() => { const m = document.querySelector('.backup-modal'); if (!m) return 'NO MODAL'; const r = m.getBoundingClientRect(); const btns = [...m.querySelectorAll('.backup-btn')].map(b => { const br = b.getBoundingClientRect(); return b.innerText + '@y' + Math.round(br.y) + 'x' + Math.round(br.x) + 'w' + Math.round(br.width); }); return { rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)], viewportH: innerHeight, text: m.innerText.replace(/\n/g, ' / '), btns, actionsDir: getComputedStyle(m.querySelector('.backup-modal-actions')).flexDirection }; }));
  await page.click('.backup-modal .backup-btn.primary');
  const dl2 = await dlEvent;
  if (dl2) { const p = await dl2.path(); log('rust.exportDownload', { name: dl2.suggestedFilename(), size: fs.statSync(p).size }); fs.copyFileSync(p, '/tmp/rust_export.zip'); }
  else log('rust.exportDownload', 'NO DOWNLOAD EVENT');
  await page.waitForTimeout(800);
  log('rust.afterExport', await page.evaluate(() => ({ toast: document.querySelector('.status-toast')?.innerText || 'none', hist: localStorage.getItem('mynote_backup_history'), last: localStorage.getItem('mynote_last_backup'), hero: document.querySelector('.backup-hero')?.innerText.replace(/\n/g, ' / '), histRows: [...document.querySelectorAll('.backup-card .backup-row')].map(e => e.innerText.replace(/\n/g, ' / ')) })));
  // reload 历史持久
  await page.reload({ waitUntil: 'load' }); await page.waitForSelector('.list-item', { timeout: 20000 }); await page.waitForTimeout(400);
  await page.$eval('h1.page-title', e => e.click()); await page.waitForTimeout(400);
  await page.click('.set-row:has-text("备份与恢复")'); await page.waitForSelector('.backup-hero'); await page.waitForTimeout(400);
  log('rust.historyAfterReload', await page.evaluate(() => [...document.querySelectorAll('.backup-row')].map(e => e.innerText.replace(/\n/g, ' / '))));
  // 点历史条目：有无恢复/弹窗
  const histCountBefore = await page.evaluate(() => localStorage.getItem('mynote_backup_history'));
  await page.evaluate(() => { const rows = [...document.querySelectorAll('.backup-row')]; const h = rows[rows.length - 1]; h && h.click(); });
  await page.waitForTimeout(600);
  log('rust.historyClick', await page.evaluate(() => ({ modal: !!document.querySelector('.backup-modal'), histSame: localStorage.getItem('mynote_backup_history') === window.__hb, hero: document.querySelector('.backup-hero')?.innerText.replace(/\n/g, ' / ') })).catch(e => 'err ' + e));
  // 导入取消
  await page.setInputFiles('#file-import', REAL); await page.waitForTimeout(700);
  log('rust.importModal', await page.evaluate(() => { const m = document.querySelector('.backup-modal'); if (!m) return 'NO MODAL'; const r = m.getBoundingClientRect(); return { rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)], text: m.innerText.replace(/\n/g, ' / ') }; }));
  const heroBeforeCancel = await page.$eval('.backup-hero', e => e.innerText);
  await page.click('.backup-modal .backup-btn.secondary'); await page.waitForTimeout(500);
  log('rust.importCancel', await page.evaluate(hb => ({ modalGone: !document.querySelector('.backup-modal'), heroSame: document.querySelector('.backup-hero')?.innerText === hb }), heroBeforeCancel));
  // 导入确认
  await page.setInputFiles('#file-import', REAL); await page.waitForTimeout(700);
  await page.click('.backup-modal .backup-btn.primary'); await page.waitForTimeout(1500);
  log('rust.importConfirm', await page.evaluate(() => ({ toast: document.querySelector('.status-toast')?.innerText || 'none', hero: document.querySelector('.backup-hero')?.innerText.replace(/\n/g, ' / '), hist: localStorage.getItem('mynote_backup_history') })));
  // 坏 zip
  fs.writeFileSync('/tmp/notzip.zip', 'this is not a zip file at all');
  await page.setInputFiles('#file-import', '/tmp/notzip.zip'); await page.waitForTimeout(900);
  log('rust.importBad', await page.evaluate(() => ({ modal: !!document.querySelector('.backup-modal'), toast: document.querySelector('.status-toast')?.innerText || 'none', hero: document.querySelector('.backup-hero')?.innerText.replace(/\n/g, ' / ') })));
  // 回列表看导入数据
  await page.click('.editor-fab.left'); await page.waitForTimeout(400);
  await page.click('.editor-fab.left'); await page.waitForTimeout(600);
  log('rust.listAfterImport', (await txt(page)).slice(0, 300).replace(/\n/g, ' | '));
  // 诊断页
  await page.$eval('h1.page-title', e => e.click()); await page.waitForTimeout(400);
  await page.click('.set-row:has-text("诊断日志")'); await page.waitForSelector('.diag-body', { timeout: 8000 }); await page.waitForTimeout(400);
  log('rust.diag', await page.evaluate(() => { const b = document.querySelector('.diag-body'); const cs = getComputedStyle(b); const lines = b.innerText.split('\n'); const tags = {}; lines.forEach(l => { const m = l.match(/^\[\d{2}:\d{2}:\d{2}\] (\S+)/); if (m) tags[m[1]] = (tags[m[1]] || 0) + 1; }); return { bg: cs.backgroundColor, color: cs.color, font: cs.fontFamily.slice(0, 40), nLines: lines.length, tags, first: lines.slice(0, 3), lsDiag: (localStorage.getItem('mynote_diag_v1') || '').length, btns: [...document.querySelectorAll('.diag-actions button')].map(e => e.innerText) }; }));
  // 复制
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: 'http://localhost:8100' }).catch(e => console.log('grant err', e.message));
  await page.click('.diag-actions button:has-text("复制全部")'); await page.waitForTimeout(600);
  log('rust.diagCopy', await page.evaluate(async () => { try { const t = await navigator.clipboard.readText(); return 'clip len=' + t.length + ' head=' + t.slice(0, 60); } catch (e) { return 'clip read err: ' + e.message; } }));
  // 清空
  await page.click('.diag-actions button:has-text("清空")'); await page.waitForTimeout(400);
  log('rust.diagAfterClear', await page.evaluate(() => ({ body: document.querySelector('.diag-body')?.innerText, ls: localStorage.getItem('mynote_diag_v1') })));
  await page.reload({ waitUntil: 'load' }); await page.waitForSelector('.list-item', { timeout: 20000 }); await page.waitForTimeout(500);
  await page.$eval('h1.page-title', e => e.click()); await page.waitForTimeout(400);
  await page.click('.set-row:has-text("诊断日志")'); await page.waitForSelector('.diag-body'); await page.waitForTimeout(400);
  log('rust.diagAfterClearReload', await page.evaluate(() => document.querySelector('.diag-body')?.innerText.slice(0, 400)));
  // 返回链
  await page.click('.editor-fab.left'); await page.waitForTimeout(400);
  log('rust.backChain1', await page.evaluate(() => document.querySelector('.page-title')?.innerText));
  await page.click('.editor-fab.left'); await page.waitForTimeout(600);
  log('rust.backToList', await page.evaluate(() => !!document.querySelector('.list-item')));
  await ctx.close();
}

// ============ ORIGINAL ============
{
  const [ctx, page] = await newPage(ORIG);
  await page.waitForTimeout(3000);
  log('orig.listHead', (await txt(page)).slice(0, 200).replace(/\n/g, ' | '));
  await page.$eval('h1.page-title', e => e.click()).catch(async () => { await page.evaluate(() => { const t = [...document.querySelectorAll('.page-title')].find(e => e.innerText.includes('此刻')); t && t.click(); }); });
  await page.waitForTimeout(900);
  log('orig.settings', await page.evaluate(() => ({ body: document.body.innerText.replace(/\n/g, ' | ').slice(0, 700), rootFs: document.documentElement.style.fontSize })));
  // 字号 大（原版按钮文本 小/中/大）
  await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(e => e.innerText === '大'); b && b.click(); });
  await page.waitForTimeout(400);
  log('orig.fontLarge', await page.evaluate(() => ({ rootStyle: document.documentElement.style.fontSize, ls: localStorage.getItem('sj_fontsize') })));
  await page.reload({ waitUntil: 'load' }); await page.waitForTimeout(2500);
  log('orig.fontAfterReload', await page.evaluate(() => ({ rootStyle: document.documentElement.style.fontSize, ls: localStorage.getItem('sj_fontsize') })));
  await page.$eval('h1.page-title', e => e.click()).catch(() => {});
  await page.waitForTimeout(900);
  await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(e => e.innerText === '中'); b && b.click(); });
  await page.waitForTimeout(300);
  // 备份页
  await page.evaluate(() => { const el = [...document.querySelectorAll('.list-item')].find(e => e.innerText.includes('备份与恢复')); el && el.click(); });
  await page.waitForTimeout(1200);
  log('orig.backup', await page.evaluate(() => document.body.innerText.replace(/\n/g, ' | ').slice(0, 800)));
  log('orig.backupLS', await page.evaluate(() => ({ histKey: localStorage.getItem('memos_backup_history'), histKeyRust: localStorage.getItem('mynote_backup_history') })));
  // 导出确认 sheet
  await page.evaluate(() => { const el = [...document.querySelectorAll('.backup-row')].find(e => e.innerText.includes('导出备份')); el && el.click(); });
  await page.waitForTimeout(700);
  log('orig.exportSheet', await page.evaluate(() => { const cand = [...document.querySelectorAll('div')].filter(e => e.innerText && e.innerText.startsWith('确认导出备份')); const m = cand[cand.length - 1]; if (!m) return document.body.innerText.slice(0, 300); const r = m.getBoundingClientRect(); return { rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)], text: m.innerText.replace(/\n/g, ' / ') }; }));
  const dlEvent = page.waitForEvent('download', { timeout: 20000 }).catch(() => null);
  await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(e => e.innerText === '确认导出'); b && b.click(); });
  const dl2 = await dlEvent;
  if (dl2) { const p = await dl2.path(); log('orig.exportDownload', { name: dl2.suggestedFilename(), size: fs.statSync(p).size }); fs.copyFileSync(p, '/tmp/orig_export.zip'); }
  else log('orig.exportDownload', 'NO DOWNLOAD (share fallback?) body=' + (await txt(page)).slice(0, 200).replace(/\n/g, ' | '));
  await page.waitForTimeout(800);
  log('orig.afterExport', await page.evaluate(() => ({ hist: localStorage.getItem('memos_backup_history'), body: document.body.innerText.replace(/\n/g, ' | ').slice(0, 700) })));
  await ctx.close();
}
await browser.close();
console.log('DONE');
