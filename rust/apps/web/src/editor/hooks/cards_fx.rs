//! 卡片接线组 hooks（批 14 三轮自 editor.rs 拆出）：
//! 打开时卡片补拉、卡片重试、Wiki 导航落盘回调。段内
//! 代码逐字搬移，只做文件组织，行为不变。

use super::super::*;

pub(in crate::editor) fn use_card_hydrate(
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
) {
// 打开时补拉（原版 hydrate）：musicCard/link-card 有 url 且
// 无标题 meta 或仍在 loading → 逐张解析（挂载快照，只跑一次）
{
    let persist = persist.clone();
    use_effect(move || {
        let snapshot = doc.peek().clone();
        for n in &snapshot {
            let ty = n.node_type.as_deref().unwrap_or("");
            if ty != "musicCard" && ty != "link-card" {
                continue;
            }
            let url = n.url.as_deref().unwrap_or("");
            if url.is_empty() {
                continue;
            }
            let status = n.status.as_deref().unwrap_or("");
            let has_title = n
                .meta
                .as_ref()
                .and_then(|m| m.get("title"))
                .and_then(|v| v.as_str())
                .map(|s| !s.is_empty())
                .unwrap_or(false);
            if has_title && status != "loading" {
                continue;
            }
            if let Some(bid) = n.id.clone() {
                spawn_resolve_card(doc, bid, url.to_string(), title, data, persist.clone(), None, None);
            }
        }
    });
}
}

pub(in crate::editor) fn use_card_retry(
    mut doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    mut card_retry: Signal<Option<String>>,
    persist: PersistHandle,
) {
// 卡片重试（原版 retryMusicCard）：先置 loading 再解析
{
    let persist = persist.clone();
    use_effect(move || {
        let retry_req = card_retry.read().clone();
        if let Some(bid) = retry_req {
            card_retry.set(None);
            let mut d = doc.read().clone();
            if let Some(loc) = find_loc(&d, &bid) {
                let url = {
                    let n = node_at_mut(&mut d, loc);
                    n.meta = Some(serde_json::Value::Null);
                    n.status = Some("loading".to_string());
                    n.url.as_deref().unwrap_or("").to_string()
                };
                if !url.is_empty() {
                    doc.set(d.clone());
                    persist.call(d, title.read().clone(), data);
                    diag::log("CARD", &format!("retry {bid}"));
                    spawn_resolve_card(doc, bid, url, title, data, persist.clone(), None, None);
                }
            }
        }
    });
}
}

pub(in crate::editor) fn use_wiki_nav(
    mut wiki_nav: Signal<Option<String>>,
    doc: Signal<Vec<Node>>,
    title: Signal<String>,
    data: Signal<BackupFile>,
    persist: PersistHandle,
    on_open_wiki: EventHandler<String>,
    memo_id: String,
) {
// Wiki 导航：收到 target 后先落盘当前 doc/title（原版
// flushAutoSave 后导航；落盘失败也照样导航，仅记日志），
// 再回调宿主解析目标（命中打开 / 未命中新建同名备忘）。
{
    let persist = persist.clone();
    let on_open_wiki = on_open_wiki.clone();
    let from_id = memo_id.clone();
    use_effect(move || {
        let req = wiki_nav.read().clone();
        if let Some(target) = req {
            wiki_nav.set(None);
            persist.call(doc.read().clone(), title.read().clone(), data);
            diag::log("WIKI", &format!("nav '{target}' from {from_id}"));
            on_open_wiki.call(target);
        }
    });
}
}
