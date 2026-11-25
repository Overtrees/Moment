//! Mynote Rust Core：文档模型与备份格式。
//! 阶段 1 目标只有一个——独立读写现有笔记数据且往返无损，
//! 格式逐字节沿用现网块 JSON + ZIP 备份，不新造格式。

pub mod backup;
pub mod backup_zip;
pub mod inline_editor;
pub mod inline_html;
pub mod mathml;
pub mod migrate;
pub mod model;

pub use backup::{AttachmentMeta, BackupFile, Manifest};
pub use backup_zip::{
    read_backup_zip, read_backup_zip_migrated, write_backup_zip, BackupPackage, BackupZipError,
};
pub use migrate::{
    dry_run_value, manifest_parse_lenient, normalize_manifest_value, normalize_value,
    MigrationStats,
};
pub use inline_editor::{editor_html_to_inlines, inlines_to_editor_html};
pub use inline_html::{html_to_inlines, inlines_to_html, safe_http_url, safe_image_url, split_highlight};
pub use mathml::{
    has_math_syntax, looks_like_math_expression, render_mathml, split_math, MathError, MathSegment,
};
pub use model::{Id, Memo, Node, Timestamp};
