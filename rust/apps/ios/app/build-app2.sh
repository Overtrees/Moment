#!/bin/bash
# Moment 原生阶段 2 构建：SwiftUI 应用 + moment-ffi →
# Moment.app（bundle id com.canopies.moment）→ ipa。
# 链路同 spike/build-spike.sh（ios-dev-linux 口径）。
set -euo pipefail
TC=$HOME/ios-native/swift-6.4.2-RELEASE-ubuntu22.04
SDK=$HOME/ios-native/iPhoneOS27.2.sdk
RD=$HOME/ios-native/swift-resource
MODS=$HOME/ios-native/mods
SKILL=$HOME/workspace/custom-skills/ios-dev-linux
HERE=$(cd "$(dirname "$0")" && pwd)
IOSDIR=$(dirname "$HERE")
OUT=$HERE/build
mkdir -p "$OUT"
CLANG=/usr/lib/llvm-18/bin/clang

XCC="-Xcc -I$SDK/usr/include -Xcc -fmodule-map-file=$SDK/usr/include/dispatch.modulemap -Xcc -fmodule-map-file=$IOSDIR/bindings/moment_ffiFFI.modulemap"
COMMON="-target arm64-apple-ios16.0 -sdk $SDK -resource-dir $RD -module-cache-path $HOME/ios-native/swift-cache -module-name MomentMain -swift-version 5 -parse-as-library -Onone -I$MODS -I$IOSDIR/bindings $XCC"

$TC/usr/bin/swift-frontend -frontend -c \
  -primary-file "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/moment_ffi.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  -primary-file "$HERE/MomentApp.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentLaunch.swift" "$HERE/MomentOps.swift" \
  "$HERE/MomentRescue.swift" "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/app.o"
# 0.9.45 自救批拆分文件（拒绝上帝文件）：各自以
# -primary-file 出一个 .o，其余全部 Swift 文件作
# 次级输入（跨文件符号可见），$COMMON 原样。
# 0.9.47 起 MomentDrag.swift（拖拽按压引擎）同此例。
# 0.9.50 起 MomentEditorTransition.swift（编辑器转
# 场宿主）同此例。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" \
  -primary-file "$HERE/MomentLaunch.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/launch.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  -primary-file "$HERE/MomentOps.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentRescue.swift" "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/ops.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" \
  -primary-file "$HERE/MomentRescue.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/rescue.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  -primary-file "$HERE/MomentDrag.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/drag.o"
# MCP 桥六文件（M1，plan_app_mcp_bridge.md §9.2）：
# 同拆分例，各自以 -primary-file 出一个 .o。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  -primary-file "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_protocol.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  -primary-file "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_transport.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  -primary-file "$HERE/MomentBridge.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" \
  -primary-file "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_tools.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  -primary-file "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_ops.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  -primary-file "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_settings.o"
# 编辑器转场宿主（0.9.50 呈现重构）：同拆分例，
# 以 -primary-file 出 transition.o。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  -primary-file "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/transition.o"
# U1 批新文件（UI 自检驱动 / 标题字段 representable /
# 落点映射纯函数）：同拆分例，各自以 -primary-file
# 出一个 .o。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  -primary-file "$HERE/MomentBridgeUITest.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_uitest.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" \
  -primary-file "$HERE/TitleTextField.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/title_field.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  -primary-file "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/title_caret.o"
