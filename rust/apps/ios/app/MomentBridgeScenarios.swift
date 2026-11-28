// ── MCP 桥场景库（M3a，方案 plan_bridge_m3.md）──
// 场景库内置于 App：编译期场景注册表 + 引擎 +
// run 日志（journal）。分发器（MomentBridge
// Tools）只做受理门（场景声明制 scope 验足 +
// 数据写前置门 + 高危场级两段），执行、证据组
// 装、跨重启续跑都在本文件。
// 共用件纪律（方案 §4.2/§4.3/§8.5）：run 互斥
// 用 UITestDriver 的 activeRunId 单锁（先落地的
// 驱动核持有，引擎只经 tryClaim/release 引用，
// 不另造第二把）；夹具登记集用 UITestFixture
// （M3a 四景均无夹具，写步守卫先行在位，夹具
// 本体随 M3b 写景落地）。
// 正文红线（方案 §5.3）：场景参数只许注册表声
// 明的标量/id/哈希，表外键一律 invalid_params；
// 正文级四件（notes_create / editor_insert_
// block / editor_update_block / editor_set_
// block_type）在本文件零出现（verify B27-4
// 守）；证据包只载 id/哈希/计数/Diag 行/量测，
// 不载正文。
// M3b 追加（同方案 §2.2）：写景四景全实装
// （delete_restore_roundtrip / drag_semantic_
// reorder / create_transition / snapshot_
// restore_drill——快照恢复景随 backup_restore_
// snapshot 工具批落地，武装门 arm_required 取
// 代原 wiring_missing 现形，见 impl_bridge_
// backup_restore.md）。

import Foundation

// ── 场景描述符与注册表 ──

struct BridgeScenarioParam {
    let key: String
    /// string | bool | number（JSON 标量三类）。
    let kind: String
    let required: Bool
}

struct BridgeScenarioDescriptor {
    let id: String
    /// run 受理时一次验足（方案 §5.1 场景声明
    /// 制）：缺层回 scope_denied 并点名缺哪层。
    let requiredScopes: [String]
    /// true → scenarios_run 整场入两段提交（场
    /// 级令牌绑工具名 + 全参数哈希，方案 §5.2）。
    let containsHighRisk: Bool
    /// true → 含事前用户指令段（执行者是助手侧
    /// 纪律，标记让其机器可见，方案 §5.2）。
    let requiresUserDirective: Bool
    /// single | crossRestart。
    let phases: String
    /// none | template（是否建夹具）。
    let fixture: String
    let params: [BridgeScenarioParam]
    /// 证据等级上限声明（方案 §8：报告不得升级）。
    let grades: [String: String]
    let summary: String
    /// 前置工具/接线未落（方案 §2 可用性
    /// wiring_missing）：清单里现形、run 受理
    /// 即拒，绝不空跑假成功。
    let wiringMissing: Bool

    /// 显式初始化器：let + 默认值不进成员
    /// 初始化器（Swift 规则），wiringMissing
    /// 的缺省 false 只能在此处给（M3b 落码时
    /// 以属性默认值声明、tree 首轮构建实证
    /// 调用点 extra argument，组版根治）。
    init(id: String,
         requiredScopes: [String],
         containsHighRisk: Bool,
         requiresUserDirective: Bool,
         phases: String,
         fixture: String,
         params: [BridgeScenarioParam],
         grades: [String: String],
         summary: String,
         wiringMissing: Bool = false) {
        self.id = id
        self.requiredScopes = requiredScopes
        self.containsHighRisk = containsHighRisk
        self.requiresUserDirective =
            requiresUserDirective
        self.phases = phases
        self.fixture = fixture
        self.params = params
        self.grades = grades
        self.summary = summary
        self.wiringMissing = wiringMissing
    }

    var dict: [String: Any] {
        [
            "id": id,
            "requiredScopes": requiredScopes,
            "containsHighRisk": containsHighRisk,
            "requiresUserDirective":
                requiresUserDirective,
            "phases": phases,
            "fixture": fixture,
            "params": params.map {
                ["key": $0.key, "kind": $0.kind,
                 "required": $0.required]
                    as [String: Any]
            },
            "grades": grades,
            "summary": summary,
            "wiringMissing": wiringMissing,
        ]
    }
}

enum BridgeScenarioRegistry {
    /// 全库恢复类场景的武装门集合（方案 §8 风
    /// 险 3）：可用性面以 arm_required 现形、run
    /// 受理未带 armRestore: true 即拒——集合单
    /// 点，availability 与受理层共消费。
    static let armGatedIds: Set<String> = [
        "snapshot_restore_drill",
        "snapshot_pending_window_restore",
    ]

    /// M3a 首批四景（方案 §2.1）：只读/低危三景
    /// 现配对（read+ops）可跑；language_roundtrip
    /// 须 write 重配对（用户动作前置，非代码缺
    /// 口——清单里以 scope_missing 现形）。
    /// M3b 写景四景（方案 §2.2）：四景全实装；
    /// 快照恢复景随工具批真接线（可用性以
    /// arm_required 现形武装门，run 未武装即
    /// 拒）。
    static let all: [BridgeScenarioDescriptor] = [
        BridgeScenarioDescriptor(
            id: "drag_trace_review",
            requiredScopes: ["read"],
            containsHighRisk: false,
            requiresUserDirective: false,
            phases: "single",
            fixture: "none",
            params: [
                BridgeScenarioParam(
                    key: "sinceTs", kind: "number",
                    required: false),
                BridgeScenarioParam(
                    key: "blockId", kind: "string",
                    required: false),
                BridgeScenarioParam(
                    key: "limit", kind: "number",
                    required: false),
            ],
            grades: [
                "chainIntegrity": "proven",
                "gestureFeel": "unknown",
            ],
            summary: "回读 DRAG 归组行判拖拽链路"
                + "完整性（成链/缺环点名）+ 原始行"),
        BridgeScenarioDescriptor(
            id: "weather_settings_flow",
            requiredScopes: ["read"],
            containsHighRisk: false,
            requiresUserDirective: false,
            phases: "single",
            fixture: "none",
            params: [
                BridgeScenarioParam(
                    key: "provider", kind: "string",
                    required: false),
            ],
            grades: [
                "stateReadback": "proven",
                "refreshSuccess": "unknown",
            ],
            summary: "天气 key 状态前后回读 + 内部"
                + "触发刷新验状态迁移（key 值不经桥）"),
        BridgeScenarioDescriptor(
            id: "ops_convergence",
            requiredScopes: ["ops"],
            containsHighRisk: false,
            requiresUserDirective: false,
            phases: "crossRestart",
            fixture: "none",
            params: [
                BridgeScenarioParam(
                    key: "expectedHash", kind: "string",
                    required: false),
            ],
            grades: [
                "hashChain": "proven",
            ],
            summary: "OPS 收敛确认链：拉源→刷新落"
                + "缓存→挂起→用户重开后续验 "
                + "bootApplied 三层哈希一致"),
        BridgeScenarioDescriptor(
            id: "language_roundtrip",
            requiredScopes: ["write"],
            containsHighRisk: false,
            requiresUserDirective: false,
            phases: "single",
            fixture: "none",
            params: [
                BridgeScenarioParam(
                    key: "code", kind: "string",
                    required: false),
            ],
            grades: [
                "preference": "proven",
                "resolution": "proven",
                "uiPresentation": "unknown",
            ],
            summary: "切语言→验生效码→切回原码"
                + "（桥腿；UI 呈现腿归 U5）"),
        BridgeScenarioDescriptor(
            id: "delete_restore_roundtrip",
            requiredScopes: ["write"],
            containsHighRisk: true,
            requiresUserDirective: true,
            phases: "single",
            fixture: "template",
            params: [
                BridgeScenarioParam(
                    key: "includePermanent",
                    kind: "bool", required: false),
            ],
            grades: [
                "data": "proven",
                "persistence": "proven",
            ],
            summary: "夹具软删→恢复守卫→恢复回读"
                + "→再软删→窗口后真删（可选永删"
                + "段：另一夹具软删后永删，段内另"
                + "验 ops；整场两段从严，见报告）"),
        BridgeScenarioDescriptor(
            id: "drag_semantic_reorder",
            requiredScopes: ["write"],
            containsHighRisk: false,
            requiresUserDirective: false,
            phases: "single",
            fixture: "template",
            params: [],
            grades: [
                "blockOrder": "proven",
                "persistence": "proven",
                "gestureFeel": "unknown",
            ],
            summary: "多块夹具经移块内部路径两次"
                + "重排→回读块序→导航通道重开再"
                + "回读（语义序与落盘面）"),
        BridgeScenarioDescriptor(
            id: "create_transition",
            requiredScopes: ["write"],
            containsHighRisk: false,
            requiresUserDirective: false,
            phases: "single",
            fixture: "template",
            params: [],
            grades: [
                "settleData": "proven",
                "smoothness": "unknown",
            ],
            summary: "经新建同路建夹具并打开，解"
                + "析 CREATE settle 分段对基线护"
                + "栏（超护栏标 degraded 不判红）"),
        BridgeScenarioDescriptor(
            id: "snapshot_restore_drill",
            requiredScopes: ["ops"],
            containsHighRisk: true,
            requiresUserDirective: true,
            phases: "single",
            fixture: "template",
            params: [
                BridgeScenarioParam(
                    key: "armRestore",
                    kind: "bool", required: false),
            ],
            grades: [
                "persistence": "proven",
            ],
            summary: "快照→变更→恢复→verifyStore"
                + " 对账（恢复目标恒为本景自取快"
                + "照；须 armRestore 武装 + 整场"
                + "两段 + 用户指令三重门，见 §8 "
                + "风险 3）"),
        BridgeScenarioDescriptor(
            id: "snapshot_pending_window_restore",
            requiredScopes: ["ops"],
            containsHighRisk: true,
            requiresUserDirective: true,
            phases: "single",
            fixture: "template",
            params: [
                BridgeScenarioParam(
                    key: "armRestore",
                    kind: "bool", required: false),
            ],
            grades: [
                "persistence": "proven",
            ],
            summary: "待删窗铸快照回归格（快照线"
                + "缺陷二）：夹具软删入窗→窗内铸"
                + "快照→窗口过期真删→恢复该快照"
                + "→清单哈希/计数同域对账（旧全"
                + "行哈希域下此链必挂 snapshot_"
                + "failed）；武装门与 drill 同集"
                + "（armGatedIds）"),
    ]

    static func descriptor(
        _ id: String) -> BridgeScenarioDescriptor? {
        all.first { $0.id == id }
    }

    /// 参数面校验（方案 §5.3）：只许声明表内的
    /// 标量键，表外键/类型不符/必填缺失一律
    /// invalid_params；声明表本身零正文键（B27-4
    /// 断言守）。值域校验只做注册表可判定的：
    /// language_roundtrip 的 code 须为五语码。
    static func validateParams(
        _ desc: BridgeScenarioDescriptor,
        _ params: [String: Any]) -> BridgeToolError? {
        let declared = Dictionary(
            uniqueKeysWithValues:
                desc.params.map { ($0.key, $0) })
        for key in params.keys
        where declared[key] == nil {
            return .invalidParams(
                "scenario \(desc.id): undeclared "
                + "param \(key)")
        }
        for p in desc.params {
            guard let v = params[p.key] else {
                if p.required {
                    return .invalidParams(
                        "scenario \(desc.id): param "
                        + "\(p.key) required")
                }
                continue
            }
            switch p.kind {
            case "string":
                if !(v is String) {
                    return .invalidParams(
                        "scenario \(desc.id): param "
                        + "\(p.key) must be string")
                }
            case "bool":
                if !(v is Bool) {
                    return .invalidParams(
                        "scenario \(desc.id): param "
                        + "\(p.key) must be bool")
                }
            case "number":
                if !(v is NSNumber) || v is Bool {
                    return .invalidParams(
                        "scenario \(desc.id): param "
                        + "\(p.key) must be number")
                }
            default:
                break
            }
        }
        if desc.id == "language_roundtrip",
           let code = params["code"] as? String,
           !LangStore.codes.contains(code) {
            return .invalidParams(
                "scenario language_roundtrip: code "
                + "must be one of "
                + LangStore.codes.joined(
                    separator: "/"))
        }
        return nil
    }

    /// 可用性（scenarios_list 逐景计算，方案
    /// §2）：不可用的场景在清单里就现形，不等
    /// 跑起来才拒。
    static func availability(
        _ desc: BridgeScenarioDescriptor,
        library: Library?,
        coordinator: BridgeCoordinator) -> String {
        guard let library else {
            return "library_unavailable"
        }
        if library.bootIsSafe {
            return "safe_mode_limited"
        }
        if library.isReadOnly {
            return "read_only_mode"
        }
        if desc.wiringMissing {
            return "wiring_missing"
        }
        // 快照恢复景的武装门（方案 §8 风险 3）：
        // 全库恢复演练默认不标 available，须
        // run 时 params 显式 armRestore: true
        // 才可跑——可用性面先以 arm_required
        // 现形，受理层同口径拒绝未武装的 run。
        if BridgeScenarioRegistry.armGatedIds
            .contains(desc.id) {
            return "arm_required"
        }
        let missing = desc.requiredScopes.filter {
            !coordinator.scopes.contains($0)
        }
        if let layer = missing.first {
            return "scope_missing:\(layer)"
        }
        return "available"
    }
}

// ── run 日志（journal）──
// 落点 Application Support/bridge-scenarios/
// runs.json（与快照同域、独立目录；不进用户备
// 份 ZIP、不进 Diag 域）。每 run 一条，保留最
// 近 10 个；scenarios_get_result 只读 journal
// 组装证据包（进程重启后仍可回读——跨重启景
// 的必需口径，方案 §4.2）。

