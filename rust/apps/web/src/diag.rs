//! 诊断日志（全模块硬规矩）：任何模块、页面都经 Diag 记一笔，
//! 方便后续定位修复与运维。内存环形缓冲（上限 300 行）+
//! localStorage 持久（键 moment_diag_v1，字符串数组，与
//! Flutter 版同形），刷新/重启不丢。诊断视图在顶栏「诊断」。

use std::collections::HashSet;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

use wasm_bindgen::JsCast;

const KEY: &str = "moment_diag_v1";
const CAP: usize = 300;

/// 历史归档键（2026-11-25 改版）：日志按天冻结——写
/// 入时发现跨日，把上一日缓冲整份冻进归档表（{at 冻
/// 结时刻 epoch ms, day 归属日 YYYY-MM-DD, lines[]}），
/// 当天缓冲清空续写。归档上限 MAX_ARCHIVES 份（超出丢
/// 最旧并记 WARN 行），防长年累积膨胀 localStorage。
const ARCHIVES_KEY: &str = "moment_diag_archives_v1";
/// 当天缓冲的归属日（YYYY-MM-DD，本地时区）：行内只有
/// [HH:MM:SS] 无日期，跨日判定靠此键与内存 CUR_DAY。
/// 键缺失（改版前存量）时缓冲整体视为当天日志、不冻结。
const DAY_KEY: &str = "moment_diag_day_v1";
const MAX_ARCHIVES: usize = 60;
/// 自动删除偏好键（"1" 开，缺失/其余 = 关，默认关）：
/// 开启时（偏好打开瞬间 + 每次 init）删除冻结时刻超
/// 过 AUTODEL_DAYS 天的归档。
const AUTODEL_KEY: &str = "moment_diag_autodel_v1";
const AUTODEL_DAYS: i64 = 30;
/// 等级门槛偏好键（all/info/warn/error，缺失 = all）：
/// 只控 Diag 页与日志视窗页的显示过滤，原文不删。
const LEVEL_KEY: &str = "moment_diag_level_v1";

/// 外壳 SW 更新提示的事件暂存键（index.html 内联脚本写）：
/// 提示在应用之外展示/点击，事件先落此键，启动时由
/// drain_swupd_events 读入 Diag 并清除。
const SWUPD_PENDING_KEY: &str = "moment_swupd_pending_v1";

/// 外壳救援层的日志键（index.html 内联脚本写）：每次加载
/// 的状态快照（只记元数据）与救援动作（导出/修复）都落
/// 此键，启动时由 drain_rescue_log 折入 Diag 并清除。
const RESCUE_LOG_KEY: &str = "moment_rescue_log_v1";

/// Panic 取证键：panic 钩同步直写（见 install_panic_hook），
/// 启动时由 drain_panic_log 折入 Diag 并清除。
const PANIC_KEY: &str = "moment_panic_v1";

/// Panic 取证钩（2026-11-24 点击死亡故障定因）：本应用为
/// panic=abort，任一 Rust panic 都以 wasm trap 呈现，外壳
/// 只能记到 `Unreachable code` 而无出处。钩在 abort 之前
/// 同步执行，把 payload 与源码位置（file:line:col）直写
/// localStorage——不走 Diag 内存环与节流落盘（崩溃现场两
/// 者都可能已不可用），两处落点：专用键 moment_panic_v1
/// （下次启动 drain 成 PANIC 行）+ Diag 键当场追加一行
/// （救援导出即刻可见）。钩内绝不 unwrap/索引，任何一步
/// 失败静默放弃，禁止二次 panic。若 trap 时专用键无新记
/// 录，即证明 trap 不是 Rust panic 本体、而是已 drop 闭
/// 包的 bindgen unreachable 桩被 JS 迟发调用——两形态以
/// 此一刀切分。main() 最先安装（先于 diag::init）。
pub fn install_panic_hook() {
    std::panic::set_hook(Box::new(|info| {
        let loc = info
            .location()
            .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
            .unwrap_or_default();
        let payload = if let Some(s) = info.payload().downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = info.payload().downcast_ref::<String>() {
            s.clone()
        } else {
            "<non-string payload>".to_string()
        };
        let line = format!("[{}] PANIC {} @ {}", clock(), payload, loc);
        let Some(storage) = web_sys::window()
            .and_then(|w| w.local_storage().ok())
            .flatten()
        else {
            return;
        };
        let mut arr: Vec<String> = storage
            .get_item(PANIC_KEY)
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        arr.push(line.clone());
        if arr.len() > 20 {
            arr.drain(..arr.len() - 20);
        }
        if let Ok(j) = serde_json::to_string(&arr) {
            let _ = storage.set_item(PANIC_KEY, &j);
        }
        let mut dl: Vec<String> = storage
            .get_item(KEY)
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        dl.push(line);
        if dl.len() > CAP {
            dl.drain(..dl.len() - CAP);
        }
        if let Ok(j) = serde_json::to_string(&dl) {
            let _ = storage.set_item(KEY, &j);
        }
    }));
}