# 权限/实况批新文件（LiveOps 封装 / 实况共享属性）：
# 同拆分例，各自以 -primary-file 出一个 .o；其余
# 15 遍已把两文件作次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  -primary-file "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/liveops.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  -primary-file "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/liveops_attr.o"
# M3a 批新文件（桥场景库/引擎/journal/量测解析）：
# 同拆分例，以 -primary-file 出一个 .o；其余 18
# 遍已把本文件作次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  -primary-file "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_scenarios.o"
# 配对二维码批新文件（配对页 URL → 二维码图纯函
# 数）：同拆分例，以 -primary-file 出一个 .o；其
# 余 19 遍已把它作次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  -primary-file "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/bridge_qr.o"
# 快照恢复批新文件（M3 backup_restore_snapshot
# 工具本体 BridgeBackupTools）：同拆分例，以
# -primary-file 出一个 .o；其余各遍已把它作次
# 级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/bridge_restore.o"
# SVG 光栅化批新文件（解码漏斗 SVG 内容嗅探分
# 流 / 离屏 WKWebView 光栅化）：同拆分例，以
# -primary-file 出一个 .o；其余 20 遍已把它作
# 次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  -primary-file "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  $COMMON -o "$OUT/svg_raster.o"
# 权限中心批新文件（权限状态真读 / 请求分发 /
# 本地网络探针 / 权限页）：同拆分例，以
# -primary-file 出一个 .o；其余 21 遍已把它作
# 次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentPermissions.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/permissions.o"
# 字体工厂批新文件（fix_dynamic_type_follow：类
# 别中枢 FontHub + 缩放工厂 FontFactory）：同拆
# 分例，以 -primary-file 出一个 .o；其余 22 遍
# 已把它作次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/font_factory.o"
# E2 撤销体系新文件（impl_editor_undo_e2：撤销
# 历史纯状态机 UndoHistoryCore）：同拆分例，以
# -primary-file 出一个 .o；其余各遍已把它作次级
# 输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentUndo.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/undo.o"
# F-09 一期跨块选区新文件（impl_cross_block_
# selection_p1：纯核心 MomentXSel + 桥接层
# MomentXSelBridge）：同拆分例，各以
# -primary-file 出一个 .o。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentXSel.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentImageLoad.swift" \
  $COMMON -o "$OUT/xsel.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/xsel_bridge.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/imageload.o"
# 开屏独立承载拆分文件（fix_statusbar_dynamic
# 立）：primary 一遍。（状态栏采样两文件的
# primary 遍已随采样整套去除拆除，remove_
# statusbar_sampling。）
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  -primary-file "$HERE/MomentSplashHost.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  $COMMON -o "$OUT/splash_host.o"
# 入树等待共享工具新文件（补丁债偿还批一 A-5：
# ViewTreeWait 逐帧复查单点）：同拆分例，以
# -primary-file 出一个 .o；其余各遍已把它作次
# 级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  $COMMON -o "$OUT/treewait.o"
# 状态栏判定引擎新文件（impl_statusbar_native_
# adaptation：相对明度判定 + 去抖/驻留/淡变状
# 态机）：同拆分例，以 -primary-file 出一个
# .o；其余各遍已把它作次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  $COMMON -o "$OUT/statusbar_engine.o"
# 状态栏根容器新文件（impl_statusbar_native_
# adaptation：全应用唯一状态栏回答者）：同拆
# 分例，以 -primary-file 出一个 .o；其余各遍
# 已把它作次级输入（跨文件符号可见）。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentStatusBarRoot.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarPixel.swift" \
  $COMMON -o "$OUT/statusbar_root.o"
# 状态栏像素保底新文件（impl_statusbar_native_
# adaptation：CGImage 点取 / CALayer 离屏 /
# 视频帧三采样器）：同拆分例，以 -primary-file
# 出一个 .o；其余各遍已把它作次级输入。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeRestore.swift" \
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  "$HERE/MomentUndo.swift" \
  "$HERE/MomentXSel.swift" \
  "$HERE/MomentImageLoad.swift" \
  "$HERE/MomentXSelBridge.swift" \
  "$HERE/MomentSplashHost.swift" \
  -primary-file "$HERE/MomentStatusBarPixel.swift" \
  "$HERE/MomentTreeWait.swift" \
  "$HERE/MomentStatusBarEngine.swift" \
  "$HERE/MomentStatusBarRoot.swift" \
  $COMMON -o "$OUT/statusbar_pixel.o"
echo "objects ok"

"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" -c \
  "$IOSDIR/src/stub.c" -o "$OUT/stub.o"
