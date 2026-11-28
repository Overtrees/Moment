import SwiftUI
import UIKit

// ── 状态栏根容器（impl_statusbar_native_adapt-
// ation）──────────────────────────────────────
// 用户 2026-11-28 方案第三条的回答面：回答者唯
// 一——本容器是全应用唯一实现 preferredStatus
// BarStyle 的控制器，且 childForStatusBarStyle
// 恒 nil（系统不会再向下问子控制器，容器之答
// 即全应用之答）；判定本体在 StatusBarEngine
// 单点，容器只负责回答与送达触发（布局/外观变
// 化）。UIApplication 旧 setter 在 iOS 27 为空
// 操作，全仓不用（既有口径）。
//
// 承载形态（与三轮根容器换根的区别，即本批不
// 重蹈闪现覆辙的构造）：容器不是启动后换上的
// window 根，而是 WindowGroup 根视图本体——
// 经 UIViewControllerRepresentable 在首帧即为
// 框架根承载的子控制器，内嵌一个 UIHosting
// Controller 持有原根 SwiftUI 视图（ListView/
// RescueView 分流 + 开屏层 + 铬面探针，逐项原
// 样）。无 window.rootViewController 替换、无
// 呈现、无根切换；开屏单承载序列（fix_splash_
// flash_sequence）结构零改动。
//
// 转发链前提（真机终判点，报告 §留账 1）：框架
// 根承载把状态栏询问沿 childForStatusBarStyle
// 转发给子控制器——本应用编辑/图片承载的
// override 在 0.9.5x 多轮真机生效即此链的实证
// （询问确达导航栈顶层承载）；本容器是根承载
// 的直接子控制器、同链受问。引擎在首次受问时
// 记 STATUSBAR answerer live 一行，装机后桥回
// 读有此行即链活、无此行即链断（届时改走每页
// 自答的回退评估，不在此预埋第二机制）。

/// 根容器呈现体：WindowGroup 根视图包一层本容
/// 器，原根视图整体作 content 嵌入。
struct StatusBarRootContainer<Content: View>:
    UIViewControllerRepresentable {
    /// 启动期初始底层（App 构建根时已知：安全
    /// 模式 → rescue；开屏资源就绪 → splash；
    /// 余 root）——容器首问前引擎即有正确底层，
    /// 其后由根的报告点（setBase）随状态更新。
    let initialSurface: StatusBarSurface
    @ViewBuilder var content: () -> Content

    func makeUIViewController(
        context: Context) -> ContainerViewController {
        let vc = ContainerViewController()
        let host = UIHostingController(rootView: content())
        vc.embed(host)
        StatusBarEngine.shared.attach(answerer: vc,
                                      base: initialSurface)
        return vc
    }

    func updateUIViewController(
        _ vc: ContainerViewController,
        context: Context) {
        vc.host?.rootView = content()
    }

    /// 回答者本体：内嵌托管控制器持原根视图；
    /// 本类只答状态栏一件（+ 布局/外观触发送达
    /// 引擎），其余控制器行为全走系统默认。
    final class ContainerViewController:
        UIViewController {
        private(set) var host: UIHostingController<Content>?

        func embed(_ host: UIHostingController<Content>) {
            addChild(host)
            // 同引擎侧：view 在本工具链 SDK 接
            // 口为 Optional，先 loadViewIfNeeded
            // 再解包（原 IUO 语义下访问即加载，
            // 行为等价）。
            loadViewIfNeeded()
            host.loadViewIfNeeded()
            guard let view else { return }
            view.addSubview(host.view)
            host.view.frame = view.bounds
            host.view.autoresizingMask =
                [.flexibleWidth, .flexibleHeight]
            host.didMove(toParent: self)
            self.host = host
        }

        /// 回答者唯一性钉子：不向下转发询问。
        override var childForStatusBarStyle:
            UIViewController? { nil }

        override var preferredStatusBarStyle:
            UIStatusBarStyle {
            StatusBarEngine.shared.answer()
        }

        /// 布局落定触发（带高/尺寸变 → 引擎重估；
        /// 与 viewDidLayoutSubviews 节流口径等价
        /// ——evaluate 幂等且廉价，翻转另有去抖与
        /// 驻留门把关，不会因布局频次抖动）。
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            StatusBarEngine.shared.noteLayout()
        }

        /// 外观/特征变化送达（全应用唯一外观订
        /// 阅点，fix_statusbar_appearance_
        /// trigger）：userInterfaceStyle 变化 =
        /// 外观切换确定性事件 → 引擎确定性入口
        /// （重算 + 直落，不经去抖候选）；其余
        /// trait 变化（内容尺寸等）仍走普通重估
        /// 通道。style 过滤同时合并同帧重复触发
        /// （一次切换 style 只变一次）。
        override func traitCollectionDidChange(
            _ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            if previous?.userInterfaceStyle
                != traitCollection.userInterfaceStyle {
                StatusBarEngine.shared
                    .noteAppearanceChanged()
            } else {
                StatusBarEngine.shared.noteTrait()
            }
        }
    }
}
