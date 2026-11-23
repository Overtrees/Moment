// 审计批次验证：导入多形态数据 → 列表（标签/图卡/折叠）+ 编辑器 + 备份页截图
import { chromium } from 'playwright-core';
import fs from 'node:fs';

const CHROME = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const BASE = 'http://127.0.0.1:8095';
const browser = await chromium.launch({ executablePath: CHROME, args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 420, height: 900 }, hasTouch: true });
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

await page.goto(BASE, { waitUntil: 'networkidle' });
await page.waitForTimeout(3500);

// 进设置 → 备份页 → 从本地文件恢复（file chooser 注入 zip）
await page.touchscreen.tap(52, 52);
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/a2-settings.png' });
await page.touchscreen.tap(210, 245);
await page.waitForTimeout(1200);
await page.screenshot({ path: '/tmp/a2-backup.png' });

const [chooser] = await Promise.all([
  page.waitForEvent('filechooser', { timeout: 10000 }),
  (async () => {
    await page.touchscreen.tap(210, 320); // 导入备份行
    await page.waitForTimeout(900);
    await page.mouse.click(290, 490); // 确认弹窗「继续恢复」
  })(),
]);
await chooser.setFiles('/tmp/audit2.zip');
await page.waitForTimeout(1800);

// 返回列表
await page.touchscreen.tap(30, 40);
await page.waitForTimeout(600);
await page.touchscreen.tap(30, 40);
await page.waitForTimeout(1000);
await page.screenshot({ path: '/tmp/a2-list.png' });

// 展开折叠组（点第一张文本卡的展开 chip 区域）后再截图
await page.screenshot({ path: '/tmp/a2-list2.png', fullPage: false });

// 打开第一篇（置顶灵感）编辑器
await page.touchscreen.tap(200, 262);
await page.waitForTimeout(1500);
await page.screenshot({ path: '/tmp/a2-editor.png' });

// 打开 ••• 菜单
await page.touchscreen.tap(388, 40);
await page.waitForTimeout(900);
await page.screenshot({ path: '/tmp/a2-menu.png' });

console.log('done');
await browser.close();