export PATH=/usr/lib/llvm-18/bin:$PATH
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -fuse-ld=lld -Wl,-adhoc_codesign \
  -L$SDK/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -framework SwiftUI -framework WebKit -framework UIKit -framework Foundation -framework CoreLocation \
  -o "$OUT/Moment" "$OUT/app.o" "$OUT/moment_ffi.o" \
  "$OUT/launch.o" "$OUT/ops.o" "$OUT/rescue.o" \
  "$OUT/drag.o" "$OUT/transition.o" \
  "$OUT/bridge_protocol.o" "$OUT/bridge_transport.o" \
  "$OUT/bridge.o" "$OUT/bridge_tools.o" \
  "$OUT/bridge_ops.o" "$OUT/bridge_settings.o" \
  "$OUT/bridge_uitest.o" "$OUT/title_field.o" \
  "$OUT/title_caret.o" "$OUT/liveops.o" \
  "$OUT/bridge_scenarios.o" \
  "$OUT/liveops_attr.o" "$OUT/bridge_qr.o" \
  "$OUT/bridge_restore.o" \
  "$OUT/svg_raster.o" "$OUT/permissions.o" \
  "$OUT/font_factory.o" "$OUT/undo.o" \
  "$OUT/xsel.o" "$OUT/xsel_bridge.o" \
  "$OUT/imageload.o" \
  "$OUT/splash_host.o" "$OUT/treewait.o" \
  "$OUT/statusbar_engine.o" "$OUT/statusbar_root.o" \
  "$OUT/statusbar_pixel.o" \
  "$IOSDIR/../../target/aarch64-apple-ios/ios/libmoment_ffi.a" \
  "$OUT/stub.o"
python3 "$SKILL/scripts/check-macho.py" "$OUT/Moment"

APP=$OUT/Moment.app
rm -rf "$APP" && mkdir -p "$APP"
cp "$OUT/Moment" "$APP/Moment"
chmod 755 "$APP/Moment"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>此刻</string>
  <key>CFBundleExecutable</key><string>Moment</string>
  <key>CFBundleIdentifier</key><string>com.canopies.moment</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Moment</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.9.66</string>
  <key>CFBundleVersion</key><string>93</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>NSLocationWhenInUseUsageDescription</key><string>用于显示你所在城市的天气</string>
  <key>NSCameraUsageDescription</key><string>用于拍摄照片并添加到备忘</string>
  <key>NSPhotoLibraryUsageDescription</key><string>用于从相册选取照片和视频添加到备忘</string>
  <key>NSPhotoLibraryAddUsageDescription</key><string>用于把备忘中的图片保存到相册</string>
  <key>NSMicrophoneUsageDescription</key><string>用于录制语音并添加到备忘</string>
  <key>NSFaceIDUsageDescription</key><string>用于通过面容 ID 解锁应用</string>
  <key>NSLocalNetworkUsageDescription</key><string>用于在局域网内发现并连接你的其他设备</string>
  <key>NSBonjourServices</key><array><string>_moment._tcp</string></array>
  <key>NSCalendarsUsageDescription</key><string>用于访问你的日历</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>用于访问你的日历</string>
  <key>NSRemindersUsageDescription</key><string>用于访问你的提醒事项</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>用于访问你的提醒事项</string>
  <key>NSSupportsLiveActivities</key><true/>
  <key>NSSupportsLiveActivitiesFrequentUpdates</key><true/>
  <key>UIBackgroundModes</key><array><string>remote-notification</string><string>processing</string><string>fetch</string></array>
  <key>BGTaskSchedulerPermittedIdentifiers</key><array><string>com.canopies.moment.bg.processing</string><string>com.canopies.moment.bg.refresh</string></array>
  <key>UILaunchScreen</key><dict><key>UIColorName</key><string>LaunchBackground</string><key>UIImageRespectsSafeAreaInsets</key><false/></dict>
  <key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
  <key>UIViewControllerBasedStatusBarAppearance</key><true/>
  <key>CFBundleIcons</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
  <key>CFBundleIcons~ipad</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