struct BridgeScenarioRun: Codable {
    var runId: String
    var scenarioId: String
    var paramsHash: String
    /// running / awaiting_manual_reopen / done /
    /// failed / expired。
    var status: String
    /// 终态码（ok / step_failed / run_timeout /
    /// hygiene_failed / language_left_changed /
    /// resume_condition_mismatch / expired /
    /// scenario_missing；运行中为 running，挂起
    /// 中为 awaiting_manual_reopen）。
    var code: String
    var stepCursor: Int = 0
    var fixtureIds: [String] = []
    var preLibraryHash: String = ""
    var postLibraryHash: String = ""
    var originBootSessionId: String = ""
    var createdAtMs: Int64 = 0
    var updatedAtMs: Int64 = 0
    /// 步记录与证据以 JSON 串落盘（[String: Any]
    /// 不直接 Codable；组装口径与 UITestJob
    /// payload 同形）。
    var stepsJSON: String = "[]"
    var evidenceJSON: String = "{}"
}

enum BridgeScenarioJournal {
    static var dirPath: String {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)[0]
        let d = base.appendingPathComponent(
            "bridge-scenarios").path
        try? FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: true)
        return d
    }

    static var filePath: String {
        dirPath + "/runs.json"
    }

    static func load() -> [BridgeScenarioRun] {
        guard let data = try? Data(contentsOf:
                URL(fileURLWithPath: filePath)),
              let runs = try? JSONDecoder().decode(
                [BridgeScenarioRun].self, from: data)
        else { return [] }
        return runs
    }

    @discardableResult
    static func save(
        _ runs: [BridgeScenarioRun]) -> Bool {
        let sorted = runs.sorted {
            $0.createdAtMs < $1.createdAtMs
        }
        let kept = Array(sorted.suffix(10))
        if kept.count < sorted.count {
            DiagLog.shared.log(.info,
                "SCENARIO journal prune dropped="
                + "\(sorted.count - kept.count)")
        }
        guard let data = try? JSONEncoder()
            .encode(kept) else { return false }
        do {
            try data.write(
                to: URL(fileURLWithPath: filePath),
                options: .atomic)
            return true
        } catch { return false }
    }

    @discardableResult
    static func upsert(
        _ run: BridgeScenarioRun) -> Bool {
        var all = load()
        if let i = all.firstIndex(
            where: { $0.runId == run.runId }) {
            all[i] = run
        } else {
            all.append(run)
        }
        return save(all)
    }

    static func run(
        _ runId: String) -> BridgeScenarioRun? {
        load().first { $0.runId == runId }
    }
}

// ── 步模型与运行上下文 ──
// 步类型封闭集（方案 §4.1）：callInternal（调
// 已有工具的内部实现函数——分发器 case 背后同
// 一函数，不经中继往返、不重复过门，门在 run
// 受理时按描述符一次验足）、invokeService（调
// 内部服务）、waitDiag、assert、suspend、
// measureInternal（Diag 内部解析）。不接受桥
// 上传任意步序列/代码/方法名。

struct BridgeScenarioStepOutcome {
    var ok = true
    var assertions: [UITestAssertion] = []
    var note: String?
    /// true → 本步后挂起（跨重启景的 suspend 步）。
    var suspend = false
}

struct BridgeScenarioStep {
    let kind: String
    let label: String
    let body: (BridgeScenarioContext,
               @escaping (BridgeScenarioStepOutcome)
                -> Void) -> Void
}

final class BridgeScenarioContext {
    let runId: String
    let descriptor: BridgeScenarioDescriptor
    let params: [String: Any]
    let library: Library
    let startedAt = Date()
    /// 单会话段总时长硬顶 120 秒（方案 §4.2）；
    /// 跨重启景的挂起段不计时（7 天过期兜底）。
    let deadline: Date
    var stepStart = Date()
    /// 步间传递面（before 态/中间回读）。须跨重
    /// 启保留的内容由场景步显式写进 evidence 的
    /// phaseA 段（journal 落盘），scratch 只活
    /// 本段进程内。
    var scratch: [String: Any] = [:]
    var measurements: [String: Any] = [:]
    var detail: [String: Any] = [:]
    var conclusion: [String: Any] = [:]
    var stepRecords: [[String: Any]] = []
    /// 写步前已取的快照 id（收尾记账判据）。
    var snapshotId: String?
    /// 场景自定义终态码（优先于 step_failed，如
    /// language_left_changed）。
    var forcedCode: String?
    /// 本 run 建的夹具 id 集（M3b 写景）：收尾
    /// 清理链与 journal fixture.ids 的单一来源。
    var fixtureIds: [String] = []
    /// 收尾清理验净后仍残留的夹具 id（快照线缺
    /// 陷一）：清理链逐篇验净、残留在此点名，终
    /// 态据此升级 hygiene_failed——不许静默残留
    /// （旧形态清理只按镜像查找、无验净、恒注销
    /// 登记，残留对后续卫生网不可见）。
    var cleanupResidue: [String] = []

    init(runId: String,
         descriptor: BridgeScenarioDescriptor,
         params: [String: Any], library: Library) {
        self.runId = runId
        self.descriptor = descriptor
        self.params = params
        self.library = library
        self.deadline = Date()
            .addingTimeInterval(120)
    }

    var shortId: String { String(runId.prefix(8)) }

    /// 本步窗口内的 Diag 行（ts ≥ 步起始）。
    func windowEntries() -> [DiagEntry] {
        let from = stepStart.timeIntervalSince1970
        return DiagLog.shared.today.filter {
            $0.ts >= from
        }
    }

    /// 轮询原语（与驱动同口径：100ms 一轮、总
    /// 截止在此收口）。
    func poll(timeoutMs: Int,
              _ cond: @escaping () -> Bool,
              done: @escaping (Bool) -> Void) {
        let limit = Date().addingTimeInterval(
            Double(timeoutMs) / 1000)
        func tick() {
            if Date() > deadline {
                done(false)
                return
            }
            if cond() { done(true); return }
            if Date() >= limit { done(false); return }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.1) { tick() }
        }
        tick()
    }

    /// 写步目标守卫（方案 §4.3）：场景的一切写
    /// 步先验目标 id ∈ 夹具登记集，不在集内以
    /// fixture_guard 中止——结构上够不到用户既
    /// 有笔记的写面。M3a 四景无夹具写步，本守
    /// 卫为 M3b 写景的引擎内单点，先行在位。
    func fixtureGuard(_ memoId: String) -> Bool {
        UITestFixture.isFixture(memoId)
    }
}

// ── 引擎 ──

final class BridgeScenarioEngine {
    static let shared = BridgeScenarioEngine()

    private var activeCtx: BridgeScenarioContext?
    private var activeRun: BridgeScenarioRun?

    var activeRunId: String? { activeCtx?.runId }
    /// 引擎或驱动任一在跑（scenarios_list 回读）。
    var anyRunBusy: Bool {
        activeCtx != nil || UITestDriver.shared.isBusy
    }

    static var runConflictError: BridgeToolError {
        BridgeToolError(
            code: "run_conflict",
            message: "another uitest/scenario run "
                + "is in progress")
    }

    private func makeRunId() -> String {
        UUID().uuidString.prefix(8).lowercased()
            + "-" + String(UUID().uuidString
                .prefix(4)).lowercased()
    }

    // ── 受理（分发器已过声明制 scope 门、参数
    // 面校验与数据写前置门）──

    func begin(
        descriptor: BridgeScenarioDescriptor,
        args: [String: Any], library: Library
    ) -> Result<String, BridgeToolError> {
        guard activeCtx == nil else {
            return .failure(Self.runConflictError)
        }
        let runId = makeRunId()
        guard UITestDriver.shared
            .tryClaimExternalRun(runId) else {
            return .failure(Self.runConflictError)
        }
        let params = args["params"]
            as? [String: Any] ?? [:]
        var run = BridgeScenarioRun(
            runId: runId,
            scenarioId: descriptor.id,
            paramsHash: BridgeDispatcher
                .paramsHash(args),
            status: "running", code: "running")
        run.preLibraryHash = library.libraryHash()
        run.originBootSessionId =
            BridgeCoordinator.shared.bootSessionId
        run.createdAtMs = Library.epochMs()
        run.updatedAtMs = run.createdAtMs
        guard BridgeScenarioJournal.upsert(run) else {
            UITestDriver.shared
                .releaseExternalRun(runId)
            return .failure(BridgeToolError(
                code: "journal_write_failed",
                message: "scenario journal is not "
                    + "writable; run not started",
                retryable: true))
        }
        let ctx = BridgeScenarioContext(
            runId: runId, descriptor: descriptor,
            params: params, library: library)
        activeCtx = ctx
        activeRun = run
        DiagLog.shared.log(.info,
            "SCENARIO run begin run=\(ctx.shortId) "
            + "scenario=\(descriptor.id)")
        execute(run: run, ctx: ctx,
                steps: BridgeScenarios.mainSteps(
                    for: descriptor.id),
                index: 0)
        return .success(runId)
    }

    // ── 步进 ──

    private func execute(
        run: BridgeScenarioRun,
        ctx: BridgeScenarioContext,
        steps: [BridgeScenarioStep], index: Int) {
        guard index < steps.count else {
            finish(run: run, ctx: ctx, code: "ok")
            return
        }
        if Date() > ctx.deadline {
            finish(run: run, ctx: ctx,
                   code: "run_timeout")
            return
        }
        let step = steps[index]
        ctx.stepStart = Date()
        let t0 = Date()
        step.body(ctx) { [weak self] outcome in
            guard let self else { return }
            let ms = Int(Date()
                .timeIntervalSince(t0) * 1000)
            var record: [String: Any] = [
                "n": ctx.stepRecords.count + 1,
                "kind": step.kind,
                "label": step.label,
                "waitMs": ms,
                "ok": outcome.ok,
                "assertions": outcome.assertions
                    .map { $0.dict },
                "diag": ctx.windowEntries()
                    .filter { e in
                        e.text.hasPrefix("SCENARIO ")
                            || e.text.hasPrefix(
                                "BRIDGE ")
                            || e.text.hasPrefix(
                                "WEATHER ")
                            || e.text.hasPrefix(
                                "OPS ")
                            || e.text.hasPrefix(
                                "DRAG ")
                            || e.text.hasPrefix(
                                "LANG ")
                    }
                    .map { $0.line },
            ]
            if let note = outcome.note {
                record["note"] = note
            }
            ctx.stepRecords.append(record)
            for a in outcome.assertions where !a.pass {
                DiagLog.shared.log(.warn,
                    "SCENARIO assert fail run="
                    + "\(ctx.shortId) "
                    + "name=\(a.name)")
            }
            DiagLog.shared.log(.info,
                "SCENARIO step run=\(ctx.shortId) "
                + "n=\(ctx.stepRecords.count) "
                + "ok=\(outcome.ok ? 1 : 0) "
                + "ms=\(ms)")
            var run = run
            run.stepCursor = ctx.stepRecords.count
            run.updatedAtMs = Library.epochMs()
            self.persist(run: run, ctx: ctx)
            self.activeRun = run
            if outcome.suspend {
                self.suspend(run: run, ctx: ctx)
                return
            }
            guard outcome.ok else {
                self.finish(
                    run: run, ctx: ctx,
                    code: ctx.forcedCode
                        ?? "step_failed")
                return
            }
            DispatchQueue.main.async {
                self.execute(run: run, ctx: ctx,
                             steps: steps,
                             index: index + 1)
            }
        }
    }

    /// journal 写穿：步界/状态迁移即落盘（证据
    /// 累积体随行），进程被杀后 journal 仍是真源。
    private func persist(
        run: BridgeScenarioRun,
        ctx: BridgeScenarioContext) {
        var run = run
        run.fixtureIds = ctx.fixtureIds
        run.stepsJSON = BridgeJSON.stringify(
            ctx.stepRecords) ?? "[]"
        let evidence: [String: Any] = [
            "measurements": ctx.measurements,
            "detail": ctx.detail,
            "conclusion": ctx.conclusion,
        ]
        run.evidenceJSON = BridgeJSON.stringify(
            evidence) ?? "{}"
        BridgeScenarioJournal.upsert(run)
    }

    // ── 挂起与收尾 ──

    private func suspend(
        run: BridgeScenarioRun,
        ctx: BridgeScenarioContext) {
        var run = run
        run.status = "awaiting_manual_reopen"
        run.code = "awaiting_manual_reopen"
        run.updatedAtMs = Library.epochMs()
        persist(run: run, ctx: ctx)
        DiagLog.shared.log(.info,
            "SCENARIO suspend run=\(ctx.shortId) "
            + "phase=awaiting_manual_reopen")
        releaseClaim(ctx)
    }

    private func finish(
        run: BridgeScenarioRun,
        ctx: BridgeScenarioContext, code: String) {
        // M3b 收尾链（方案 §4.1/§4.3）：带夹具
        // 的 run 无论成败先走夹具清理（关在席 →
        // 软删 → 立即真删 → 注销登记），清理落
        // 定后才算 postHash 对账——与驱动清理同
        // 链；无夹具景（M3a）直达收尾，行为不变。
        guard !ctx.fixtureIds.isEmpty else {
            finishAfterCleanup(run: run, ctx: ctx,
                               code: code)
            return
        }
        BridgeScenarioFixtureCleanup.run(ctx: ctx) {
            [weak self] in
            self?.finishAfterCleanup(
                run: run, ctx: ctx, code: code)
        }
    }

