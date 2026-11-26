// 专用探针：编辑器更多菜单「添加附件」唤起链（2026-11-24 回归锁）。
// 守的行为（确诊 diagnose_addatt_imgpage.md）：
//  ① 附件图片文件行点按仍进图片页（扩围入口 209f567 不回归）：
//     tap 附件行 → .img-page 在场、标题 == att-photo.png →
//     页内返回回编辑页。
//  ② 菜单「添加附件」真实 tap 调起系统文件选择：夹具首块为
//     大图、几何上压在菜单面板下方——tap label 中心后
//     filechooser 必须触发（label 原生唤起链完整交付），
//     且不进图片页（点按不得被改道到下方图片块）；菜单
//     退场照常（Diag EDIT menu closed 落盘）。
//     病灶形态：关菜单在 pointerdown 预关（E-6 初版）时，
//     .is-closing 的 pointer-events:none 在手势中途摘掉面板
//     命中，兼容 click 改道离开 label、唤起链断裂——本段
//     以真实 touchscreen tap 守，程序化 click 绕过命中测试
//     测不出（probe_pages_editor_rust 的 ATTACH_CHOOSER 即
//     因此漏过）。
//  ③ 全链：filechooser 选入文本文件后，新附件文件行落块
//     （行内含文件名 menu_att.txt）。
// 夹具 PNG 以 zlib 手工构造（IHDR 指定宽高），不依赖 PIL。
// 用法: node probe_menu_attach.mjs [baseURL]
import { chromium } from 'playwright-core';
import { execSync } from 'node:child_process';

const url = process.argv[2] || 'http://localhost:8096/';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

execSync(`python3 - <<'PYEOF'
import json, struct, zlib, zipfile

def png(w, h):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    raw = (b'\\x00' + b'\\x00' * (w * 3)) * h
    return (b'\\x89PNG\\r\\n\\x1a\\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

doc = [{"id": "ma-img", "type": "image", "attrs": {"fileId": "imgA"}, "children": []},
       {"id": "ma-att", "type": "attachment", "attrs": {"fileId": "attImg"}, "image": False, "children": []}]
for i in range(1, 11):
    doc.append({"id": f"ma-f{i}", "type": "paragraph", "children": [{"text": f"填充段落 {i}。"}]})
memo = {"id": "ma-memo", "title": "菜单附件探针", "pinned": False,
        "createdAt": "2026-11-22T10:00:00+08:00", "updatedAt": "2026-11-22T10:00:00+08:00",
        "doc": doc}
z = zipfile.ZipFile('/tmp/menu_attach_probe.zip', 'w')
z.writestr('memos.json', json.dumps({"version": 2, "memos": [memo]}, ensure_ascii=False))
z.writestr('manifest.json', json.dumps({"version": 1, "attachments": {
    "imgA": {"name": "photo-a.png", "type": "image/png"},
    "attImg": {"name": "att-photo.png", "type": "image/png"}}}))
z.writestr('attachments/imgA', png(1200, 1600))
z.writestr('attachments/attImg', png(1600, 1200))
z.close()
open('/tmp/menu_att.txt', 'w').write('menu attach probe file')
print('menu_attach_probe.zip ready')
PYEOF`);

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true, colorScheme: 'light' });
const page = await ctx.newPage();
page.on('pageerror', (e) => console.log('PAGEERROR', String(e).slice(0, 200)));

let pass = 0, fail = 0;
function ok(name, cond, extra = '') {
  if (cond) { pass++; console.log('  ok', name); }
  else { fail++; console.log('  FAIL', name, extra); }
}

const diagText = () => page.evaluate(() => localStorage.getItem('moment_diag_v1') || '');
async function waitDiag(pred, timeoutMs = 10000) {
  const t0 = Date.now();
  let txt = await diagText();
  while (!pred(txt) && Date.now() - t0 < timeoutMs) {
    await page.waitForTimeout(200);
    txt = await diagText();
  }
  return txt;
}

// 导入夹具（与 probe_lightbox_page 同流程）
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('h1.page-title', { timeout: 8000 });
await page.$eval('h1.page-title', (e) => e.click());
await page.waitForSelector('.page-content', { timeout: 8000 });
await page.click('.set-row:has-text("备份与恢复")');
await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
await page.setInputFiles('#file-import', '/tmp/menu_attach_probe.zip');
await page.waitForSelector('.backup-modal', { timeout: 8000 });
await page.click('.backup-modal .backup-btn.primary');
await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { polling: 200, timeout: 15000 });
await page.click('.editor-fab.left');
await page.waitForSelector('.seg-row', { timeout: 8000 }).catch(() => {});
await page.click('.editor-fab.left');
await page.waitForSelector('.glass-search-trigger', { state: 'attached', timeout: 10000 });

