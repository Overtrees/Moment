// Moment MCP 桥中继（moment-bridge，M1 通道 + M2 工具面）
// 方案：docs/reports/plan_app_mcp_bridge.md。
// 形态：Cloudflare Worker（模块格式）+ Durable
// Object 会话室（一配对一室）。助手面 = MCP
// Streamable HTTP（POST /mcp）；设备面 = App 出站
// WSS（GET /app/connect），承载原始 MCP JSON-RPC
// 帧（自定义设备传输，非标准 MCP 传输）。
// 中继零业务存储：只存配对元数据（公钥、凭据哈
// 希、能力位、状态）与调用元计数；不落笔记正文、
// Diag 正文、工具参数与结果。
// 与 moment-ops 完全独立（不同 Worker/凭据域）。

const PROTOCOL_PREFERRED = "2025-06-18";
const PROTOCOL_SUPPORTED = ["2025-06-18", "2025-03-26", "2025-11-25"];
const RELAY_VERSION = "1.1.0";
const PAIRING_TTL_MS = 10 * 60 * 1000;
const READ_TIMEOUT_MS = 15000;
const CONTROL_TIMEOUT_MS = 20000;
const WRITE_TIMEOUT_MS = 30000;
const RATE_WINDOW_MS = 60 * 1000;
const RATE_MAX_CALLS = 120;
// 连接稳定性（fix_bridge_stability）：authed socket
// 超过 STALE_SOCKET_MS 无任何入站帧即视为僵尸——
// App 前台心跳 20s 一帧，120s = 6 帧余量；后台挂
// 起的 App 本就无法应答，按离线处理与语义一致。
// WAIT_DEVICE_MS 是 tools/call 无可用 socket 时等
// 设备重连落地的短窗（轮询间隔 WAIT_POLL_MS），
// 使「正在重连的设备」不立刻吃 app_offline。
const STALE_SOCKET_MS = 120000;
const WAIT_DEVICE_MS = 4000;
const WAIT_POLL_MS = 200;
// 会话恢复令牌（fix_bridge_reconnect_flow R1）：
// 全量挑战握手之外开一条恢复路——welcome 下发
// 32B 令牌（明文仅此一帧），中继只存其 sha256；
// App 后续连接首帧呈递令牌，命中即免挑战直达
// welcome 并轮换新令牌（旧令牌立即失效）。滑动
// 有效期 30 天（每次成功恢复续期）；吊销/配对
// 重置同步清哈希。未命中/过期一律回
// resume_rejected，App 无感回退现行挑战路径。
const RESUME_TTL_MS = 30 * 24 * 60 * 60 * 1000;