/// 折入上次会话的 panic 记录（init 调用，与 SWUPD/RESCUE
/// 同口径：读入成 PANIC 行、清键防重复折入）。
fn drain_panic_log() {
    let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    else {
        return;
    };
    let Ok(Some(json)) = storage.get_item(PANIC_KEY) else {
        return;
    };
    let _ = storage.remove_item(PANIC_KEY);
    if let Ok(rows) = serde_json::from_str::<Vec<String>>(&json) {
        for row in rows {
            // 存储行自带「[时刻] PANIC 」前缀，drain 时剥掉
            // 再以 PANIC 标签重记，避免导出里出现 PANIC 套
            // PANIC 的嵌套回声；原时刻已在行内、剥后不丢信息
            // （log 另加当前时刻前缀，双时刻仍可对读）。
            let body = row
                .split_once("] ")
                .map(|(_, rest)| rest.strip_prefix("PANIC ").unwrap_or(rest))
                .unwrap_or(&row);
            log("PANIC", body);
        }
        flush_persist();
    }
}

/// 「应用已活」标记（救援层看门狗读）：init 后 2s 由存活
/// 闭包写（见 init）。若应用在数据加载/首帧前后
/// panic=abort，闭包随 wasm 实例死亡、标记永不更新，
/// 外壳 12s 看门狗据此出救援条。值 = {"t": epoch ms}。
const BOOT_OK_KEY: &str = "moment_boot_ok";

static LINES: Mutex<Vec<String>> = Mutex::new(Vec::new());
static ARCHIVES: Mutex<Vec<DiagArchive>> = Mutex::new(Vec::new());
/// 当天缓冲归属日（与 DAY_KEY 同步）：空 = 尚未由
/// init/首行写入播种，首行时以今日播种（不冻结）。
static CUR_DAY: Mutex<String> = Mutex::new(String::new());

/// 一份按天冻结的历史归档：at = 冻结时刻（epoch ms，
/// 胶囊与视窗页标题取它格式化），day = 行的归属日，
/// lines = 冻结时的当天缓冲全量（上限 CAP 行）。存
/// 储走 serde_json::Value 手工组装/解析（web crate 无
/// serde 直依赖，与全仓 Value 口径一致）。
#[derive(Clone)]
pub struct DiagArchive {
    pub at: i64,
    pub day: String,
    pub lines: Vec<String>,
}

impl DiagArchive {
    fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "at": self.at,
            "day": self.day,
            "lines": self.lines,
        })
    }

    /// 坏条目（字段缺失/类型不合）整份丢弃：归档只是
    /// 历史留存，宁缺勿假。
    fn from_json(v: &serde_json::Value) -> Option<DiagArchive> {
        Some(DiagArchive {
            at: v.get("at")?.as_i64()?,
            day: v.get("day")?.as_str()?.to_string(),
            lines: v
                .get("lines")?
                .as_array()?
                .iter()
                .filter_map(|l| l.as_str().map(str::to_string))
                .collect(),
        })
    }
}

/// 日志视窗页请求（Diag 页点归档胶囊/当天卡时构造）：
/// stamp = 标题基串「YYYY-MM-DD HH:mm」（归档取冻结
/// 时刻、当天取打开时刻），lines = 打开时刻的行快照
/// （归档本已冻结；当天取现行缓冲全量，视窗页内按等
/// 级门槛过滤显示、导出走全量）。
#[derive(Clone, PartialEq)]
pub struct LogViewReq {
    pub stamp: String,
    pub lines: Vec<String>,
}

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

fn now_ms() -> i64 {
    js_sys::Date::now() as i64
}

/// 今日日期串（本地时区 YYYY-MM-DD）：跨日归档判定与
/// 归档 day 字段的唯一出处。
fn today_str() -> String {
    let d = js_sys::Date::new_0();
    format!(
        "{:04}-{:02}-{:02}",
        d.get_full_year(),
        d.get_month() + 1,
        d.get_date()
    )
}