    private func finishAfterCleanup(
        run: BridgeScenarioRun,
        ctx: BridgeScenarioContext, code: String) {
        var run = run
        var code = code
        // 清理残留升级（快照线缺陷一）：收尾清
        // 理验净未过（夹具仍在库）是卫生事故，
        // 按终态码优先级（hygiene_failed 高于
        // aborted_user_active/run_timeout/
        // step_failed/ok）升级；场景自定义终态
        // 码（如 language_left_changed）是本场
        // 首要结局、不覆盖，残留仍记 detail +
        // Diag 点名。
        if !ctx.cleanupResidue.isEmpty {
            ctx.detail["cleanupResidue"] =
                ctx.cleanupResidue
            DiagLog.shared.log(.error,
                "SCENARIO hygiene run=\(ctx.shortId) "
                + "cleanupResidue="
                + "\(ctx.cleanupResidue.count)")
            if ["ok", "step_failed", "run_timeout",
                "aborted_user_active"].contains(code) {
                code = "hygiene_failed"
            }
        }
        let postHash = ctx.library.libraryHash()
        run.postLibraryHash = postHash
        // 卫生对账（方案 §4.3）：单会话景全程库
        // 哈希应守恒（M3a 四景均不写库数据），漂
        // 移即全场降格 hygiene_failed；跨重启景
        // 的挂起窗含用户正常使用，只记账不降格。
        if ctx.descriptor.phases == "single" {
            let match = postHash
                == run.preLibraryHash
            DiagLog.shared.log(.info,
                "SCENARIO hygiene run=\(ctx.shortId) "
                + "hashMatch=\(match ? 1 : 0)")
            if !match, code == "ok" {
                code = "hygiene_failed"
            }
        }
        run.code = code
        run.status = code == "ok" ? "done" : "failed"
        run.updatedAtMs = Library.epochMs()
        persist(run: run, ctx: ctx)
        if ctx.snapshotId != nil {
            BridgeWriteSupport.shared
                .recordCompletion(
                    tool: "scenarios_run",
                    idemKey: nil, idemHash: "",
                    payload: [
                        "preDocHash":
                            run.preLibraryHash,
                        "postDocHash": postHash,
                    ])
        }
        DiagLog.shared.log(
            code == "ok" ? .info : .warn,
            "SCENARIO run end run=\(ctx.shortId) "
            + "code=\(code)")
        releaseClaim(ctx)
    }

    private func releaseClaim(
        _ ctx: BridgeScenarioContext) {
        UITestDriver.shared.releaseExternalRun(
            ctx.runId)
        if activeCtx?.runId == ctx.runId {
            activeCtx = nil
            activeRun = nil
        }
    }

    // ── 跨重启续跑（双钩子，方案 §4.2）──
    // 钩子一：BridgeCoordinator.start 尾（via=
    // boot，新进程扫 journal）；钩子二：
    // rescue_try_normal_start 模式翻转点（via=
    // modeflip，同进程回 normal 后通知）。续跑
    // 前先验条件（库就绪/bootMode 与场景预期相
    // 符/会话关系），不符标 failed 并保留证据，
    // 不强行收尾出假结论。

    func resumePendingRuns(
        library: Library, via: String) {
        resumeWhenReady(library: library, via: via,
                        attempt: 0)
    }

    func noteModeFlippedToNormal(library: Library) {
        resumePendingRuns(library: library,
                          via: "modeflip")
    }

    private func resumeWhenReady(
        library: Library, via: String, attempt: Int) {
        // OPS 点名禁桥时桥不启动、场景面不在位：
        // 挂起 run 留待后续钩子，不在此消费。
        guard !BridgeCoordinator.shared.opsDisabled
        else { return }
        guard library.isDbOpen, library.didLoad else {
            if attempt < 120 {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.5) {
                    [weak self] in
                    self?.resumeWhenReady(
                        library: library, via: via,
                        attempt: attempt + 1)
                }
            }
            return
        }
        let awaiting = BridgeScenarioJournal.load()
            .filter {
                $0.status == "awaiting_manual_reopen"
            }
        for run in awaiting {
            evaluateResume(run: run,
                           library: library, via: via,
                           claimTries: 0)
        }
    }

    private func evaluateResume(
        run: BridgeScenarioRun, library: Library,
        via: String, claimTries: Int) {
        var run = run
        let boot = BridgeCoordinator.shared
            .bootSessionId
        if via == "boot",
           run.originBootSessionId == boot {
            return // 同进程，非重开
        }
        if via == "modeflip",
           run.originBootSessionId != boot {
            return // 非本进程挂起的 run
        }
        guard let desc = BridgeScenarioRegistry
            .descriptor(run.scenarioId) else {
            run.status = "failed"
            run.code = "scenario_missing"
            run.updatedAtMs = Library.epochMs()
            BridgeScenarioJournal.upsert(run)
            DiagLog.shared.log(.warn,
                "SCENARIO run end run="
                + "\(String(run.runId.prefix(8))) "
                + "code=scenario_missing")
            return
        }
        // 挂起超 7 天自动过期关单（方案 §2.1）。
        if Library.epochMs() - run.updatedAtMs
            > 7 * 86_400_000 {
            run.status = "expired"
            run.code = "expired"
            run.updatedAtMs = Library.epochMs()
            BridgeScenarioJournal.upsert(run)
            DiagLog.shared.log(.warn,
                "SCENARIO run end run="
                + "\(String(run.runId.prefix(8))) "
                + "code=expired")
            return
        }
        // bootMode 预期：M3a 跨重启景恒预期
        // normal 重开（ops_convergence 的 boot
        // Applied 在安全模式判定下不构成收敛证
        // 据）；modeflip 路径到达此处即已 normal。
        if via == "boot", library.bootIsSafe {
            run.status = "failed"
            run.code = "resume_condition_mismatch"
            run.updatedAtMs = Library.epochMs()
            var evidence = BridgeJSON.parseObject(
                run.evidenceJSON) ?? [:]
            var conclusion = evidence["conclusion"]
                as? [String: Any] ?? [:]
            conclusion["resumeNote"] =
                "reopened in safe mode; scenario "
                + "expected a normal reopen"
            evidence["conclusion"] = conclusion
            run.evidenceJSON = BridgeJSON.stringify(
                evidence) ?? run.evidenceJSON
            BridgeScenarioJournal.upsert(run)
            DiagLog.shared.log(.warn,
                "SCENARIO run end run="
                + "\(String(run.runId.prefix(8))) "
                + "code=resume_condition_mismatch")
            return
        }
        guard activeCtx == nil else {
            retryResumeLater(run: run,
                             library: library, via: via,
                             claimTries: claimTries)
            return
        }
        guard UITestDriver.shared
            .tryClaimExternalRun(run.runId) else {
            retryResumeLater(run: run,
                             library: library, via: via,
                             claimTries: claimTries)
            return
        }
        run.status = "running"
        run.code = "running"
        run.updatedAtMs = Library.epochMs()
        BridgeScenarioJournal.upsert(run)
        let params: [String: Any] = [:]
        let ctx = BridgeScenarioContext(
            runId: run.runId, descriptor: desc,
            params: params, library: library)
        // 证据与步记录从 journal 恢复续排（步号
        // 跨段连续）。
        let evidence = BridgeJSON.parseObject(
            run.evidenceJSON) ?? [:]
        ctx.measurements = evidence["measurements"]
            as? [String: Any] ?? [:]
        ctx.detail = evidence["detail"]
            as? [String: Any] ?? [:]
        ctx.conclusion = evidence["conclusion"]
            as? [String: Any] ?? [:]
        if let data = run.stepsJSON
            .data(using: .utf8),
           let steps = try? JSONSerialization
            .jsonObject(with: data)
            as? [[String: Any]] {
            ctx.stepRecords = steps
        }
        activeCtx = ctx
        activeRun = run
        DiagLog.shared.log(.info,
            "SCENARIO resume run=\(ctx.shortId) "
            + "via=\(via)")
        execute(run: run, ctx: ctx,
                steps: BridgeScenarios.resumeSteps(
                    for: desc.id),
                index: 0)
    }

    /// 互斥被占（驱动/另一景在跑）时延迟重试，
    /// 有界（15 次 × 2s）后留待下个钩子。
    private func retryResumeLater(
        run: BridgeScenarioRun, library: Library,
        via: String, claimTries: Int) {
        guard claimTries < 15 else {
            DiagLog.shared.log(.warn,
                "SCENARIO resume deferred run="
                + "\(String(run.runId.prefix(8))) "
                + "reason=busy")
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2) { [weak self] in
            self?.evaluateResume(
                run: run, library: library, via: via,
                claimTries: claimTries + 1)
        }
    }
}

// ── 夹具收尾清理（M3b，方案 §4.3）──
// 与驱动清理同链：夹具正在编辑器在席时先经
// 导航通道关编辑器，再逐篇走库级清理（待删
// 集内 → 直接真删；在册 → 软删后立即真删），
// 最后注销登记集。引擎 finish 对带夹具的 run
// 无论成败都先走本链再对账（卫生口径的落点）。
// 逐篇验净（快照线缺陷一补）：清理后回读全集
// 确认消失才注销登记；残留点名记入 ctx 并由
// finish 升级终态 hygiene_failed。

enum BridgeScenarioFixtureCleanup {

    static func run(
        ctx: BridgeScenarioContext,
        completion: @escaping () -> Void) {
        let seated = EditorSeatRegistry.shared
            .currentMemoId
        if let seated,
           ctx.fixtureIds.contains(seated) {
            BridgeNavigationChannel.shared
                .requestClose { _ in
                    sweep(ctx: ctx)
                    completion()
                }
        } else {
            sweep(ctx: ctx)
            completion()
        }
    }

    static func sweep(ctx: BridgeScenarioContext) {
        for id in ctx.fixtureIds {
            if ctx.library
                .pendingDeletions[id] != nil {
                ctx.library
                    .commitPendingDeletion(id: id)
            } else if let item = ctx.library.memos
                .first(where: { $0.id == id }) {
                ctx.library.softRemove(item)
                ctx.library
                    .commitPendingDeletion(id: id)
            }
            // 验净（快照线缺陷一，与驱动清理
            // cleanupFixture 同口径）：删除动作做
            // 过 ≠ 夹具已消失——逐篇以全集回读验
            // 净，确认消失才注销登记 + 记清理行；
            // 仍在者记残留（ctx.cleanupResidue，
            // 终态升级 hygiene_failed 的判据）且
            // 不注销登记，残留对夹具卫生网保持
            // 可见。旧形态无条件注销 + 恒记成功
            // 行，残留自此不可见、静默留库。
            let gone = !BridgeReadTools
                .allMemos(ctx.library)
                .contains { $0.id == id }
            if gone {
                UITestFixture.unregister(id)
                DiagLog.shared.log(.info,
                    "SCENARIO fixture cleanup "
                    + "id=\(id)")
            } else {
                ctx.cleanupResidue.append(id)
                DiagLog.shared.log(.error,
                    "SCENARIO fixture cleanup "
                    + "RESIDUE id=\(id)")
            }
        }
    }
}

// ── 场景实装（M3a 四景 + M3b 写景，方案
// §2.1/§2.2）──

enum BridgeScenarios {

    static func mainSteps(
        for id: String) -> [BridgeScenarioStep] {
        switch id {
        case "drag_trace_review":
            return dragTraceReviewSteps()
        case "weather_settings_flow":
            return weatherSettingsFlowSteps()
        case "ops_convergence":
            return opsConvergenceMainSteps()
        case "language_roundtrip":
            return languageRoundtripSteps()
        case "delete_restore_roundtrip":
            return deleteRestoreSteps()
        case "drag_semantic_reorder":
            return dragSemanticReorderSteps()
        case "create_transition":
            return createTransitionSteps()
        case "snapshot_restore_drill":
            return snapshotRestoreDrillSteps()
        case "snapshot_pending_window_restore":
            return snapshotPendingWindowRestoreSteps()
        default:
            return []
        }
    }

    static func resumeSteps(
        for id: String) -> [BridgeScenarioStep] {
        switch id {
        case "ops_convergence":
            return opsConvergenceResumeSteps()
        default:
            return []
        }
    }

    /// settingsGet 的天气段（双 key 的 state/
    /// source，永不含 key 值——沿 settings_get
    /// 既定口径）。
    private static func weatherDict(
    ) -> [String: Any] {
        BridgeSettingsTools.settingsGet(
            coordinator: BridgeCoordinator.shared
        )["weather"] as? [String: Any] ?? [:]
    }

    private static func setHash(
        _ set: [String: Any]) -> String {
        BridgeCanonical.sha256Hex(set) ?? ""
    }

    // ── drag_trace_review（read，无夹具）──
    // 引擎内直读 DRAG 行归组判链路完整性；收集
    // 与归组解析与 metrics_drag_trace 工具共用
    // BridgeDragTraceParser.collect/parse 单一
    // 来源（矩阵 §5 禁双轨，U3 出货时切换点已
    // 兑现——景与工具同入参同解析，见 §4.13）。

