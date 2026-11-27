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
  $COMMON -o "$OUT/moment_ffi.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  -primary-file "$HERE/MomentApp.swift" \
  "$HERE/MomentLaunch.swift" "$HERE/MomentOps.swift" \
  "$HERE/MomentRescue.swift" "$HERE/MomentDrag.swift" \
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
  $COMMON -o "$OUT/launch.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  -primary-file "$HERE/MomentOps.swift" \
  "$HERE/MomentRescue.swift" "$HERE/MomentDrag.swift" \
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
  $COMMON -o "$OUT/ops.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" \
  -primary-file "$HERE/MomentRescue.swift" \
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
  $COMMON -o "$OUT/rescue.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  -primary-file "$HERE/MomentDrag.swift" \
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
  $COMMON -o "$OUT/drag.o"
# MCP 桥六文件（M1，plan_app_mcp_bridge.md §9.2）：
# 同拆分例，各自以 -primary-file 出一个 .o。
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  -primary-file "$HERE/MomentBridgeProtocol.swift" \
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
  $COMMON -o "$OUT/bridge_protocol.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  -primary-file "$HERE/MomentBridgeTransport.swift" \
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
  $COMMON -o "$OUT/bridge_transport.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  -primary-file "$HERE/MomentBridge.swift" \
  "$HERE/MomentBridgeTools.swift" \
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
  $COMMON -o "$OUT/bridge_tools.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  -primary-file "$HERE/MomentBridgeOps.swift" \
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
  $COMMON -o "$OUT/bridge_ops.o"
$TC/usr/bin/swift-frontend -frontend -c \
  "$IOSDIR/bindings/moment_ffi.swift" \
  "$HERE/MomentApp.swift" "$HERE/MomentLaunch.swift" \
  "$HERE/MomentOps.swift" "$HERE/MomentRescue.swift" \
  "$HERE/MomentDrag.swift" \
  "$HERE/MomentBridgeProtocol.swift" \
  "$HERE/MomentBridgeTransport.swift" \
  "$HERE/MomentBridge.swift" "$HERE/MomentBridgeTools.swift" \
  "$HERE/MomentBridgeOps.swift" \
  -primary-file "$HERE/MomentBridgeSettings.swift" \
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
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  -primary-file "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
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
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  -primary-file "$HERE/MomentBridgeUITest.swift" \
  "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  $COMMON -o "$OUT/bridge_uitest.o"
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
  "$HERE/MomentBridgeUITest.swift" \
  -primary-file "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  $COMMON -o "$OUT/title_field.o"
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
  -primary-file "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
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
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  -primary-file "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  $COMMON -o "$OUT/liveops.o"
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
  -primary-file "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
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
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  -primary-file "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
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
  "$HERE/MomentBridgeOps.swift" \
  "$HERE/MomentBridgeSettings.swift" \
  "$HERE/MomentEditorTransition.swift" \
  "$HERE/MomentBridgeScenarios.swift" \
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentLiveOps.swift" \
  "$HERE/MomentLiveOpsAttributes.swift" \
  -primary-file "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentSvgRaster.swift" \
  "$HERE/MomentFontFactory.swift" \
  "$HERE/MomentPermissions.swift" \
  $COMMON -o "$OUT/bridge_qr.o"
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
  "$HERE/MomentPermissions.swift" \
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
  -primary-file "$HERE/MomentPermissions.swift" \
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
  -primary-file "$HERE/MomentFontFactory.swift" \
  $COMMON -o "$OUT/font_factory.o"
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
  "$OUT/svg_raster.o" "$OUT/permissions.o" \
  "$OUT/font_factory.o" \
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
  <key>CFBundleShortVersionString</key><string>0.9.58</string>
  <key>CFBundleVersion</key><string>85</string>
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
  <key>UIViewControllerBasedStatusBarAppearance</key><false/>
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
# 把 Moment.entitlements 嵌进主二进制并回读校验——
# 工具内部 verify 不过即非零退出、set -e 中断构建，
# 不带病出包。工具缺失时不中断（verify [33] 会红、
# 出包门拦下），与 accord 缺失同口径。
ENTITLE="$HOME/ios-native/bin/macho-entitle"
if [ -x "$ENTITLE" ]; then
  "$ENTITLE" embed "$APP/Moment" \
    "$HERE/Moment.entitlements" --info "$APP/Info.plist"
  echo "entitlements embedded + verified (aps-environment)"
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
# group 共享容器，矩阵 #27），置入 PlugIns/ 后封包。
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
APPEX="$APP/PlugIns/MomentLiveOpsWidget.appex"
mkdir -p "$APPEX"
cp "$OUT/MomentLiveOpsWidget" "$APPEX/MomentLiveOpsWidget"
chmod 755 "$APPEX/MomentLiveOpsWidget"
cp "$HERE/MomentLiveOpsWidget-Info.plist" \
  "$APPEX/Info.plist"
if [ -x "$ENTITLE" ]; then
  "$ENTITLE" embed "$APPEX/MomentLiveOpsWidget" \
    "$HERE/MomentLiveOpsWidget.entitlements" \
    --info "$APPEX/Info.plist"
  echo "widget extension injected (empty entitlements)"
else
  echo "widget extension injected (no entitle tool)"
fi

rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
cp -r "$APP" "$OUT/Payload/"
IPA=$OUT/Moment-stage2.ipa
(cd "$OUT" && rm -f "$IPA" && zip -qr "$IPA" Payload)
ls -la "$IPA"