/// 时刻格式化（本地时区「YYYY-MM-DD HH:mm」）：归档
/// 胶囊文本与视窗页标题的统一口径。
pub fn stamp_of(ms: i64) -> String {
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_f64(ms as f64));
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}",
        d.get_full_year(),
        d.get_month() + 1,
        d.get_date(),
        d.get_hours(),
        d.get_minutes()
    )
}

/// 当前时刻的 stamp（当天卡打开视窗页时取标题用）。
pub fn now_stamp() -> String {
    stamp_of(now_ms())
}

fn storage() -> Option<web_sys::Storage> {
    web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
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

// ── 全局错误捕获（批 10 P-D8）────────────────────────
// window error / unhandledrejection 统一记 ERR 行：此前
// 未捕获异常在 Diag 里毫无踪迹，崩溃/白屏类问题只能靠猜。
// 只旁路记录、不干预——不调 preventDefault、不吞事件，
// 页面原有的错误表现行为不变。ERR 行立即落盘（含节流欠
// 账行）：错误常是崩溃前兆，等 1s 合并窗口可能永远等不
// 到。同文错误每会话只记一次（复用 log_once 的 seen 集，
// clear 后重置），防 rAF 循环抛错类场景刷屏 + 反复写盘。

/// ERR 行：记一行并立即落盘；同文每会话去重。
pub fn log_err(msg: &str) {
    log_err_full("RENDER", msg, msg, "", "");
}

/// 带徽章投递的 ERR 行（审计 E-1）：原版全局错误监听在记
/// 录的同时把异常投进右下角错误徽章（addError）；Rust 的
/// 钩子在此同口径投递——kind 为原版 type（RENDER/PROMISE），
/// badge_msg/loc/stack 为徽章条目字段（与 Diag 行文案分开，
/// Diag 行保留既有格式）。去重与 Diag 共用同一 seen 集：
/// 同文错误每会话只记一行、也只投一枚（防刷屏，原版徽章
/// 上限 20 条另有兜底）。
pub fn log_err_full(kind: &'static str, msg: &str, badge_msg: &str, loc: &str, stack: &str) {
    let fresh = seen()
        .lock()
        .unwrap()
        .insert(format!("err:{msg}"));
    if fresh {
        log("ERR", msg);
        flush_persist();
        crate::errbadge::add_error(kind, badge_msg, loc, stack);
    }
}

fn js_str(obj: &wasm_bindgen::JsValue, key: &str) -> String {
    js_sys::Reflect::get(obj, &wasm_bindgen::JsValue::from_str(key))
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_default()
}

fn trunc(s: &str, n: usize) -> String {
    if s.chars().count() > n {
        format!("{}…", s.chars().take(n).collect::<String>())
    } else {
        s.to_string()
    }
}

/// rejection reason 文本化：字符串直用；Error 取
/// name/message；其余 JSON 化兜底（循环结构失败再退回
/// Debug 摘要）。上限 300 字，防巨行撑爆环。
fn reason_text(v: &wasm_bindgen::JsValue) -> String {
    if let Some(s) = v.as_string() {
        return trunc(&s, 300);
    }
    let msg = js_str(v, "message");
    if !msg.is_empty() {
        let name = js_str(v, "name");
        return trunc(
            &(if name.is_empty() {
                msg
            } else {
                format!("{name}: {msg}")
            }),
            300,
        );
    }
    let json = js_sys::JSON::stringify(v)
        .ok()
        .and_then(|s| s.as_string());
    trunc(json.as_deref().unwrap_or("(unprintable reason)"), 300)
}

static HOOKS_INSTALLED: AtomicBool = AtomicBool::new(false);

/// 全局错误钩（init 调一次，幂等）：error / unhandled-
/// rejection 两路。资源加载类 error 事件无 message 字段，
/// 跳过不记（非 JS 异常、避免噪声行）。
fn install_error_hooks() {
    if HOOKS_INSTALLED.swap(true, Ordering::SeqCst) {
        return;
    }
    let Some(w) = web_sys::window() else { return };
    let on_error = wasm_bindgen::closure::Closure::wrap(Box::new(move |e: web_sys::Event| {
        let ev: &wasm_bindgen::JsValue = e.as_ref();
        let msg = js_str(ev, "message");
        if msg.is_empty() {
            return;
        }
        let file = js_str(ev, "filename");
        let mut s = format!("window.onerror {msg}");
        // 徽章条目字段（原版 addError 口径）：loc = 文件名
        // （去路径）:行号，stack = e.error 的堆栈。
        let mut loc = String::new();
        if !file.is_empty() {
            let line = js_sys::Reflect::get(ev, &wasm_bindgen::JsValue::from_str("lineno"))
                .ok()
                .and_then(|v| v.as_f64())
                .map(|n| n as i64)
                .unwrap_or(0);
            s.push_str(&format!(" @ {file}:{line}"));
            loc = format!(
                "{}:{}",
                file.rsplit('/').next().unwrap_or(&file),
                line
            );
        }
        let stack = js_sys::Reflect::get(ev, &wasm_bindgen::JsValue::from_str("error"))
            .map(|err| js_str(&err, "stack"))
            .unwrap_or_default();
        log_err_full("RENDER", &trunc(&s, 300), &msg, &loc, &stack);
    }) as Box<dyn FnMut(web_sys::Event)>);
    let _ = w.add_event_listener_with_callback("error", on_error.as_ref().unchecked_ref());
    on_error.forget();
    let on_rej = wasm_bindgen::closure::Closure::wrap(Box::new(move |e: web_sys::Event| {
        let ev: &wasm_bindgen::JsValue = e.as_ref();
        if let Ok(reason) = js_sys::Reflect::get(ev, &wasm_bindgen::JsValue::from_str("reason")) {
            let text = reason_text(&reason);
            let stack = js_str(&reason, "stack");
            log_err_full(
                "PROMISE",
                &format!("unhandledrejection {text}"),
                &text,
                "",
                &stack,
            );
        }
    }) as Box<dyn FnMut(web_sys::Event)>);
    let _ = w.add_event_listener_with_callback(
        "unhandledrejection",
        on_rej.as_ref().unchecked_ref(),
    );
    on_rej.forget();
    // 桥错误回传口的收端（批 10 P-D8）：bridge.rs 的
    // __mnErr 以 mn-bridge-err 事件（detail.where/msg）
    // 回传桥内被捕获的异常，此处统一记 ERR 行。走事件而
    // 非桥 op 通道：op 的处理端在 editor.rs，本口收端自
    // 洽于 diag，不依赖编辑器消息循环存活。
    let on_bridge = wasm_bindgen::closure::Closure::wrap(Box::new(move |e: web_sys::Event| {
        let ev: &wasm_bindgen::JsValue = e.as_ref();
        let Ok(detail) = js_sys::Reflect::get(ev, &wasm_bindgen::JsValue::from_str("detail"))
        else {
            return;
        };
        let where_ = js_str(&detail, "where");
        let msg = js_str(&detail, "msg");
        if msg.is_empty() {
            return;
        }
        log_err(&trunc(
            &format!(
                "bridge {}: {msg}",
                if where_.is_empty() { "?" } else { &where_ }
            ),
            300,
        ));
    }) as Box<dyn FnMut(web_sys::Event)>);
    let _ = w.add_event_listener_with_callback(
        "mn-bridge-err",
        on_bridge.as_ref().unchecked_ref(),
    );
    on_bridge.forget();
}

/// 外壳 SW 更新提示的暂存事件读入（init 调一次）：条目
/// {e: shown|clicked, v: 新代 VERSION 戳, t: HH:MM:SS}，
/// 逐条转 SWUPD 行（行文走 log() 与现行格式一致）。键无
/// 论解析成败都先清除，防坏值每次启动反复重试；应用异
/// 常未启动时事件留在键里不丢、下次启动补记。
fn drain_swupd_events() {
    let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    else {
        return;
    };
    let Ok(Some(json)) = storage.get_item(SWUPD_PENDING_KEY) else {
        return;
    };
    let _ = storage.remove_item(SWUPD_PENDING_KEY);
    let Ok(events) = serde_json::from_str::<Vec<serde_json::Value>>(&json) else {
        return;
    };
    for ev in &events {
        let what = match ev.get("e").and_then(|v| v.as_str()) {
            Some("shown") => "prompt shown",
            Some("clicked") => "update clicked",
            _ => continue,
        };
        let ver = ev.get("v").and_then(|v| v.as_str()).unwrap_or("");
        let at = ev.get("t").and_then(|v| v.as_str()).unwrap_or("");
        log("SWUPD", &format!("{what} ver={ver} at={at}"));
    }
}

/// 外壳救援层的日志读入（init 调一次）：条目 kind =
/// snapshot（每次加载的状态快照，只记元数据）/ export /
/// repair（面板动作）。纯快照只是导出备料，健康启动静默
/// 清除、不刷 Diag 环；含动作条目时逐条转 RESCUE 行，并
/// 给最新快照一行摘要作回执（救援后现场状态有据可查）。
/// 键无论解析成败都先清除，防坏值每次启动反复重试。
fn drain_rescue_log() {
    let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    else {
        return;
    };
    let Ok(Some(json)) = storage.get_item(RESCUE_LOG_KEY) else {
        return;
    };
    let _ = storage.remove_item(RESCUE_LOG_KEY);
    let Ok(entries) = serde_json::from_str::<Vec<serde_json::Value>>(&json) else {
        return;
    };
    fn kind_of<'a>(e: &'a serde_json::Value) -> &'a str {
        e.get("kind").and_then(|v| v.as_str()).unwrap_or("")
    }
    let has_action = entries
        .iter()
        .any(|e| matches!(kind_of(e), "repair" | "export"));
    if !has_action {
        return;
    }
    for e in &entries {
        let at = e.get("t").and_then(|v| v.as_str()).unwrap_or("");
        match kind_of(e) {
            "repair" => log(
                "RESCUE",
                &format!("repair boot at={at} (sw unregistered, caches cleared)"),
            ),
            "export" => log("RESCUE", &format!("diagnostics exported at={at}")),
            _ => {}
        }
    }
    if let Some(snap) = entries.iter().rev().find(|e| kind_of(e) == "snapshot") {
        let count = |k: &str| {
            snap.get(k)
                .and_then(|v| v.as_array())
                .map(|a| a.len())
                .unwrap_or(0)
        };
        let at = snap.get("t").and_then(|v| v.as_str()).unwrap_or("");
        let after = snap
            .get("afterRepair")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        log(
            "RESCUE",
            &format!(
                "snapshot at={at} sw={} caches={} idb={} ls={} afterRepair={after}",
                count("sw"),
                count("caches"),
                count("idb"),
                count("ls")
            ),
        );
    }
}