    private static func dragTraceReviewSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "measureInternal",
                label: "collect + group DRAG lines"
            ) { ctx, done in
                let entries = BridgeDragTraceParser
                    .collect(ctx.params)
                let limit = min(500, max(1,
                    (ctx.params["limit"] as? NSNumber)?
                        .intValue ?? 200))
                let parsed = BridgeDragTraceParser
                    .parse(entries)
                ctx.measurements["drag"] =
                    parsed.summary
                ctx.detail["attempts"] =
                    parsed.attempts
                ctx.detail["rawLines"] =
                    BridgeDragTraceParser
                        .guardedRawLines(
                            entries, limit: limit)
                ctx.conclusion = parsed.conclusion
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "drag_lines_present",
                        pass: !entries.isEmpty,
                        expected: ">0",
                        actual: "\(entries.count)"),
                ]
                if entries.isEmpty {
                    out.note = "窗口内无拖拽记录"
                        + "（空结论，不判失败）"
                }
                done(out)
            },
        ]
    }

    // ── weather_settings_flow（read，无夹具）──
    // 前读 key 状态 → 既有刷新路径触发一次 →
    // 后读对比。刷新成败受外部额度/网络支配，
    // 与状态回读链分开判（方案 §2.1）：provider
    // 失败如实回签名，不把整场判红。

    private static func weatherSettingsFlowSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "callInternal",
                label: "read weather key states "
                    + "(before)") { ctx, done in
                let w = weatherDict()
                ctx.scratch["weatherBefore"] = w
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "weather_keys_present",
                        pass: w["qweather"] != nil
                            && w["caiyun"] != nil,
                        expected: "qweather+caiyun",
                        actual: "\(w.keys.sorted())"),
                ]
                done(out)
            },
            BridgeScenarioStep(
                kind: "invokeService",
                label: "trigger refresh + observe "
                    + "terminal WEATHER event"
            ) { ctx, done in
                ctx.stepStart = Date()
                // 缓存命中路在 refreshIfNeeded 内
                // 同步落 now；抓调用前后的 now 在
                // 位与否判路径（fetch 路有 1.5s
                // 延迟 + 网络往返，now 不会同步出）。
                let hadNow = WeatherService.shared
                    .now != nil
                WeatherService.shared
                    .refreshIfNeeded()
                let cachePath = !hadNow
                    && WeatherService.shared.now != nil
                if cachePath {
                    ctx.measurements["weather"] = [
                        "refreshPath": "cache",
                        "refreshOutcome": "cache_hit",
                    ]
                    done(BridgeScenarioStepOutcome())
                    return
                }
                var terminal: String?
                ctx.poll(timeoutMs: 30_000) {
                    for e in ctx.windowEntries()
                    where e.text.hasPrefix("WEATHER ")
                    {
                        if e.text.hasPrefix(
                            "WEATHER fetched") {
                            terminal = e.text.contains(
                                "provider=qweather")
                                ? "fetched_qweather"
                                : "fetched_caiyun"
                        } else if e.text.hasPrefix(
                            "WEATHER provider=fail") {
                            terminal = "provider_fail"
                        } else if e.text.hasPrefix(
                            "WEATHER no api key") {
                            terminal = "no_api_key"
                        } else if e.text.hasPrefix(
                            "WEATHER locate failed") {
                            terminal = "locate_failed"
                        }
                        if terminal != nil {
                            return true
                        }
                    }
                    return false
                } done: { ok in
                    var out =
                        BridgeScenarioStepOutcome()
                    let lines = ctx.windowEntries()
                        .filter {
                            $0.text.hasPrefix(
                                "WEATHER ")
                        }
                        .map { $0.line }
                    ctx.measurements["weather"] = [
                        "refreshPath": "fetch",
                        "refreshOutcome":
                            terminal ?? "unobserved",
                        "weatherLines": lines,
                    ]
                    if !ok {
                        out.ok = false
                        out.note = "30s 内无终局 "
                            + "WEATHER 事件（刷新链"
                            + "未落定）"
                    }
                    done(out)
                }
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "read weather key states "
                    + "(after) + assert unchanged"
            ) { ctx, done in
                let after = weatherDict()
                let before = ctx.scratch[
                    "weatherBefore"]
                    as? [String: Any] ?? [:]
                let same = setHash(before)
                    == setHash(after)
                ctx.detail["weatherBefore"] = before
                ctx.detail["weatherAfter"] = after
                let m = ctx.measurements["weather"]
                    as? [String: Any] ?? [:]
                ctx.conclusion = [
                    "stateChain": "proven",
                    "refreshOutcome":
                        m["refreshOutcome"]
                        as? String ?? "unobserved",
                    "keyStatesUnchanged": same,
                ]
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "key_states_unchanged",
                        pass: same,
                        expected: "before == after",
                        actual: same ? "equal"
                            : "diverged"),
                ]
                done(out)
            },
        ]
    }

    // ── ops_convergence（ops，跨重启）──
    // A 段：读三层 → 直拉双源（与 ops_refresh 同
    // 一条 fetchWithOutcome 链——fetchFrom 为
    // OpsDirectives 私有，场景不另写拉取实现，
    // sanitize/落缓存口径天然同源）→ 校验缓存已
    // 收敛到源头 → 挂起。B 段（重开后）：boot
    // Applied 与源头哈希比对关单。

    private static func opsConvergenceMainSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "callInternal",
                label: "read effective (before)"
            ) { ctx, done in
                let eff = BridgeOpsTools
                    .opsGetEffective(
                        library: ctx.library)
                let cache = eff["currentCache"]
                    as? [String: Any] ?? [:]
                ctx.scratch["cacheBefore"] = cache
                ctx.scratch["bootAppliedBefore"] =
                    eff["bootApplied"]
                done(BridgeScenarioStepOutcome())
            },
            BridgeScenarioStep(
                kind: "invokeService",
                label: "fetch dual sources"
            ) { ctx, done in
                ctx.stepStart = Date()
                OpsDirectives.shared
                    .fetchWithOutcome { outcome in
                    DispatchQueue.main.async {
                        let fetched =
                            OpsDirectives.shared
                                .current
                        let sourceHash = setHash(
                            BridgeOpsFormat.setDict(
                                fetched))
                        let fetchedLine = DiagLog
                            .shared.today.last(
                                where: {
                                    $0.text.hasPrefix(
                                        "OPS directives fetched")
                                })?.text ?? ""
                        var phaseA: [String: Any] = [
                            "sourceHash": sourceHash,
                            "successSource":
                                outcome.successSource,
                            "failures":
                                outcome.failures,
                            "fetchedLine": fetchedLine,
                        ]
                        if let expected =
                            ctx.params["expectedHash"]
                                as? String {
                            phaseA["expectedHash"] =
                                expected
                        }
                        ctx.detail["phaseA"] = phaseA
                        var out =
                            BridgeScenarioStepOutcome()
                        out.assertions = [
                            UITestAssertion(
                                name: "fetch_succeeded",
                                pass: !outcome
                                    .successSource
                                    .isEmpty,
                                expected: "a source",
                                actual: outcome
                                    .successSource
                                    .isEmpty
                                    ? "all failed: "
                                        + outcome
                                            .failures
                                            .joined(
                                                separator: ",")
                                    : outcome
                                        .successSource),
                        ]
                        if let expected =
                            ctx.params["expectedHash"]
                                as? String {
                            out.assertions.append(
                                UITestAssertion(
                                    name: "expected_hash"
                                        + "_matches",
                                    pass: sourceHash
                                        == expected,
                                    expected: expected,
                                    actual: sourceHash))
                        }
                        if !outcome.successSource
                            .isEmpty,
                           let expected =
                            ctx.params["expectedHash"]
                                as? String,
                           sourceHash != expected {
                            out.ok = false
                            out.note = "源头哈希与 "
                                + "expectedHash 不符，"
                                + "前提已破，不挂起"
                        }
                        if outcome.successSource
                            .isEmpty {
                            out.ok = false
                            out.note = "双源拉取全失败"
                        }
                        done(out)
                    }
                }
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "cache converged to source"
            ) { ctx, done in
                let phaseA = ctx.detail["phaseA"]
                    as? [String: Any] ?? [:]
                let sourceHash = phaseA["sourceHash"]
                    as? String ?? ""
                let cacheHash = setHash(
                    BridgeOpsFormat.setDict(
                        OpsDirectives.cached()))
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "cache_matches_source",
                        pass: cacheHash == sourceHash,
                        expected: sourceHash,
                        actual: cacheHash),
                ]
                out.ok = cacheHash == sourceHash
                done(out)
            },
            BridgeScenarioStep(
                kind: "suspend",
                label: "suspend awaiting manual "
                    + "reopen") { _, done in
                var out = BridgeScenarioStepOutcome()
                out.suspend = true
                done(out)
            },
        ]
    }

    private static func opsConvergenceResumeSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "callInternal",
                label: "verify bootApplied after "
                    + "reopen") { ctx, done in
                let phaseA = ctx.detail["phaseA"]
                    as? [String: Any] ?? [:]
                let sourceHash = phaseA["sourceHash"]
                    as? String ?? ""
                let eff = BridgeOpsTools
                    .opsGetEffective(
                        library: ctx.library)
                let bootSet = eff["bootApplied"]
                    as? [String: Any] ?? [:]
                let cacheSet = (eff["currentCache"]
                    as? [String: Any])?["set"]
                    as? [String: Any] ?? [:]
                let bootHash = setHash(bootSet)
                let cacheHash = setHash(cacheSet)
                let converged = eff["converged"]
                    as? Bool ?? false
                ctx.measurements["ops"] = [
                    "sourceHash": sourceHash,
                    "cacheHash": cacheHash,
                    "bootAppliedHash": bootHash,
                    "converged": converged,
                ]
                ctx.detail["launchLines"] =
                    DiagLog.shared.today
                        .filter {
                            $0.text.hasPrefix(
                                "LAUNCH ")
                        }
                        .suffix(10).map { $0.line }
                let allMatch = bootHash == sourceHash
                    && cacheHash == sourceHash
                ctx.conclusion = [
                    "verdict": allMatch
                        ? "converged" : "diverged",
                    "threeLayerHashMatch": allMatch,
                ]
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "boot_applied_matches"
                            + "_source",
                        pass: bootHash == sourceHash,
                        expected: sourceHash,
                        actual: bootHash),
                    UITestAssertion(
                        name: "cache_matches_source",
                        pass: cacheHash == sourceHash,
                        expected: sourceHash,
                        actual: cacheHash),
                ]
                out.ok = allMatch
                if !allMatch {
                    out.note = "三层哈希未一致（见 "
                        + "measurements.ops 对照表）"
                }
                done(out)
            },
        ]
    }

    // ── language_roundtrip（write，无夹具）──
    // 前读 → 写前快照（数据写纪律，方案 §4.3）
    // → 内部同路切目标码 → 生效码双路验 → 切回
    // 原码 → 再验。切回失败红标 language_left_
    // changed（不静默留改动，方案 §2.1）。

    private static func languageRoundtripSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "callInternal",
                label: "read current language"
            ) { ctx, done in
                let lang = BridgeSettingsTools
                    .settingsGet(
                        coordinator:
                            BridgeCoordinator.shared
                    )["language"]
                    as? [String: Any] ?? [:]
                ctx.scratch["origPreference"] =
                    lang["preference"] as? String
                        ?? "system"
                ctx.scratch["origResolved"] =
                    lang["resolved"] as? String
                        ?? LangStore.shared.code
                ctx.scratch["target"] =
                    ctx.params["code"] as? String
                        ?? "zh-CN"
                done(BridgeScenarioStepOutcome())
            },
            BridgeScenarioStep(
                kind: "invokeService",
                label: "snapshot before write"
            ) { ctx, done in
                var out = BridgeScenarioStepOutcome()
                switch BridgeWriteSupport.shared
                    .ensureSnapshot(
                        library: ctx.library,
                        args: ["idempotencyKey":
                            "scenario:\(ctx.runId)"],
                        reason:
                            "scenario:language_roundtrip",
                        force: false) {
                case .success(let snap):
                    ctx.snapshotId = snap
                case .failure(let e):
                    out.ok = false
                    out.note = "snapshot failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "set target language + verify"
            ) { ctx, done in
                let target = ctx.scratch["target"]
                    as? String ?? "zh-CN"
                var out = BridgeScenarioStepOutcome()
                switch BridgeSettingsTools.setLanguage(
                    ["code": target,
                     "idempotencyKey":
                        "scenario:\(ctx.runId):set"]) {
                case .success(let p):
                    let resolved = p["resolved"]
                        as? String ?? ""
                    let appLang = BridgeReadTools
                        .appState(
                            library: ctx.library
                        )["lang"] as? String ?? ""
                    out.assertions = [
                        UITestAssertion(
                            name: "resolved_is_target",
                            pass: resolved == target,
                            expected: target,
                            actual: resolved),
                        UITestAssertion(
                            name: "app_state_lang_is"
                                + "_target",
                            pass: appLang == target,
                            expected: target,
                            actual: appLang),
                    ]
                    out.ok = resolved == target
                        && appLang == target
                case .failure(let e):
                    out.ok = false
                    out.note = "setLanguage failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "restore original language "
                    + "+ verify") { ctx, done in
                let pref = ctx.scratch["origPreference"]
                    as? String ?? "system"
                let origResolved = ctx.scratch[
                    "origResolved"] as? String ?? ""
                var out = BridgeScenarioStepOutcome()
                switch BridgeSettingsTools.setLanguage(
                    ["code": pref,
                     "idempotencyKey":
                        "scenario:\(ctx.runId):restore"]
                ) {
                case .success(let p):
                    let resolved = p["resolved"]
                        as? String ?? ""
                    let restored =
                        resolved == origResolved
                    out.assertions = [
                        UITestAssertion(
                            name: "resolved_restored",
                            pass: restored,
                            expected: origResolved,
                            actual: resolved),
                    ]
                    if !restored {
                        ctx.forcedCode =
                            "language_left_changed"
                        ctx.conclusion = [
                            "languageLeftChanged": true,
                            "currentCode": resolved,
                            "note": "切回原码未生效；"
                                + "请在设置页手动切回",
                        ]
                        out.ok = false
                    }
                case .failure(let e):
                    ctx.forcedCode =
                        "language_left_changed"
                    ctx.conclusion = [
                        "languageLeftChanged": true,
                        "currentCode":
                            LangStore.shared.code,
                        "note": "切回失败（\(e.code)）；"
                            + "请在设置页手动切回",
                    ]
                    out.ok = false
                }
                done(out)
            },
        ]
    }

    // ── M3b 写景共用件 ──

    /// 写前快照步（写景共用，方案 §4.3）：经写
    /// 底座会话级快照入口取一份，reason 记场景
    /// id；失败即停场。各写工具内部同路亦经同
    /// 一入口（同会话同前缀复用一份）。
    private static func snapshotStep(
        _ scenarioId: String) -> BridgeScenarioStep {
        BridgeScenarioStep(
            kind: "invokeService",
            label: "snapshot before write"
        ) { ctx, done in
            var out = BridgeScenarioStepOutcome()
            switch BridgeWriteSupport.shared
                .ensureSnapshot(
                    library: ctx.library,
                    args: ["idempotencyKey":
                        "scenario:\(ctx.runId)"],
                    reason: "scenario:\(scenarioId)",
                    force: false) {
            case .success(let snap):
                ctx.snapshotId = snap
            case .failure(let e):
                out.ok = false
                out.note = "snapshot failed: "
                    + e.code
            }
            done(out)
        }
    }

    /// 夹具建篇（与驱动 setup 同路，方案 §4.3
    /// 共用登记集）：create() 建篇（内置空模
    /// 板）→ 标题打自检标记 → 可选模板块集替
    /// 换 → persist → 登记集登记。模板正文为
    /// App 内置（UITestFixtureTemplate），永不
    /// 经中继（方案 §5.3）。
    @discardableResult
    private static func createFixture(
        _ ctx: BridgeScenarioContext,
        kind: UITestFixtureKind?,
        suffix: String) -> String? {
        let item = ctx.library.create()
        guard ctx.library.memos.contains(
            where: { $0.id == item.id }) else {
            return nil
        }
        var titled = item
        titled.title = UITestFixture.titleMark
            + String(ctx.runId.prefix(4)) + suffix
        if let kind,
           let built = UITestFixtureTemplate
            .build(kind) {
            titled.blocks = built.blocks
        }
        ctx.library.persist(titled)
        UITestFixture.register(item.id)
        ctx.fixtureIds.append(item.id)
        DiagLog.shared.log(.info,
            "SCENARIO fixture create id=\(item.id)")
        return item.id
    }

    /// 夹具当前条目（全集口径：列表 + 待删集，
    /// 与桥读面同一全集函数）。
    private static func fixtureItem(
        _ ctx: BridgeScenarioContext,
        _ memoId: String) -> MemoItem? {
        BridgeReadTools.allMemos(ctx.library)
            .first { $0.id == memoId }
    }

    private static func fixtureDocHash(
        _ ctx: BridgeScenarioContext,
        _ memoId: String) -> String {
        fixtureItem(ctx, memoId).flatMap {
            BridgeDocHash.of($0)
        } ?? ""
    }

    /// 块序证据（只 id/type 序列，方案 §5.3）：
    /// 经库镜像回读——与桥块序回读同一资料源。
    private static func fixtureBlockOrder(
        _ ctx: BridgeScenarioContext,
        _ memoId: String) -> [[String: Any]] {
        fixtureItem(ctx, memoId)?.blocks.map {
            ["id": $0.id, "type": $0.type]
                as [String: Any]
        } ?? []
    }

    private static func orderIds(
        _ order: [[String: Any]]) -> [String] {
        order.map { $0["id"] as? String ?? "" }
    }

    /// 软删步（删除恢复景主链共用）：expected
    /// DocHash 以调用前回读为准（docHash 守卫
    /// 同路），成功后断言待删登记 + 列表摘除。
    private static func softDeleteStep(
        label: String, keySuffix: String,
        detailKey: String) -> BridgeScenarioStep {
        BridgeScenarioStep(
            kind: "callInternal", label: label
        ) { ctx, done in
            let id = ctx.scratch["fixtureId"]
                as? String ?? ""
            var out = BridgeScenarioStepOutcome()
            switch BridgeWriteTools.softDelete(
                ["memoId": id,
                 "idempotencyKey":
                    "scenario:\(ctx.runId)"
                    + ":\(keySuffix)",
                 "expectedDocHash":
                    fixtureDocHash(ctx, id)],
                library: ctx.library) {
            case .success(let p):
                ctx.detail[detailKey] = [
                    "deletedAtMs":
                        p["deletedAtMs"] ?? NSNull(),
                    "undoExpiresAtMs":
                        p["undoExpiresAtMs"]
                            ?? NSNull(),
                    "postDocHash":
                        p["postDocHash"] ?? "",
                ]
                let pending = ctx.library
                    .pendingDeletions[id] != nil
                let absent = !ctx.library.memos
                    .contains { $0.id == id }
                out.assertions = [
                    UITestAssertion(
                        name: "pending_registered",
                        pass: pending,
                        expected: "in pending set",
                        actual: pending
                            ? "pending" : "missing"),
                    UITestAssertion(
                        name: "absent_from_list",
                        pass: absent,
                        expected: "not in memos",
                        actual: absent
                            ? "absent" : "present"),
                ]
                out.ok = pending && absent
            case .failure(let e):
                out.ok = false
                out.note = "softDelete failed: "
                    + e.code
            }
            done(out)
        }
    }

    /// 关编辑器步（导航通道同路）：无在席即现状
    /// 成功；通道失败如实回码，不假成功。
    private static func closeEditorStep(
        label: String) -> BridgeScenarioStep {
        BridgeScenarioStep(
            kind: "invokeService", label: label
        ) { ctx, done in
            BridgeNavigationChannel.shared
                .requestClose { result in
                var out = BridgeScenarioStepOutcome()
                switch result {
                case .success:
                    let seated = EditorSeatRegistry
                        .shared.currentMemoId
                    out.assertions = [
                        UITestAssertion(
                            name: "editor_unseated",
                            pass: seated == nil,
                            expected: "none",
                            actual: seated ?? "none"),
                    ]
                    out.ok = seated == nil
                case .failure(let e):
                    out.ok = false
                    out.note = "requestClose "
                        + "failed: \(e.code)"
                }
                done(out)
            }
        }
    }

    // ── delete_restore_roundtrip（write，整场
    // 两段；夹具，方案 §2.2）──
    // 软删 → 恢复守卫（待删集最近一篇须为夹具
    // 本篇才恢复——恢复只认最近一篇，用户若在
    // 间隙软删了自己的笔记，守卫不过即中止该
    // 段，绝不替用户恢复错篇）→ 恢复后 docHash
    // 回读 → 再软删 → 等 8 秒窗口自动真删 →
    // 回读全集确认。可选永删段：另一夹具软删
    // 后经永删内部同路真删，段内另验 ops
    // scope（描述符 scopes 只声明 write，ops
    // 为段级门，方案 §2.2 表注记）。

    private static func deleteRestoreSteps()
        -> [BridgeScenarioStep] {
        [
            snapshotStep(
                "delete_restore_roundtrip"),
            BridgeScenarioStep(
                kind: "invokeService",
                label: "create fixture (empty "
                    + "template)") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard let id = createFixture(
                    ctx, kind: nil, suffix: "删恢")
                else {
                    out.ok = false
                    out.note = "fixture create did "
                        + "not land in the library"
                    done(out)
                    return
                }
                ctx.scratch["fixtureId"] = id
                let hash = fixtureDocHash(ctx, id)
                ctx.scratch["docHash0"] = hash
                out.assertions = [
                    UITestAssertion(
                        name: "fixture_registered",
                        pass: ctx.fixtureGuard(id),
                        expected: "in fixture "
                            + "registry",
                        actual: id),
                    UITestAssertion(
                        name: "doc_hash_present",
                        pass: !hash.isEmpty,
                        expected: "non-empty",
                        actual: hash),
                ]
                out.ok = ctx.fixtureGuard(id)
                    && !hash.isEmpty
                done(out)
            },
            softDeleteStep(
                label: "soft delete fixture",
                keySuffix: "soft1",
                detailKey: "softDelete1"),
            BridgeScenarioStep(
                kind: "assert",
                label: "restore guard: fixture "
                    + "is most recent pending"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let latest = ctx.library
                    .pendingDeletion?.id ?? ""
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "fixture_is_latest"
                            + "_pending",
                        pass: latest == id,
                        expected: id,
                        actual: latest),
                ]
                out.ok = latest == id
                if latest != id {
                    ctx.conclusion["restoreGuard"] =
                        "blocked"
                    out.note = "最近待删非夹具（疑"
                        + "用户间隙软删了自己的笔"
                        + "记），中止恢复段；夹具由"
                        + "收尾链清理"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "restore fixture + verify "
                    + "docHash") { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let hash0 = ctx.scratch["docHash0"]
                    as? String ?? ""
                var out = BridgeScenarioStepOutcome()
                switch BridgeWriteTools.restoreDeleted(
                        ["memoId": id,
                         "idempotencyKey":
                            "scenario:\(ctx.runId)"
                            + ":restore"],
                        library: ctx.library) {
                case .success(let p):
                    let post = p["postDocHash"]
                        as? String ?? ""
                    let back = ctx.library.memos
                        .contains { $0.id == id }
                    let hashBack = fixtureDocHash(
                        ctx, id)
                    ctx.detail["restore"] = [
                        "postDocHash": post,
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "back_in_list",
                            pass: back,
                            expected: "in memos",
                            actual: back
                                ? "present" : "missing"),
                        UITestAssertion(
                            name: "doc_hash_restored",
                            pass: post == hash0
                                && hashBack == hash0,
                            expected: hash0,
                            actual: hashBack),
                    ]
                    out.ok = back
                        && post == hash0
                        && hashBack == hash0
                case .failure(let e):
                    out.ok = false
                    out.note = "restore failed: "
                        + e.code
                }
                done(out)
            },
            softDeleteStep(
                label: "soft delete fixture again",
                keySuffix: "soft2",
                detailKey: "softDelete2"),
            BridgeScenarioStep(
                kind: "waitDiag",
                label: "undo window expiry "
                    + "commits deletion"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                ctx.poll(timeoutMs: 15_000) {
                    ctx.library
                        .pendingDeletions[id] == nil
                        && fixtureItem(ctx, id)
                            == nil
                } done: { ok in
                    var out =
                        BridgeScenarioStepOutcome()
                    out.assertions = [
                        UITestAssertion(
                            name: "truly_deleted"
                                + "_after_window",
                            pass: ok,
                            expected: "absent "
                                + "everywhere",
                            actual: ok
                                ? "absent"
                                : "still present"),
                    ]
                    out.ok = ok
                    if !ok {
                        out.note = "窗口过后夹具仍"
                            + "在（自动真删未落定）"
                    }
                    done(out)
                }
            },
            BridgeScenarioStep(
                kind: "invokeService",
                label: "permanent segment: "
                    + "create fixture 2"
            ) { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard permanentEnabled(ctx) else {
                    out.note = "permanent segment "
                        + "skipped (includePermanent"
                        + " not set)"
                    done(out)
                    return
                }
                guard let id = createFixture(
                    ctx, kind: nil, suffix: "永删")
                else {
                    out.ok = false
                    out.note = "fixture 2 create "
                        + "did not land"
                    done(out)
                    return
                }
                ctx.scratch["fixture2Id"] = id
                out.assertions = [
                    UITestAssertion(
                        name: "fixture2_registered",
                        pass: ctx.fixtureGuard(id),
                        expected: "in fixture "
                            + "registry",
                        actual: id),
                ]
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "permanent segment: soft "
                    + "delete fixture 2"
            ) { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard permanentEnabled(ctx) else {
                    out.note = "permanent segment "
                        + "skipped"
                    done(out)
                    return
                }
                let id = ctx.scratch["fixture2Id"]
                    as? String ?? ""
                switch BridgeWriteTools.softDelete(
                    ["memoId": id,
                     "idempotencyKey":
                        "scenario:\(ctx.runId)"
                        + ":soft3",
                     "expectedDocHash":
                        fixtureDocHash(ctx, id)],
                    library: ctx.library) {
                case .success:
                    let pending = ctx.library
                        .pendingDeletions[id] != nil
                    out.assertions = [
                        UITestAssertion(
                            name: "fixture2_pending",
                            pass: pending,
                            expected: "in pending set",
                            actual: pending
                                ? "pending" : "missing"),
                    ]
                    out.ok = pending
                case .failure(let e):
                    out.ok = false
                    out.note = "softDelete (fixture"
                        + " 2) failed: \(e.code)"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "permanent segment: delete "
                    + "permanently") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard permanentEnabled(ctx) else {
                    out.note = "permanent segment "
                        + "skipped"
                    done(out)
                    return
                }
                guard BridgeCoordinator.shared
                    .scopes.contains("ops") else {
                    out.ok = false
                    out.note = "permanent segment "
                        + "requires ops scope "
                        + "(segment-level gate)"
                    done(out)
                    return
                }
                let id = ctx.scratch["fixture2Id"]
                    as? String ?? ""
                guard let pending = ctx.library
                    .pendingDeletions[id] else {
                    out.ok = false
                    out.note = "fixture 2 not in "
                        + "pending set"
                    done(out)
                    return
                }
                let pendingHash = BridgeDocHash
                    .of(pending.item) ?? ""
                switch BridgeWriteTools.deletePermanent(
                        ["memoId": id,
                         "idempotencyKey":
                            "scenario:\(ctx.runId)"
                            + ":permdel",
                         "confirmMemoId": id,
                         "expectedDocHash":
                            pendingHash],
                        library: ctx.library) {
                case .success(let p):
                    let gone = fixtureItem(ctx, id)
                        == nil
                    ctx.detail["permanentDelete"] = [
                        "preDocHash": pendingHash,
                        "postDocHash":
                            p["postDocHash"] ?? "",
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "gone_everywhere",
                            pass: gone,
                            expected: "absent "
                                + "everywhere",
                            actual: gone
                                ? "absent"
                                : "still present"),
                    ]
                    out.ok = gone
                case .failure(let e):
                    out.ok = false
                    out.note = "deletePermanent "
                        + "failed: \(e.code)"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "compose conclusion"
            ) { ctx, done in
                ctx.conclusion = [
                    "verdict": "roundtrip_complete",
                    "permanentSegment":
                        permanentEnabled(ctx)
                            ? "executed" : "skipped",
                    "restoreGuard":
                        ctx.conclusion["restoreGuard"]
                            as? String ?? "passed",
                ]
                done(BridgeScenarioStepOutcome())
            },
        ]
    }

    private static func permanentEnabled(
        _ ctx: BridgeScenarioContext) -> Bool {
        (ctx.params["includePermanent"]
            as? Bool) == true
    }

    // ── drag_semantic_reorder（write，夹具，
    // 方案 §2.2）──
    // 多块夹具（复用驱动多块模板，登记集共用）
    // → 移块内部同路两次（首块→尾、中间相邻
    // 两块互换）→ 库镜像回读块序逐字断言 → 关
    // 编辑器（保未在席）→ 导航通道重开 → 在席
    // 块序再回读 → 关编辑器。证据只载 id/type
    // 块序与 docHash 链；真实拾起/识别器不在
    // 本景证据面（grades 已声明 unknown）。

    private static func performMove(
        _ ctx: BridgeScenarioContext,
        keySuffix: String, blockId: String,
        toIndex: Int?, beforeBlockId: String?
    ) -> Result<[String: Any], BridgeToolError> {
        let id = ctx.scratch["fixtureId"]
            as? String ?? ""
        var args: [String: Any] = [
            "memoId": id,
            "idempotencyKey":
                "scenario:\(ctx.runId)"
                + ":\(keySuffix)",
            "expectedDocHash":
                fixtureDocHash(ctx, id),
            "blockId": blockId,
        ]
        if let toIndex { args["toIndex"] = toIndex }
        if let beforeBlockId {
            args["beforeBlockId"] = beforeBlockId
        }
        return BridgeWriteTools.moveBlock(
            args, library: ctx.library)
    }

    private static func dragSemanticReorderSteps()
        -> [BridgeScenarioStep] {
        [
            snapshotStep("drag_semantic_reorder"),
            BridgeScenarioStep(
                kind: "invokeService",
                label: "create multi-block fixture"
            ) { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard let id = createFixture(
                    ctx, kind: .blocks,
                    suffix: "重排") else {
                    out.ok = false
                    out.note = "fixture create did "
                        + "not land in the library"
                    done(out)
                    return
                }
                ctx.scratch["fixtureId"] = id
                let order = fixtureBlockOrder(
                    ctx, id)
                ctx.detail["initialOrder"] = order
                let types = Set(order.map {
                    $0["type"] as? String ?? ""
                })
                out.assertions = [
                    UITestAssertion(
                        name: "block_count_ge_4",
                        pass: order.count >= 4,
                        expected: ">=4",
                        actual: "\(order.count)"),
                    UITestAssertion(
                        name: "multi_type",
                        pass: types.count >= 4,
                        expected: ">=4 types",
                        actual: "\(types.count)"),
                ]
                out.ok = order.count >= 4
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "move first block to tail"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let ids = orderIds(
                    fixtureBlockOrder(ctx, id))
                var out = BridgeScenarioStepOutcome()
                guard ids.count >= 4 else {
                    out.ok = false
                    out.note = "fixture block "
                        + "count < 4"
                    done(out)
                    return
                }
                var expected = ids
                let first = expected.removeFirst()
                expected.append(first)
                switch performMove(
                    ctx, keySuffix: "move1",
                    blockId: first,
                    toIndex: ids.count - 1,
                    beforeBlockId: nil) {
                case .success(let p):
                    let got = p["blockOrder"]
                        as? [String] ?? []
                    ctx.scratch["expectedOrder"] =
                        expected
                    ctx.detail["docHashAfterMove1"] =
                        p["postDocHash"] ?? ""
                    out.assertions = [
                        UITestAssertion(
                            name: "order_after_move1",
                            pass: got == expected,
                            expected: expected.joined(
                                separator: ","),
                            actual: got.joined(
                                separator: ",")),
                    ]
                    out.ok = got == expected
                case .failure(let e):
                    out.ok = false
                    out.note = "moveBlock (first "
                        + "to tail) failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "swap middle pair"
            ) { ctx, done in
                let prev = ctx.scratch[
                    "expectedOrder"] as? [String]
                    ?? []
                var out = BridgeScenarioStepOutcome()
                guard prev.count >= 4 else {
                    out.ok = false
                    out.note = "no expected order "
                        + "from move 1"
                    done(out)
                    return
                }
                var expected = prev
                expected.swapAt(1, 2)
                // 把当前第 3 块移到第 2 块之前，
                // 即中间相邻两块互换（一次移动）。
                switch performMove(
                    ctx, keySuffix: "move2",
                    blockId: prev[2],
                    toIndex: nil,
                    beforeBlockId: prev[1]) {
                case .success(let p):
                    let got = p["blockOrder"]
                        as? [String] ?? []
                    ctx.scratch["expectedOrder"] =
                        expected
                    ctx.detail["docHashAfterMove2"] =
                        p["postDocHash"] ?? ""
                    out.assertions = [
                        UITestAssertion(
                            name: "order_after_move2",
                            pass: got == expected,
                            expected: expected.joined(
                                separator: ","),
                            actual: got.joined(
                                separator: ",")),
                    ]
                    out.ok = got == expected
                case .failure(let e):
                    out.ok = false
                    out.note = "moveBlock (swap) "
                        + "failed: \(e.code)"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "readback order matches "
                    + "after moves") { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let expected = ctx.scratch[
                    "expectedOrder"] as? [String]
                    ?? []
                let order = fixtureBlockOrder(
                    ctx, id)
                ctx.detail["afterMovesOrder"] =
                    order
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "readback_order"
                            + "_matches",
                        pass: orderIds(order)
                            == expected,
                        expected: expected.joined(
                            separator: ","),
                        actual: orderIds(order)
                            .joined(separator: ",")),
                ]
                out.ok = orderIds(order) == expected
                done(out)
            },
            closeEditorStep(
                label: "ensure editor closed "
                    + "before reopen"),
            BridgeScenarioStep(
                kind: "callInternal",
                label: "reopen via navigation "
                    + "channel + seat readback"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                BridgeEditorTools.open(
                    ["memoId": id],
                    library: ctx.library) { result in
                    var out =
                        BridgeScenarioStepOutcome()
                    switch result {
                    case .success(let seat):
                        let blocks = seat["blocks"]
                            as? [[String: Any]] ?? []
                        ctx.detail["reopenedOrder"] =
                            blocks
                        let expected = ctx.scratch[
                            "expectedOrder"]
                            as? [String] ?? []
                        let got = blocks.map {
                            $0["id"] as? String ?? ""
                        }
                        out.assertions = [
                            UITestAssertion(
                                name: "seat_order"
                                    + "_matches",
                                pass: got == expected,
                                expected: expected
                                    .joined(
                                        separator: ","),
                                actual: got.joined(
                                    separator: ",")),
                        ]
                        out.ok = got == expected
                    case .failure(let e):
                        out.ok = false
                        out.note = "editor open "
                            + "failed: \(e.code)"
                    }
                    done(out)
                }
            },
            closeEditorStep(label: "close editor"),
            BridgeScenarioStep(
                kind: "assert",
                label: "compose conclusion"
            ) { ctx, done in
                ctx.conclusion = [
                    "verdict": "order_preserved",
                    "stages": ["initial",
                               "afterMoves",
                               "reopened"],
                ]
                done(BridgeScenarioStepOutcome())
            },
        ]
    }

    // ── create_transition（write，夹具，方案
    // §2.2）──
    // 经新建同路（create() 开量测账 + 导航通
    // 道打开，EditorModel 按 id 认领计时痕）
    // → 等 CREATE settle 行落定 → 以共用解析
    // 器（与量测工具同一实现，单一来源）逐段
    // 解析 → 对基线护栏比对：settle 缺失/超时
    // = 场景失败；分段超护栏 = 结论 degraded
    // 并逐段列明，不整场判红（判读归助手侧）。
    // 护栏来源：fix_transition_refactor.md 真
    // 机十连实测（create 1–6ms、listpass
    // 1×3–8ms、avatar 0ms）与 round2 定案期望
    // （listpass 趟数 1、bodypass ≤3）；护栏取
    // 实测的宽放量级，只抓病理级回退，随版本
    // 修订。

    private static let settleMsGuard = 2_000
    private static let settlePassGuard = 5
    private static let settleBodyPassGuard = 10

    private static func createTransitionSteps()
        -> [BridgeScenarioStep] {
        [
            snapshotStep("create_transition"),
            BridgeScenarioStep(
                kind: "invokeService",
                label: "create fixture via "
                    + "new-note path") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard let id = createFixture(
                    ctx, kind: nil, suffix: "新建")
                else {
                    out.ok = false
                    out.note = "fixture create did "
                        + "not land in the library"
                    done(out)
                    return
                }
                ctx.scratch["fixtureId"] = id
                out.assertions = [
                    UITestAssertion(
                        name: "fixture_registered",
                        pass: ctx.fixtureGuard(id),
                        expected: "in fixture "
                            + "registry",
                        actual: id),
                ]
                out.ok = ctx.fixtureGuard(id)
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "open via navigation "
                    + "channel") { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                BridgeEditorTools.open(
                    ["memoId": id],
                    library: ctx.library) { result in
                    var out =
                        BridgeScenarioStepOutcome()
                    switch result {
                    case .success(let seat):
                        let seatedId = seat["memoId"]
                            as? String ?? ""
                        out.assertions = [
                            UITestAssertion(
                                name: "fixture_seated",
                                pass: seatedId == id,
                                expected: id,
                                actual: seatedId),
                        ]
                        out.ok = seatedId == id
                    case .failure(let e):
                        out.ok = false
                        out.note = "editor open "
                            + "failed: \(e.code)"
                    }
                    done(out)
                }
            },
            BridgeScenarioStep(
                kind: "waitDiag",
                label: "await CREATE settle + "
                    + "parse vs baseline"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                DiagLog.shared.loadIfNeeded()
                let prefix = "CREATE settle "
                    + "id=\(id) "
                ctx.poll(timeoutMs: 15_000) {
                    DiagLog.shared.today.contains {
                        $0.text.hasPrefix(prefix)
                    }
                } done: { found in
                    var out =
                        BridgeScenarioStepOutcome()
                    guard found,
                          let line = DiagLog.shared
                            .today.last(where: {
                                $0.text.hasPrefix(
                                    prefix)
                            })?.text,
                          let parsed =
                            BridgeCreateSettleParser.parseLine(line)
                    else {
                        out.ok = false
                        out.note = "15s 内无本夹具"
                            + "的 CREATE settle 行"
                        done(out)
                        return
                    }
                    let seg = parsed.segments
                    ctx.detail["settleRaw"] = line
                    ctx.measurements[
                        "createSettle"] = seg
                    let core = ["create", "model",
                                "dest", "appear"]
                    let corePresent = core
                        .allSatisfy {
                            (seg[$0] as? Int) != nil
                        }
                    var over: [String] = []
                    for k in ["create", "model",
                              "dest", "appear",
                              "avatar", "kb",
                              "listpassMs"]
                    where (seg[k] as? Int
                            ?? 0) > settleMsGuard {
                        over.append(k)
                    }
                    if (seg["listpassPasses"]
                        as? Int ?? 0)
                        > settlePassGuard {
                        over.append("listpassPasses")
                    }
                    if (seg["bodypass"] as? Int
                        ?? 0) > settleBodyPassGuard {
                        over.append("bodypass")
                    }
                    ctx.detail["settleOverGuard"] =
                        over
                    ctx.conclusion = [
                        "verdict": over.isEmpty
                            ? "within_baseline"
                            : "degraded",
                        "overGuardSegments": over,
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "settle_present",
                            pass: true,
                            expected: "CREATE "
                                + "settle line",
                            actual: "id="
                                + parsed.memoId),
                        UITestAssertion(
                            name: "settle_core"
                                + "_segments",
                            pass: corePresent,
                            expected: "create/model"
                                + "/dest/appear "
                                + "numeric",
                            actual: seg.keys.sorted()
                                .joined(
                                    separator: ",")),
                    ]
                    out.ok = corePresent
                    if !over.isEmpty {
                        out.note = "分段超护栏"
                            + "（degraded，不判红）："
                            + over.joined(
                                separator: ",")
                    }
                    done(out)
                }
            },
            closeEditorStep(label: "close editor"),
        ]
    }

    // ── snapshot_restore_drill（ops，整场两
    // 段 + 用户指令 + armRestore 武装，夹具，
    // 方案 §2.2/§8 风险 3）──
    // 建夹具 → 本景自取快照（专用 takeSnapshot
    // 强制新取，不走会话复用——A 态必须恰为本
    // 景夹具建成后的库态，会话复用会把 A 错指
    // 到更早的快照）→ 软删夹具变更（hash B 须
    // ≠ A）→ 恢复守卫（当前哈希须恰为 B，快照
    // 后除本景外有任何变更即拒跑——恢复是全
    // 库替换语义，间隙里用户的真实编辑会被一
    // 并回滚）→ backup_restore_snapshot 内部
    // 同路恢复（目标 id 由引擎内定，不接受桥
    // 传 snapshotId，防恢复面变成任意回滚入
    // 口；工具内恢复前强制再快照即回滚路）→
    // 断言回到 A 态（哈希/计数/夹具回列表三
    // 面）→ 清理在恢复后的库上执行（引擎收尾
    // 链）。证据 = 快照清单 vs 对账表 + 三段哈
    // 希（A/B/恢复后）。

    private static func snapshotRestoreDrillSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "invokeService",
                label: "create fixture (empty "
                    + "template)") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard let id = createFixture(
                    ctx, kind: nil, suffix: "快照")
                else {
                    out.ok = false
                    out.note = "fixture create did "
                        + "not land in the library"
                    done(out)
                    return
                }
                ctx.scratch["fixtureId"] = id
                out.assertions = [
                    UITestAssertion(
                        name: "fixture_registered",
                        pass: ctx.fixtureGuard(id),
                        expected: "in fixture "
                            + "registry",
                        actual: id),
                ]
                out.ok = ctx.fixtureGuard(id)
                done(out)
            },
            BridgeScenarioStep(
                kind: "invokeService",
                label: "take snapshot of fixture "
                    + "state (hash A)") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                switch BridgeWriteSupport.shared
                    .takeSnapshot(
                        library: ctx.library,
                        reason:
                            "scenario:"
                            + "snapshot_restore_drill") {
                case .success(let snap):
                    ctx.snapshotId = snap
                    ctx.scratch["snapId"] = snap
                    let hashA = ctx.library
                        .libraryHash()
                    ctx.scratch["hashA"] = hashA
                    let record = BridgeWriteSupport
                        .shared.snapshotRecord(
                            id: snap)
                    ctx.detail["snapshotTarget"] = [
                        "snapshotId": snap,
                        "libraryHash": hashA,
                        "memoCount":
                            record?.memoCount
                                ?? NSNull(),
                        "manifestHash":
                            record?.preHash ?? "",
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "snapshot_recorded",
                            pass: record != nil
                                && record?.preHash
                                    == hashA,
                            expected: hashA,
                            actual: record?.preHash
                                ?? "missing"),
                    ]
                    out.ok = record != nil
                        && record?.preHash == hashA
                case .failure(let e):
                    out.ok = false
                    out.note = "snapshot failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "mutate fixture (soft "
                    + "delete, hash B)") { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let hashA = ctx.scratch["hashA"]
                    as? String ?? ""
                var out = BridgeScenarioStepOutcome()
                switch BridgeWriteTools.softDelete(
                    ["memoId": id,
                     "idempotencyKey":
                        "scenario:\(ctx.runId)"
                        + ":mutate",
                     "expectedDocHash":
                        fixtureDocHash(ctx, id)],
                    library: ctx.library) {
                case .success:
                    let hashB = ctx.library
                        .libraryHash()
                    ctx.scratch["hashB"] = hashB
                    let pending = ctx.library
                        .pendingDeletions[id] != nil
                    ctx.detail["mutation"] = [
                        "libraryHash": hashB,
                        "pending": pending,
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "fixture_pending",
                            pass: pending,
                            expected: "in pending set",
                            actual: pending
                                ? "pending" : "missing"),
                        UITestAssertion(
                            name: "hash_b_differs_a",
                            pass: !hashB.isEmpty
                                && hashB != hashA,
                            expected: "!= A",
                            actual: hashB),
                    ]
                    out.ok = pending && hashB != hashA
                case .failure(let e):
                    out.ok = false
                    out.note = "softDelete (mutate) "
                        + "failed: \(e.code)"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "restore guard: current "
                    + "hash is exactly B") { ctx, done in
                let hashB = ctx.scratch["hashB"]
                    as? String ?? ""
                let now = ctx.library.libraryHash()
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "no_external_change",
                        pass: now == hashB,
                        expected: hashB,
                        actual: now),
                ]
                out.ok = now == hashB
                if now != hashB {
                    ctx.conclusion["restoreGuard"] =
                        "blocked"
                    out.note = "快照后库有本景之外"
                        + "的变更，拒跑恢复（全库替"
                        + "换会一并回滚用户编辑）"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "restore snapshot + verify "
                    + "back to A") { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let snap = ctx.scratch["snapId"]
                    as? String ?? ""
                let hashA = ctx.scratch["hashA"]
                    as? String ?? ""
                var out = BridgeScenarioStepOutcome()
                switch BridgeBackupTools
                    .restoreSnapshot(
                        ["snapshotId": snap,
                         "idempotencyKey":
                            "scenario:\(ctx.runId)"
                            + ":restore"],
                        library: ctx.library) {
                case .success(let p):
                    let postHash = p[
                        "postLibraryHash"]
                        as? String ?? ""
                    let back = ctx.library.memos
                        .contains { $0.id == id }
                    ctx.detail["restore"] = [
                        "postLibraryHash": postHash,
                        "memoCount":
                            p["memoCount"]
                                ?? NSNull(),
                        "expectedMemoCount":
                            p["expectedMemoCount"]
                                ?? NSNull(),
                        "preRestoreSnapshotId":
                            p["preRestoreSnapshotId"]
                                ?? "",
                        "hashA": hashA,
                        "hashB": ctx.scratch["hashB"]
                            ?? "",
                    ]
                    let postCount = (p["memoCount"]
                        as? NSNumber)?.intValue ?? -1
                    let expectCount = (p[
                        "expectedMemoCount"]
                        as? NSNumber)?.intValue ?? -2
                    out.assertions = [
                        UITestAssertion(
                            name: "hash_back_to_a",
                            pass: postHash == hashA,
                            expected: hashA,
                            actual: postHash),
                        UITestAssertion(
                            name: "fixture_back_in_list",
                            pass: back,
                            expected: "in memos",
                            actual: back
                                ? "present" : "missing"),
                        UITestAssertion(
                            name: "count_matches"
                                + "_manifest",
                            pass: postCount
                                == expectCount,
                            expected: "\(expectCount)",
                            actual: "\(postCount)"),
                    ]
                    out.ok = postHash == hashA && back
                case .failure(let e):
                    out.ok = false
                    out.note = "restore failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "compose conclusion"
            ) { ctx, done in
                ctx.conclusion = [
                    "verdict": "restore_verified",
                    "restoreGuard":
                        ctx.conclusion["restoreGuard"]
                            as? String ?? "passed",
                    "hashA": ctx.scratch["hashA"]
                        ?? "",
                    "hashB": ctx.scratch["hashB"]
                        ?? "",
                ]
                done(BridgeScenarioStepOutcome())
            },
        ]
    }

    // ── snapshot_pending_window_restore
    // （ops，整场两段 + 用户指令 + armRestore
    // 武装，夹具，快照线缺陷二回归格）──
    // 夹具软删入待删窗 → **窗内**铸快照（清单
    // 哈希的铸造时点恰在待删集非空时——缺陷二
    // 的触发条件）→ 等窗口过期真删 → 恢复守
    // 卫（当前哈希须恰等于清单哈希：规范域下
    // 铸时与窗外同值；旧全行域下铸时含标记行、
    // 过期后不含，守卫先红）→ 内部同路恢复 →
    // 断言恢复成功且哈希/计数与清单同域一致、
    // 夹具不复活（它从未进 ZIP）。

    private static func
        snapshotPendingWindowRestoreSteps()
        -> [BridgeScenarioStep] {
        [
            BridgeScenarioStep(
                kind: "invokeService",
                label: "create fixture (empty "
                    + "template)") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                guard let id = createFixture(
                    ctx, kind: nil, suffix: "窗恢")
                else {
                    out.ok = false
                    out.note = "fixture create did "
                        + "not land in the library"
                    done(out)
                    return
                }
                ctx.scratch["fixtureId"] = id
                out.assertions = [
                    UITestAssertion(
                        name: "fixture_registered",
                        pass: ctx.fixtureGuard(id),
                        expected: "in fixture "
                            + "registry",
                        actual: id),
                ]
                out.ok = ctx.fixtureGuard(id)
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "soft delete fixture "
                    + "(enters pending window)"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                var out = BridgeScenarioStepOutcome()
                switch BridgeWriteTools.softDelete(
                    ["memoId": id,
                     "idempotencyKey":
                        "scenario:\(ctx.runId)"
                        + ":mutate",
                     "expectedDocHash":
                        fixtureDocHash(ctx, id)],
                    library: ctx.library) {
                case .success:
                    let pending = ctx.library
                        .pendingDeletions[id] != nil
                    out.assertions = [
                        UITestAssertion(
                            name: "fixture_pending",
                            pass: pending,
                            expected: "in pending set",
                            actual: pending
                                ? "pending" : "missing"),
                    ]
                    out.ok = pending
                case .failure(let e):
                    out.ok = false
                    out.note = "softDelete (mutate) "
                        + "failed: \(e.code)"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "invokeService",
                label: "take snapshot inside "
                    + "pending window") { ctx, done in
                var out = BridgeScenarioStepOutcome()
                switch BridgeWriteSupport.shared
                    .takeSnapshot(
                        library: ctx.library,
                        reason:
                            "scenario:"
                            + "snapshot_pending_"
                            + "window_restore") {
                case .success(let snap):
                    ctx.snapshotId = snap
                    ctx.scratch["snapId"] = snap
                    let record = BridgeWriteSupport
                        .shared.snapshotRecord(
                            id: snap)
                    ctx.scratch["manifestHash"] =
                        record?.preHash ?? ""
                    ctx.scratch["manifestCount"] =
                        record?.memoCount ?? -1
                    ctx.detail["snapshotTarget"] = [
                        "snapshotId": snap,
                        "manifestHash":
                            record?.preHash ?? "",
                        "manifestCount":
                            record?.memoCount
                                ?? NSNull(),
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "snapshot_recorded",
                            pass: record != nil,
                            expected: "manifest entry",
                            actual: record != nil
                                ? "recorded" : "missing"),
                    ]
                    out.ok = record != nil
                case .failure(let e):
                    out.ok = false
                    out.note = "snapshot failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "waitDiag",
                label: "undo window expiry "
                    + "commits deletion"
            ) { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                ctx.poll(timeoutMs: 15_000) {
                    ctx.library
                        .pendingDeletions[id] == nil
                        && fixtureItem(ctx, id)
                            == nil
                } done: { ok in
                    var out =
                        BridgeScenarioStepOutcome()
                    out.assertions = [
                        UITestAssertion(
                            name: "truly_deleted"
                                + "_after_window",
                            pass: ok,
                            expected: "absent "
                                + "everywhere",
                            actual: ok
                                ? "absent"
                                : "still present"),
                    ]
                    out.ok = ok
                    done(out)
                }
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "restore guard: current "
                    + "hash equals manifest hash"
            ) { ctx, done in
                let manifestHash =
                    ctx.scratch["manifestHash"]
                        as? String ?? ""
                let now = ctx.library.libraryHash()
                var out = BridgeScenarioStepOutcome()
                out.assertions = [
                    UITestAssertion(
                        name: "hash_stable_across"
                            + "_window",
                        pass: now == manifestHash,
                        expected: manifestHash,
                        actual: now),
                ]
                out.ok = now == manifestHash
                if now != manifestHash {
                    ctx.conclusion["restoreGuard"] =
                        "blocked"
                    out.note = "待删窗内外哈希不同"
                        + "域（清单哈希与活库哈希口"
                        + "径不一致），拒跑恢复"
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "callInternal",
                label: "restore snapshot + verify "
                    + "same domain") { ctx, done in
                let id = ctx.scratch["fixtureId"]
                    as? String ?? ""
                let snap = ctx.scratch["snapId"]
                    as? String ?? ""
                let manifestHash =
                    ctx.scratch["manifestHash"]
                        as? String ?? ""
                let manifestCount =
                    ctx.scratch["manifestCount"]
                        as? Int ?? -1
                var out = BridgeScenarioStepOutcome()
                switch BridgeBackupTools
                    .restoreSnapshot(
                        ["snapshotId": snap,
                         "idempotencyKey":
                            "scenario:\(ctx.runId)"
                            + ":restore"],
                        library: ctx.library) {
                case .success(let p):
                    let postHash = p[
                        "postLibraryHash"]
                        as? String ?? ""
                    let postCount = (p["memoCount"]
                        as? NSNumber)?.intValue ?? -2
                    let back = fixtureItem(ctx, id)
                        != nil
                    ctx.detail["restore"] = [
                        "postLibraryHash": postHash,
                        "memoCount": postCount,
                        "manifestHash": manifestHash,
                        "manifestCount":
                            manifestCount,
                        "preRestoreSnapshotId":
                            p["preRestoreSnapshotId"]
                                ?? "",
                    ]
                    out.assertions = [
                        UITestAssertion(
                            name: "hash_matches"
                                + "_manifest",
                            pass: postHash
                                == manifestHash,
                            expected: manifestHash,
                            actual: postHash),
                        UITestAssertion(
                            name: "count_matches"
                                + "_manifest",
                            pass: postCount
                                == manifestCount,
                            expected:
                                "\(manifestCount)",
                            actual: "\(postCount)"),
                        UITestAssertion(
                            name: "fixture_stays"
                                + "_deleted",
                            pass: !back,
                            expected: "absent "
                                + "everywhere",
                            actual: back
                                ? "present" : "absent"),
                    ]
                    out.ok = postHash == manifestHash
                        && postCount == manifestCount
                        && !back
                case .failure(let e):
                    out.ok = false
                    out.note = "restore failed: "
                        + e.code
                }
                done(out)
            },
            BridgeScenarioStep(
                kind: "assert",
                label: "compose conclusion"
            ) { ctx, done in
                ctx.conclusion = [
                    "verdict":
                        "pending_window_restore"
                        + "_verified",
                    "restoreGuard":
                        ctx.conclusion["restoreGuard"]
                            as? String ?? "passed",
                    "manifestHash":
                        ctx.scratch["manifestHash"]
                        ?? "",
                ]
                done(BridgeScenarioStepOutcome())
            },
        ]
    }
}

