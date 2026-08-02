import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// 桌面端集成：托盘常驻与登录自启动。
///
/// 关闭主窗口行为（Spec §5.3）：开启监听时关闭主窗口 → 最小化到托盘继续监听；
/// 未开启监听时关闭主窗口 → 退出应用。决策逻辑为纯函数，便于测试。
/// 托盘图标资源与真实托盘交互需真机验证（本机无法构建原生平台）。
class DesktopIntegration {
  static final bool isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static const _appName = 'DriftClip';

  /// 关闭主窗口时是否最小化到托盘（Spec §5.3）。
  static bool shouldCloseToTray({required bool listening}) =>
      isDesktop && listening;

  /// 初始化登录自启动。托盘图标资源（assets/icon.png）需后续提供，
  /// 缺失时静默降级，不影响核心功能。
  Future<void> init() async {
    if (!isDesktop) return;
    try {
      LaunchAtStartup.instance.setup(
        appName: _appName,
        appPath: Platform.resolvedExecutable,
      );
    } catch (_) {
      // 平台不支持时静默降级
    }
  }

  /// 注册/注销「登录后自动启动」（默认关闭，Spec §5.3）。
  Future<void> setAutoStart(bool enabled) async {
    if (!isDesktop) return;
    try {
      if (enabled) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
    } catch (_) {
      // 静默降级；自启动是增强能力
    }
  }
}
