// Moment 热更新指令通道（S13，0.9.45）：运维指令
// （白名单两字段）双源拉取/缓存/guard 查询
// （OpsStep / OpsDirectiveSet / OpsDirectives）。
// 规格见 docs/reports/plan_native_rescue.md S13；
// 本文件自 MomentApp.swift 拆出（拒绝上帝文件，
// 独立成文件），消费点（判定/跳步/救援页）在
// Library / DiagLog / RescueView。
import Foundation
import Combine

// ── 热更新指令通道（S13，用户 2026-11-27 新规）──
// 运维指令（白名单两字段）双源托管，救援壳/正常启
// 动后拉取落缓存，guard 点按 disableSteps 跳步、
// forceSafeMode 带回安全模式——极端问题（闪退类）
// 以热路径绕行解决，不靠重装新 ipa。核心步（开
// 库/读数据/解析/再水化）不设 guard、指令点名也
// 无效：热修面只辖非核心步，数据层永不被指令改
// 写。指令文件与 Diag 同隔离域（diag/ops-
// directives.json）。
enum OpsStep {
    /// 附件类型表刷新（LaunchStep.attachTypes 同名，
    /// 判图回落扩展名口径）。
    static let attachTypes = LaunchStep.attachTypes
    /// Diag 冻结合并写盘段（DiagLog.flushStructural
    /// Persist 辖区）。
    static let diagFreezePersist = "Diag冻结写盘"
    /// 天气自动刷新（ListView.onAppear 触发点）。
    static let weatherRefresh = "天气自动刷新"
    /// 公式预热：现无预热调用点（MathImageStore
    /// .entry 懒加载），步名先行登记——新增预热时
    /// 必须先查 isDisabled(本步名) 才许执行。
    static let mathPreheat = "公式预热"
}

/// 指令集（白名单解析产物）：只认 disableSteps 与
/// forceSafeMode 两字段，version 只记不判。解析走
/// JSONSerialization 逐字段类型核对——字段缺失/
/// 类型越界/未知字段一律忽略，整包坏损返回 nil
/// （消费侧当空指令）。
struct OpsDirectiveSet: Codable, Equatable {
    var version: Int = 1
    var disableSteps: [String] = []
    var forceSafeMode: Bool = false

    func isDisabled(_ step: String) -> Bool {
        disableSteps.contains(step)
    }
}

final class OpsDirectives: ObservableObject {
    static let shared = OpsDirectives()

    /// 端点双源（常量集中）：主 = Cloudflare
    /// Worker（no-store、改指令即时生效）；备 =
    /// GitHub Pages（CDN 缓存约 10 分钟，拉取带时
    /// 间戳参数绕）。第一个成功为准。
    static let endpointWorker =
        "https://moment-ops.overtrees.workers.dev/ops.json"
    static let endpointGithub =
        "https://overtrees.github.io/moment-ops/ops.json"

    @Published private(set) var current: OpsDirectiveSet
    /// 最近一次成功拉取的来源（worker/github），
    /// 未拉过为空串；缓存命中的摘要呈现走 current。
    @Published private(set) var lastSource: String = ""

    init() {
        current = Self.loadCache() ?? OpsDirectiveSet()
    }

    static var cachePath: String {
        DiagLog.diagDirPath() + "/ops-directives.json"
    }

    /// 缓存/网络共用白名单解析（纯函数、无副作用、
    /// 不记日志——DiagLog 的 guard 点反向调用它，
    /// 必须保持无环）。
    static func sanitize(_ data: Data)
        -> OpsDirectiveSet? {
        guard let obj = try? JSONSerialization
                .jsonObject(with: data)
                as? [String: Any] else { return nil }
        var set = OpsDirectiveSet()
        if let v = obj["version"] as? Int {
            set.version = v
        }
        if let arr = obj["disableSteps"] as? [Any] {
            set.disableSteps = arr.compactMap {
                $0 as? String
            }
        }
        if let f = obj["forceSafeMode"] as? Bool {
            set.forceSafeMode = f
        }
        return set
    }

    static func loadCache() -> OpsDirectiveSet? {
        guard let data = try? Data(
                contentsOf: URL(fileURLWithPath: cachePath))
        else { return nil }
        return sanitize(data)
    }

    /// 同步读缓存（判定/guard 消费面）：无缓存或坏
    /// 损当空指令。
    static func cached() -> OpsDirectiveSet {
        loadCache() ?? OpsDirectiveSet()
    }

    /// 正常模式 didLoad 后后台刷新一次（为下次启
    /// 动备缓存，本次不生效——guard 读的是启动时
    /// 缓存，热指令下次启动兑现，口径与 Web 救援
    /// 开关「重启即生效」同）。
    static func refreshInBackground() {
        shared.fetch()
    }

    /// 双源顺序拉取：主源失败（网络错/非 200/解
    /// 析失败）落备源，全失败记 warn（logOnce）。
    /// 成功落缓存 + 更新 current + 记 fetched 行。
    func fetch(completion: (() -> Void)? = nil) {
        fetchFrom(index: 0, completion: completion)
    }

    private func fetchFrom(
        index: Int, completion: (() -> Void)?) {
        let sources: [(String, String)] = [
            ("worker", Self.endpointWorker),
            ("github", Self.endpointGithub),
        ]
        guard index < sources.count else {
            DiagLog.shared.logOnce(
                "ops-fetch-fail", .warn,
                "OPS directives fetch failed")
            completion?()
            return
        }
        let (src, base) = sources[index]
        let stamp = Int(Date().timeIntervalSince1970)
        guard let url = URL(
            string: base + "?t=\(stamp)") else {
            fetchFrom(index: index + 1,
                      completion: completion)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        URLSession.shared.dataTask(
            with: req) { [weak self] data, resp, _ in
            let okStatus = (resp as? HTTPURLResponse)?
                .statusCode == 200
            if let data, okStatus,
               let set = Self.sanitize(data) {
                if let encoded = try? JSONEncoder()
                    .encode(set) {
                    try? encoded.write(
                        to: URL(fileURLWithPath:
                                Self.cachePath),
                        options: .atomic)
                }
                DispatchQueue.main.async {
                    self?.current = set
                    self?.lastSource = src
                }
                DiagLog.shared.log(.info,
                    "OPS directives fetched src=\(src) "
                    + "steps=\(set.disableSteps.count) "
                    + "forceSafe="
                    + (set.forceSafeMode ? "1" : "0"))
                completion?()
            } else {
                self?.fetchFrom(index: index + 1,
                                completion: completion)
            }
        }.resume()
    }
}
