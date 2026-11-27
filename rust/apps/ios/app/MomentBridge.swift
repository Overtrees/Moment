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

    func clearPairing() {
        kcDelete("pairingId")
        kcDelete("scopes")
        kcDelete("pairedAtMs")
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

    var isPaired: Bool { identity.pairingId != nil }
    var deviceFingerprint: String? { identity.fingerprint() }
    /// 分发器形态：安全模式 = 受限（仅 bridge_status），
    /// 正常 = 完整只读集。
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
        if !enabled {
            setState("off", reason: "start")
        } else if !isPaired {
            setState("unpaired", reason: "start")
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
            } else {
                setState("unpaired", reason: "toggle")
            }
        } else {
            cancelReconnect()
            stopHeartbeat()
            transport.close(suppressNotify: true)
            setState("off", reason: "toggle")
        }
    }

    // ── 连接管理 ──

    private func wireTransport() {
        transport.onText = { [weak self] text in
            self?.handleFrame(text)
        }
        transport.onSocketDown = { [weak self] in
            DispatchQueue.main.async {
                self?.handleSocketDown()
            }
        }
    }

    private func connectNow(reason: String) {
        guard let pid = identity.pairingId else {
            setState("unpaired", reason: reason)
            return
        }
        cancelReconnect()
        setState("connecting", reason: reason)
        transport.connect(pairingId: pid)
    }

    private func handleSocketDown() {
        stopHeartbeat()
        guard enabled, !opsDisabled, isPaired else {
            setState(enabled ? "unpaired" : "off",
                     reason: "socket_down")
            return
        }
        backoffAttempt += 1
        setState("backoff", reason: "socket_down")
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
                self.transport.close(suppressNotify: true)
                self.handleSocketDown()
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
            } else if self.enabled, !self.opsDisabled,
                      self.isPaired {
                self.connectNow(reason: "foreground")
            }
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

    func beginPairing() {
        if !enabled { setEnabled(true) }
        guard !opsDisabled else { return }
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
                self.pendingPairing = nil
                self.setState("unpaired",
                              reason: "pair_start_failed")
                return
            }
            self.startPairingPoll()
        }
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
            if Library.epochMs() > p.expiresAtMs {
                self.pollTimer?.invalidate()
                self.pendingPairing = nil
                DiagLog.shared.log(.warn,
                    "BRIDGE pairing_expired")
                self.setState("unpaired", reason: "expired")
                return
            }
            self.httpJSON(
                method: "GET",
                path: "/pair/status?pid="
                    + p.id, body: nil) { status, obj in
                guard status == 200,
                      let state = obj?["state"] as? String
                else { return }
                if state == "paired" {
                    let granted = obj?["scopes"]
                        as? [String] ?? ["read"]
                    self.finishPairing(granted: granted)
                } else if state == "expired"
                            || state == "revoked" {
                    self.pollTimer?.invalidate()
                    self.pendingPairing = nil
                    self.setState("unpaired",
                                  reason: "pair_\(state)")
                }
            }
        }
    }

    private func finishPairing(granted: [String]) {
        pollTimer?.invalidate()
        guard let p = pendingPairing else { return }
        identity.pairingId = p.id
        identity.scopes = granted
        scopes = granted
        pendingPairing = nil
        DiagLog.shared.log(.info,
            "BRIDGE paired scopes="
            + "\(granted.joined(separator: ","))")
        connectNow(reason: "paired")
    }

    func cancelPairing() {
        pollTimer?.invalidate()
        pendingPairing = nil
        DiagLog.shared.log(.info, "BRIDGE pairing_cancelled")
        setState(enabled ? "unpaired" : "off",
                 reason: "pair_cancel")
    }

    /// 断开并吊销：本地先行（删配对记录与设备密
    /// 钥），中继吊销尽力而为（设备签名授权）。
    func disconnectAndRevoke() {
        pollTimer?.invalidate()
        pendingPairing = nil
        stopHeartbeat()
        cancelReconnect()
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