</dict>
</plist>
PLIST

# 五语 InfoPlist.strings（权限批提前落地 i18n I5 的
# 系统面部分）：显示名五语 + 七项用途串本地化，主
# plist 内保留 zh-CN 默认值、.strings 按系统语言
# 覆盖。文案真源 = impl_ios_entitlements_liveops.md
# §四全表，改文案先改报告再改此处（verify [33] 锁
# 键集五份一致）。
write_infoplist_strings() {
  # $1 = lproj 目录名，$2 = 显示名，其后 11 个参数依次为
  # 定位/相机/相册读/相册写/麦克风/FaceID/本地网络/
  # 日历（旧）/日历（全访问）/提醒（旧）/提醒（全访问）。
  # 日历/提醒四串为权限中心批增补（impl_permission_
  # center.md）：A 段矩阵 #12 原裁不声明，本批按用户
  # 权限中心口径补声明以使 EventKit 请求路径存在。
  local dir="$APP/$1.lproj"
  mkdir -p "$dir"
  {
    printf '"CFBundleDisplayName" = "%s";\n' "$2"
    printf '"NSLocationWhenInUseUsageDescription" = "%s";\n' "$3"
    printf '"NSCameraUsageDescription" = "%s";\n' "$4"
    printf '"NSPhotoLibraryUsageDescription" = "%s";\n' "$5"
    printf '"NSPhotoLibraryAddUsageDescription" = "%s";\n' "$6"
    printf '"NSMicrophoneUsageDescription" = "%s";\n' "$7"
    printf '"NSFaceIDUsageDescription" = "%s";\n' "$8"
    printf '"NSLocalNetworkUsageDescription" = "%s";\n' "$9"
    printf '"NSCalendarsUsageDescription" = "%s";\n' "${10}"
    printf '"NSCalendarsFullAccessUsageDescription" = "%s";\n' "${11}"
    printf '"NSRemindersUsageDescription" = "%s";\n' "${12}"
    printf '"NSRemindersFullAccessUsageDescription" = "%s";\n' "${13}"
  } > "$dir/InfoPlist.strings"
}
write_infoplist_strings zh-Hans "此刻" \
  "用于显示你所在城市的天气" \
  "用于拍摄照片并添加到备忘" \
  "用于从相册选取照片和视频添加到备忘" \
  "用于把备忘中的图片保存到相册" \
  "用于录制语音并添加到备忘" \
  "用于通过面容 ID 解锁应用" \
  "用于在局域网内发现并连接你的其他设备" \
  "用于访问你的日历" \
  "用于访问你的日历" \
  "用于访问你的提醒事项" \
  "用于访问你的提醒事项"
write_infoplist_strings zh-Hant "此刻" \
  "用於顯示你所在城市的天氣" \
  "用於拍攝照片並加入備忘" \
  "用於從相簿選取照片和影片加入備忘" \
  "用於把備忘中的圖片儲存到相簿" \
  "用於錄製語音並加入備忘" \
  "用於透過面容 ID 解鎖應用程式" \
  "用於在區域網路內尋找並連接你的其他裝置" \
  "用於存取你的日曆" \
  "用於存取你的日曆" \
  "用於存取你的提醒事項" \
  "用於存取你的提醒事項"
write_infoplist_strings en "Moment" \
  "Show the weather for the city you are in" \
  "Take photos and add them to your notes" \
  "Pick photos and videos from your library to add to your notes" \
  "Save images from your notes to your photo library" \
  "Record voice and add it to your notes" \
  "Unlock the app with Face ID" \
  "Discover and connect to your other devices on the local network" \
  "Access your calendar" \
  "Access your calendar" \
  "Access your reminders" \
  "Access your reminders"