// ── DRAG 链归组解析（drag_trace_review 本体）──
// 事件分类与尝试（attempt）切分：press target
// 开新尝试，尝试内收 press state/pickup/
// converge/menu/drop/cancel；完整性 = 有 pickup
// 且有终局（drop 或 cancel），缺环逐项点名。
// press reject/disarmed/norow 是「按压未达目
// 标」的独立结局，不入尝试、只入汇总计数。

enum BridgeDragTraceParser {

    /// DRAG 行收集（景与 metrics_drag_trace 工
    /// 具共用单一来源，矩阵 §5/§4.13）：今日
    /// Diag 中 DRAG 前缀行，按 sinceTs（毫秒，
    /// 含界）与 blockId（行内 id= 匹配）过滤；
    /// limit 不在此钳（回行上限由消费方按各自
    /// 口径取，parse 吃全集保归组完整）。
    static func collect(
        _ params: [String: Any]) -> [DiagEntry] {
        DiagLog.shared.loadIfNeeded()
        var entries = DiagLog.shared.today
            .filter {
                $0.text.hasPrefix("DRAG ")
            }
        if let since = (params["sinceTs"]
            as? NSNumber)?.doubleValue {
            entries = entries.filter {
                $0.ts * 1000 >= since
            }
        }
        if let bid = params["blockId"] as? String {
            entries = entries.filter {
                $0.text.contains("id=\(bid)")
            }
        }
        return entries
    }