// 打开夹具备忘（身份打印留证，防测错篇）
await page.evaluate(() => {
  const el = [...document.querySelectorAll('.img-card-title-text, .list-item .item-title-text')]
    .find((e) => e.textContent.includes('菜单附件探针'));
  if (el) el.click();
});
await page.waitForSelector('.detail', { timeout: 8000 });
await page.waitForTimeout(900);
ok('打开夹具备忘「菜单附件探针」进入编辑页', (await page.$('.detail')) !== null);

// ① 附件图片文件行点按仍进图片页（扩围入口不回归）
{
  const zone = await page.evaluate(() => {
    const row = document.querySelector('[data-wrapbid="ma-att"] .attachment-file');
    if (!row) return null;
    const r = row.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  ok('① 附件行可定位', !!zone);
  await page.touchscreen.tap(zone.x, zone.y);
  await page.waitForSelector('.img-page', { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(400);
  ok('① 附件图片行 tap 进图片页', (await page.$('.img-page')) !== null);
  const title = await page.evaluate(() => document.querySelector('.img-page .page-title')?.textContent.trim() || '');
  ok('① 标题 == att-photo.png', title === 'att-photo.png', title);
  await page.click('.img-page .editor-fab.left');
  await page.waitForSelector('.detail', { timeout: 8000 });
  await page.waitForTimeout(600);
  ok('① 返回回编辑页', (await page.$('.img-page')) === null && (await page.$('.detail')) !== null);
}

// ② 菜单「添加附件」真实 tap 调起系统文件选择、不进图片页
{
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.waitForTimeout(400);
  const info = await page.evaluate(() => {
    const lab = document.querySelector('.editor-menu-panel label[for="file-attach"]');
    if (!lab) return null;
    const r = lab.getBoundingClientRect();
    const cx = r.x + r.width / 2, cy = r.y + r.height / 2;
    const under = document.elementFromPoint(cx, cy);
    const inLabel = !!(under && under.closest && under.closest('label[for="file-attach"]'));
    const img = document.querySelector('[data-wrapbid="ma-img"] img');
    const ir = img ? img.getBoundingClientRect() : null;
    const imgUnder = !!(ir && cx >= ir.x && cx <= ir.x + ir.width && cy >= ir.y && cy <= ir.y + ir.height);
    return { x: cx, y: cy, inLabel, imgUnder };
  });
  ok('② label 可定位且点位命中 label 本体', !!info && info.inLabel, JSON.stringify(info));
  ok('② 几何前提：label 点位下方压着图片块（改道落点在场）', !!info && info.imgUnder, JSON.stringify(info));
  const fcP = page.waitForEvent('filechooser', { timeout: 8000 }).catch(() => null);
  await page.touchscreen.tap(info.x, info.y);
  const fc = await fcP;
  ok('② tap 后系统文件选择被调起（filechooser 触发）', !!fc);
  await page.waitForTimeout(500);
  ok('② 未进图片页（点按未被改道到下方图片块）', (await page.$('.img-page')) === null);
  const diag = await waitDiag((t) => t.includes('menu closed'));
  ok('② 菜单退场照常（Diag EDIT menu closed）', diag.includes('menu closed'));

  // ③ 全链：选入文本文件 → 新附件文件行落块
  if (fc) {
    await fc.setFiles('/tmp/menu_att.txt');
    const landed = await page.waitForFunction(() => {
      const rows = [...document.querySelectorAll('#editor-root .attachment-file')];
      return rows.some((r) => r.innerText.includes('menu_att.txt'));
    }, null, { polling: 200, timeout: 10000 }).catch(() => null);
    ok('③ 选文件后新附件行落块（menu_att.txt）', !!landed);
  } else {
    ok('③ 选文件后新附件行落块（menu_att.txt）', false, 'no filechooser');
  }
}

await browser.close();
console.log(`\nprobe_menu_attach: ${pass} pass, ${fail} fail`);
if (fail === 0) console.log('ALL PASS');
process.exit(fail === 0 ? 0 : 1);
