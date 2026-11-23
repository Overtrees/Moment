//! 诊断日志（全模块硬规矩）：任何模块、页面都经 Diag 记一笔，
//! 方便后续定位修复与运维。内存环形缓冲（上限 300 行）+
//! localStorage 持久（键 mynote_diag_v1，字符串数组，与
//! Flutter 版同形），刷新/重启不丢。诊断视图在顶栏「诊断」。

use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

use wasm_bindgen::JsCast;

const KEY: &str = "mynote_diag_v1";
const CAP: usize = 300;

static LINES: Mutex<Vec<String>> = Mutex::new(Vec::new());

fn seen() -> &'static Mutex<HashSet<String>> {
    static SEEN: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
    SEEN.get_or_init(|| Mutex::new(HashSet::new()))
}

fn clock() -> String {
    let d = js_sys::Date::new_0();
    format!(
        "{:02}:{:02}:{:02}",
        d.get_hours(),
        d.get_minutes(),
        d.get_seconds()
    )
}

fn persist(lines: &[String]) {
    if let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    {
        if let Ok(json) = serde_json::to_string(&lines) {
            let _ = storage.set_item(KEY, &json);
        }
    }
}

// ── 节流合并落盘（批 10 T-F）──────────────────────────
// 旧实现 log 每行同步全量序列化 300 行环写 localStorage：
// 标题帧行是输入期最高频来源，主线程代价随行数线性涨。
// 改为欠账标记 + 1s 窗口合并：log 只置标记并挂一次定时
// 刷，窗口内后续行并入同一次全量写。内存环即时更新、不
// 丢行；落盘至多滞后 1s，pagehide 时兜底刷出（init 装），
// ERR 行走 flush_persist 立即刷（含欠账行）——跨会话持
// 久语义与键/环容量不变。
static PERSIST_OWED: AtomicBool = AtomicBool::new(false);

fn schedule_persist() {
    if PERSIST_OWED.swap(true, Ordering::SeqCst) {
        return; // 窗口内已挂，本行并入同一次写
    }
    if let Some(w) = web_sys::window() {
        let cb = wasm_bindgen::closure::Closure::once_into_js(flush_persist);
        let _ = w.set_timeout_with_callback_and_timeout_and_arguments_0(
            cb.unchecked_ref(),
            1000,
        );
    }
}

/// 立即落盘（含节流窗口内的欠账行）；无欠账时不写。
pub fn flush_persist() {
    if !PERSIST_OWED.swap(false, Ordering::SeqCst) {
        return;
    }
    let lines = LINES.lock().unwrap();
    persist(&lines);
}

/// 启动时从 localStorage 读回历史日志（main 里调一次）。
pub fn init() {
    if let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    {
        if let Ok(Some(json)) = storage.get_item(KEY) {
            if let Ok(saved) = serde_json::from_str::<Vec<String>>(&json) {
                let mut lines = LINES.lock().unwrap();
                *lines = saved.into_iter().rev().take(CAP).rev().collect();
            }
        }
    }
    // 节流落盘的兜底（批 10 T-F）：页面隐藏/卸载时把窗口
    // 内的欠账行刷出，刷新/切后台不丢最近 1s 的日志。
    if let Some(w) = web_sys::window() {
        let on_hide = wasm_bindgen::closure::Closure::wrap(Box::new(flush_persist)
            as Box<dyn FnMut()>);
        let _ = w.add_event_listener_with_callback(
            "pagehide",
            on_hide.as_ref().unchecked_ref(),
        );
        on_hide.forget();
    }
}

pub fn log(tag: &str, msg: &str) {
    let line = format!("[{}] {} {}", clock(), tag, msg);
    let mut lines = LINES.lock().unwrap();
    lines.push(line);
    if lines.len() > CAP {
        let excess = lines.len() - CAP;
        lines.drain(..excess);
    }
    drop(lines);
    schedule_persist();
}

/// 同一 key 只记一次（渲染降级、附件缺失这类会反复触发的点）。
pub fn log_once(key: &str, tag: &str, msg: &str) {
    let fresh = seen().lock().unwrap().insert(key.to_string());
    if fresh {
        log(tag, msg);
    }
}

// ── 结果侧量测（2026-11-23 补齐，诊断覆盖红线）──────────
// 上面的 log 记的是派生/写入的「意图」；带区类问题定案需要
// DOM 实值——computed 颜色、变量实值、节点存亡、晚到写入。
// 以下量测一律 js_sys::eval 一次性批量脚本：同步直取、同任
// 务成行，不 spawn、不改任何现有行为与时序。脚本失败（无
// window 等）静默跳过，诊断不得反噬功能。