    struct Parsed {
        var attempts: [[String: Any]] = []
        var summary: [String: Any] = [:]
        var conclusion: [String: Any] = [:]
    }

    private static func kind(
        of text: String) -> String {
        switch true {
        case text.hasPrefix("DRAG engine attached"):
            return "attached"
        case text.hasPrefix("DRAG press target"):
            return "press_target"
        case text.hasPrefix("DRAG press reject"):
            return "press_reject"
        case text.hasPrefix("DRAG press disarmed"):
            return "press_disarmed"
        case text.hasPrefix("DRAG press norow"):
            return "press_norow"
        case text.hasPrefix("DRAG press state="):
            return "press_state"
        case text.hasPrefix("DRAG pickup"):
            return "pickup"
        case text.hasPrefix("DRAG converge"):
            return "converge"
        case text.hasPrefix("DRAG menu show"):
            return "menu_show"
        case text.hasPrefix("DRAG menu delete"):
            return "menu_delete"
        case text.hasPrefix("DRAG drop"):
            return "drop"
        case text.hasPrefix("DRAG cancel"):
            return "cancel"
        case text.hasPrefix("DRAG began orphan"):
            return "began_orphan"
        case text.hasPrefix(
            "DRAG anchor attach deferred"):
            return "anchor_deferred"
        default:
            return "other"
        }
    }

