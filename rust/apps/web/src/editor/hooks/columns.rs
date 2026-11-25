//! 双栏组 hooks（批 14 三轮自 editor.rs 拆出）：头像/
//! DOM 回写/背景色信号、双栏与宽屏判定及监听、双栏首
//! 次落锚。段内代码逐字搬移；仅 bg/layout 两处信号初
//! 始值改由调用点以挂载快照求值后传入（求值时点与原
//! 闭包同位），其余不变。

use super::super::*;

/// 双栏组信号（use_columns 返回）。
pub(in crate::editor) struct Columns {
    pub(in crate::editor) avatar_url: Signal<Option<String>>,
    pub(in crate::editor) dom_set: Signal<Option<(String, String, usize)>>,
    pub(in crate::editor) bg: Signal<Option<String>>,
    pub(in crate::editor) twopane: Signal<bool>,
    pub(in crate::editor) wide: Signal<bool>,
}

pub(in crate::editor) fn use_columns(
    mut data: Signal<BackupFile>,
    memo_id: String,
    doc: Signal<Vec<Node>>,
    bg_init: Option<String>,
    layout_init: Option<mynote_core::MemoLayout>,
    avatar_init: Option<String>,
    mut layout_sig: Signal<Option<mynote_core::MemoLayout>>,
) -> Columns {
// 本篇头像（原版 per-note avatar，存 backup.avatars[memoId]）：
// 初值由调用点在打开交接时一次性捕获传入（实例自有口
// 径），会话内变更走 TitleDock 换头像路径写本信号，不回
// 查总数据。
let avatar_url = use_signal(|| avatar_init);
let dom_set = use_signal(|| Option::<(String, String, usize)>::None);
// 背景色 / 双栏：存 memo 类型字段（bgColor、layout）。
let bg = use_signal(|| bg_init);
let twopane = use_signal(|| {
    let layout = layout_init.as_ref();
    if let Some(mode) = layout.and_then(|l| l.mode.as_deref()) {
        return mode == "independent";
    }
    if layout.is_some() {
        // G-2（A-2 批翻转）：layout 存在但无 mode 时默认
        // independent，与原版 normalize 缺 mode 口径对齐
        // （editor.render.js）。旧 twoPane 形已由迁移通道
        // 归一为 mode（§2.2），主线不再读。此类 layout 只
        // 来自导入的旧/手写备份；首次宽屏打开后落锚/关存
        // 路径会将其归一为带 mode 的完整形状（名单合法者
        // 名单不动）。
        return true;
    }
    web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|st| st.get_item("sj_editor_independent_scroll").ok().flatten())
        .map(|v| v == "1")
        .unwrap_or(false)
});
// 宽屏判定（原版双栏媒体查询）：(min-width:768px 且
// min-height:600px) 或 min-width:1100px；matchMedia 监听
let mut wide = use_signal(|| {
    web_sys::window()
        .map(|w| {
            w.match_media("(min-width: 768px) and (min-height: 600px), (min-width: 1100px)")
                .ok()
                .flatten()
                .map(|m| m.matches())
                .unwrap_or(false)
        })
        .unwrap_or(false)
});
use_effect(move || {
    spawn(async move {
        let mut eval = document::eval(
            // change 监听具名登记（页面副作用审计·泄漏 3）：
            // 旧实现匿名 addEventListener，每次挂载 +1 且永
            // 不摘除、卸载后仍向死通道 send。改走具名
            // handler + window.__mnWideCleanup 幂等清理：
            // 重挂载先调上一代清理，卸载时 sync_editor_
            // cleanup 同步直调，与桥清理并入同一次卸载清理。
            "(() => { if (window.__mnWideCleanup) window.__mnWideCleanup(); const mq = window.matchMedia('(min-width: 768px) and (min-height: 600px), (min-width: 1100px)'); const h = (e) => dioxus.send(e.matches); mq.addEventListener('change', h); window.__mnWideCleanup = () => { mq.removeEventListener('change', h); window.__mnWideCleanup = null; }; dioxus.send(mq.matches); })();",
        );
        while let Ok(v) = eval.recv::<bool>().await {
            // PERF（第八批 T2）：初值回送与现值相同（窄屏
            // false = 初始值）时不 set——Signal::set 无条件
            // 通知订阅者，同值 set 会让整个 Editor 在挂载
            // 后多渲一遍（实测渲染遍数 2→1、打开长任务
            // 173→128ms）；值真变化时照旧 set，行为不变。
            if *wide.peek() != v {
                wide.set(v);
            }
        }
    });
});
// 双栏落锚（原版 captureColumnLayout 在独立滚动启用时
// 捕获成员并落库的口径）：独立双栏首次渲染且备忘尚无
// 有效 layout 锚时，按规范估高分界一次性落锚；此后成
// 员由锚决定，不随编辑、卡片加载、会话漂移。只写
// extra.layout，不动 doc/title/updated_at。
let mut col_anchor_done = use_signal(|| false);
{
    let memo_id = memo_id.clone();
    use_effect(move || {
        if *col_anchor_done.read() {
            return;
        }
        if !(*twopane.read() && *wide.read()) {
            return;
        }
        let d = doc.read().clone();
        // 已锚判定读实例 layout（写点全镜像后与总数据同
        // 值），不回查总表。
        let anchored = layout_sig
            .read()
            .clone()
            .and_then(|l| normalize_boundary(&d, &l))
            .is_some();
        col_anchor_done.set(true);
        if anchored || d.len() < 2 {
            return;
        }
        let b = canonical_boundary(&d);
        let ids: Vec<String> = d
            .iter()
            .map(|n| n.id.as_ref().map(|i| i.to_string()).unwrap_or_default())
            .collect();
        let (left, right) = ids.split_at(b.min(ids.len()));
        let new_layout = mynote_core::MemoLayout {
            version: Some(1),
            mode: Some("independent".to_string()),
            left: Some(left.to_vec()),
            right: Some(right.to_vec()),
        };
        let mut backup = data.read().clone();
        if let Some(m) = backup
            .memos
            .iter_mut()
            .find(|m| m.id.to_string() == memo_id)
        {
            m.layout = Some(new_layout.clone());
        }
        data.set(backup.clone());
        layout_sig.set(Some(new_layout));
        diag::log("EDIT", &format!("column anchor captured boundary={b}"));
        spawn(async move {
            save_backup(&backup).await;
        });
    });
}
    Columns { avatar_url, dom_set, bg, twopane, wide }
}