write_infoplist_strings ja "瞬間" \
  "現在いる都市の天気を表示するために使用します" \
  "写真を撮影してメモに追加するために使用します" \
  "ライブラリから写真やビデオを選んでメモに追加するために使用します" \
  "メモの画像をフォトライブラリに保存するために使用します" \
  "音声を録音してメモに追加するために使用します" \
  "Face IDでアプリのロックを解除するために使用します" \
  "ローカルネットワーク上の他のデバイスを検出して接続するために使用します" \
  "カレンダーにアクセスするために使用します" \
  "カレンダーにアクセスするために使用します" \
  "リマインダーにアクセスするために使用します" \
  "リマインダーにアクセスするために使用します"
write_infoplist_strings ko "순간" \
  "현재 계신 도시의 날씨를 표시하는 데 사용됩니다" \
  "사진을 촬영해 메모에 추가하는 데 사용됩니다" \
  "보관함에서 사진과 동영상을 선택해 메모에 추가하는 데 사용됩니다" \
  "메모의 이미지를 사진 보관함에 저장하는 데 사용됩니다" \
  "음성을 녹음해 메모에 추가하는 데 사용됩니다" \
  "Face ID로 앱 잠금을 해제하는 데 사용됩니다" \
  "로컬 네트워크에서 다른 기기를 찾아 연결하는 데 사용됩니다" \
  "캘린더에 접근하는 데 사용됩니다" \
  "캘린더에 접근하는 데 사용됩니다" \
  "미리 알림에 접근하는 데 사용됩니다" \
  "미리 알림에 접근하는 데 사용됩니다"
echo "InfoPlist.strings injected (5 locales)"

# Entitlements 嵌入（权限批）：ld64.lld 的 adhoc 签名
# 不带 entitlements，装机重签会原样保留二进制内嵌集，
# 故构建期以 macho-entitle（tree ~/ios-native/bin，
# 自补工具、源码 workspace/ios-tools/macho_entitle.py）
# 把 Moment.entitlements 嵌进主二进制——embed 收尾自
# 带 AMFI 口径全量校验（validate：签名区落 __LINKEDIT
# 内 + 全部页哈希自洽），不过即非零退出、set -e 中断
# 构建，不带病出包；下方再显式 validate 一道硬门
# （fix_install_signing_0958：0.9.58 起旧工具嵌坏签名
# 面而自带弱校验全程绿灯的根治）。工具缺失时不中断
# （verify [33] 会红、出包门拦下），与 accord 同口径。
ENTITLE="$HOME/ios-native/bin/macho-entitle"
if [ -x "$ENTITLE" ]; then
  "$ENTITLE" embed "$APP/Moment" \
    "$HERE/Moment.entitlements" --info "$APP/Info.plist"
  "$ENTITLE" validate "$APP/Moment" --info "$APP/Info.plist"
  echo "entitlements embedded + validated (aps-environment)"
else
  echo "macho-entitle NOT found, bundle without entitlements"
fi

# 应用图标 + 开屏底色（Assets.car 路线，2026-11-26
# 定案）：真源在 icon-src/——moment.icon（Icon
# Composer 三外观：浅/深/着色）+ Assets.xcassets
# （LaunchBackground colorset，浅 #2379DC / 深
# #1F1F21，与开屏底色同值）。用 accord（Linux 版
# actool，~/ios-native/bin/accord）编译：.icon 包名
# 即 catalog 内图标名，故先复制改名 AppIcon.icon
# 对齐 CFBundleIconName=AppIcon（包内一字不动）。
# 只把 Assets.car 装进 .app；accord 顺手吐的散落
# AppIcon*.png 绝不入包（入包系统就按普通 PNG 图
# 标处理、不读 car——技能 package.md 口径）。
# accord 缺失时不中断构建，但 verify [8] 会红、
# 出包门拦下。构建目录放 $OUT（/tmp 是 512M
# tmpfs，car 中间产物会把它撑爆）。
ACCORD="$HOME/ios-native/bin/accord"
CARWORK="$OUT/carbuild"
if [ -x "$ACCORD" ] && [ -f "$HERE/icon-src/moment.icon/icon.json" ]; then
  rm -rf "$CARWORK" && mkdir -p "$CARWORK"
  cp -R "$HERE/icon-src/moment.icon" "$CARWORK/AppIcon.icon"
  cp -R "$HERE/icon-src/Assets.xcassets" "$CARWORK/Assets.xcassets"
  "$ACCORD" --compile "$CARWORK/out" \
    --platform iphoneos \
    --minimum-deployment-target 16.0 \
    --app-icon AppIcon \
    --target-device iphone --target-device ipad \
    --output-partial-info-plist "$CARWORK/out/partial.plist" \
    --output-format human-readable-text \
    "$CARWORK/AppIcon.icon" "$CARWORK/Assets.xcassets"
  cp "$CARWORK/out/Assets.car" "$APP/Assets.car"
  echo "Assets.car injected (icon 3 appearances + LaunchBackground colorset)"
