import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'clipboard_monitor.dart';
import 'settings_store.dart';
import 'upload_coordinator.dart';

/// 桌面端集成：托盘常驻、关窗最小化与登录自启动（ROADMAP P1.1–P1.3）。
///
/// 关闭主窗口行为（Spec §5.3）：开启监听时关闭主窗口 → 隐藏到托盘继续监听；
/// 未开启监听时关闭主窗口 → 退出应用。决策逻辑为纯函数，便于测试。
class DesktopIntegration with TrayListener, WindowListener {
  static final bool isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// macOS 登录自启动走自定义通道（原生侧用 SMAppService 实现，ROADMAP P1.3）；
  /// launch_at_startup 插件没有 macOS 原生实现，只在 Windows/Linux 使用。
  static const _macChannel = MethodChannel('driftclip/desktop');

  static const _appName = 'DriftClip';
  static const _trayIconPath = 'assets/tray/tray_icon.png';

  ClipboardMonitor? _monitor;
  SettingsStore? _settings;
  UploadCoordinator? _uploader;
  bool _listening = false;
  bool _trayReady = false;

  /// 关闭主窗口时是否最小化到托盘（Spec §5.3）。
  static bool shouldCloseToTray({required bool listening}) =>
      isDesktop && listening;

  /// 当前平台是否展示「登录自启动」开关（仅桌面；移动端无自启动概念）。
  static bool get supportsAutoStart => isDesktop;

  /// 初始化托盘、关窗拦截与自启动插件注册。
  /// 须在 main() 中 windowManager.ensureInitialized() 之后调用。
  Future<void> init({
    ClipboardMonitor? monitor,
    SettingsStore? settings,
    UploadCoordinator? uploader,
  }) async {
    _monitor = monitor;
    _settings = settings;
    _uploader = uploader;
    if (!isDesktop) return;

    if (!Platform.isMacOS) {
      // Windows/Linux：launch_at_startup 为纯 Dart 注册表/.desktop 实现。
      try {
        LaunchAtStartup.instance.setup(
          appName: _appName,
          appPath: Platform.resolvedExecutable,
        );
      } catch (_) {
        // 平台不支持时静默降级
      }
    }

    _listening = settings?.listenEnabled ?? false;
    try {
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
    } catch (_) {
      // 拦截失败时退化为系统默认关窗行为
    }
    await _initTray();
    _uploader?.syncStatus.addListener(_onSyncStatusChanged);
  }

  /// 监听状态变化（设置页 / 托盘两个入口）后刷新托盘菜单。
  Future<void> setListening(bool v) async {
    _listening = v;
    await refreshTrayMenu();
  }

  /// 注册/注销「登录后自动启动」（默认关闭，Spec §5.3）。
  Future<void> setAutoStart(bool enabled) async {
    if (!isDesktop) return;
    try {
      if (Platform.isMacOS) {
        await _macChannel.invokeMethod('setLoginItemEnabled', {
          'enabled': enabled,
        });
        return;
      }
      if (enabled) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
    } catch (_) {
      // 静默降级；自启动是增强能力
    }
  }

  // —— 托盘 ————————————————————————————————————————————————

  Future<void> _initTray() async {
    try {
      trayManager.addListener(this);
      await trayManager.setIcon(_trayIconPath);
      await trayManager.setToolTip(_appName);
      await refreshTrayMenu();
      _trayReady = true;
    } catch (_) {
      // 托盘初始化失败（图标缺失/平台差异）不影响主功能
    }
  }

  /// 按当前监听状态与待同步条数刷新托盘菜单（ROADMAP P1.5）。
  Future<void> refreshTrayMenu() async {
    try {
      final pending = _uploader?.syncStatus.value.pendingCount ?? 0;
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '打开主窗口'),
            MenuItem.separator(),
            MenuItem(
              key: 'toggle-listen',
              label: _listening ? '暂停剪贴板监听' : '恢复剪贴板监听',
            ),
            MenuItem(
              key: 'pending',
              label: pending > 0 ? '待同步：$pending 条，将自动补传' : '已全部同步',
            ),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出 DriftClip'),
          ],
        ),
      );
    } catch (_) {
      // 托盘不可用时忽略
    }
  }

  void _onSyncStatusChanged() {
    if (_trayReady) {
      unawaited(refreshTrayMenu());
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showMainWindow();
      case 'toggle-listen':
        final v = !_listening;
        _settings?.setListenEnabled(v);
        if (v) {
          _monitor?.start();
        } else {
          _monitor?.stop();
        }
        unawaited(setListening(v));
      case 'quit':
        unawaited(windowManager.destroy());
    }
  }

  @override
  void onTrayIconMouseDown() {
    _showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  Future<void> _showMainWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // 窗口管理不可用时忽略
    }
  }

  // —— 关窗行为（WindowListener） ————————————————————————————
  @override
  void onWindowClose() async {
    if (shouldCloseToTray(listening: _listening)) {
      try {
        await windowManager.hide();
        return;
      } catch (_) {
        // 隐藏失败则继续走退出
      }
    }
    try {
      await windowManager.destroy();
    } catch (_) {
      // 忽略：窗口可能已销毁
    }
  }
}
