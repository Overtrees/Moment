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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  -primary-file "$HERE/MomentBridgeUITest.swift" \
  "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" \
  -primary-file "$HERE/TitleTextField.swift" \
  "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
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
  "$HERE/MomentBridgeUITest.swift" "$HERE/TitleTextField.swift" \
  -primary-file "$HERE/TitleTapCaret.swift" \
  "$HERE/MomentBridgeQR.swift" \
  $COMMON -o "$OUT/title_caret.o"
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentBridgeQR.swift" \
  "$HERE/MomentBridgeQR.swift" \
  -primary-file "$HERE/MomentBridgeQR.swift" \
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
  "$OUT/title_caret.o" \
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
  <key>CFBundleShortVersionString</key><string>0.9.57</string>
  <key>CFBundleVersion</key><string>84</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UISupportedInterfaceOrientations~ipad</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
  <key>NSLocationWhenInUseUsageDescription</key><string>用于显示你所在城市的天气</string>
  <key>UILaunchScreen</key><dict><key>UIColorName</key><string>LaunchBackground</string><key>UIImageRespectsSafeAreaInsets</key><false/></dict>
  <key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
  <key>UIViewControllerBasedStatusBarAppearance</key><false/>
  <key>CFBundleIcons</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
  <key>CFBundleIcons~ipad</key><dict><key>CFBundlePrimaryIcon</key><dict><key>CFBundleIconName</key><string>AppIcon</string></dict></dict>
</dict>
</plist>
PLIST

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

rm -rf "$OUT/Payload" && mkdir -p "$OUT/Payload"
cp -r "$APP" "$OUT/Payload/"
IPA=$OUT/Moment-stage2.ipa
(cd "$OUT" && rm -f "$IPA" && zip -qr "$IPA" Payload)
ls -la "$IPA"