else
  echo "accord or icon-src NOT found, bundle without Assets.car"
fi

# 开屏矢量资源（用户素材包 native-splash）：原生开屏
# 视图只读这两份 vector.json（Canvas 矢量绘制，PNG
# 素材同目录留档、位图路径未启用）。
for th in light dark; do
  SJ="$HERE/assets/native-splash/MomentSplash-$th-vector.json"
  if [ -f "$SJ" ]; then
    cp "$SJ" "$APP/"
    echo "splash vector injected ($th)"
  else
    echo "splash vector NOT found ($th)"
  fi
done

# 天气 key 构建注入（用户裁定）：源文件在仓外
# ~/ios-native/weather-keys.json（不入 git）；存在则打进
# bundle，缺失则天气链按 Web 无 key 口径静默不发请求。
if [ -f "$HOME/ios-native/weather-keys.json" ]; then
  cp "$HOME/ios-native/weather-keys.json" "$APP/weather-keys.json"
  echo "weather keys injected (bundle)"
else
  echo "weather keys NOT found, bundle without keys"
fi

# 五语语言包（原生 i18n I1，立项 plan_native_i18n.md）：
# 真源 = Web 语言包 rust/apps/web/lang/*.json，构建
# 时原样拷入 .app/lang/——单一真源、与 Web 永远同
# 源，完整性由 verify [9] 以 md5 对账。缺源时不中断
# 构建，但 verify [9] 会红、出包门拦下。
LANGSRC="$HERE/../../web/lang"
if [ -f "$LANGSRC/zh-CN.json" ]; then
  mkdir -p "$APP/lang"
  cp "$LANGSRC"/*.json "$APP/lang/"
  echo "lang packs injected (5, from web source)"
else
  echo "lang packs NOT found, bundle without lang"
fi

# Live Activity 扩展（权限批，定案 §5.2）：可见实况
# 必须有 widget extension 绘制。两文件以 $COMMON 同
# 旗标编译（模块名与主 App 同为 MomentMain——
# ActivityAttributes 跨进程按类型全名匹配，两侧同名
# 同构是硬要求），单独链接成 appex 二进制、自有
# Info.plist、entitlements 为空集（实况不依赖 app
# group 共享容器，矩阵 #27）。编译与 check-macho
# 保持（防代码腐烂），捆绑与否由下方开关门控。
# 捆绑开关（0.9.61 装机过渡处置，定案 fix_
# install_signing_0958.md 附记）：用户二分实测
# ——交付包去掉 appex 后可装（剥 entitlements
# 版与保留 entitlements 版均可装）、带 appex
# 的两版（原版与 VB）均不可装，消去法闭合：
# 真阻因 = appex 本体被捆绑。机理未定，候选
# 含现行签名通道的 profile 不覆盖 appex 的
# bundle id（com.canopies.moment.liveops）、
# 签名通道对嵌套 bundle 的处理、appex 结构面
# 等，根治排查另线展开（diag_appex_install.
# md）——本开关只是过渡：保证本版可装，appex
# 照常编译 + check-macho（防腐烂）但不拷入
# PlugIns/ 交付；待根治定案、appex 以可装形
# 态回归时，把开关置 1 即恢复捆绑（下方版本
# 同步与 entitle/validate 随开关一并恢复）。
BUNDLE_WIDGET_EXT=0
$TC/usr/bin/swift-frontend -frontend -c \
  -primary-file "$HERE/MomentLiveOpsWidget.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  $COMMON -o "$OUT/liveops_widget.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$HERE/MomentLiveOpsWidget.swift" \
  -primary-file "$HERE/MomentLiveOpsAttributes.swift" \
  $COMMON -o "$OUT/liveops_widget_attr.o"
"$CLANG" -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -fuse-ld=lld -Wl,-adhoc_codesign \
  -L$SDK/usr/lib/swift -Wl,-rpath,/usr/lib/swift \
  -framework SwiftUI -framework WidgetKit \
  -framework UIKit -framework Foundation \
  -o "$OUT/MomentLiveOpsWidget" \
  "$OUT/liveops_widget.o" "$OUT/liveops_widget_attr.o" \
  "$OUT/stub.o"
python3 "$SKILL/scripts/check-macho.py" \
  "$OUT/MomentLiveOpsWidget"
if [ "$BUNDLE_WIDGET_EXT" = 1 ]; then
APPEX="$APP/PlugIns/MomentLiveOpsWidget.appex"
mkdir -p "$APPEX"
cp "$OUT/MomentLiveOpsWidget" "$APPEX/MomentLiveOpsWidget"
chmod 755 "$APPEX/MomentLiveOpsWidget"
cp "$HERE/MomentLiveOpsWidget-Info.plist" \
  "$APPEX/Info.plist"
# appex 版本与主程序单源同步（fix_install_signing_
# 0958）：静态 plist 的版本曾冻在 0.9.57/84、与主程序
# 逐版脱钩；拷入后以刚生成的主程序 Info.plist 为单
# 源回写两键，再走 entitle（slot-1 哈希的须是同步
# 后的 plist，故同步必须在 embed 之前）。
python3 - "$APP/Info.plist" "$APPEX/Info.plist" <<'PYEOF'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    main_plist = plistlib.load(f)
with open(sys.argv[2], "rb") as f:
    appex_plist = plistlib.load(f)
appex_plist["CFBundleShortVersionString"] = \
    main_plist["CFBundleShortVersionString"]
appex_plist["CFBundleVersion"] = main_plist["CFBundleVersion"]
with open(sys.argv[2], "wb") as f:
    plistlib.dump(appex_plist, f, fmt=plistlib.FMT_XML)
PYEOF
if [ -x "$ENTITLE" ]; then
  "$ENTITLE" embed "$APPEX/MomentLiveOpsWidget" \
    "$HERE/MomentLiveOpsWidget.entitlements" \
    --info "$APPEX/Info.plist"
  "$ENTITLE" validate "$APPEX/MomentLiveOpsWidget" \
    --info "$APPEX/Info.plist"
  echo "widget extension injected (empty entitlements, validated)"
else
  echo "widget extension injected (no entitle tool)"
fi
else
  echo "widget extension compiled + checked only, NOT bundled (BUNDLE_WIDGET_EXT=0; install root-fix)"
fi

# 封包硬断言（0.9.61 装机根治）：开关关闭时交付
# .app 内绝不允许出现 PlugIns/，在场即停构建、
# 不带病出包（与 verify [52] INS52-3 同锁）。
if [ "$BUNDLE_WIDGET_EXT" != 1 ] && [ -e "$APP/PlugIns" ]; then
  echo "FATAL: BUNDLE_WIDGET_EXT off but PlugIns present in app bundle" >&2
  exit 1
fi

rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
cp -r "$APP" "$OUT/Payload/"
IPA=$OUT/Moment-stage2.ipa
(cd "$OUT" && rm -f "$IPA" && zip -qr "$IPA" Payload)
ls -la "$IPA"
