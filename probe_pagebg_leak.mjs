// 页面色泄漏探针：编辑页（自定义醒目背景）→ 列表 → 设置 → 备份，
// 逐页量测 html/body 内联与计算背景、#body-before-bg 残留、清理痕迹
// （window.__mnEsc / __mnBgCleanup / __mnBgActive 是否被卸载清理摘除）。
// 用法: node probe_pagebg_leak.mjs <url>
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8205/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, zipfile, datetime
now = datetime.datetime.now().astimezone()
ts = now.isoformat()
def memo(mid, title, text, bg=None):
    m = {"id": mid, "title": title, "pinned": False, "createdAt": ts, "updatedAt": ts,
         "doc": [{"id": mid + "b1", "type": "paragraph", "children": [{"text": text}]},
                 {"id": mid + "b2", "type": "paragraph", "children": [{"text": "第二段，撑高度用。" + "长文本" * 60}]}]}
    if bg: m["bgColor"] = bg
    return m
memos = [memo("bgvivid", "醒目背景备忘", "这篇有自定义背景色 #FF5722。", "#FF5722"),
         memo("bgplain", "默认背景备忘", "这篇没有自定义背景。")]
data = {"version": 2, "exportedAt": ts, "memos": memos, "avatars": {}}
man = {"version": 1, "attachments": {}}
z = zipfile.ZipFile('/tmp/pagebg/fixture.zip', 'w')
z.writestr('memos.json', json.dumps(data, ensure_ascii=False))
z.writestr('manifest.json', json.dumps(man))
z.close()
print('fixture ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, acceptDownloads: true });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));

const measure = (label) => page.evaluate((label) => {
  const de = document.documentElement, b = document.body;
  const st = document.getElementById('body-before-bg');
  return {
    label,
    htmlInline: de.style.backgroundColor || '',
    bodyInline: b.style.backgroundColor || '',
    rootVar: de.style.getPropertyValue('--mn-root-bg').trim(),
    bodyComputed: getComputedStyle(b).backgroundColor,
    htmlComputed: getComputedStyle(de).backgroundColor,
    gradStylePresent: !!st,
    gradStyleText: st ? st.textContent.slice(0, 120) : '',
    mnEsc: typeof window.__mnEsc,
    mnBgCleanup: typeof window.__mnBgCleanup,
    mnBgActive: window.__mnBgActive,
    mnTypedMark: typeof window.__mnTypedMark,
  };
}, label);

await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 20000 });

// 导入夹具
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', '/tmp/pagebg/fixture.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), { timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });

console.log(JSON.stringify(await measure('list-after-import'), null, 1));

// 打开醒目背景备忘
await page.click('.list-item:has-text("醒目背景备忘")');
await page.waitForSelector('#editor-root, .editor-body', { timeout: 10000 });
await page.waitForTimeout(600);
console.log(JSON.stringify(await measure('editor-vivid'), null, 1));

// 编辑页内滚动，让顶部渐变 alpha 拉满（#body-before-bg 写入渐变色）
await page.evaluate(() => window.scrollTo(0, 300));
await page.waitForTimeout(500);
console.log(JSON.stringify(await measure('editor-vivid-scrolled'), null, 1));

// 返回列表
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.waitForTimeout(600);
console.log(JSON.stringify(await measure('list-after-editor'), null, 1));

// 进设置页
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.waitForTimeout(400);
console.log(JSON.stringify(await measure('settings-after-editor'), null, 1));

// 进备份页
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.waitForTimeout(400);
console.log(JSON.stringify(await measure('backup-after-editor'), null, 1));

// 回列表，再开默认背景备忘 → 返回列表（默认色泄漏格）
await page.click('.editor-fab.left');
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 8000 });
await page.click('.list-item:has-text("默认背景备忘")');
await page.waitForSelector('#editor-root, .editor-body', { timeout: 10000 });
await page.waitForTimeout(600);
console.log(JSON.stringify(await measure('editor-plain'), null, 1));
await page.click('.editor-fab.left');
await page.waitForSelector('.list-item', { timeout: 10000 });
await page.waitForTimeout(600);
console.log(JSON.stringify(await measure('list-after-plain-editor'), null, 1));

console.log('PAGEERRORS:', JSON.stringify(errors));
await browser.close();
