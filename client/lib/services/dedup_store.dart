import 'package:shared_preferences/shared_preferences.dart';

/// 客户端本地去重摘要（Spec §4.2）：
/// - 只保存最近一次【成功上传】正文的 SHA-256 摘要，不保存完整正文；
/// - 跨应用重启保存；
/// - 更换 Key 时清除摘要（由设置 Key 的流程调用 clear()）。
class DedupStore {
  static const _kLastHash = 'last_uploaded_sha256';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? get lastHash => _prefs?.getString(_kLastHash);

  Future<void> update(String sha256Hex) async {
    await _prefs?.setString(_kLastHash, sha256Hex);
  }

  Future<void> clear() async {
    await _prefs?.remove(_kLastHash);
  }
}