/// 写「应用已活」标记（init 后 2s 的存活闭包调）：写标记
/// 这一动作本身即存活证明——闭包能被调到，说明 wasm 实
/// 例活到了这一刻；若此前已 panic=abort，闭包随实例死
/// 亡、标记停留在上一会话的值，外壳看门狗据此判死。
fn mark_boot_ok() {
    if let Some(storage) = web_sys::window()
        .and_then(|w| w.local_storage().ok())
        .flatten()
    {
        let t = js_sys::Date::now() as i64;
        let _ = storage.set_item(BOOT_OK_KEY, &format!("{{\"t\":{t}}}"));
    }
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
        // 归档表读回（改版存储升级）：坏值当空表，不挡
        // 启动（归档只是历史留存，丢了不伤当天日志）。
        if let Ok(Some(json)) = storage.get_item(ARCHIVES_KEY) {
            if let Ok(serde_json::Value::Array(arr)) =
                serde_json::from_str::<serde_json::Value>(&json)
            {
                *ARCHIVES.lock().unwrap() =
                    arr.iter().filter_map(DiagArchive::from_json).collect();
            }
        }
        // 归属日播种：有存量键用存量（随后 rotate 判定
        // 是否跨日冻结）；无键 = 改版前存量，缓冲整体
        // 视为当天日志（用户口径），以今日播种不冻结。
        match storage.get_item(DAY_KEY).ok().flatten() {
            Some(day) => *CUR_DAY.lock().unwrap() = day,
            None => {
                *CUR_DAY.lock().unwrap() = today_str();
                persist_day();
            }
        }
    }
    // 跨日冻结（上一日缓冲 → 归档 + archived 结果行，
    // 须在各 drain 之前：drain 行属今天、入新缓冲）。
    rotate_if_needed();
    // 自动删除（偏好开时每次启动清一遍过期归档）。
    if autodel_enabled() {
        purge_old_archives();
    }
    drain_swupd_events();
    drain_rescue_log();
    drain_panic_log();
    // boot-ok 存活证明（救援层看门狗）：init 后 2s 写标记
    // （与节流落盘同款 once 闭包 + set_timeout）。数据加
    // 载与首帧正常都在此窗口内完成；应用若在此前死掉，
    // 标记不更新、外壳 12s 后出救援条。
    if let Some(w) = web_sys::window() {
        let cb = wasm_bindgen::closure::Closure::once_into_js(mark_boot_ok);
        let _ = w.set_timeout_with_callback_and_timeout_and_arguments_0(
            cb.unchecked_ref(),
            2000,
        );
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
    install_error_hooks();
}

