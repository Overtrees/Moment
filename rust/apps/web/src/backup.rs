//! 备份 provider 边界：备份包（格式冻结的 ZIP，见
//! mynote_core 的 write_backup_zip / read_backup_zip）的送出
//! 与取回通道。备份页（settings::BackupView）只经此边界与
//! 通道打交道：导出把包字节交给 provider.store，导入从
//! provider.fetch 取回包字节；包的生成/校验/落库、确认底
//! 表、toast 与历史仍归备份页，provider 只搬运字节。
//!
//! 现有 provider：
//! - FileProvider（ProviderId::File）：本地文件通道。送出 =
//!   系统分享面板（可存「文件」App / iCloud Drive 等），
//!   不支持或失败回落浏览器下载；取回 = 备份页隐藏文件
//!   input 已选定的文件（选择动作由导入行 label 原生触发，
//!   fetch 只读已选文件，与旧 pick_file_bytes 同行为）。
//!
//! 预留 provider（只留接口位与类型，无实现、无 UI 入口）：
//! - CloudKitProvider（ProviderId::CloudKit）：接入条件 =
//!   用户本人 Apple Developer Program 会员与 CloudKit JS
//!   容器就绪；届时为其实现 BackupProvider 并在 current()
//!   处按配置切换，备份页与备份包格式不动。

use wasm_bindgen::JsCast;
use wasm_bindgen_futures::JsFuture;

use crate::diag;

/// 备份通道标识（Diag 口径用）。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum ProviderId {
    File,
    CloudKit,
}

impl ProviderId {
    pub(crate) fn as_str(&self) -> &'static str {
        match self {
            ProviderId::File => "file",
            ProviderId::CloudKit => "cloudkit",
        }
    }
}

/// provider.store 的结果：经分享面板送达 / 用户在分享面板
/// 取消（什么都不做）/ 已回落下载送达。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum StoreOutcome {
    Shared,
    Cancelled,
    Downloaded,
}

/// 备份 provider 边界。store/fetch 只搬运备份包字节，不碰
/// 包格式与数据落库。
pub(crate) trait BackupProvider {
    fn id(&self) -> ProviderId;
    /// 送出一个备份包（导出方向）。
    async fn store(&self, filename: &str, bytes: &[u8]) -> StoreOutcome;
    /// 取回一个备份包（恢复方向）：(文件名, 字节)；用户
    /// 取消或来源无数据返回 None。
    async fn fetch(&self) -> Option<(String, Vec<u8>)>;
}

/// 当前启用的 provider（文件通道）。CloudKit 接入后在此按
/// 配置切换，调用方不变。
pub(crate) fn current() -> FileProvider {
    FileProvider
}

/// 本地文件通道（见模块头）。
pub(crate) struct FileProvider;

impl BackupProvider for FileProvider {
    fn id(&self) -> ProviderId {
        ProviderId::File
    }

    async fn store(&self, filename: &str, bytes: &[u8]) -> StoreOutcome {
        let outcome = match try_share_zip(bytes, filename).await {
            ShareOutcome::Shared => StoreOutcome::Shared,
            ShareOutcome::Cancelled => StoreOutcome::Cancelled,
            ShareOutcome::Fallback => {
                download_zip(bytes, filename);
                StoreOutcome::Downloaded
            }
        };
        diag::log(
            "EXPORT",
            &format!(
                "provider={} store {filename} -> {outcome:?}",
                self.id().as_str()
            ),
        );
        outcome
    }

    async fn fetch(&self) -> Option<(String, Vec<u8>)> {
        let got = pick_file_bytes().await;
        if let Some((name, bytes)) = &got {
            diag::log(
                "IMPORT",
                &format!(
                    "provider={} fetch {name} {}B",
                    self.id().as_str(),
                    bytes.len()
                ),
            );
        }
        got
    }
}

/// CloudKit provider 的接口位：类型先行，实现待接入（接入
/// 条件与切换点见模块头与 current()）。刻意不实现
/// BackupProvider、无 UI 入口，避免出现假通道。
#[allow(dead_code)]
pub(crate) struct CloudKitProvider;

enum ShareOutcome {
    Shared,
    Cancelled,
    Fallback,
}

/// 系统分享：字节 → Blob URL → JS fetch 转 File → canShare
/// 判定 → navigator.share。返回 shared/cancelled/fallback。
async fn try_share_zip(bytes: &[u8], filename: &str) -> ShareOutcome {
    let Some(window) = web_sys::window() else {
        return ShareOutcome::Fallback;
    };
    let Some(_doc) = window.document() else {
        return ShareOutcome::Fallback;
    };
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::BlobPropertyBag::new();
    opts.set_type("application/zip");
    let Ok(blob) = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &opts) else {
        return ShareOutcome::Fallback;
    };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(&blob) else {
        return ShareOutcome::Fallback;
    };
    let fname_js = serde_json::to_string(filename).unwrap_or_else(|_| "\"backup.zip\"".to_string());
    let js = format!(
        "(async () => {{ try {{ if (!navigator.share || !navigator.canShare) {{ dioxus.send('fallback'); return; }} const r = await fetch('{url}'); const b = await r.blob(); const f = new File([b], {fname_js}, {{ type: 'application/zip' }}); if (!navigator.canShare({{ files: [f] }})) {{ dioxus.send('fallback'); return; }} await navigator.share({{ files: [f] }}); dioxus.send('shared'); }} catch (e) {{ dioxus.send(e && e.name === 'AbortError' ? 'cancelled' : 'fallback'); }} }})();"
    );
    let mut eval = dioxus::document::eval(&js);
    let outcome = match eval.recv::<String>().await {
        Ok(v) if v == "shared" => ShareOutcome::Shared,
        Ok(v) if v == "cancelled" => ShareOutcome::Cancelled,
        _ => ShareOutcome::Fallback,
    };
    let _ = web_sys::Url::revoke_object_url(&url);
    outcome
}

fn download_zip(bytes: &[u8], filename: &str) {
    let Some(window) = web_sys::window() else { return };
    let Some(doc) = window.document() else { return };
    let arr = js_sys::Uint8Array::from(bytes);
    let parts = js_sys::Array::new();
    parts.push(&arr);
    let opts = web_sys::BlobPropertyBag::new();
    opts.set_type("application/zip");
    let Ok(blob) = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &opts) else {
        return;
    };
    let Ok(url) = web_sys::Url::create_object_url_with_blob(&blob) else {
        return;
    };
    if let Ok(el) = doc.create_element("a") {
        let a: web_sys::HtmlAnchorElement = el.unchecked_into();
        a.set_href(&url);
        a.set_download(filename);
        a.click();
    }
    let _ = web_sys::Url::revoke_object_url(&url);
}

/// 读导入文件：返回 (文件名, 字节)。文件名供历史条目 detail
/// （原版 restore 条目 detail = file.name）。
async fn pick_file_bytes() -> Option<(String, Vec<u8>)> {
    let window = web_sys::window()?;
    let doc = window.document()?;
    let input: web_sys::HtmlInputElement = doc.get_element_by_id("file-import")?.dyn_into().ok()?;
    let file = input.files()?.get(0)?;
    let name = file.name();
    let buf = JsFuture::from(file.array_buffer()).await.ok()?;
    let arr = js_sys::Uint8Array::new(&buf);
    let bytes = arr.to_vec();
    input.set_value("");
    Some((name, bytes))
}
