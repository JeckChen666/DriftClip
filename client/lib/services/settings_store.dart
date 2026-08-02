import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 客户端本地设置：服务地址、Key、监听开关、自动启动偏好、安装 ID。
/// 全部持久化到 shared_preferences。
///
/// 安装 ID 规则（Spec §2.1）：每次安装生成随机 UUID 并安全保存，
/// 不来自硬件，重装后变化。
class SettingsStore {
  static const _kApiBaseUrl = 'api_base_url';
  static const _kApiKey = 'api_key';
  static const _kListen = 'listen_enabled';
  static const _kAutoStart = 'auto_start';
  static const _kInstallId = 'installation_id';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError('SettingsStore 未初始化，请先调用 init()');
    }
    return p;
  }

  /// 默认服务地址在打包时内置（Spec §8.1），可用 --dart-define=DRIFTCLIP_API_BASE=... 覆盖；
  /// 用户可在设置中修改并持久化。
  String get apiBaseUrl =>
      _p.getString(_kApiBaseUrl) ??
      const String.fromEnvironment('DRIFTCLIP_API_BASE',
          defaultValue: 'http://127.0.0.1:8080');
  Future<void> setApiBaseUrl(String v) => _p.setString(_kApiBaseUrl, v);

  String? get apiKey => _p.getString(_kApiKey);
  Future<void> setApiKey(String? v) {
    if (v == null || v.isEmpty) {
      return _p.remove(_kApiKey);
    }
    return _p.setString(_kApiKey, v.trim());
  }

  /// 监听默认关闭，必须由用户显式打开（Spec §5.2）。
  bool get listenEnabled => _p.getBool(_kListen) ?? false;
  Future<void> setListenEnabled(bool v) => _p.setBool(_kListen, v);

  /// 「登录后自动启动」默认关闭（Spec §5.3），桌面端生效。
  bool get autoStart => _p.getBool(_kAutoStart) ?? false;
  Future<void> setAutoStart(bool v) => _p.setBool(_kAutoStart, v);

  String installationId() {
    var id = _p.getString(_kInstallId);
    if (id == null || id.isEmpty) {
      id = _generateUuidV4();
      _p.setString(_kInstallId, id);
    }
    return id;
  }

  String _generateUuidV4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