// ── 等级维（2026-11-25 改版）────────────────────────
// 行格式兼容口径：info 行与旧格式逐字一致
// 「[HH:MM:SS] TAG msg」——全仓探针以 includes('TAG '
// + 正文前缀) 与 '] ERR ' 匹配既有行，此二式必须不失
// 效。warn/error（显式等级、非 ERR 通道）把等级标记
// 编进方括号内时刻之后：「[HH:MM:SS W] TAG msg」/
// 「[HH:MM:SS E] TAG msg」——'] TAG ' 子串与行首 '['
// 均不变，探针口径零影响。读侧分级（line_level）：
// 括号内 W/E 标记优先；无标记时 ERR/PANIC 两标签本身
// 即错误通道、归 error；其余（含全部旧存量行）归
// info（用户口径：无等级标记按 info 读）。
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Info,
    Warn,
    Error,
}

fn format_line(level: Level, tag: &str, msg: &str) -> String {
    match level {
        Level::Info => format!("[{}] {} {}", clock(), tag, msg),
        Level::Warn => format!("[{} W] {} {}", clock(), tag, msg),
        Level::Error => format!("[{} E] {} {}", clock(), tag, msg),
    }
}

/// 一行的等级（显示过滤的判定出处，规则见上注）。
pub fn line_level(line: &str) -> Level {
    let Some(end) = line.find(']') else {
        return Level::Info;
    };
    let head = &line[..end];
    if head.ends_with(" W") {
        return Level::Warn;
    }
    if head.ends_with(" E") {
        return Level::Error;
    }
    if let Some(rest) = line.get(end + 2..) {
        let tag = rest.split(' ').next().unwrap_or("");
        if tag == "ERR" || tag == "PANIC" {
            return Level::Error;
        }
    }
    Level::Info
}

