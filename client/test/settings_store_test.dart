import 'package:driftclip_client/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsStore> store(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final s = SettingsStore();
    await s.init();
    return s;
  }

  group('setApiBaseUrl 归一化', () {
    test('去除末尾斜杠', () async {
      final s = await store({});
      await s.setApiBaseUrl('http://example.com:26000/');
      expect(s.apiBaseUrl, 'http://example.com:26000');
    });

    test('去除多个末尾斜杠与首尾空白', () async {
      final s = await store({});
      await s.setApiBaseUrl('  https://driftclip.example.com//  ');
      expect(s.apiBaseUrl, 'https://driftclip.example.com');
    });

    test('无斜杠地址原样保留', () async {
      final s = await store({});
      await s.setApiBaseUrl('http://47.96.90.99:26000');
      expect(s.apiBaseUrl, 'http://47.96.90.99:26000');
    });

    test('持久化后可读回', () async {
      final s = await store({
        'api_base_url': 'http://stored.example.com:8080',
      });
      expect(s.apiBaseUrl, 'http://stored.example.com:8080');
    });
  });
}
