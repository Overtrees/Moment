// ── MCP 桥协调器 + 设备身份（M1）──
// 设备身份 = Keychain P-256 密钥对（私钥不出
// Keychain），连接时对中继挑战签名；配对元数据
// （pairingId/能力位）同存 Keychain——凭据类数据
// 绝不进 UserDefaults/Diag/备份。协调器管状态机
// （开关/配对/连接/退避/吊销/OPS 禁用）、控制帧
// （挑战/心跳/在场）、JSON-RPC 入口与调用留痕。
// 桥只在前台在线：后台不假装可用，断开即离线
// 语义（方案 §3 纪律）。

import Foundation
import Combine
import Network
import Security
import UIKit

// ── 设备身份（Keychain） ──

final class BridgeIdentity {
    private let keyTag = Data(
        "com.canopies.moment.bridge.devicekey".utf8)
    private let service = "com.canopies.moment.bridge"

    // 设备私钥（P-256，永久驻 Keychain）。
    private func loadPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary, &item) == errSecSuccess,
            let item else { return nil }
        return (item as! SecKey)
    }

    private func createPrivateKey() -> SecKey? {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String:
                kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String:
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateRandomKey(
            attrs as CFDictionary, &error)
    }

    func privateKey() -> SecKey? {
        loadPrivateKey() ?? createPrivateKey()
    }

    /// 公钥原始表示（65 字节 X9.63 未压缩点）。
    func publicKeyRaw() -> Data? {
        guard let priv = privateKey(),
              let pub = SecKeyCopyPublicKey(priv)
        else { return nil }
        var error: Unmanaged<CFError>?
        return SecKeyCopyExternalRepresentation(
            pub, &error) as Data?
    }

    /// 设备指纹 = sha256(公钥原始表示) 前 16 hex
    /// 大写、四位分组（与中继侧同算式，配对核对面）。
    func fingerprint() -> String? {
        guard let raw = publicKeyRaw() else { return nil }
        let hex = BridgeHash.sha256Hex(raw).uppercased()
        let head = String(hex.prefix(16))
        var out = ""
        for (i, ch) in head.enumerated() {
            if i > 0 && i % 4 == 0 { out += " " }
            out.append(ch)
        }
        return out
    }

    /// ECDSA P-256/SHA-256 签名（X9.62 DER 编码，
    /// 中继侧转 raw 后以 WebCrypto 验签）。
    func sign(_ data: Data) -> Data? {
        guard let priv = privateKey() else { return nil }
        var error: Unmanaged<CFError>?
        return SecKeyCreateSignature(
            priv, .ecdsaSignatureMessageX962SHA256,
            data as CFData, &error) as Data?
    }

    func deleteDeviceKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // 配对元数据（Keychain 泛型密码项）。
    private func kcSet(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func kcGet(_ account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func kcDelete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    var pairingId: String? {
        get { kcGet("pairingId") }
        set {
            if let newValue { kcSet("pairingId", newValue) }
            else { kcDelete("pairingId") }
        }
    }

    var scopes: [String] {
        get {
            (kcGet("scopes") ?? "")
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
        }
        set { kcSet("scopes", newValue.joined(separator: ",")) }
    }

    // 待配对会话落盘（配对状态根治，定案
    // fix_bridge_pairing_state.md）：pid 与过期时刻
    // 同存 Keychain——配对流程大部分时间用户在
    // App 外（浏览器确认 + 凭据录入），App 被挂起
    // 甚至杀死后冷启必须能凭落盘记录向中继校准，
    // 只存内存等于把收敛押在前台轮询单点上。
    var pendingPairingId: String? {
        get { kcGet("pendingPairingId") }
        set {
            if let newValue {
                kcSet("pendingPairingId", newValue)
            } else { kcDelete("pendingPairingId") }
        }
    }

    var pendingExpiresAtMs: Int64 {
        get { Int64(kcGet("pendingExpiresAtMs") ?? "") ?? 0 }
        set { kcSet("pendingExpiresAtMs", String(newValue)) }
    }

    func clearPendingPairing() {
        kcDelete("pendingPairingId")
        kcDelete("pendingExpiresAtMs")
    }

    func clearPairing() {
        kcDelete("pairingId")
        kcDelete("scopes")
        kcDelete("pairedAtMs")
        clearPendingPairing()
    }
}

// ── 协调器 ──

struct BridgePairingSession: Equatable {
    var id: String
    var fingerprint: String
    var expiresAtMs: Int64
}

struct BridgeCallRecord: Identifiable {
    var id = UUID()
    var tool: String
    var code: String
    var ms: Int
    var atMs: Int64
}

final class BridgeCoordinator: ObservableObject {
    static let shared = BridgeCoordinator()

    @Published private(set) var linkState: String = "off"
    @Published var enabled: Bool = false
    @Published private(set) var pendingPairing:
        BridgePairingSession?
    @Published private(set) var scopes: [String] = []
    @Published private(set) var recentCalls:
        [BridgeCallRecord] = []

    /// 本进程启动会话 id（每次冷启新生成）与中继
    /// 授予的连接会话 id（welcome 回带）。
    let bootSessionId = UUID().uuidString
    private(set) var appSessionId: String = ""

    private(set) var opsDisabled = false
    private var started = false
    weak var library: Library?

    private let identity = BridgeIdentity()
    private let transport = BridgeWssTransport()
    private var backoffAttempt = 0
    private var reconnectWork: DispatchWorkItem?
    private var heartbeatTimer: Timer?
    private var pollTimer: Timer?
    private var lastPongAt = Date()
    // 稳定性量测与探活（fix_bridge_stability）：
    // sessionUpAt 记本次 connected 的起点，断开时
    // 打 session down 带时长；probeToken 使每次探
    // 活自带令牌，新连接/新探活使旧探活结论失效；
    // pathMonitor 盯网络路径签名（接口集 + 可达）。
    private var sessionUpAt: Date?
    private var probeToken: UUID?
    private var probeWork: DispatchWorkItem?
    private var pathMonitor: NWPathMonitor?
    private var pathSignature = ""

    var isPaired: Bool { identity.pairingId != nil }
    var deviceFingerprint: String? { identity.fingerprint() }
    /// 分发器形态：安全模式 = 受限（可用集见
    /// BridgeDispatcher.safeLimitedTools），
    /// 正常 = 完整工具集（M1 只读 + M2 写面）。
    var dispatcherForm: String {
        (library?.bootIsSafe ?? false) ? "limited" : "full"
    }

    var linkStateKey: String {
        switch linkState {
        case "connected": return "bridge.state_connected"
        case "connecting": return "bridge.state_connecting"
        case "backoff": return "bridge.state_backoff"
        case "pairing": return "bridge.state_pairing"
        case "unpaired": return "bridge.state_unpaired"
        case "revoked": return "bridge.state_revoked"
        case "opsDisabled": return "bridge.state_ops_disabled"
        default: return "bridge.state_off"
        }
    }

    private func setState(_ s: String, reason: String) {
        let from = linkState
        linkState = s
        if from != s {
            DiagLog.shared.log(.info,
                "BRIDGE state \(from)->\(s) reason=\(reason)")
        }
    }

    // ── 启动与开关 ──

    func start(library: Library) {
        guard !started else { return }
        started = true
        self.library = library
        enabled = UserDefaults.standard.bool(
            forKey: "bridgeEnabled")
        scopes = identity.scopes
        opsDisabled = OpsDirectives.cached()
            .isDisabled(OpsStep.bridge)
        DiagLog.shared.log(.info,
            "BRIDGE start enabled=\(enabled ? 1 : 0) "
            + "paired=\(isPaired ? 1 : 0) "
            + "opsDisabled=\(opsDisabled ? 1 : 0)")
        if opsDisabled {
            DiagLog.shared.log(.warn,
                "BRIDGE tools_rejected reason=ops_disabled")
            setState("opsDisabled", reason: "ops")
            return
        }
        wireTransport()
        observeScene()
        observePath()
        if !enabled {
            setState("off", reason: "start")
        } else if !isPaired {
            // 冷启恢复落盘待配对会话并校准：上个
            // 进程可能在用户于 App 外确认配对后被
            // 杀，收敛不能只靠当时的前台轮询。
            if restorePendingIfNeeded() != nil {
                setState("pairing", reason: "start")
                revalidatePairing()
            } else {
                setState("unpaired", reason: "start")
            }
        } else {
            connectNow(reason: "start")
        }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "bridgeEnabled")
        enabled = on
        DiagLog.shared.log(.info,
            "BRIDGE enable set=\(on ? 1 : 0)")
        if opsDisabled {
            DiagLog.shared.log(.warn,
                "BRIDGE tools_rejected reason=ops_disabled")
            setState("opsDisabled", reason: "toggle")
            return
        }
        if on {
            if isPaired {
                connectNow(reason: "toggle")
            } else if restorePendingIfNeeded() != nil {
                revalidatePairing()
            } else {
                setState("unpaired", reason: "toggle")
            }
        } else {
            cancelReconnect()
            stopHeartbeat()
            sessionUpAt = nil
            transport.close(suppressNotify: true)
            setState("off", reason: "toggle")
        }
    }

    // ── 连接管理 ──

    private func wireTransport() {
        transport.onText = { [weak self] text in
            self?.handleFrame(text)
        }
        transport.onSocketDown = { [weak self] reason in
            DispatchQueue.main.async {
                self?.handleSocketDown(reason: reason)
            }
        }
    }

    private func connectNow(reason: String) {
        guard let pid = identity.pairingId else {
            setState("unpaired", reason: reason)
            return
        }
        cancelReconnect()
        invalidateProbe()
        // 用户可见触发（启动/回前台/路径恢复/开关/
        // 配对完成）开新一轮退避周期：旧实现计数只
        // 在 welcome 清零，前台手动重连失败后仍背
        // 着最高 30s 的旧档位，用户盯着界面干等。
        if reason != "backoff" { backoffAttempt = 0 }
        DiagLog.shared.log(.info,
            "BRIDGE connect reason=\(reason) "
            + "attempt=\(backoffAttempt)")
        setState("connecting", reason: reason)
        transport.connect(pairingId: pid)
    }

    private func handleSocketDown(reason: String) {
        stopHeartbeat()
        invalidateProbe()
        if let up = sessionUpAt {
            sessionUpAt = nil
            DiagLog.shared.log(.warn,
                "BRIDGE session down reason=\(reason) "
                + "dur=\(Int(Date().timeIntervalSince(up)))s")
        }
        guard enabled, !opsDisabled, isPaired else {
            setState(enabled ? "unpaired" : "off",
                     reason: reason)
            return
        }
        backoffAttempt += 1
        setState("backoff", reason: reason)
        let base = min(30.0, pow(2.0, Double(backoffAttempt - 1)))
        let delay = base + Double.random(in: 0..<1)
        DiagLog.shared.log(.warn,
            "BRIDGE reconnect_scheduled attempt="
            + "\(backoffAttempt) delay=\(Int(delay))s")
        let work = DispatchWorkItem { [weak self] in
            self?.connectNow(reason: "backoff")
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay, execute: work)
    }

    /// 硬重连单点（心跳超时/探活失败共用）：关当前
    /// 连接并立即走断开处置（其内排退避重连）。
    private func forceReconnect(reason: String) {
        stopHeartbeat()
        transport.close()
        handleSocketDown(reason: reason)
    }

    private func cancelReconnect() {
        reconnectWork?.cancel()
        reconnectWork = nil
    }

    private func startHeartbeat() {
        stopHeartbeat()
        lastPongAt = Date()
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: 20, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            if Date().timeIntervalSince(self.lastPongAt) > 50 {
                DiagLog.shared.log(.warn,
                    "BRIDGE error code=heartbeat_timeout "
                    + "where=transport")
                self.forceReconnect(
                    reason: "heartbeat_timeout")
                return
            }
            _ = self.transport.send(
                "{\"moment.control\":\"ping\"}")
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // ── 前台探活与路径看门狗（fix_bridge_stability）──
    //
    // 半死连接（挂起期底层链路已断、URLSession 却
    // 未报失败）下 isOpen 与 linkState 都停在旧值：
    // 旧前台钩子只看 isOpen 发 presence，永不重连，
    // 只能等心跳 50s 陈旧 + 20s  tick（最长 ~70s）
    // 才自愈，且该窗内中继侧 socket 在册、调用全
    // 部超时。探活把判定压到前台 5s：发一帧 ping，
    // 限期内 pong 未达（lastPongAt 未推进）或未达
    // connected 即硬重连。路径变化（Wi-Fi/蜂窝切
    // 换、断网恢复）同理：已连先探活、未连立即重
    // 连，不再干等 socket 自己报错。

    private func invalidateProbe() {
        probeToken = nil
        probeWork?.cancel()
        probeWork = nil
    }

    private func probeLiveness() {
        guard enabled, !opsDisabled, isPaired,
              transport.isOpen else { return }
        let token = UUID()
        probeToken = token
        probeWork?.cancel()
        let pongAtStart = lastPongAt
        _ = transport.send(
            "{\"moment.control\":\"ping\"}")
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.probeToken == token
            else { return }
            self.probeToken = nil
            if self.linkState == "connected",
               self.lastPongAt > pongAtStart {
                DiagLog.shared.log(.info, "BRIDGE probe ok")
            } else {
                DiagLog.shared.log(.warn,
                    "BRIDGE probe fail state="
                    + "\(self.linkState)")
                self.forceReconnect(reason: "probe_timeout")
            }
        }
        probeWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 5, execute: work)
    }

    private func observePath() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let sig = path.availableInterfaces
                .map { String(describing: $0.type) }
                .joined(separator: ",")
                + (path.status == .satisfied ? "|up" : "|down")
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async {
                self?.handlePath(sig: sig,
                                 satisfied: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(
            label: "moment.bridge.path"))
    }

    private func handlePath(sig: String, satisfied: Bool) {
        let prev = pathSignature
        pathSignature = sig
        // 首报只建基线（启动流程自会连接）；未启用
        // /未配对不动作。
        guard !prev.isEmpty, prev != sig,
              enabled, !opsDisabled, isPaired else { return }
        DiagLog.shared.log(.info,
            "BRIDGE path changed sig=\(sig)")
        guard satisfied else { return }
        if transport.isOpen {
            probeLiveness()
        } else {
            connectNow(reason: "path")
        }
    }

    private func observeScene() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self, self.transport.isOpen else { return }
            _ = self.transport.send(
                "{\"moment.control\":\"presence\","
                + "\"state\":\"background\"}")
            DiagLog.shared.log(.info,
                "BRIDGE presence state=background")
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            DiagLog.shared.log(.info,
                "BRIDGE presence state=foreground")
            if self.transport.isOpen {
                _ = self.transport.send(
                    "{\"moment.control\":\"presence\","
                    + "\"state\":\"foreground\"}")
            } else if self.enabled, !self.opsDisabled {
                if self.isPaired {
                    self.connectNow(reason: "foreground")
                } else {
                    // 回前台校准：配对确认多发生在
                    // App 外（浏览器页），回来时按
                    // 中继事实收敛待配对会话。
                    self.revalidatePairing()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            // 回到前台且 socket 名义在位：5s 探活定
            // 生死（半死连接的唯一快速通道，见
            // probeLiveness 注）。
            guard let self, self.transport.isOpen
            else { return }
            self.probeLiveness()
        }
    }

    // ── 帧处理 ──

    private func handleFrame(_ text: String) {
        guard text.utf8.count <= BridgeProto.maxFrameBytes,
              let obj = BridgeJSON.parseObject(text)
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handleFrameOnMain(obj)
        }
    }

    private func handleFrameOnMain(_ obj: [String: Any]) {
        if let control = obj["moment.control"] as? String {
            handleControl(control, obj)
            return
        }
        guard let method = obj["method"] as? String else {
            return // 响应/通知帧：M1 设备侧不消费
        }
        let id = obj["id"] ?? NSNull()
        if method == "tools/call" {
            let params = obj["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"]
                as? [String: Any] ?? [:]
            BridgeDispatcher.shared.dispatch(
                name: name, args: args,
                library: library, coordinator: self) {
                [weak self] result in
                let resp: [String: Any] = [
                    "jsonrpc": "2.0", "id": id,
                    "result": result,
                ]
                if let text = BridgeJSON.stringify(resp) {
                    _ = self?.transport.send(text)
                }
            }
        } else if obj["id"] != nil {
            let resp: [String: Any] = [
                "jsonrpc": "2.0", "id": id,
                "error": [
                    "code": -32601,
                    "message": "method not found: \(method)",
                    "data": ["code": "unknown_tool"],
                ],
            ]
            if let text = BridgeJSON.stringify(resp) {
                _ = transport.send(text)
            }
        }
    }

    private func handleControl(
        _ control: String, _ obj: [String: Any]) {
        switch control {
        case "challenge":
            guard let nonce = obj["nonce"] as? String,
                  let nonceData = Data(base64Encoded: nonce),
                  let sig = identity.sign(nonceData) else {
                DiagLog.shared.log(.error,
                    "BRIDGE error code=sign_failed "
                    + "where=challenge")
                return
            }
            let resp: [String: Any] = [
                "moment.control": "challenge_response",
                "signature": sig.base64EncodedString(),
            ]
            if let text = BridgeJSON.stringify(resp) {
                _ = transport.send(text)
            }
        case "welcome":
            appSessionId = obj["appSessionId"] as? String ?? ""
            sessionUpAt = Date()
            if let granted = obj["scopes"] as? [String] {
                scopes = granted
                identity.scopes = granted
            }
            backoffAttempt = 0
            setState("connected", reason: "welcome")
            DiagLog.shared.log(.info,
                "BRIDGE session up appSession="
                + "\(appSessionId) scopes="
                + "\(scopes.joined(separator: ","))")
            startHeartbeat()
        case "pong":
            lastPongAt = Date()
        case "revoke-notice":
            identity.clearPairing()
            scopes = []
            stopHeartbeat()
            transport.close(suppressNotify: true)
            DiagLog.shared.log(.warn,
                "BRIDGE revoked via=relay")
            setState("revoked", reason: "relay")
        default:
            break
        }
    }

    // ── 配对 ──

    func pairingURL() -> URL? {
        guard let p = pendingPairing else { return nil }
        var comps = URLComponents(string: BridgeProto.relayBase + "/pair")
        comps?.queryItems = [
            URLQueryItem(name: "pid", value: p.id),
            URLQueryItem(name: "fp", value: p.fingerprint),
        ]
        return comps?.url
    }

    // 待配对会话的落盘/恢复/清除三件套：会话身份
    // 在整个配对流程内稳定，进程死亡、切后台、
    // 本地过期都不得让它凭空消失或被换新。
    private func persistPending(
        _ session: BridgePairingSession) {
        identity.pendingPairingId = session.id
        identity.pendingExpiresAtMs = session.expiresAtMs
    }

    @discardableResult
    private func restorePendingIfNeeded()
        -> BridgePairingSession? {
        if let p = pendingPairing { return p }
        guard let pid = identity.pendingPairingId,
              let fp = identity.fingerprint()
        else { return nil }
        let session = BridgePairingSession(
            id: pid, fingerprint: fp,
            expiresAtMs: identity.pendingExpiresAtMs)
        pendingPairing = session
        return session
    }

    private func dropPending() {
        pollTimer?.invalidate()
        pendingPairing = nil
        identity.clearPendingPairing()
    }

    func beginPairing() {
        if !enabled { setEnabled(true) }
        guard !opsDisabled else { return }
        // 已配对不得被开始动作冲掉：旧实现无条件
        // 新铸 pid，用户见「未配对」再点一次即把
        // 中继已 paired、密钥已注册的旧 pid 孤儿化。
        if isPaired {
            connectNow(reason: "begin_guard")
            return
        }
        // 已有待配对会话则复用同一 pid：未过期续
        // 轮询，已过期先校准定夺（中继可能已
        // paired，本地时钟无权判死）。
        if let p = restorePendingIfNeeded() {
            if Library.epochMs() <= p.expiresAtMs {
                setState("pairing", reason: "begin_resume")
                startPairingPoll()
            } else {
                setState("pairing", reason: "begin_recheck")
            }
            revalidatePairing()
            return
        }
        guard let pub = identity.publicKeyRaw(),
              let fp = identity.fingerprint() else {
            DiagLog.shared.log(.error,
                "BRIDGE error code=identity_unavailable "
                + "where=pairing")
            return
        }
        let pid = UUID().uuidString
        let session = BridgePairingSession(
            id: pid, fingerprint: fp,
            expiresAtMs: Library.epochMs() + 600_000)
        pendingPairing = session
        persistPending(session)
        setState("pairing", reason: "begin")
        DiagLog.shared.log(.info,
            "BRIDGE pairing_started fp=\(fp)")
        let body: [String: Any] = [
            "pairingId": pid,
            "pubKeyB64": pub.base64EncodedString(),
            "fingerprint": fp,
            "label": "Moment iOS",
            "scopes": ["read"],
        ]
        httpJSON(method: "POST", path: "/pair/start",
                 body: body) { [weak self] status, _ in
            guard let self else { return }
            if status != 200 {
                DiagLog.shared.log(.error,
                    "BRIDGE error code=pair_start_failed "
                    + "where=relay http=\(status)")
                self.dropPending()
                self.setState("unpaired",
                              reason: "pair_start_failed")
                return
            }
            self.startPairingPoll()
        }
    }

    /// 状态校准单点（启动/回前台/开启开关/设置页
    /// 出现时调用）：未配对但有待配对会话时向中继
    /// 查一次并按中继事实收敛——收敛不再押在配对
    /// 当时的前台轮询窗口上。
    func revalidatePairing() {
        guard started, enabled, !opsDisabled,
              !isPaired,
              let p = restorePendingIfNeeded()
        else { return }
        DiagLog.shared.log(.info, "BRIDGE revalidate")
        queryPairingStatus(p)
        startPairingPoll()
    }

    private func startPairingPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 2.5, repeats: true) {
            [weak self] _ in
            guard let self,
                  let p = self.pendingPairing else {
                self?.pollTimer?.invalidate()
                return
            }
            self.queryPairingStatus(p)
        }
    }

    /// 向中继查一次待配对会话并按中继事实处置
    /// （轮询与校准共用）：先问中继再谈过期——
    /// 中继对 pending 的过期在 status 读取时自行
    /// 翻转回 expired、对 paired 不设过期，本地
    /// 时钟抢先判定曾把已成功的配对误杀。
    private func queryPairingStatus(
        _ p: BridgePairingSession) {
        httpJSON(method: "GET",
                 path: "/pair/status?pid=" + p.id,
                 body: nil) { [weak self] status, obj in
            guard let self else { return }
            // 会话已被清除/替换则弃答。
            guard self.pendingPairing?.id == p.id
            else { return }
            guard status == 200,
                  let state = obj?["state"] as? String
            else {
                if status == 404 {
                    self.dropPending()
                    self.setState("unpaired",
                                  reason: "pair_unknown")
                } else if Library.epochMs()
                            > p.expiresAtMs {
                    // 无答复且本地已过期：只停轮询、
                    // 内存会话放下，落盘记录保留待
                    // 下次校准定夺（不凭本地时钟判死）。
                    self.pollTimer?.invalidate()
                    self.pendingPairing = nil
                    DiagLog.shared.log(.warn,
                        "BRIDGE pairing_expired")
                    self.setState("unpaired",
                                  reason: "expired")
                }
                return
            }
            switch state {
            case "paired":
                let granted = obj?["scopes"]
                    as? [String] ?? ["read"]
                self.finishPairing(granted: granted)
            case "expired", "revoked", "unknown":
                self.dropPending()
                self.setState("unpaired",
                              reason: "pair_\(state)")
            default:
                break // pending：继续轮询
            }
        }
    }

    private func finishPairing(granted: [String]) {
        guard let p = pendingPairing else { return }
        dropPending()
        identity.pairingId = p.id
        identity.scopes = granted
        scopes = granted
        DiagLog.shared.log(.info,
            "BRIDGE paired scopes="
            + "\(granted.joined(separator: ","))")
        connectNow(reason: "paired")
    }

    func cancelPairing() {
        dropPending()
        DiagLog.shared.log(.info, "BRIDGE pairing_cancelled")
        setState(enabled ? "unpaired" : "off",
                 reason: "pair_cancel")
    }

    /// 断开并吊销：本地先行（删配对记录与设备密
    /// 钥），中继吊销尽力而为（设备签名授权）。
    func disconnectAndRevoke() {
        dropPending()
        stopHeartbeat()
        cancelReconnect()
        sessionUpAt = nil
        transport.close(suppressNotify: true)
        if let pid = identity.pairingId,
           let sig = identity.sign(
               Data("revoke:\(pid)".utf8)) {
            var req = URLRequest(
                url: URL(string: BridgeProto.relayBase
                         + "/pair/revoke")!)
            req.httpMethod = "POST"
            req.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")
            req.setValue(sig.base64EncodedString(),
                         forHTTPHeaderField: "X-Device-Signature")
            req.httpBody = BridgeJSON.stringify(
                ["pairingId": pid])?.data(using: .utf8)
            URLSession.shared.dataTask(with: req) {
                _, _, _ in
            }.resume()
        }
        identity.clearPairing()
        identity.deleteDeviceKey()
        scopes = []
        appSessionId = ""
        DiagLog.shared.log(.warn, "BRIDGE revoked via=app")
        setState(enabled ? "unpaired" : "off",
                 reason: "revoke")
    }

    // ── 调用留痕（分发器回写） ──

    func recordCall(tool: String, code: String, ms: Int) {
        DiagLog.shared.log(.info,
            "BRIDGE tool \(tool) ms=\(ms) code=\(code)")
        recentCalls.insert(
            BridgeCallRecord(tool: tool, code: code,
                             ms: ms, atMs: Library.epochMs()),
            at: 0)
        if recentCalls.count > 20 {
            recentCalls.removeLast(
                recentCalls.count - 20)
        }
    }

    // ── HTTP 小工具（配对面） ──

    private func httpJSON(
        method: String, path: String,
        body: [String: Any]?,
        completion: @escaping (Int, [String: Any]?) -> Void) {
        guard let url = URL(
            string: BridgeProto.relayBase + path) else {
            completion(0, nil)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        if let body {
            req.setValue("application/json",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = BridgeJSON.stringify(body)?
                .data(using: .utf8)
        }
        URLSession.shared.dataTask(with: req) {
            data, resp, _ in
            let status = (resp as? HTTPURLResponse)?
                .statusCode ?? 0
            var obj: [String: Any]?
            if let data {
                obj = try? JSONSerialization.jsonObject(
                    with: data) as? [String: Any]
            }
            DispatchQueue.main.async {
                completion(status, obj)
            }
        }.resume()
    }
}