/// 等级门槛（Diag 页等级行的四档）：All 与 Info 同效
/// （全显），Warn 起只显 warn+error，Error 只显 error。
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum LevelFilter {
    All,
    Info,
    Warn,
    Error,
}

impl LevelFilter {
    pub fn key(self) -> &'static str {
        match self {
            LevelFilter::All => "all",
            LevelFilter::Info => "info",
            LevelFilter::Warn => "warn",
            LevelFilter::Error => "error",
        }
    }

    pub fn from_key(s: &str) -> LevelFilter {
        match s {
            "info" => LevelFilter::Info,
            "warn" => LevelFilter::Warn,
            "error" => LevelFilter::Error,
            _ => LevelFilter::All,
        }
    }

    fn min_level(self) -> Level {
        match self {
            LevelFilter::All | LevelFilter::Info => Level::Info,
            LevelFilter::Warn => Level::Warn,
            LevelFilter::Error => Level::Error,
        }
    }
}

/// 当前等级门槛偏好（每次现读，Diag 页与视窗页同值）。
pub fn level_filter() -> LevelFilter {
    storage()
        .and_then(|s| s.get_item(LEVEL_KEY).ok().flatten())
        .map(|v| LevelFilter::from_key(&v))
        .unwrap_or(LevelFilter::All)
}

/// 设等级门槛：落偏好 + 记结果行（等级变更属用户动
/// 作，按硬规矩留痕）。
pub fn set_level_filter(f: LevelFilter) {
    if let Some(s) = storage() {
        let _ = s.set_item(LEVEL_KEY, f.key());
    }
    log("DIAG", &format!("level {}", f.key()));
}

/// 按门槛过滤出行列（原文不动，只影响呈现）。
pub fn filter_lines(lines: &[String], f: LevelFilter) -> Vec<String> {
    let min = f.min_level();
    lines
        .iter()
        .filter(|l| line_level(l) >= min)
        .cloned()
        .collect()
}

fn persist_archives() {
    let arch = ARCHIVES.lock().unwrap();
    if let Some(s) = storage() {
        let arr: Vec<serde_json::Value> = arch.iter().map(DiagArchive::to_json).collect();
        if let Ok(json) = serde_json::to_string(&arr) {
            let _ = s.set_item(ARCHIVES_KEY, &json);
        }
    }
}

fn persist_day() {
    let day = CUR_DAY.lock().unwrap().clone();
    if let Some(s) = storage() {
        let _ = s.set_item(DAY_KEY, &day);
    }
}

