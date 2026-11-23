// 审计修复后逐页截图核对：列表 / 设置 / 备份页 / 编辑器（含待办+引用+音乐卡）
import { chromium } from 'playwright-core';
import fs from 'node:fs';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = 'http://127.0.0.1:8095/';
const OUT = '/tmp/shots_audit_fix';
fs.mkdirSync(OUT, { recursive: true });

(async () => {
  const browser = await chromium.launch({ executablePath: EXE, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 420, height: 900 }, hasTouch: true, isMobile: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[pageerror]', String(e).slice(0, 200)));
  await page.goto(BASE, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: OUT + '/01-list.png' });

  // 设置页：点左上头像
  await page.touchscreen.tap(52, 52);
  await page.waitForTimeout(1800);
  await page.screenshot({ path: OUT + '/02-settings.png' });

  // 备份页：点「备份与恢复」行（约 y=245）
  await page.touchscreen.tap(210, 245);
  await page.waitForTimeout(1800);
  await page.screenshot({ path: OUT + '/03-backup.png' });

  // 返回列表 → 打开音乐种子笔记验证卡片补拉
  await page.touchscreen.tap(24, 52);
  await page.waitForTimeout(1200);
  await page.touchscreen.tap(24, 52);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: OUT + '/04-list2.png' });

  await browser.close();
  console.log('done');
})().catch((e) => { console.error(e); process.exit(1); });
