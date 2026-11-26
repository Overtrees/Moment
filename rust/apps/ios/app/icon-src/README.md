# icon-src — Assets.car 编译输入（真源）

本目录是 iOS 图标与系统开屏静态帧的**唯一真源**，由
`.github/workflows/build-assets-car.yml`（macos-26 + Xcode 26）在 CI 上
编译成 `Assets.car`，产物以 base64 分片回填到 `../assets-car/`。

- `Mynote.icon/` — Icon Composer 源包（原壳素材，用户提供）。
  icon.json 内含 light/dark/tinted 三种 appearance 的图层透明度特化，
  **原样保真编译，禁止改图层/改 json**。
  注意：actool 以 .icon 包的**文件名 stem** 作为图标在 catalog 内的
  名字，本 app 的 CFBundleIconName 是 `AppIcon`，所以工作流会先把它
  复制改名为 `AppIcon.icon` 再编译（包内内容一字不动）。
- `splash-layers/` — 开屏分层 PNG 与 bounds.json（原壳素材）。
- `composite_launch.py` — 把分层 PNG 按 bounds 合成为全屏静态帧：
  `python3 composite_launch.py` → `LaunchBackground-light.png` /
  `LaunchBackground-dark.png`（1179×2556）。静态帧供 UILaunchScreen 的
  LaunchBackground imageset 使用，与 app 内矢量开屏首帧同构。
- `LaunchBackground-*.png` — 上述合成成品（已提交，工作流直接取用）。

本地（Linux）编不出 Assets.car（actool 仅 macOS/Xcode），改图标或开屏
素材后：更新本目录 → 若改了分层图先重跑 composite_launch.py →
手动触发 build-assets-car 工作流 → 主线把 assets-car 分片解码回
Assets.car 并接入 build-app2.sh。