/// 冻结一份归档并落盘；超上限丢最旧（丢弃在落盘后以
/// WARN 行留痕——归档静默消失会让「日志不见了」无从
/// 定位，属降级事件、归 warn）。
fn push_archive(a: DiagArchive) {
    let mut dropped: Option<String> = None;
    {
        let mut arch = ARCHIVES.lock().unwrap();
        arch.push(a);
        while arch.len() > MAX_ARCHIVES {
            dropped = Some(arch.remove(0).day);
        }
    }
    persist_archives();
    if let Some(day) = dropped {
        log_warn("DIAG", &format!("archive cap, dropped oldest day={day}"));
    }
}

/// 跨日轮转（每行写入前查一次，日期串比较、代价可
/// 忽略）：归属日与今日不同且缓冲非空 → 整份冻结为
/// 归档（冻结时刻 = 此刻）、缓冲清空、归属日推进，
/// 并在新缓冲首记 archived 结果行。缓冲为空只推进
/// 归属日、不产空归档。CUR_DAY 未播种（init 前的零
/// 星调用）时以今日播种、不冻结（存量视为当天）。
fn rotate_if_needed() {
    let today = today_str();
    let cur = CUR_DAY.lock().unwrap().clone();
    if cur.is_empty() {
        *CUR_DAY.lock().unwrap() = today;
        persist_day();
        return;
    }
    if cur == today {
        return;
    }
    let old: Vec<String> = {
        let mut lines = LINES.lock().unwrap();
        std::mem::take(&mut *lines)
    };
    *CUR_DAY.lock().unwrap() = today;
    persist_day();
    if old.is_empty() {
        return;
    }
    let n = old.len();
    push_archive(DiagArchive {
        at: now_ms(),
        day: cur.clone(),
        lines: old,
    });
    let note = format_line(Level::Info, "DIAG", &format!("archived {cur} lines={n}"));
    let mut lines = LINES.lock().unwrap();
    lines.push(note);
    drop(lines);
    schedule_persist();
}

fn push_line(line: String) {
    rotate_if_needed();
    let mut lines = LINES.lock().unwrap();
    lines.push(line);
    if lines.len() > CAP {
        let excess = lines.len() - CAP;
        lines.drain(..excess);
    }
    drop(lines);
    schedule_persist();
}

pub fn log(tag: &str, msg: &str) {
    push_line(format_line(Level::Info, tag, msg));
}