    private static func field(
        _ text: String, _ key: String) -> String? {
        guard let r = text.range(of: "\(key)=") else {
            return nil
        }
        let rest = text[r.upperBound...]
        return rest.split(separator: " ").first
            .map(String.init)
    }

    static func parse(
        _ entries: [DiagEntry]) -> Parsed {
        var parsed = Parsed()
        var attempts: [[String: Any]] = []
        var cur: [String: Any]?
        var counts: [String: Int] = [:]
        func flush() {
            if let c = cur { attempts.append(c) }
            cur = nil
        }
        for e in entries {
            let k = kind(of: e.text)
            counts[k, default: 0] += 1
            switch k {
            case "press_target":
                flush()
                cur = [
                    "blockId": field(e.text, "id")
                        ?? "",
                    "startTsMs": Int64(e.ts * 1000),
                    "events": ["press_target"],
                    "pressStates": [] as [String],
                    "hasPickup": false,
                    "terminal": "",
                ]
            case "press_state", "pickup",
                 "converge", "menu_show",
                 "menu_delete", "drop", "cancel":
                guard var c = cur else { continue }
                var events = c["events"]
                    as? [String] ?? []
                events.append(k)
                c["events"] = events
                if k == "press_state",
                   let s = field(e.text, "state") {
                    var states = c["pressStates"]
                        as? [String] ?? []
                    states.append(s)
                    c["pressStates"] = states
                }
                if k == "pickup" {
                    c["hasPickup"] = true
                }
                if k == "drop" || k == "cancel" {
                    c["terminal"] = k
                }
                cur = c
            default:
                continue
            }
        }
        flush()
        var incomplete: [[String: Any]] = []
        for i in attempts.indices {
            let hasPickup = attempts[i]["hasPickup"]
                as? Bool ?? false
            let terminal = attempts[i]["terminal"]
                as? String ?? ""
            var missing: [String] = []
            if !hasPickup { missing.append("pickup") }
            if terminal.isEmpty {
                missing.append("drop_or_cancel")
            }
            attempts[i]["missing"] = missing
            attempts[i]["complete"] = missing.isEmpty
            if !missing.isEmpty {
                incomplete.append([
                    "blockId": attempts[i]["blockId"]
                        as? String ?? "",
                    "missing": missing,
                ])
            }
        }
        parsed.attempts = attempts
        parsed.summary = [
            "totalLines": entries.count,
            "attempts": attempts.count,
            "completeAttempts":
                attempts.count - incomplete.count,
            "incompleteAttempts": incomplete.count,
            "pressRejects":
                counts["press_reject"] ?? 0,
            "pressDisarmed":
                counts["press_disarmed"] ?? 0,
            "pressNorow": counts["press_norow"] ?? 0,
            "pickups": counts["pickup"] ?? 0,
            "drops": counts["drop"] ?? 0,
            "cancels": counts["cancel"] ?? 0,
        ]
        let verdict: String
        if entries.isEmpty {
            verdict = "no_drag_records"
        } else if !attempts.isEmpty
                    && incomplete.isEmpty {
            verdict = "chains_complete"
        } else {
            verdict = "chains_incomplete"
        }
        parsed.conclusion = [
            "verdict": verdict,
            "incomplete": incomplete,
        ]
        return parsed
    }