// 工具清单（M1 只读集 + M2 落地集：设置写、删除
// 系、块级结构写、ops_validate、rescue 动作；
// U1 批入册：编辑器在席四件 + UI 自检驱动四件
// [uitest_*，归 ops 层另账]；布防批入册：
// rescue_arm_safe_mode [ops 层 + 两段提交]；
// M3a 入册：场景库三件 [scenarios_*] + 量测一
// 件 [metrics_create_settle]，合计 35 件）。
// 场景门归属：scenarios_list / scenarios_get_
// result / metrics_create_settle 为 read 级；
// scenarios_run 不入下方任何 scope 集合——逐
// 景 scope 由 App 场景注册表声明、分发器受理
// 时验足点名（声明制，中继只转发）。
// 正文级工具（notes_create、editor_insert_
// block、editor_update_block、editor_set_block_
// type）待端到端加密专项评审裁定，不入册。
// 与 App 侧 MomentBridgeProtocol.swift 的 manifest
// 逐字对齐；manifestHash = sha256(
//   protocol + "|" + 工具名排序后逗号连接)。
const TOOLS = [
  {
    name: "bridge_status",
    description: "桥自身状态：开关、配对态、传输态、能力位、协议版本与清单哈希、会话 id。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "app_state",
    description: "App 状态：版本、启动模式、库状态、笔记计数、全库哈希、语言与 OPS 摘要。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "diag_tail",
    description: "回读 App 内诊断日志（尾部）。scope=today|archive，archive 时须带 archiveStamp。",
    inputSchema: {
      type: "object",
      properties: {
        scope: { type: "string", enum: ["today", "archive"] },
        archiveStamp: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 200 },
        minLevel: { type: "string", enum: ["all", "warn", "error"] },
        beforeTs: { type: "number" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "diag_search",
    description: "在 App 内诊断日志中按字面子串（或正则）搜索，搜索在 App 内执行。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        scope: { type: "string", enum: ["today", "archive"] },
        archiveStamp: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 200 },
        regex: { type: "boolean" },
      },
      required: ["query"],
      additionalProperties: false,
    },
  },
  {
    name: "notes_list",
    description: "笔记摘要列表（id/标题/置顶/时间/块数/docHash），游标分页。",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "integer", minimum: 1, maximum: 100 },
        cursor: { type: "string" },
        includeDeleted: { type: "boolean" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "notes_search",
    description: "按 App 内搜索口径（FTS + 补充扫描）搜笔记，回摘要数组。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        limit: { type: "integer", minimum: 1, maximum: 100 },
      },
      required: ["query"],
      additionalProperties: false,
    },
  },
  {
    name: "notes_get",
    description: "读一篇笔记全量元信息与块（按块游标分页）；原子块只回类型与 attrs 元信息。",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
        blockCursor: { type: "integer", minimum: 0 },
        maxBlocks: { type: "integer", minimum: 1, maximum: 100 },
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "ops_get_effective",
    description: "OPS 三层回读：本次启动实际消费(bootApplied)/当前缓存/最近拉取，并列与收敛判定。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "ops_get_sources",
    description: "OPS 双源源头回读（中继执行，origin=relay）：只证明源头内容，不证明 App 已生效。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "ops_refresh",
    description: "触发 App 双源拉取 OPS 指令并落缓存；生效点为下次启动（effectiveFrom=next_launch）。需 ops 能力位。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "rescue_status",
    description: "安全模式与哨兵状态回读：启动模式、哨兵文件、救援留痕、DB 元数据、Diag 计数、桥分发器形态。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "ops_validate",
    description: "OPS 指令发布前预检（纯校验、不落盘不下发）：回被接受字段、被忽略的未知字段、非法步名、规范形与哈希。",
    inputSchema: {
      type: "object",
      properties: {
        directive: { type: "object" },
      },
      required: ["directive"],
      additionalProperties: false,
    },
  },
  {
    name: "rescue_try_normal_start",
    description: "安全模式内尝试正常启动（运维高危，需 ops 能力位 + 两段提交：先以 dryRun=true 取 actionToken，60 秒内回带执行）。仅当前处于安全模式时可调；forceSafeMode 仍在位时会在返回中明示。",
    inputSchema: {
      type: "object",
      properties: {
        dryRun: { type: "boolean" },
        actionToken: { type: "string" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "rescue_arm_safe_mode",
    description: "布防下次启动进入安全模式（运维高危，需 ops 能力位 + 两段提交：先以 dryRun=true 取 actionToken，60 秒内回带执行）。单机版 forceSafeMode：App 在 diag 域写一次性标记，下次启动判定消费恰一次后转审计留痕；App 不能被远程重启，只布防、等用户下次打开才生效。安全模式内不可调（回 safe_mode_limited），远程解除布防不存在（禁区）。",
    inputSchema: {
      type: "object",
      properties: {
        reason: { type: "string" },
        idempotencyKey: { type: "string" },
        dryRun: { type: "boolean" },
        actionToken: { type: "string" },
      },
      required: ["reason", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "settings_get",
    description: "设置状态回读：语言偏好与生效码、白名单开关现值、天气 key 状态与来源（只报状态，绝不回值）。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "settings_set_language",
    description: "切换界面语言（需 write 能力位）。code 为五语码或 system（跟随系统）。",
    inputSchema: {
      type: "object",
      properties: {
        code: { type: "string" },
        idempotencyKey: { type: "string" },
      },
      required: ["code", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "settings_set_toggle",
    description: "改白名单开关（需 write 能力位）。注册表首批仅 diagAutodel（Diag 30 天自动删除）；桥自身开关等永不入表。",
    inputSchema: {
      type: "object",
      properties: {
        key: { type: "string" },
        value: { type: "boolean" },
        idempotencyKey: { type: "string" },
      },
      required: ["key", "value", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "settings_clear_weather_key",
    description: "清除用户自填的天气 key 覆盖（需 write 能力位）；只清自填，构建注入仍在时来源回 bundle。不提供经桥写入天气 key 的工具。",
    inputSchema: {
      type: "object",
      properties: {
        provider: { type: "string", enum: ["qweather", "caiyun"] },
        idempotencyKey: { type: "string" },
      },
      required: ["provider", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "notes_soft_delete",
    description: "软删一篇笔记（需 write 能力位）：打标落盘 + 8 秒撤销窗口，与 App 内删除同一机制。写前自动快照。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        expectedDocHash: { type: "string" },
        idempotencyKey: { type: "string" },
      },
      required: ["memoId", "expectedDocHash", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "notes_restore_deleted",
    description: "恢复待删集中的笔记（需 write 能力位）。仅支持最近一篇待删（App 现行撤销口径），非最近一篇回 restore_unsupported。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        idempotencyKey: { type: "string" },
      },
      required: ["memoId", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "notes_delete_permanent",
    description: "永久删除（运维高危，需 ops 能力位 + 两段提交 + confirmMemoId 逐字回带）。仅限已软删（待删集内）的笔记；执行前强制单独快照。先以 dryRun=true 取 actionToken。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        expectedDocHash: { type: "string" },
        confirmMemoId: { type: "string" },
        idempotencyKey: { type: "string" },
        dryRun: { type: "boolean" },
        actionToken: { type: "string" },
      },
      required: ["memoId", "expectedDocHash", "confirmMemoId", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "editor_delete_block",
    description: "删除一篇笔记中的一个块（需 write 能力位，语义级结构写）：经 App 文档路径落盘并回读校验。只删结构、不带正文参数。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        blockId: { type: "string" },
        expectedDocHash: { type: "string" },
        idempotencyKey: { type: "string" },
      },
      required: ["memoId", "blockId", "expectedDocHash", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "editor_move_block",
    description: "语义重排一个块（需 write 能力位）：beforeBlockId/afterBlockId/toIndex 三选一定位。只改文档序，不产生任何触摸/识别器事件。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        blockId: { type: "string" },
        beforeBlockId: { type: "string" },
        afterBlockId: { type: "string" },
        toIndex: { type: "integer", minimum: 0 },
        expectedDocHash: { type: "string" },
        idempotencyKey: { type: "string" },
      },
      required: ["memoId", "blockId", "expectedDocHash", "idempotencyKey"],
      additionalProperties: false,
    },
  },
  {
    name: "editor_open",
    description: "经导航通道打开一篇笔记到编辑器并回在席状态（需 write 能力位）。通道错误走 nav 错误域：nav_unavailable（未接线/不在位，可重试）、nav_timeout（等落定超时，可重试）、memo_busy（他篇在席）、memo_not_found、read_only_mode。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
      },
      required: ["memoId"],
      additionalProperties: false,
    },
  },
  {
    name: "editor_get_state",
    description: "编辑器在席状态回读（只读）：在席篇 id/标题/dirty/聚焦块/块序（id+type，不含正文）。无在席回 seated=false；带 memoId 与在席不符回 memo_busy。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "editor_focus_block",
    description: "把编辑器焦点落到指定块（需 write 能力位）：caret=end（缺省）/start 两态。无在席回 nav_unavailable，他篇在席回 memo_busy。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        blockId: { type: "string" },
        caret: { type: "string", enum: ["end", "start"] },
      },
      required: ["memoId", "blockId"],
      additionalProperties: false,
    },
  },
  {
    name: "editor_save_now",
    description: "强制当前编辑器立即落盘并回读对账（需 write 能力位）：回 docHash/libraryHash/dirty。无在席回 nav_unavailable，他篇在席回 memo_busy。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
      },
      required: ["memoId"],
      additionalProperties: false,
    },
  },
  {
    name: "uitest_list_surfaces",
    description: "UI 自检驱动（需 ops 能力位）：列出当前已注册的 UI 面（id/kind/实例/在位/帧/状态键），并报告驱动夹具残留数。只读。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "uitest_run",
    description: "UI 自检驱动（需 ops 能力位 + 两段提交：先以 dryRun=true 取 actionToken，60 秒内回带执行）：异步启动一个自检场景作业，回 runId 后用 uitest_get_result 轮询。场景 s1_title_reedit：标题胶囊二次编辑回路。",
    inputSchema: {
      type: "object",
      properties: {
        scenario: { type: "string" },
        dryRun: { type: "boolean" },
        actionToken: { type: "string" },
      },
      required: ["scenario"],
      additionalProperties: false,
    },
  },
  {
    name: "uitest_get_result",
    description: "UI 自检驱动（需 ops 能力位）：按 runId 读作业状态与结论（终态码、逐步断言、卫生链对账、复原状态）。",
    inputSchema: {
      type: "object",
      properties: {
        runId: { type: "string" },
      },
      required: ["runId"],
      additionalProperties: false,
    },
  },
  {
    name: "uitest_measure",
    description: "UI 自检驱动（需 ops 能力位）：几何探针入口。U1 仅注册壳——已知探针 id 回 invalid_params（探针随 U2 批落地），未知 id 回 invalid_params。",
    inputSchema: {
      type: "object",
      properties: {
        probe: { type: "string" },
      },
      required: ["probe"],
      additionalProperties: false,
    },
  },
  {
    name: "scenarios_list",
    description: "场景库（M3a，read 级）：列 App 内置场景注册表（声明 scope/高危/事前指令标记/参数表/证据等级）与逐景可用性——缺层以 scope_missing 在清单里现形，不等跑起来才拒。",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "scenarios_run",
    description: "场景库（M3a）：受理一个内置场景并立即回 runId（异步作业，结论经 scenarios_get_result 轮询）。逐景 scope 由 App 注册表声明制裁定（中继不设集合门）：缺层回 scope_denied 并点名；含高危段的场景整场两段提交（dryRun 先行取令牌）。params 只许场景声明的标量键，表外键回 invalid_params；与 UI 自检驱动共用单 run 互斥，占用中回 run_conflict。跨重启景（ops_convergence）挂起后于下次启动自动续跑收尾。",
    inputSchema: {
      type: "object",
      properties: {
        scenario: { type: "string" },
        params: { type: "object" },
        dryRun: { type: "boolean" },
        actionToken: { type: "string" },
      },
      required: ["scenario"],
      additionalProperties: false,
    },
  },
  {
    name: "scenarios_get_result",
    description: "场景库（M3a，read 级）：按 runId 读 journal 证据包（状态/终态码/逐步断言/量测/结论；只含 id/哈希/计数/Diag 行，不含正文）。进程重启后仍可回读最近 10 个 run。",
    inputSchema: {
      type: "object",
      properties: {
        runId: { type: "string" },
      },
      required: ["runId"],
      additionalProperties: false,
    },
  },
  {
    name: "metrics_create_settle",
    description: "量测（M3a，read 级）：解析 Diag 中 CREATE settle 行（新建→编辑页首帧分段 create/model/dest/appear/listpass/avatar/bodypass/claim/kb），回逐段数值与原始行；只出数不出结论，基线判读在助手侧。",
    inputSchema: {
      type: "object",
      properties: {
        memoId: { type: "string" },
        limit: { type: "number" },
        sinceTs: { type: "number" },
      },
      additionalProperties: false,
    },
  },
];
const TOOL_NAMES = new Set(TOOLS.map((t) => t.name));
const OPS_SCOPE_TOOLS = new Set(["ops_refresh", "notes_delete_permanent", "rescue_try_normal_start", "rescue_arm_safe_mode"]);
const WRITE_SCOPE_TOOLS = new Set([
  "settings_set_language", "settings_set_toggle", "settings_clear_weather_key",
  "notes_soft_delete", "notes_restore_deleted",
  "editor_delete_block", "editor_move_block",
  "editor_open", "editor_focus_block", "editor_save_now",
]);
const UITEST_SCOPE_TOOLS = new Set([
  "uitest_list_surfaces", "uitest_run", "uitest_get_result", "uitest_measure",
]);
const RELAY_TOOLS = new Set(["ops_get_sources"]);

const OPS_SOURCES = [
  ["worker", "https://moment-ops.overtrees.workers.dev/ops.json"],
  ["github", "https://overtrees.github.io/moment-ops/ops.json"],
];

// ---------- 通用小工具 ----------

function b64encode(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}
function b64decode(str) {
  const s = atob(str.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}
function b64urlEncode(bytes) {
  return b64encode(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function sha256hex(data) {
  const buf = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const digest = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
// 等长十六进制串常时比对（令牌哈希校验用，避免
// 逐字短路的时序侧信道；长度不等直接判否）。
function hashEqualHex(a, b) {
  if (typeof a !== "string" || typeof b !== "string"
      || a.length !== b.length || a.length === 0) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
// 签发/轮换恢复令牌：32B 随机，明文只经 welcome
// 一帧下发；record 只落 sha256 哈希与到期时刻。
async function issueResumeToken(rec) {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const token = b64urlEncode(bytes);
  rec.resumeTokenHash = await sha256hex(token);
  rec.resumeExpMs = Date.now() + RESUME_TTL_MS;
  return token;
}
async function manifestHash() {
  const names = TOOLS.map((t) => t.name).sort().join(",");
  return sha256hex(PROTOCOL_PREFERRED + "|" + names);
}
function fingerprintOf(pubKeyBytes) {
  return sha256hex(pubKeyBytes).then((hex) =>
    hex.slice(0, 16).toUpperCase().replace(/(.{4})(?=.)/g, "$1 "));
}
function jsonResponse(obj, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...extraHeaders },
  });
}
function toolErrorResult(code, message, retryable = false) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify({ code, message, retryable }),
      },
    ],
    isError: true,
  };
}
function toolOkResult(payload) {
  return { content: [{ type: "text", text: JSON.stringify(payload) }], isError: false };
}
function rpcError(id, code, message, dataCode) {
  const err = { code, message };
  if (dataCode) err.data = { code: dataCode };
  return { jsonrpc: "2.0", id: id ?? null, error: err };
}
// DER（X9.62）ECDSA 签名 → raw r||s（WebCrypto 口径）。
function derToRaw(sig) {
  if (sig.length === 64) return sig;
  if (sig[0] !== 0x30) throw new Error("bad signature encoding");
  let off = 2;
  if (sig[1] & 0x80) off += sig[1] & 0x7f;
  const readInt = () => {
    if (sig[off] !== 0x02) throw new Error("bad der int");
    const len = sig[off + 1];
    let v = sig.slice(off + 2, off + 2 + len);
    off += 2 + len;
    while (v.length > 32 && v[0] === 0) v = v.slice(1);
    const out = new Uint8Array(32);
    out.set(v, 32 - v.length);
    return out;
  };
  const r = readInt();
  const s = readInt();
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}
function sanitizeOps(obj) {
  if (!obj || typeof obj !== "object") return null;
  const set = { version: 1, disableSteps: [], forceSafeMode: false };
  if (Number.isInteger(obj.version)) set.version = obj.version;
  if (Array.isArray(obj.disableSteps)) {
    set.disableSteps = obj.disableSteps.filter((x) => typeof x === "string");
  }
  if (typeof obj.forceSafeMode === "boolean") set.forceSafeMode = obj.forceSafeMode;
  return set;
}
function opsCanonical(set) {
  return JSON.stringify({
    version: set.version,
    disableSteps: set.disableSteps,
    forceSafeMode: set.forceSafeMode,
  });
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

// ---------- Durable Object：一配对一室 ----------

export class BridgeRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.pending = new Map(); // relayId -> {resolve, timer}
    this.seq = 0;
    this.rate = { windowStart: 0, count: 0 };
  }

  async record() {
    return (await this.state.storage.get("pairing")) || null;
  }
  async saveRecord(rec) {
    await this.state.storage.put("pairing", rec);
  }

  // 选连接口径（fix_bridge_stability）：只认
  // authed 且未僵尸（lastSeenAt 在 STALE 窗内）的
  // socket，多条并存时取 epoch 最大（最近认证）、
  // 同 epoch 取 lastSeenAt 最新——旧实现取「第一
  // 个 authed」会把请求持续喂给先到的僵尸连接。
  deviceSocket() {
    const now = Date.now();
    let best = null;
    let bestAtt = null;
    for (const ws of this.state.getWebSockets("device")) {
      const att = ws.deserializeAttachment() || {};
      if (!att.authed) continue;
      if (now - (att.lastSeenAt || 0) > STALE_SOCKET_MS) continue;
      if (!best
          || (att.epoch || 0) > (bestAtt.epoch || 0)
          || ((att.epoch || 0) === (bestAtt.epoch || 0)
              && (att.lastSeenAt || 0) > (bestAtt.lastSeenAt || 0))) {
        best = ws;
        bestAtt = att;
      }
    }
    return best;
  }

  // 僵尸回收闹钟：把下一次检查定在最近一条连接的
  // 僵尸时刻 +1s；alarm 到点逐条关僵尸并续定。
  async ensureAlarm(fromMs) {
    const deadline = (fromMs || Date.now()) + STALE_SOCKET_MS + 1000;
    if (deadline > (this.alarmFor || 0)) {
      this.alarmFor = deadline;
      await this.state.storage.setAlarm(deadline);
    }
  }

  async alarm() {
    const now = Date.now();
    let next = Infinity;
    for (const ws of this.state.getWebSockets("device")) {
      const att = ws.deserializeAttachment() || {};
      const born = att.authed ? (att.lastSeenAt || 0)
                               : (att.connectedAt || now);
      const staleAt = born + STALE_SOCKET_MS;
      if (now > staleAt) {
        this.failPendingFor(ws);
        try { ws.close(4000, att.authed ? "stale_socket" : "auth_timeout"); }
        catch { /* noop */ }
      } else {
        next = Math.min(next, staleAt);
      }
    }
    this.alarmFor = 0;
    if (next !== Infinity) {
      this.alarmFor = next + 1000;
      await this.state.storage.setAlarm(this.alarmFor);
    }
  }

  // 只失败挂在指定 socket 上的在飞请求（按连接打
  // 标，fix_bridge_stability）：旧实现任一 authed
  // socket 关闭即冲掉全室 pending，新连接在飞的
  // 调用会被旧连接的迟到 close 误杀。
  failPendingFor(ws) {
    for (const [id, entry] of this.pending) {
      if (entry.ws === ws) {
        this.pending.delete(id);
        clearTimeout(entry.timer);
        entry.resolve(null);
      }
    }
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (request.headers.get("Upgrade") === "websocket") {
      return this.handleConnect(request, url);
    }
    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
    switch (path) {
      // 路径口径（2026-11-27 定案）：Worker 转发 URL 为
      // https://room/<path>，pathname 不含 /room 前缀
      // （room 是主机名）——本表与转发侧逐字对齐，
      // 曾因多写 /room 前缀全量落 default 404
      // not_found、配对首跑即败，勿再加前缀。
      case "/pair-start": return this.pairStart(body);
      case "/pair-status": return this.pairStatus(url);
      case "/pair-confirm": return this.pairConfirm(body);
      case "/revoke": return this.revoke(body, request);
      case "/mcp": return this.mcp(body);
      default: return jsonResponse({ error: "not_found" }, 404);
    }
  }

  // ----- 配对 -----

  async pairStart(body) {
    const { pairingId, pubKeyB64, fingerprint, label, scopes } = body || {};
    if (!pairingId || !pubKeyB64 || !fingerprint) {
      return jsonResponse({ error: "bad_request" }, 400);
    }
    const existing = await this.record();
    if (existing && existing.state === "paired") {
      return jsonResponse({ error: "already_paired" }, 409);
    }
    let pubKeyBytes;
    try {
      pubKeyBytes = b64decode(pubKeyB64);
    } catch {
      return jsonResponse({ error: "bad_pubkey" }, 400);
    }
    const fp = await fingerprintOf(pubKeyBytes);
    if (fp !== fingerprint) {
      return jsonResponse({ error: "fingerprint_mismatch" }, 400);
    }
    const now = Date.now();
    await this.saveRecord({
      pairingId,
      pubKeyB64,
      fingerprint,
      label: typeof label === "string" ? label.slice(0, 64) : "",
      requestedScopes: Array.isArray(scopes) ? scopes : ["read"],
      scopes: [],
      clientKeyHash: "",
      state: "pending",
      createdAt: now,
      expiresAt: now + PAIRING_TTL_MS,
      pairedAt: 0,
      lastSeenAt: 0,
      epoch: 0,
      calls: 0,
      resumeTokenHash: "",
      resumeExpMs: 0,
    });
    return jsonResponse({ state: "pending", expiresAt: now + PAIRING_TTL_MS });
  }

  async pairStatus(url) {
    const rec = await this.record();
    if (!rec) return jsonResponse({ state: "unknown" }, 404);
    if (rec.state === "pending" && Date.now() > rec.expiresAt) {
      rec.state = "expired";
      await this.saveRecord(rec);
    }
    const out = { state: rec.state, expiresAt: rec.expiresAt };
    if (rec.state === "paired") {
      out.scopes = rec.scopes;
      out.pairedAt = rec.pairedAt;
    }
    return jsonResponse(out);
  }

  async pairConfirm(body) {
    const { fingerprint, scopes } = body || {};
    const rec = await this.record();
    if (!rec) return jsonResponse({ error: "no_pairing" }, 404);
    if (rec.state === "revoked") return jsonResponse({ error: "revoked" }, 403);
    if (rec.state === "paired") return jsonResponse({ error: "already_paired" }, 409);
    if (rec.state !== "pending") return jsonResponse({ error: "not_pending" }, 409);
    if (Date.now() > rec.expiresAt) {
      rec.state = "expired";
      await this.saveRecord(rec);
      return jsonResponse({ error: "expired" }, 410);
    }
    if (fingerprint !== rec.fingerprint) {
      return jsonResponse({ error: "fingerprint_mismatch" }, 400);
    }
    const granted = ["read"];
    if (Array.isArray(scopes)) {
      if (scopes.includes("write")) granted.push("write");
      if (scopes.includes("ops")) granted.push("ops");
    }
    const secretBytes = new Uint8Array(32);
    crypto.getRandomValues(secretBytes);
    const secret = b64urlEncode(secretBytes);
    rec.clientKeyHash = await sha256hex(secret);
    rec.scopes = granted;
    rec.state = "paired";
    rec.pairedAt = Date.now();
    await this.saveRecord(rec);
    const clientKey = "mb1." + rec.pairingId + "." + secret;
    return jsonResponse({ clientKey, scopes: granted, fingerprint: rec.fingerprint });
  }

  async revoke(body, request) {
    const rec = await this.record();
    if (!rec) return jsonResponse({ error: "no_pairing" }, 404);
    // 授权路径二选一：客户端凭据（Bearer）或设备签名
    // （X-Device-Signature 对 pairingId 的签名字节）。
    let ok = false;
    const auth = request.headers.get("Authorization") || "";
    if (auth.startsWith("Bearer mb1.")) {
      const secret = auth.slice("Bearer mb1.".length).split(".").slice(1).join(".");
      if (secret && (await sha256hex(secret)) === rec.clientKeyHash) ok = true;
    }
    const devSig = request.headers.get("X-Device-Signature");
    if (!ok && devSig) {
      ok = await this.verifyDeviceSignature(
        rec, new TextEncoder().encode("revoke:" + rec.pairingId), devSig);
    }
    if (!ok) return jsonResponse({ error: "unauthorized" }, 401);
    rec.state = "revoked";
    // 吊销同步清恢复令牌：已下发的令牌立即失效，
    // 不留「吊销后仍可恢复会话」的尾巴。
    rec.resumeTokenHash = "";
    rec.resumeExpMs = 0;
    await this.saveRecord(rec);
    const ws = this.deviceSocket();
    if (ws) {
      try {
        ws.send(JSON.stringify({ "moment.control": "revoke-notice" }));
        ws.close(4001, "revoked");
      } catch { /* 已断开 */ }
    }
    return jsonResponse({ state: "revoked" });
  }

  async verifyDeviceSignature(rec, messageBytes, sigB64) {
    try {
      const key = await crypto.subtle.importKey(
        "raw", b64decode(rec.pubKeyB64),
        { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
      const raw = derToRaw(b64decode(sigB64));
      return await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" }, key, raw, messageBytes);
    } catch {
      return false;
    }
  }

  // ----- 设备连接（WSS） -----

  handleConnect(request, url) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const nonceBytes = new Uint8Array(32);
    crypto.getRandomValues(nonceBytes);
    const nonce = b64encode(nonceBytes);
    this.state.acceptWebSocket(server, ["device"]);
    server.serializeAttachment({
      authed: false,
      nonce,
      pairingId: url.searchParams.get("pid") || "",
      connectedAt: Date.now(),
    });
    server.send(JSON.stringify({ "moment.control": "challenge", nonce }));
    return new Response(null, { status: 101, webSocket: client });
  }

  // 认证收口（挑战应答与会话恢复共用）：顶替旧
  // 连接、epoch+1、轮换恢复令牌、置 att 并回
  // welcome。welcome 先发、record 落盘随后——
  // epoch/令牌哈希的持久化移出 welcome 关键路径
  // （fix_bridge_reconnect_flow R1：恢复路径的存
  // 储成本只剩命中校验的那一次读）。
  async completeAuth(ws, att, rec) {
    // 单活连接：新连接顶旧连接；挂在旧连接上
    // 的在飞请求立即失败（不等其自身超时）。
    for (const other of this.state.getWebSockets("device")) {
      if (other !== ws) {
        const oa = other.deserializeAttachment() || {};
        if (oa.authed) {
          this.failPendingFor(other);
          try { other.close(4002, "superseded"); } catch { /* noop */ }
        }
      }
    }
    rec.epoch = (rec.epoch || 0) + 1;
    rec.lastSeenAt = Date.now();
    const resumeToken = await issueResumeToken(rec);
    att.authed = true;
    att.epoch = rec.epoch;
    att.lastSeenAt = Date.now();
    att.nonce = "";
    ws.serializeAttachment(att);
    ws.send(JSON.stringify({
      "moment.control": "welcome",
      appSessionId: "s" + rec.epoch + "-" + Date.now().toString(36),
      scopes: rec.scopes,
      resumeToken,
      resumeExpMs: rec.resumeExpMs,
    }));
    await this.saveRecord(rec);
    await this.ensureAlarm(att.lastSeenAt);
  }

  async webSocketMessage(ws, message) {
    let msg;
    try {
      msg = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message));
    } catch {
      return;
    }
    const att = ws.deserializeAttachment() || {};
    // 逐 socket 新鲜度（fix_bridge_stability）：
    // 任一入站帧刷新本连接 lastSeenAt（≥5s 才回写
    // attachment 防抖），deviceSocket 的僵尸判定与
    // alarm 回收都以此为准，不再靠全室共享的
    // rec.lastSeenAt（多连接并存时会互相掩盖）。
    if (att.authed) {
      const nowMs = Date.now();
      if (nowMs - (att.lastSeenAt || 0) >= 5000) {
        att.lastSeenAt = nowMs;
        ws.serializeAttachment(att);
        await this.ensureAlarm(nowMs);
      }
    }
    const control = msg["moment.control"];
    if (control) {
      if (control === "challenge_response") {
        const rec = await this.record();
        if (!rec || rec.state !== "paired") {
          try { ws.close(4003, "pairing_required"); } catch { /* noop */ }
          return;
        }
        if (att.pairingId && att.pairingId !== rec.pairingId) {
          try { ws.close(4003, "pairing_mismatch"); } catch { /* noop */ }
          return;
        }
        const okSig = await this.verifyDeviceSignature(
          rec, b64decode(att.nonce || ""), msg.signature || "");
        if (!okSig) {
          try { ws.close(4003, "unauthorized"); } catch { /* noop */ }
          return;
        }
        await this.completeAuth(ws, att, rec);
        return;
      }
      if (control === "resume") {
        // 会话恢复（fix_bridge_reconnect_flow
        // R1）：连接后首帧呈递令牌，校验 = 一次
        // record 读 + 哈希常时比对。命中直达
        // welcome（completeAuth 内轮换新令牌、
        // 旧令牌随即失效）；未命中/过期/已吊销
        // 回 resume_rejected，App 持留的
        // challenge 随即走全量路径（无感回退）。
        if (att.authed) return;
        const rec = await this.record();
        const token = typeof msg.token === "string"
          ? msg.token : "";
        let hit = false;
        if (rec && rec.state === "paired"
            && (!att.pairingId
                || att.pairingId === rec.pairingId)
            && rec.resumeTokenHash
            && (rec.resumeExpMs || 0) > Date.now()
            && token) {
          hit = hashEqualHex(
            await sha256hex(token), rec.resumeTokenHash);
        }
        if (!hit) {
          try {
            ws.send(JSON.stringify({
              "moment.control": "resume_rejected",
            }));
          } catch { /* noop */ }
          return;
        }
        await this.completeAuth(ws, att, rec);
        return;
      }
      if (control === "ping") {
        // R2：pong 立即回，不再夹 record 读+写。
        // 新鲜度已由逐 socket attachment 承担
        // （本函数入口的刷新段），rec.lastSeenAt
        // 全仓无读方（选连/alarm 均读 att），其
        // 更新收敛到 completeAuth 一处低频写。
        try { ws.send(JSON.stringify({ "moment.control": "pong" })); } catch { /* noop */ }
        return;
      }
      // presence / incident_hint 等：只作在线信
      // 号，不落存储、不转发（R2 同口径删存储
      // 往返；在线时刻由入口的 att 刷新段承担）。
      return;
    }
    // JSON-RPC 响应（设备 → 中继）：按 id 回配等待者。
    if (att.authed && msg && (msg.result !== undefined || msg.error !== undefined)
        && typeof msg.id === "string") {
      const entry = this.pending.get(msg.id);
      if (entry) {
        this.pending.delete(msg.id);
        clearTimeout(entry.timer);
        entry.resolve(msg);
      }
    }
  }

  async webSocketClose(ws) {
    // 只结清挂在本连接上的在飞请求（见
    // failPendingFor 的按连接打标）。
    this.failPendingFor(ws);
  }

  async webSocketError(ws) {
    // 异常断链（无 close 握手）与 close 同处置：
    // 旧实现无此处理器，错误断链的在飞请求只能
    // 干等各自超时。
    this.failPendingFor(ws);
    try { ws.close(4000, "socket_error"); } catch { /* noop */ }
  }

  // ----- 助手面 MCP -----

  async mcp(body) {
    const { secret, rpcText } = body || {};
    const rec = await this.record();
    if (!rec) {
      return jsonResponse(rpcError(null, -32001, "pairing not found", "pairing_required"), 401);
    }
    if (rec.state === "revoked") {
      return jsonResponse(rpcError(null, -32001, "pairing revoked", "revoked"), 401);
    }
    if (rec.state !== "paired" || !secret
        || (await sha256hex(secret)) !== rec.clientKeyHash) {
      return jsonResponse(rpcError(null, -32001, "unauthorized", "unauthorized"), 401);
    }
    let rpc;
    try {
      rpc = JSON.parse(rpcText);
    } catch {
      return jsonResponse(rpcError(null, -32700, "parse error"), 400);
    }
    const isNotification = rpc.id === undefined;
    const sessionHeaders = { "Mcp-Session-Id": "mb-" + rec.pairingId.slice(0, 8) };
    const method = rpc.method || "";
    if (method === "initialize") {
      const asked = rpc.params && rpc.params.protocolVersion;
      const version = PROTOCOL_SUPPORTED.includes(asked) ? asked : PROTOCOL_PREFERRED;
      return jsonResponse({
        jsonrpc: "2.0",
        id: rpc.id,
        result: {
          protocolVersion: version,
          capabilities: { tools: {} },
          serverInfo: { name: "moment-bridge", version: RELAY_VERSION },
        },
      }, 200, sessionHeaders);
    }
    if (isNotification) {
      return new Response(null, { status: 202 });
    }
    if (method === "ping") {
      return jsonResponse({ jsonrpc: "2.0", id: rpc.id, result: {} }, 200, sessionHeaders);
    }
    if (method === "tools/list") {
      return jsonResponse({
        jsonrpc: "2.0",
        id: rpc.id,
        result: { tools: TOOLS },
      }, 200, sessionHeaders);
    }
    if (method === "tools/call") {
      const name = rpc.params && rpc.params.name;
      const args = (rpc.params && rpc.params.arguments) || {};
      if (!TOOL_NAMES.has(name)) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("unknown_tool", "tool not in manifest: " + name),
        }, 200, sessionHeaders);
      }
      // 限速（按 pairing 的滚动窗口，仅 tools/call 计数）。
      const now = Date.now();
      if (now - this.rate.windowStart > RATE_WINDOW_MS) {
        this.rate = { windowStart: now, count: 0 };
      }
      this.rate.count += 1;
      if (this.rate.count > RATE_MAX_CALLS) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("rate_limited", "relay rate limit", true),
        }, 200, sessionHeaders);
      }
      if (OPS_SCOPE_TOOLS.has(name) && !rec.scopes.includes("ops")) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("scope_denied", "tool requires ops scope: " + name),
        }, 200, sessionHeaders);
      }
      if (WRITE_SCOPE_TOOLS.has(name) && !rec.scopes.includes("write")) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("scope_denied", "tool requires write scope: " + name),
        }, 200, sessionHeaders);
      }
      if (UITEST_SCOPE_TOOLS.has(name) && !rec.scopes.includes("ops")) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("scope_denied", "tool requires ops scope: " + name),
        }, 200, sessionHeaders);
      }
      rec.calls = (rec.calls || 0) + 1;
      rec.lastSeenAt = rec.lastSeenAt || 0;
      await this.saveRecord(rec);
      if (RELAY_TOOLS.has(name)) {
        const result = await this.opsGetSources();
        return jsonResponse({ jsonrpc: "2.0", id: rpc.id, result }, 200, sessionHeaders);
      }
      let ws = this.deviceSocket();
      if (!ws) {
        // 等设备短窗（fix_bridge_stability）：设
        // 备常在调用到达的同一秒内重连落地（前台
        // 探活/退避到点），立即判离线会把这类调用
        // 全数误杀；轮询至多 WAIT_DEVICE_MS，落
        // 地即照常转发，窗尽仍无才回 app_offline。
        const deadline = Date.now() + WAIT_DEVICE_MS;
        while (!ws && Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, WAIT_POLL_MS));
          ws = this.deviceSocket();
        }
      }
      if (!ws) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("app_offline", "no live device connection", true),
        }, 200, sessionHeaders);
      }
      const relayId = "r" + (++this.seq) + "-" + Date.now().toString(36);
      const timeout = (WRITE_SCOPE_TOOLS.has(name) || name === "notes_delete_permanent" || name === "rescue_try_normal_start")
        ? WRITE_TIMEOUT_MS
        : OPS_SCOPE_TOOLS.has(name) ? CONTROL_TIMEOUT_MS : READ_TIMEOUT_MS;
      const deviceRpc = { jsonrpc: "2.0", id: relayId, method: "tools/call", params: { name, arguments: args } };
      const response = await new Promise((resolve) => {
        const timer = setTimeout(() => {
          this.pending.delete(relayId);
          resolve(null);
        }, timeout);
        this.pending.set(relayId, { resolve, timer, ws });
        try {
          ws.send(JSON.stringify(deviceRpc));
        } catch {
          clearTimeout(timer);
          this.pending.delete(relayId);
          resolve(null);
        }
      });
      if (!response) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult("app_offline", "device did not answer in time", true),
        }, 200, sessionHeaders);
      }
      if (response.error) {
        return jsonResponse({
          jsonrpc: "2.0", id: rpc.id,
          result: toolErrorResult(
            (response.error.data && response.error.data.code) || "device_error",
            response.error.message || "device error"),
        }, 200, sessionHeaders);
      }
      return jsonResponse({
        jsonrpc: "2.0", id: rpc.id, result: response.result,
      }, 200, sessionHeaders);
    }
    return jsonResponse(rpcError(rpc.id, -32601, "method not found: " + method), 200, sessionHeaders);
  }

  async opsGetSources() {
    const out = { origin: "relay", fetchedAt: Date.now() };
    let peerSets = [];
    for (const [name, base] of OPS_SOURCES) {
      const stamp = Math.floor(Date.now() / 1000);
      const url = base + "?t=" + stamp;
      try {
        const resp = await fetch(url, { headers: { "Cache-Control": "no-store" } });
        const text = await resp.text();
        let set = null;
        try { set = sanitizeOps(JSON.parse(text)); } catch { set = null; }
        if (resp.status === 200 && set) {
          out[name] = {
            ok: true,
            httpStatus: resp.status,
            set,
            hash: await sha256hex(opsCanonical(set)),
          };
          peerSets.push(set);
        } else {
          out[name] = { ok: false, httpStatus: resp.status, set: null, hash: null };
        }
      } catch (e) {
        out[name] = { ok: false, httpStatus: 0, set: null, hash: null, error: String(e).slice(0, 120) };
      }
    }
    out.peersAgree = peerSets.length === 2
      && opsCanonical(peerSets[0]) === opsCanonical(peerSets[1]);
    return toolOkResult(out);
  }
}

