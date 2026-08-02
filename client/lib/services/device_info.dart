import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 设备元数据采集（Spec §3.1）：
/// 只采集平台、系统版本、设备名与客户端版本，不采集硬件序列号/MAC/精确位置。
class DeviceInfo {
  static String platform() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem; // windows / macos / linux / android / ios
  }

  static String osVersion() => kIsWeb ? '' : Platform.operatingSystemVersion;

  static String deviceModel() => kIsWeb ? '' : Platform.localHostname;

  static String appVersion() => '0.1.0';
}