/// 同步批量 eval：脚本须以返回字符串的 IIFE 为形。
pub fn batch(script: &str) -> Option<String> {
    js_sys::eval(script).ok()?.as_string()
}

/// GEO 片段（POST/LBX 共用口径，脚本内联展开）：临时探针元
/// 素实测 env(safe-area-inset-top)（与 SAFE 行同法）。
const PROBE_JS: &str = r#"(() => {
  const de = document.documentElement, bd = document.body;
  const cs = getComputedStyle(de), bs = getComputedStyle(bd);
  const p = document.createElement('div');
  p.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;padding-top:env(safe-area-inset-top)';
  bd.appendChild(p); const sat = getComputedStyle(p).paddingTop; p.remove();
  const vv = window.visualViewport;
  const nc = s => s.replace(/\s/g, '');
  return 'html=' + nc(cs.backgroundColor) + ' body=' + nc(bs.backgroundColor)
    + ' var=' + (cs.getPropertyValue('--mn-root-bg').trim() || '(unset)')
    + ' rgb=' + (cs.getPropertyValue('--mn-root-rgb').trim() || '(unset)')
    + ' inl=' + (nc(de.style.backgroundColor) || '(unset)') + '/' + (nc(bd.style.backgroundColor) || '(unset)')
    + ' vv=' + (vv ? Math.round(vv.height) + '/' + Math.round(vv.offsetTop) : '-')
    + ' sy=' + Math.round(window.scrollY || 0) + ' sat=' + sat;
})()"#;

/// 残留普查：交接/清理类节点的存亡计数 + body 直接子节点。
/// bbbg = #body-before-bg 在否——编辑器渐变改写装置移除后
/// 应恒 false，是其「恒不存在」的长期证据。
const CENSUS_JS: &str = r#"(() => {
  const q = s => document.querySelectorAll(s).length;
  const kids = Array.from(document.body.children).map(e => e.tagName + (e.id ? '#' + e.id : '')).join(',');
  return 'stage=' + q('.editor-stage') + ' eroot=' + q('#editor-root') + ' leaving=' + q('.page-leaving')
    + ' bbbg=' + (!!document.getElementById('body-before-bg')) + ' kids=[' + kids + ']';
})()"#;

/// 延迟重采样：只取根色诸项（computed/变量/内联原值），
/// 抓提交后的晚到写入/回写。
const LATE_JS: &str = r#"(() => {
  const de = document.documentElement;
  const cs = getComputedStyle(de);
  return 'html=' + cs.backgroundColor.replace(/\s/g, '')
    + ' var=' + (cs.getPropertyValue('--mn-root-bg').trim() || '(unset)')
    + ' inl=' + (de.style.backgroundColor.replace(/\s/g, '') || '(unset)')
    + ' bbbg=' + (!!document.getElementById('body-before-bg'));
})()"#;

/// 灯箱量测：根色实值 + .lightbox 挂载链首三段与 rect + GEO。
const LBX_JS: &str = r#"(() => {
  const el = document.querySelector('.lightbox');
  const cs = getComputedStyle(document.documentElement);
  let s = 'root=' + cs.backgroundColor.replace(/\s/g, '');
  if (el) {
    const r = el.getBoundingClientRect();
    const chain = []; let n = el;
    while (n && chain.length < 3) { chain.push(n.tagName + (n.id ? '#' + n.id : '') + (typeof n.className === 'string' && n.className ? '.' + n.className.split(' ')[0] : '')); n = n.parentElement; }
    s += ' el=' + chain.join('>') + ' rect=' + Math.round(r.left) + ',' + Math.round(r.top) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height);
  } else { s += ' el=none'; }
  const p = document.createElement('div');
  p.style.cssText = 'position:fixed;top:0;left:0;visibility:hidden;padding-top:env(safe-area-inset-top)';
  document.body.appendChild(p); const sat = getComputedStyle(p).paddingTop; p.remove();
  const vv = window.visualViewport;
  return s + ' vv=' + (vv ? Math.round(vv.height) + '/' + Math.round(vv.offsetTop) : '-')
    + ' sy=' + Math.round(window.scrollY || 0) + ' sat=' + sat;
})()"#;

/// 根色 computed 实测一行（kind = POST 提交点 / ROOTSET 写后回读）。
pub fn log_probe(tag: &str, kind: &str) {
    if let Some(s) = batch(PROBE_JS) {
        log(tag, &format!("{kind} {s}"));
    }
}

