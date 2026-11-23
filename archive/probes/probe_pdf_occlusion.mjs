// 探针：导出面板关闭在页面被遮挡/冻结时是否完成（PDF 锁页续修）
// 用法: node probe_pdf_occlusion.mjs <base> [--assert-fixed]
// 场景 A 对照：前台点遮罩关闭，量关闭完成延迟。
// 场景 B 事件复刻：点 PDF → 真实弹窗抢焦点（opener hidden）→
//   观察 220ms 关闭计时与面板卸载何时发生；关弹窗回前台后再量。
// 场景 C 冻结：CDP Page.setWebLifecycleState frozen 挂起页面，
//   关闭发起后冻结 3s 再解冻，量计时器与完成的实际时刻。
// 仪器（开编辑页后 evaluate 注入）：
//   __timers 记录每个 setTimeout 的 delay/调度/触发时刻；
//   __obs MutationObserver 记录面板/遮罩进出 DOM 的时刻；
//   __vis 记录 visibilitychange。
import { chromium } from 'playwright-core';

const base = process.argv[2] || 'http://localhost:8231/';
const assertFixed = process.argv.includes('--assert-fixed');
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';

let failures = 0;
const ok = (name, cond, val) => {
  if (!cond) failures++;
  console.log((cond ? '✓ ' : '✗ ') + name + (val !== undefined ? ' = ' + val : ''));
};
const info = (name, val) => console.log('· ' + name + (val !== undefined ? ' = ' + val : ''));

// ---------- 夹具 zip（同 smoke-rustweb-export 的内存构造） ----------
const crcTable = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xFFFFFFFF; for (const b of buf) c = crcTable[(c ^ b) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files) {
  const enc = new TextEncoder();
  const chunks = []; const central = []; let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name); const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const crc = crc32(data); const size = data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true);
    lh.setUint32(14, crc, true); lh.setUint32(18, size, true); lh.setUint32(22, size, true);
    lh.setUint16(26, name.length, true);
    chunks.push(Buffer.from(lh.buffer), Buffer.from(name), Buffer.from(data));
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true);
    ch.setUint32(16, crc, true); ch.setUint32(20, size, true); ch.setUint32(24, size, true);
    ch.setUint16(28, name.length, true); ch.setUint32(42, offset, true);
    central.push(Buffer.from(ch.buffer), Buffer.from(name));
    offset += 30 + name.length + size;
  }
  const cdSize = central.reduce((a, c) => a + c.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
  end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  return Buffer.concat([...chunks, ...central, Buffer.from(end.buffer)]);
}
const ts = new Date().toISOString();
const para = (bid, text) => ({ id: bid, type: 'paragraph', children: [{ text }] });
const fixtureZip = zipStore([
  { name: 'memos.json', data: JSON.stringify({ version: 2, exportedAt: ts, memos: [
    { id: 'occ1', title: '遮挡测试', pinned: false, createdAt: ts, updatedAt: ts,
      doc: [para('o1', '遮挡探针正文第一段。'), para('o2', '第二段用于命中与打字验证。'), para('o3', '第三段。')] },
  ], avatars: {} }) },
  { name: 'manifest.json', data: JSON.stringify({ version: 1, attachments: {} }) },
]);

const INSTRUMENT = () => {
  if (window.__inst) return;
  window.__inst = true;
  window.__timers = [];
  const rawST = window.setTimeout.bind(window);
  window.setTimeout = (fn, delay, ...rest) => {
    const rec = { delay: delay || 0, t0: performance.now(), firedAt: null };
    window.__timers.push(rec);
    if (window.__timers.length > 200) window.__timers.shift();
    return rawST((...a) => { rec.firedAt = performance.now(); fn(...a); }, delay, ...rest);
  };
  window.__obs = [];
  let hadPanel = !!document.querySelector('.editor-export-panel');
  let hadScrim = !!document.querySelector('.menu-scrim');
  new MutationObserver(() => {
    const p = !!document.querySelector('.editor-export-panel');
    const s = !!document.querySelector('.menu-scrim');
    if (p !== hadPanel) { window.__obs.push({ t: performance.now(), what: p ? 'panel-in' : 'panel-gone' }); hadPanel = p; }
    if (s !== hadScrim) { window.__obs.push({ t: performance.now(), what: s ? 'scrim-in' : 'scrim-gone' }); hadScrim = s; }
  }).observe(document.documentElement, { childList: true, subtree: true });
  window.__vis = [{ t: performance.now(), state: document.visibilityState }];
  document.addEventListener('visibilitychange', () => {
    window.__vis.push({ t: performance.now(), state: document.visibilityState });
  });
};