    /// 原始行回传（字节守卫同 diag_tail 口径：
    /// 整包超 maxDiagBytes 从最旧端裁，保最新）。
    static func guardedRawLines(
        _ entries: [DiagEntry], limit: Int
    ) -> [[String: Any]] {
        var tail = Array(entries.suffix(limit))
        func dicts() -> [[String: Any]] {
            tail.map {
                ["ts": Int64($0.ts * 1000),
                 "level": $0.level, "text": $0.text]
                    as [String: Any]
            }
        }
        while tail.count > 1 {
            let payload: [String: Any] = [
                "entries": dicts(),
            ]
            let size = BridgeCanonical
                .data(payload)?.count ?? 0
            if size <= BridgeProto.maxDiagBytes {
                break
            }
            tail.removeFirst()
        }
        return dicts()
    }
}

// ── CREATE settle 解析（metrics_create_settle
// 本体；create_transition 景 M3b 复用同一解析
// 器，单一来源——矩阵 §5 裁定）──
// settle 行形态（EditorModel.logCreateSettle）：
// CREATE settle id=<id> create=<n|na>ms model=
// <n|na>ms dest=<n|na>ms appear=<n|na>ms list
// pass=<趟>x<ms>ms avatar=<n|na>ms bodypass=<n>
// claim=<ok<0|1>/inwindow<0|1>|na> kb=<n|na>ms。

enum BridgeCreateSettleParser {

    static func parseLine(
        _ text: String
    ) -> (memoId: String,
          segments: [String: Any])? {
        guard text.hasPrefix("CREATE settle ")
        else { return nil }
        var memoId = ""
        var segments: [String: Any] = [:]
        func msValue(_ raw: String) -> Any {
            let v = raw.hasSuffix("ms")
                ? String(raw.dropLast(2)) : raw
            if v == "na" { return NSNull() }
            return Int(v) ?? NSNull()
        }
        for token in text.split(separator: " ") {
            let parts = token.split(
                separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let raw = String(parts[1])
            switch key {
            case "id":
                memoId = raw
            case "create", "model", "dest",
                 "appear", "avatar", "kb":
                segments[key] = msValue(raw)
            case "listpass":
                let v = raw.hasSuffix("ms")
                    ? String(raw.dropLast(2)) : raw
                let xy = v.split(separator: "x")
                if xy.count == 2 {
                    segments["listpassPasses"] =
                        Int(xy[0]) ?? NSNull()
                    segments["listpassMs"] =
                        Int(xy[1]) ?? NSNull()
                }
            case "bodypass":
                segments["bodypass"] =
                    Int(raw) ?? NSNull()
            case "claim":
                segments["claim"] = raw == "na"
                    ? NSNull() : raw
            default:
                continue
            }
        }
        guard !memoId.isEmpty else { return nil }
        return (memoId, segments)
    }
}

// ── 场景工具面（分发器 case 背后）──

enum BridgeScenarioTools {

    static func list(
        library: Library?,
        coordinator: BridgeCoordinator
    ) -> [String: Any] {
        let scenarios = BridgeScenarioRegistry.all
            .map { desc -> [String: Any] in
                var d = desc.dict
                d["availability"] =
                    BridgeScenarioRegistry
                        .availability(
                            desc, library: library,
                            coordinator: coordinator)
                return d
            }
        return [
            "scenarios": scenarios,
            "activeRunId": BridgeScenarioEngine
                .shared.activeRunId ?? NSNull(),
            "runBusy": BridgeScenarioEngine.shared
                .anyRunBusy,
            "journalRuns": BridgeScenarioJournal
                .load().count,
        ]
    }

    /// 受理（分发器已按描述符验足 scope、校验参
    /// 数面并过数据写前置门）：引擎占互斥开跑，
    /// 立即回 runId（异步作业信封，方案 §3.3）。
    static func run(
        _ args: [String: Any], library: Library
    ) -> Result<[String: Any], BridgeToolError> {
        guard let sid = args["scenario"] as? String,
              let desc = BridgeScenarioRegistry
                .descriptor(sid) else {
            return .failure(.invalidParams(
                "unknown scenario"))
        }
        // 前置未落的景（wiring_missing）在清单
        // 现形、受理即拒——绝不进引擎空跑出假
        // 成功（步表恒为空只是第二道防线）。
        if desc.wiringMissing {
            return .failure(BridgeToolError(
                code: "wiring_missing",
                message: "scenario \(sid) is "
                    + "registered but its prerequisite"
                    + " tooling is not implemented "
                    + "yet"))
        }
        // 快照恢复景武装门（方案 §8 风险 3）：
        // 未显式 armRestore: true 的 run 受理即
        // 拒——与整场两段、事前用户指令三重叠
        // 加，防全库恢复演练被顺手触发。
        if BridgeScenarioRegistry.armGatedIds
            .contains(sid) {
            let params = args["params"]
                as? [String: Any] ?? [:]
            if (params["armRestore"] as? Bool)
                != true {
                return .failure(BridgeToolError(
                    code: "arm_required",
                    message: "scenario \(sid) "
                        + "requires params.armRestore"
                        + " = true (explicit arming "
                        + "for a full-library restore "
                        + "drill)"))
            }
        }
        switch BridgeScenarioEngine.shared.begin(
            descriptor: desc, args: args,
            library: library) {
        case .success(let runId):
            return .success([
                "runId": runId,
                "scenario": sid,
                "acceptedAtMs": Library.epochMs(),
            ])
        case .failure(let e):
            return .failure(e)
        }
    }

    /// 证据包只读 journal 组装（进程重启后仍可
    /// 回读）：只含 id/哈希/计数/Diag 行/量测，
    /// 不含正文（方案 §5.3）。
    static func getResult(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        guard let runId = args["runId"] as? String,
              !runId.isEmpty else {
            return .failure(.invalidParams(
                "runId required"))
        }
        guard let run = BridgeScenarioJournal
            .run(runId) else {
            return .failure(.invalidParams(
                "unknown runId: \(runId)"))
        }
        let evidence = BridgeJSON.parseObject(
            run.evidenceJSON) ?? [:]
        var steps: [[String: Any]] = []
        if let data = run.stepsJSON
            .data(using: .utf8),
           let arr = try? JSONSerialization
            .jsonObject(with: data)
            as? [[String: Any]] {
            steps = arr
        }
        let desc = BridgeScenarioRegistry
            .descriptor(run.scenarioId)
        var payload: [String: Any] = [
            "runId": run.runId,
            "scenario": run.scenarioId,
            "status": run.status,
            "code": run.code,
            "paramsHash": run.paramsHash,
            "createdAtMs": run.createdAtMs,
            "updatedAtMs": run.updatedAtMs,
            "fixture": [
                "ids": run.fixtureIds,
                "preLibraryHash":
                    run.preLibraryHash,
                "postLibraryHash":
                    run.postLibraryHash,
            ] as [String: Any],
            "steps": steps,
            "measurements":
                evidence["measurements"]
                    as? [String: Any] ?? [:],
            "detail": evidence["detail"]
                as? [String: Any] ?? [:],
            "conclusion": evidence["conclusion"]
                as? [String: Any] ?? [:],
            "grades": desc?.grades ?? [:],
        ]
        if BridgeScenarioEngine.shared.activeRunId
            == run.runId {
            payload["live"] = true
        }
        return .success(payload)
    }
}

// ── 量测工具面：CREATE settle 解析 + DRAG
// 轨迹归组 ──
// 纯 Diag 读（read 级）：settle 回最近行的逐段
// 解析 + 原始行，供新建过渡基线对照；drag
// trace 回 DRAG 行的归组解析（尝试链完整性 +
// 汇总 + 结论）+ 原始行，与 drag_trace_review
// 景共用 BridgeDragTraceParser 单一收集/解析
// （矩阵 §5 切换点，U3 出货）。两工具都只出数
// 与解析结论，阈值判读在助手侧/场景侧。

enum BridgeMetricsTools {

    static func createSettle(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        DiagLog.shared.loadIfNeeded()
        let limit = min(100, max(1,
            (args["limit"] as? NSNumber)?.intValue
                ?? 20))
        var matched: [(entry: DiagEntry,
                       memoId: String,
                       segments: [String: Any])] = []
        for e in DiagLog.shared.today
        where e.text.hasPrefix("CREATE settle ") {
            guard let parsed = BridgeCreateSettleParser
                .parseLine(e.text) else {
                continue
            }
            if let want = args["memoId"] as? String,
               !want.isEmpty, parsed.memoId != want {
                continue
            }
            if let since = (args["sinceTs"]
                as? NSNumber)?.doubleValue,
               e.ts * 1000 < since {
                continue
            }
            matched.append((e, parsed.memoId,
                            parsed.segments))
        }
        let page = Array(matched.suffix(limit))
        return .success([
            "entries": page.map { m in
                [
                    "ts": Int64(m.entry.ts * 1000),
                    "memoId": m.memoId,
                    "segments": m.segments,
                    "raw": m.entry.text,
                ] as [String: Any]
            },
            "returned": page.count,
            "totalMatched": matched.count,
        ])
    }

    /// metrics_drag_trace（U3 出货，清单第 36
    /// 件）：入参与 drag_trace_review 景同名同
    /// 义（sinceTs 毫秒/blockId/limit），收集与
    /// 解析走 BridgeDragTraceParser.collect/
    /// parse 单一来源——景判链路完整性断言、本
    /// 工具回全量解析供真机轨迹复核（EDT-29）。
    static func dragTrace(
        _ args: [String: Any]
    ) -> Result<[String: Any], BridgeToolError> {
        let entries = BridgeDragTraceParser
            .collect(args)
        let limit = min(500, max(1,
            (args["limit"] as? NSNumber)?.intValue
                ?? 200))
        let parsed = BridgeDragTraceParser
            .parse(entries)
        return .success([
            "summary": parsed.summary,
            "conclusion": parsed.conclusion,
            "attempts": parsed.attempts,
            "rawLines": BridgeDragTraceParser
                .guardedRawLines(
                    entries, limit: limit),
            "totalLines": entries.count,
        ])
    }
}
