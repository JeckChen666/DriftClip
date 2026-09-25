import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// 设备元数据采集（Spec §3.1）：
/// 只采集平台、系统版本、设备名与客户端版本，不采集硬件序列号/MAC/精确位置。
class DeviceInfo {
  // 版本号唯一来源是 pubspec（ROADMAP P0.5）：启动时经 init() 读取一次，
  // 读取失败或测试环境未初始化时使用回退值。
  static String _appVersion = '0.0.0-dev';

  static String platform() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem; // windows / macos / linux / android / ios
  }

  static String osVersion() => kIsWeb ? '' : Platform.operatingSystemVersion;

  static String deviceModel() => kIsWeb ? '' : Platform.localHostname;

  static String appVersion() => _appVersion;

  /// main() 启动时调用一次，从系统包信息读取 pubspec 中声明的版本号。
  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      // 保持回退值：版本号仅用于展示与排查
    }
  }
}
