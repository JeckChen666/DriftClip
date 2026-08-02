import 'package:driftclip_client/services/dedup_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('去重摘要持久化并跨实例保留', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DedupStore();
    await store.init();
    await store.update('abc123');

    // 模拟重启：新的实例读取同一存储
    final store2 = DedupStore();
    await store2.init();
    expect(store2.lastHash, 'abc123');
  });

  test('clear 清除摘要', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DedupStore();
    await store.init();
    await store.update('abc');
    await store.clear();
    expect(store.lastHash, isNull);
  });
}