/// WARN 行：降级/兜底/重试类事件（功能未失败但走了
/// 次优路径，后续筛选「警告」档即为看这一类）。error
/// 档不另设入口：全局错误走 log_err 的 ERR 通道、模
/// 块级失败同样归 ERR/PANIC 标签（line_level 按标签
/// 归 error），显式 E 标记只留给格式层（format_line）
/// 与读侧解析，不造无调用方的 API。
pub fn log_warn(tag: &str, msg: &str) {
    push_line(format_line(Level::Warn, tag, msg));
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

/// GEO 片段（POST 用口径，脚本内联展开）：临时探针元素
/// 实测 env(safe-area-inset-top)（与 SAFE 行同法）。
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
/// 应恒 false，是其「恒不存在」的长期证据。leaving =
/// .page-leaving 计数——该层已随栈式快照交接整套退役
/// （2026-11-24 统一机制收敛），恒 0 为其「不复活」哨兵。
/// imgp = .img-
/// page 计数（图片页，2026-11-24 由浮层改独立页面）：卸
/// 载/提交点普查须能直接断言「图片页残留 = 0」。
const CENSUS_JS: &str = r#"(() => {
  const q = s => document.querySelectorAll(s).length;
  const kids = Array.from(document.body.children).map(e => e.tagName + (e.id ? '#' + e.id : '')).join(',');
  return 'stage=' + q('.editor-stage') + ' eroot=' + q('#editor-root') + ' leaving=' + q('.page-leaving')
    + ' imgp=' + q('.img-page')
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
/// 前调用，快照含尚在场的弹窗节点。
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

/// 归档表快照（存储序 = 冻结先后，旧→新；Diag 页显
/// 示时倒序为新→旧）。
pub fn archives() -> Vec<DiagArchive> {
    ARCHIVES.lock().unwrap().clone()
}

/// 自动删除偏好现值（默认关）。
pub fn autodel_enabled() -> bool {
    storage()
        .and_then(|s| s.get_item(AUTODEL_KEY).ok().flatten())
        .map(|v| v == "1")
        .unwrap_or(false)
}

/// 设自动删除偏好：落盘 + 记结果行；开启瞬间即清一
/// 遍过期归档（不等下次启动，用户开了就该立刻生效）。
pub fn set_autodel(on: bool) {
    if let Some(s) = storage() {
        let _ = s.set_item(AUTODEL_KEY, if on { "1" } else { "0" });
    }
    log("DIAG", &format!("autodel {}", if on { "on" } else { "off" }));
    if on {
        purge_old_archives();
    }
}

/// 删除冻结时刻超过 AUTODEL_DAYS 天的归档；删了才记
/// 结果行（无可删不记，免每次启动刷一行空转记录）。
pub fn purge_old_archives() {
    let cutoff = now_ms() - AUTODEL_DAYS * 86_400_000;
    let n = {
        let mut arch = ARCHIVES.lock().unwrap();
        let before = arch.len();
        arch.retain(|a| a.at >= cutoff);
        before - arch.len()
    };
    if n > 0 {
        persist_archives();
        log("DIAG", &format!("autodel purged {n}"));
    }
}

// ── 视窗页导出（系统分享链）──────────────────────────
// 与附件打开的分享链同构（blocks::open_js_file）：点
// 击手势内同步构造 File → canShare 通过走 navigator
// .share({files, title=文件名})，Promise 结局异步回
// 记；API 缺失/canShare 不过 → 同步降级 <a download>。
// 导出内容 = 该份日志全量行（不按等级门槛过滤——导
// 出是取证动作，过滤只是呈现）。结局一律记 DIAG
// export 结果行（ok/cancelled/err），不静默。

fn js_error_name(e: &wasm_bindgen::JsValue) -> String {
    js_sys::Reflect::get(e, &wasm_bindgen::JsValue::from_str("name"))
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_else(|| "Error".to_string())
}

pub fn export_log(stamp: &str, lines: &[String]) {
    let fname = format!("{stamp}.log");
    let body = lines.join("\n");
    let bytes = body.as_bytes();
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::FilePropertyBag::new();
    opts.set_type("text/plain");
    let Ok(file) = web_sys::File::new_with_u8_array_sequence_and_options(&parts, &fname, &opts)
    else {
        log("DIAG", &format!("export err {fname} file-construct"));
        return;
    };
    let size = bytes.len();
    let Some(window) = web_sys::window() else {
        log("DIAG", &format!("export err {fname} no-window"));
        return;
    };
    let nav = window.navigator();
    let nav_js: wasm_bindgen::JsValue = nav.clone().into();
    let has_fn = |key: &str| {
        js_sys::Reflect::get(&nav_js, &wasm_bindgen::JsValue::from_str(key))
            .map(|v| v.is_function())
            .unwrap_or(false)
    };
    if has_fn("share") && has_fn("canShare") {
        let data = web_sys::ShareData::new();
        let files = js_sys::Array::new();
        files.push(&file);
        data.set_files(&wasm_bindgen::JsValue::from(files));
        data.set_title(&fname);
        if nav.can_share_with_data(&data) {
            let promise = nav.share_with_data(&data);
            let fname2 = fname.clone();
            dioxus::prelude::spawn(async move {
                use wasm_bindgen_futures::JsFuture;
                match JsFuture::from(promise).await {
                    Ok(_) => log("DIAG", &format!("export ok {fname2} {size}B")),
                    Err(e) => {
                        let en = js_error_name(&e);
                        if en == "AbortError" {
                            log("DIAG", &format!("export cancelled {fname2}"));
                        } else {
                            log("DIAG", &format!("export err {fname2} {en}"));
                        }
                    }
                }
            });
            return;
        }
    }
    // 下载兜底（与 blocks::download_js_file 同形态）。
    let mut delivered = false;
    if let Some(doc) = window.document() {
        if let Ok(url) = web_sys::Url::create_object_url_with_blob(file.unchecked_ref()) {
            if let Ok(el) = doc.create_element("a") {
                let a: web_sys::HtmlAnchorElement = el.unchecked_into();
                a.set_href(&url);
                a.set_download(&fname);
                a.click();
                delivered = true;
            }
            let _ = web_sys::Url::revoke_object_url(&url);
        }
    }
    if delivered {
        log("DIAG", &format!("export ok {fname} {size}B (download)"));
    } else {
        log("DIAG", &format!("export err {fname} download-failed"));
    }
}