/// 残留普查一行（tag 随打点处：APP 提交点 / EDIT 清理后）。
pub fn log_census(tag: &str) {
    if let Some(s) = batch(CENSUS_JS) {
        log(tag, &format!("CENSUS {s}"));
    }
}

/// 延迟重采样一行（提交闭包挂 300/1000/3000ms 三发）。
pub fn log_late(delay_ms: u32) {
    if let Some(s) = batch(LATE_JS) {
        log("APP", &format!("LATE {delay_ms} {s}"));
    }
}

/// 灯箱一行（phase = open/close/pop）。
pub fn log_lbx(phase: &str) {
    if let Some(s) = batch(LBX_JS) {
        log("EDIT", &format!("LBX {phase} {s}"));
    }
}

/// 弹窗整屏层普查：computed position=fixed 且 rect 覆盖视口
/// 九成的层（tag#id.class@z 序）+ 弹窗/底表主节点的 rect 与
/// computed 背景。备份弹窗底部实心栏排查的第 0 步仪器（审
/// 计 audit_confirm_bottom_bar §6）：此前备份弹窗 open/close
/// 零 Diag、过渡点外的整屏层清单与开后根色回读全缺，本普
/// 查与 log_modal 的延迟重采样补齐这三处。
const MODAL_JS: &str = r#"(() => {
  const vw = window.innerWidth, vh = window.innerHeight;
  const nc = s => s.replace(/\s/g, '');
  const nm = e => e.tagName + (e.id ? '#' + e.id : '') + (typeof e.className === 'string' && e.className ? '.' + e.className.trim().split(/\s+/)[0] : '');
  const full = [];
  document.querySelectorAll('body *').forEach(e => {
    const cs = getComputedStyle(e);
    if (cs.position !== 'fixed') return;
    const r = e.getBoundingClientRect();
    if (r.width >= vw * 0.9 && r.height >= vh * 0.9) full.push(nm(e) + '@' + cs.zIndex);
  });
  const det = sel => {
    const e = document.querySelector(sel);
    if (!e) return sel + '=none';
    const r = e.getBoundingClientRect();
    return sel + '=' + Math.round(r.left) + ',' + Math.round(r.top) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height)
      + ' bg=' + nc(getComputedStyle(e).backgroundColor);
  };
  return 'full=[' + full.join(',') + '] '
    + det('.backup-modal-scrim') + ' ' + det('.backup-modal') + ' '
    + det('.sheet-scrim') + ' ' + det('.bg-sheet') + ' '
    + det('.image-text-sheet-backdrop') + ' ' + det('.image-text-sheet');
})()"#;

/// 弹窗延迟重采样一行（LATE 同形态、标弹窗 tag）。
fn log_modal_late(tag: &str, delay_ms: u32) {
    if let Some(s) = batch(LATE_JS) {
        log("MODAL", &format!("{tag} LATE {delay_ms} {s}"));
    }
}

/// 弹窗一行（tag = backup/sheet-bg/sheet-media，phase =
/// open/close）：根色快照（PROBE 同字段：html/body computed、
/// 变量、内联、GEO）+ 整屏层普查同行。open 另挂 300/1000ms
/// 两发延迟重采样抓开后晚到变化；close 由调用方在元素摘除
/// 前调用（比照 LBX close 口径），快照含尚在场的弹窗节点。
pub fn log_modal(tag: &str, phase: &str) {
    let probe = batch(PROBE_JS);
    let layers = batch(MODAL_JS);
    if probe.is_some() || layers.is_some() {
        log(
            "MODAL",
            &format!(
                "{tag} {phase} {} {}",
                probe.as_deref().unwrap_or(""),
                layers.as_deref().unwrap_or("")
            ),
        );
    }
    if phase == "open" {
        if let Some(w) = web_sys::window() {
            for delay in [300u32, 1000] {
                let t = tag.to_string();
                let late = wasm_bindgen::closure::Closure::once_into_js(move || {
                    log_modal_late(&t, delay)
                });
                let _ = w.set_timeout_with_callback_and_timeout_and_arguments_0(
                    late.unchecked_ref(),
                    delay as i32,
                );
            }
        }
    }
}

pub fn lines() -> Vec<String> {
    LINES.lock().unwrap().clone()
}

pub fn clear() {
    let mut lines = LINES.lock().unwrap();
    lines.clear();
    persist(&lines);
    drop(lines);
    // 已同步落盘：销掉节流欠账，窗口尾的定时刷将无事可做。
    PERSIST_OWED.store(false, Ordering::SeqCst);
    seen().lock().unwrap().clear();
}