// ---------- Worker 入口 ----------

async function roomStub(env, pairingId) {
  const name = await sha256hex(pairingId);
  return env.BRIDGE_ROOM.get(env.BRIDGE_ROOM.idFromName(name));
}

function pairPage(pid, fp, error) {
  const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moment MCP 桥 · 配对</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;margin:24px;line-height:1.55;color:#1c1c1e}
code{background:#f2f2f7;padding:2px 6px;border-radius:6px}
.fp{font-size:20px;letter-spacing:1px;font-weight:600}
.err{color:#b00020}label{display:block;margin:8px 0}
button{font-size:16px;padding:10px 18px;border-radius:10px;border:0;background:#2379dc;color:#fff}
.note{color:#666;font-size:13px}</style></head><body>
<h2>Moment MCP 桥 · 配对确认</h2>
${error ? `<p class="err">${escapeHtml(error)}</p>` : ""}
<p>请核对下面指纹与 Moment App 配对页显示的<b>完全一致</b>，不一致请立即关闭本页。</p>
<p class="fp">${escapeHtml(fp || "-")}</p>
<p class="note">配对 ID：<code>${escapeHtml((pid || "").slice(0, 8))}…</code></p>
<form method="POST" action="/pair/confirm">
<input type="hidden" name="pid" value="${escapeHtml(pid || "")}">
<input type="hidden" name="fp" value="${escapeHtml(fp || "")}">
<label><input type="checkbox" checked disabled> read · 只读（状态 / 诊断 / 笔记读 / 运维回读）— 必选</label>
<label><input type="checkbox" name="scope_write" value="1"> write · 功能写（M2 起生效）</label>
<label><input type="checkbox" name="scope_ops" value="1"> ops · 运维（含 OPS 刷新；高危动作另有确认）</label>
<button type="submit">确认配对</button>
</form>
<p class="note">确认后本页将一次性显示客户端访问密钥，请将其粘贴到 Muse 的安全凭据页完成连接器注册；密钥不会再次显示。</p>
</body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

function pairDonePage(clientKey, fp) {
  const html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Moment MCP 桥 · 配对完成</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;margin:24px;line-height:1.55;color:#1c1c1e}
code{background:#f2f2f7;padding:2px 6px;border-radius:6px;word-break:break-all}
.key{font-size:14px}</style></head><body>
<h2>配对完成</h2>
<p>设备指纹：<code>${escapeHtml(fp)}</code></p>
<p>客户端访问密钥（<b>只显示这一次</b>）：</p>
<p class="key"><code>${escapeHtml(clientKey)}</code></p>
<p>请把这条密钥粘贴到 Muse 的安全凭据页（连接器 moment-bridge 注册）完成接入，不要发到聊天里、不要存进仓库。</p>
</body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    try {
      if (path === "/health") {
        return jsonResponse({ ok: true, service: "moment-bridge", version: RELAY_VERSION });
      }
      if (path === "/pair" && request.method === "GET") {
        return pairPage(url.searchParams.get("pid") || "", url.searchParams.get("fp") || "", "");
      }
      if (path === "/pair/start" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        if (!body.pairingId) return jsonResponse({ error: "bad_request" }, 400);
        const stub = await roomStub(env, body.pairingId);
        return stub.fetch("https://room/pair-start", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
      }
      if (path === "/pair/status" && request.method === "GET") {
        const pid = url.searchParams.get("pid") || "";
        if (!pid) return jsonResponse({ error: "bad_request" }, 400);
        const stub = await roomStub(env, pid);
        return stub.fetch("https://room/pair-status?pid=" + encodeURIComponent(pid));
      }
      if (path === "/pair/confirm" && request.method === "POST") {
        // App 内确认通道（JSON，fix_bridge_pairing_inapp）：
        // 与下方表单通道同入 DO pair-confirm 单点、同校验
        // （指纹/pending/过期），clientKey 只回本次 JSON
        // 响应一次；表单通道（网页配对页）逐字不变。
        if ((request.headers.get("Content-Type") || "")
            .includes("application/json")) {
          const body = await request.json().catch(() => ({}));
          const pid = String(body.pairingId || "");
          if (!pid) return jsonResponse({ error: "bad_request" }, 400);
          const stub = await roomStub(env, pid);
          return stub.fetch("https://room/pair-confirm", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              fingerprint: String(body.fingerprint || ""),
              scopes: Array.isArray(body.scopes)
                ? body.scopes : ["read"],
            }),
          });
        }
        const form = await request.formData();
        const pid = String(form.get("pid") || "");
        const fp = String(form.get("fp") || "");
        if (!pid) return pairPage("", "", "配对参数缺失，请从 App 重新打开配对链接。");
        const scopes = ["read"];
        if (form.get("scope_write")) scopes.push("write");
        if (form.get("scope_ops")) scopes.push("ops");
        const stub = await roomStub(env, pid);
        const resp = await stub.fetch("https://room/pair-confirm", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ fingerprint: fp, scopes }),
        });
        const data = await resp.json().catch(() => ({}));
        if (!resp.ok || !data.clientKey) {
          return pairPage(pid, fp, "配对失败：" + (data.error || resp.status) + "（会话可能已过期，请在 App 内重新开始配对）");
        }
        return pairDonePage(data.clientKey, data.fingerprint || fp);
      }
      if (path === "/pair/revoke" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const pid = body.pairingId || "";
        if (!pid) return jsonResponse({ error: "bad_request" }, 400);
        const stub = await roomStub(env, pid);
        return stub.fetch("https://room/revoke", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": request.headers.get("Authorization") || "",
            "X-Device-Signature": request.headers.get("X-Device-Signature") || "",
          },
          body: JSON.stringify(body),
        });
      }
      if (path === "/app/connect" && request.method === "GET") {
        const pid = url.searchParams.get("pid") || "";
        if (!pid) return jsonResponse({ error: "bad_request" }, 400);
        const stub = await roomStub(env, pid);
        return stub.fetch(request);
      }
      if (path === "/mcp") {
        if (request.method === "GET") {
          return jsonResponse(rpcError(null, -32000, "GET not supported; use POST"), 405);
        }
        const auth = request.headers.get("Authorization") || "";
        const m = auth.match(/^Bearer mb1\.([^.]+)\.(.+)$/);
        if (!m) {
          return jsonResponse(rpcError(null, -32001, "unauthorized", "unauthorized"), 401);
        }
        const [, pid, secret] = m;
        const stub = await roomStub(env, pid);
        if (request.method === "DELETE") {
          return jsonResponse({}, 200);
        }
        const rpcText = await request.text();
        return stub.fetch("https://room/mcp", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ secret, rpcText }),
        });
      }
      return jsonResponse({ error: "not_found" }, 404);
    } catch (e) {
      return jsonResponse({ error: "relay_error", detail: String(e).slice(0, 200) }, 500);
    }
  },
};
