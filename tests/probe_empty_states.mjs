// 专用探针：三态空状态（批 12 P-U2）。
//  ① 搜索零结果：输入无命中词 → 空状态（标题含查询词 +
//     清除搜索按钮）；点清除 → 列表恢复；Diag 记
//     「empty state shown: search-none」。
//  ② 空库：IDB 写入空 memos（version:2, memos:[]）重载 →
//     空库状态（标题 + 新建备忘按钮）；点新建 → 编辑器
//     打开；Diag 记 empty-library。
//  ③ 加载失败：IDB 写入损坏 memos_json 重载 → 失败状态
//     （标题 + 重新加载按钮、列表与新建卡不渲染）；Diag
//     记 parse err + shown: load-error。
// 用法：node probe_empty_states.mjs [base]
import { chromium } from 'playwright-core';
const base = process.argv[2] || 'http://localhost:8096/';
// 本探针以 IDB 注入造空库/损坏态；dual 后端下加载源为
// SQLite、IDB 注入不生效，故全程钉 idb 后端（persist 既
// 有 ?backend= 覆盖口径、重载保留参数），断言不变。
const url = base + (base.includes('?') ? '&' : '?') + 'backend=idb';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });
const L = (...a) => console.log(...a);
let fails = 0;
const ok = (name, cond, extra = '') => { L(cond ? '✓' : '✗ FAIL', name, extra); if (!cond) fails++; };

const ctx = await browser.newContext({ viewport: { width: 393, height: 852 } });
const page = await ctx.newPage();
await page.goto(url, { waitUntil: 'load' });
await page.waitForSelector('.list-item', { timeout: 30000 });
await page.waitForTimeout(800);

const diagHas = async (substr, tries = 20) => {
  for (let i = 0; i < tries; i++) {
    const lines = await page.evaluate(() => {
      try { return JSON.parse(localStorage.getItem('moment_diag_v1') || '[]'); } catch (e) { return []; }
    });
    if (lines.some((l) => String(l).includes(substr))) return true;
    await page.waitForTimeout(500);
  }
  return false;
};
const setMemosJson = async (val) => {
  await page.evaluate(async (v) => {
    const db = await new Promise((res, rej) => {
      const r = indexedDB.open('moment-web');
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
    // IDB 分条合流适配：注入旧形载荷时同事务清分条形态
    // （信封/顺序/分条店），使下次加载走旧形通道读到本载
    // 荷（迁移或失败态由应用自身口径决定），断言不变。
    await new Promise((res, rej) => {
      const tx = db.transaction(['kv', 'memos'], 'readwrite');
      tx.objectStore('kv').put(v, 'memos_json');
      tx.objectStore('kv').delete('backup_meta');
      tx.objectStore('kv').delete('memos_order');
      tx.objectStore('memos').clear();
      tx.oncomplete = res;
      tx.onerror = () => rej(tx.error);
    });
  }, val);
};

// ① 搜索零结果
await page.click('.glass-search-trigger');
await page.waitForSelector('.glass-search-input', { timeout: 8000 });
await page.fill('.glass-search-input', 'zzz不存在的词zzz');
await page.waitForTimeout(800);
let st = page.locator('.empty-state');
ok('① 搜索空状态出现', (await st.count()) === 1);
ok('① 标题含查询词', (await st.locator('.empty-state-title').innerText()).includes('zzz不存在的词zzz'));
ok('① Diag 记 search-none', await diagHas('empty state shown: search-none'));
await st.locator('.empty-state-btn').click();
await page.waitForTimeout(600);
ok('① 清除后空状态消失', (await page.locator('.empty-state').count()) === 0);
ok('① 清除后列表恢复', (await page.locator('.list-item').count()) > 1);

// ② 空库
await setMemosJson(JSON.stringify({ version: 2, memos: [] }));
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(1500);
st = page.locator('.empty-state');
ok('② 空库状态出现', (await st.count()) === 1);
ok('② 空库标题', (await st.locator('.empty-state-title').innerText()).includes('还没有备忘'));
ok('② Diag 记 empty-library', await diagHas('empty state shown: empty-library'));
await st.locator('.empty-state-btn').click();
await page.waitForTimeout(1200);
ok('② 点新建打开编辑器', (await page.locator('.editor-stage').count()) === 1);
// 输入内容使备忘非空（空新备忘返回时按既有口径自动删除，
// 不入内容则回列表仍是空库、断言无从区分）。落点须在首段
// 可编辑块上——.detail 是整页容器、其顶部属页头排除区。
await page.locator('.blk-p.ed-line').first().click();
await page.keyboard.type('空库新建验证');
await page.waitForTimeout(600);
await page.click('.editor-fab.left');
await page.waitForTimeout(1200);
ok('② 返回后空状态消失（已有 1 篇）', (await page.locator('.empty-state').count()) === 0);

// ③ 加载失败
await setMemosJson('{corrupt-json');
await page.reload({ waitUntil: 'load' });
await page.waitForTimeout(1500);
st = page.locator('.empty-state');
ok('③ 失败状态出现', (await st.count()) === 1);
ok('③ 失败标题', (await st.locator('.empty-state-title').innerText()).includes('备忘加载失败'));
ok('③ 失败说明含诊断引导', (await st.locator('.empty-state-sub').innerText()).includes('诊断日志'));
ok('③ 列表不渲染（种子不冒充数据）', (await page.locator('.list-item').count()) === 0);
ok('③ Diag 记 parse err', await diagHas('parse err'));
ok('③ Diag 记 load-error', await diagHas('empty state shown: load-error'));

await browser.close();
L(fails === 0 ? 'ALL PASS' : `${fails} FAILURES`);
process.exit(fails === 0 ? 0 : 1);
