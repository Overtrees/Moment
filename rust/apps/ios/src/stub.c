/* __isPlatformVersionAtLeast 桩：该符号由真机 Swift 运行时
 * 提供，Linux 工具链无实现，链接期补等价桩（ios-dev-linux
 * 技能 link.md ②）。部署目标 16.0：major<=16 返回 1。 */
int __isPlatformVersionAtLeast(int platform, int major, int minor, int patch) {
  (void)platform; (void)minor; (void)patch;
  return major <= 16 ? 1 : 0;
}
