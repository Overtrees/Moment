//! 备份文件格式：ZIP 内的 memos.json（version 2）与 manifest.json
//! （version 1）。去兼容第五步（D1，用户拍板）起备份格式定为
//! Rust 原生形：模型即格式——导出由模型直出序列化，导入先经
//! core::migrate 迁移通道把旧形态归一再入模型（入口见
//! backup_zip::read_backup_zip_migrated）。avatars 的结构不
//! 建模、原样透传——它是首页/编辑页头像功能的数据通道，不属
//! 兼容层（用户硬约束，不得误伤）。

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::model::Memo;

/// memos.json 根对象。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BackupFile {
    pub version: u32,
    #[serde(rename = "exportedAt", default, skip_serializing_if = "Option::is_none")]
    pub exported_at: Option<Value>,
    #[serde(default)]
    pub memos: Vec<Memo>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatars: Option<Value>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

/// manifest.json 根对象（原生形）：version + attachments 字典
/// （附件 id → 条目）。旧形态（attachments 数组形、根级多余键）
/// 只在迁移通道归一，主线模型不承载、manifest 原文透传已退役
/// （refactor_remove_compat §2.10/§2.12、第五步）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Manifest {
    pub version: u32,
    #[serde(default)]
    pub attachments: BTreeMap<String, AttachmentMeta>,
}

impl Default for Manifest {
    /// 空清单的原生形：`{"version":1,"attachments":{}}`。
    fn default() -> Self {
        Manifest {
            version: 1,
            attachments: BTreeMap::new(),
        }
    }
}

/// manifest 的单个附件条目：只有 name / type 两字段。形态依据
/// （三方同形，proven）：真实备份普查——原版与 Flutter 两份
/// 验收包各 17 条目全为 {name, type}；原版写入点
/// （src/services/drive.js）同形；Rust 编辑器两处写入点
/// （editor.rs 附件/媒体入仓）同形。条目多余键、name/type
/// 缺失或非字符串等旧形态只在迁移通道归一。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AttachmentMeta {
    #[serde(default)]
    pub name: String,
    #[serde(default, rename = "type")]
    pub mime: String,
}