const STATE = () => {
  const diag = localStorage.getItem('mynote_diag_v1') || '';
  // 命中点取正文首块中心（固定点会落到块间空隙误判）
  const blk = document.querySelector('.editor-body [data-bid]');
  let hit = null;
  if (blk) {
    const r = blk.getBoundingClientRect();
    hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
  }
  const scrim = document.querySelector('.menu-scrim');
  const panel = document.querySelector('.editor-export-panel');
  return {
    vis: document.visibilityState,
    panel: !!panel,
    scrim: !!scrim,
    scrimPE: scrim ? getComputedStyle(scrim).pointerEvents : null,
    panelPE: panel ? getComputedStyle(panel).pointerEvents : null,
    hitLabel: hit ? hit.tagName + '.' + String(hit.className).slice(0, 30) : 'none',
    hitInBody: !!(hit && hit.closest && hit.closest('.editor-body')),
    closedLines: (diag.match(/export panel closed[^\"]*/g) || []).length,
    resumeLines: (diag.match(/export (panel )?(closed|open settled) on resume[^\"]*/g) || []).length,
    diagTail: diag.slice(-400),
  };
};

async function importAndOpen(page) {
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForSelector('.list-item', { timeout: 20000 });
  const hasMemo = await page.evaluate(() => document.body.innerText.includes('遮挡测试'));
  if (!hasMemo) {
    await page.$eval('h1.page-title', (e) => e.click());
    await page.waitForSelector('.page-content', { timeout: 8000 });
    await page.click('.set-row:has-text("备份与恢复")');
    await page.waitForSelector('#file-import', { state: 'attached', timeout: 8000 });
    await page.setInputFiles('#file-import', { name: 'occ.zip', mimeType: 'application/zip', buffer: fixtureZip });
    await page.waitForSelector('.backup-modal', { timeout: 8000 });
    await page.click('.backup-modal .backup-btn.primary');
    await page.waitForFunction(() => document.querySelector('.backup-toast')?.innerText.includes('已导入'), null, { timeout: 15000 });
  }
  await page.goto(base + '?open=occ1', { waitUntil: 'load' });
  await page.waitForSelector('.editor-body [data-bid]', { timeout: 15000 });
  await page.waitForTimeout(700);
  await page.evaluate(INSTRUMENT);
}

async function openExportPanel(page) {
  await page.click('.editor-fab.right');
  await page.waitForSelector('.editor-menu-panel', { timeout: 8000 });
  await page.locator('.editor-menu-panel .menu-item', { hasText: '导出' }).first().click();
  await page.waitForSelector('.editor-export-panel', { timeout: 8000 });
  await page.waitForTimeout(600);
}

async function pollUntil(page, fn, timeoutMs, step = 150) {
  const t0 = Date.now();
  let last = null;
  while (Date.now() - t0 < timeoutMs) {
    last = await page.evaluate(fn);
    if (last) return { value: last, elapsed: Date.now() - t0 };
    await page.waitForTimeout(step);
  }
  return { value: last, elapsed: Date.now() - t0 };
}

const browser = await chromium.launch({ executablePath: exe, args: ['--no-sandbox'] });

// ================= 场景 A：前台对照 =================
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await openExportPanel(page);
  const t0 = Date.now();
  await page.mouse.click(40, 620); // 遮罩空白处
  const stImm = await page.evaluate(STATE); // 关闭发起瞬间（卸载计时未到）
  const done = await pollUntil(page, () => !document.querySelector('.editor-export-panel') && !document.querySelector('.menu-scrim'), 5000);
  const st = await page.evaluate(STATE);
  const timers = await page.evaluate(() => window.__timers.filter((t) => t.delay === 220).slice(-2));
  info('A 前台关闭完成延迟 ms', done.elapsed);
  info('A 220 计时器', JSON.stringify(timers));
  ok('A 前台关闭可完成', !!done.value, `panel=${st.panel} scrim=${st.scrim}`);
  ok('A 关闭后正文命中', st.hitInBody, st.hitLabel);
  if (assertFixed) {
    ok('A 关闭发起瞬间遮罩已不拦截', !stImm.scrim || stImm.scrimPE === 'none', `scrim=${stImm.scrim} PE=${stImm.scrimPE}`);
    ok('A 关闭发起瞬间面板已不拦截', !stImm.panel || stImm.panelPE === 'none', `panel=${stImm.panel} PE=${stImm.panelPE}`);
  }
  ok('A 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ================= 场景 B：PDF 弹窗遮挡 =================
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await openExportPanel(page);
  const popupP = page.waitForEvent('popup', { timeout: 10000 }).catch(() => null);
  const t0 = Date.now();
  await page.click('[data-export-format="pdf"]');
  const popup = await popupP;
  info('B 弹窗出现', !!popup);
  let occludedMs = null;
  let completedWhileOccluded = false;
  let stOcc = null;
  if (popup) {
    await popup.bringToFront().catch(() => {});
    await page.waitForTimeout(300);
    stOcc = await page.evaluate(STATE);
    info('B 遮挡中 opener 状态', JSON.stringify({ vis: stOcc.vis, panel: stOcc.panel, scrim: stOcc.scrim, scrimPE: stOcc.scrimPE, panelPE: stOcc.panelPE, hitInBody: stOcc.hitInBody }));
    // 遮挡期轮询最长 20s
    const tOcc = Date.now();
    while (Date.now() - tOcc < 20000) {
      const s = await page.evaluate(STATE);
      if (!s.panel && !s.scrim) { completedWhileOccluded = true; occludedMs = Date.now() - t0; break; }
      await page.waitForTimeout(500);
    }
    if (!completedWhileOccluded) occludedMs = Date.now() - t0;
    info('B 遮挡期是否完成关闭', completedWhileOccluded + ` (观察 ${occludedMs}ms)`);
    const timers = await page.evaluate(() => window.__timers.filter((t) => t.delay === 220).slice(-3).map((t) => ({ t0: Math.round(t.t0), firedAt: t.firedAt == null ? null : Math.round(t.firedAt) })));
    info('B 220 计时器调度/触发（页内 performance.now）', JSON.stringify(timers));
    // 回前台
    await popup.close().catch(() => {});
    await page.bringToFront().catch(() => {});
    const done = await pollUntil(page, () => !document.querySelector('.editor-export-panel') && !document.querySelector('.menu-scrim'), 10000);
    info('B 回前台后完成额外延迟 ms', done.elapsed);
    const st = await page.evaluate(STATE);
    info('B 最终状态', JSON.stringify({ panel: st.panel, scrim: st.scrim, hitInBody: st.hitInBody, closed: st.closedLines, resume: st.resumeLines }));
    if (assertFixed) {
      ok('B 遮挡发起后遮罩即刻不拦截（pointer-events none 或已卸载）', !stOcc.scrim || stOcc.scrimPE === 'none', `scrimPE=${stOcc.scrimPE}`);
      ok('B 遮挡发起后面板即刻不拦截', !stOcc.panel || stOcc.panelPE === 'none', `panelPE=${stOcc.panelPE}`);
      ok('B 回前台后关闭迅速补完 (<=3000ms)', !!done.value && done.elapsed <= 3000, done.elapsed);
      ok('B 补完后正文命中', st.hitInBody, st.hitLabel);
    } else {
      // 复现口径：遮挡 20s 内未完成 = 复现成功（记为 info，不断言失败）
      info('B 复现判定（遮挡期未完成=复现锁页）', !completedWhileOccluded);
    }
  }
  ok('B 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ============ 场景 C：虚拟时间暂停（计时器队列挂起） ============
// headless shell 里 Page.setWebLifecycleState frozen 不挂起计时
// 器（实测 span 仍 221ms），改用 Emulation.setVirtualTimePolicy
// pause：虚拟时钟停摆 = 后台页计时器被整体挂起的确定性模型。
// 流程：开面板 → 暂停虚拟时间 → 发起关闭 → 真实等 2.5s →
// 查面板/遮罩/计时器/命中（应全部卡住）→ 派发回前台事件
// （visibilitychange/pageshow/focus，修复后应触发补完）→
// 恢复虚拟时间 → 查最终完成。
{
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await openExportPanel(page);
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setVirtualTimePolicy', { policy: 'pause' });
  // 发起关闭：evaluate 直派 click（虚拟时间暂停下 Playwright 的
  // 可操作性等待不可靠；Dioxus 事件处理是事件驱动非计时驱动）
  await page.evaluate(() => document.querySelector('.menu-scrim').click());
  await page.waitForTimeout(2500); // Node 侧真实时间
  const stPause = await page.evaluate(STATE);
  const timersPause = await page.evaluate(() => window.__timers.filter((t) => t.delay === 220).slice(-2).map((t) => ({ t0: Math.round(t.t0), firedAt: t.firedAt == null ? null : Math.round(t.firedAt) })));
  info('C 暂停 2.5s 后状态', JSON.stringify({ panel: stPause.panel, scrim: stPause.scrim, scrimPE: stPause.scrimPE, hitInBody: stPause.hitInBody, hit: stPause.hitLabel }));
  info('C 暂停期 220 计时器', JSON.stringify(timersPause));
  // 回前台事件（不恢复虚拟时间）：修复后应由补完机制收尾
  await page.evaluate(() => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('pageshow'));
    window.dispatchEvent(new Event('focus'));
  });
  await page.waitForTimeout(800);
  const stResume = await page.evaluate(STATE);
  info('C 回前台事件后状态', JSON.stringify({ panel: stResume.panel, scrim: stResume.scrim, hitInBody: stResume.hitInBody, closed: stResume.closedLines, resume: stResume.resumeLines }));
  // 恢复虚拟时间，计时器应随后触发完成（若未被补完抢先）
  await cdp.send('Emulation.setVirtualTimePolicy', { policy: 'advance', budget: 10000 });
  const done = await pollUntil(page, () => !document.querySelector('.editor-export-panel') && !document.querySelector('.menu-scrim'), 8000);
  info('C 恢复虚拟时间后完成额外延迟 ms', done.elapsed);
  const stEnd = await page.evaluate(STATE);
  if (assertFixed) {
    ok('C 关闭发起即释放遮罩命中（暂停期 PE=none 或已卸载）', !stPause.scrim || stPause.scrimPE === 'none', `scrimPE=${stPause.scrimPE}`);
    ok('C 暂停期正文命中已恢复', stPause.hitInBody, stPause.hitLabel);
    ok('C 回前台事件触发补完（虚拟时间仍暂停）', !stResume.panel && !stResume.scrim, `panel=${stResume.panel} scrim=${stResume.scrim}`);
    ok('C 补完 Diag 有记录', stResume.resumeLines >= 1 || stEnd.resumeLines >= 1, `resume=${stEnd.resumeLines}`);
    ok('C 最终无残留且正文命中', !!done.value && stEnd.hitInBody, stEnd.hitLabel);
  } else {
    info('C 复现判定（暂停期面板残留+计时器未触发+命中被拦截=复现）',
      stPause.panel && stPause.scrim && timersPause.length > 0 && timersPause[timersPause.length - 1].firedAt === null && !stPause.hitInBody);
    info('C 复现判定（回前台事件无补完=复现）', stResume.panel && stResume.scrim);
  }
  ok('C 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

// ============ 场景 D：代际防误关（补完 × 重开 × 旧计时） ============
// 关闭挂起 → 回前台补完抢先完成 → 立刻重开面板 → 旧 220ms
// 计时随后触发时必须按代际作废，不得把新面板误关。
if (assertFixed) {
  const ctx = await browser.newContext({ viewport: { width: 393, height: 852 }, hasTouch: true });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await importAndOpen(page);
  await openExportPanel(page);
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Emulation.setVirtualTimePolicy', { policy: 'pause' });
  await page.evaluate(() => document.querySelector('.menu-scrim').click());
  await page.waitForTimeout(400);
  // 计时仍挂起时回前台补完
  await page.evaluate(() => {
    document.dispatchEvent(new Event('visibilitychange'));
    window.dispatchEvent(new Event('focus'));
  });
  await page.waitForTimeout(500);
  const stD1 = await page.evaluate(STATE);
  info('D 补完后状态', JSON.stringify({ panel: stD1.panel, scrim: stD1.scrim, resume: stD1.resumeLines }));
  // 恢复虚拟时间并立刻重开面板（旧计时将在此期间触发）；
  // 预算给足：Playwright 等待轮询的 rAF 会快速烧虚拟时间，
  // 预算耗尽等于再次暂停（首跑 10000 即因此让面板渲染停摆）
  await cdp.send('Emulation.setVirtualTimePolicy', { policy: 'advance', budget: 10000000 });
  await openExportPanel(page);
  await page.waitForTimeout(900); // 旧计时 + 开场 rAF 均应已落定
  const stD2 = await page.evaluate(STATE);
  info('D 重开后状态', JSON.stringify({ panel: stD2.panel, panelPE: stD2.panelPE, closed: stD2.closedLines }));
  ok('D 补完先行完成关闭', !stD1.panel && !stD1.scrim && stD1.resumeLines >= 1, `resume=${stD1.resumeLines}`);
  ok('D 重开面板未被旧计时误关', stD2.panel && stD2.panelPE === 'auto', `panel=${stD2.panel} PE=${stD2.panelPE}`);
  ok('D 无 pageerror', errors.length === 0, errors.slice(0, 2).join(' | '));
  await ctx.close();
}

await browser.close();
console.log(assertFixed ? (failures ? `FAILURES: ${failures}` : 'ALL PASS') : 'REPRO DONE');
process.exit(assertFixed ? (failures ? 1 : 0) : 0);
