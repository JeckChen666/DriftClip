import 'dart:convert';

import 'package:driftclip_client/services/api_client.dart';
import 'package:driftclip_client/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ApiClient> client(MockClient mock, {String? key}) async {
    SharedPreferences.setMockInitialValues({'api_key': key ?? 'dc_test'});
    final settings = SettingsStore();
    await settings.init();
    return ApiClient(settings: settings, client: mock);
  }

  test('上传成功返回 id', () async {
    final api = await client(MockClient((req) async {
      expect(req.url.path, '/api/v1/history');
      expect(req.headers['authorization'], 'Bearer dc_test');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['source'], 'manual');
      return http.Response('{"id": 42}', 201,
          headers: {'content-type': 'application/json'});
    }));
    final r = await api.upload(const HistoryDraft(
      content: 'x',
      source: 'manual',
      platform: 'macos',
      osVersion: '',
      deviceModel: '',
      appVersion: '',
      installationId: 'i',
    ));
    expect(r.ok, isTrue);
    expect(r.data, 42);
  });

  test('列表解析 items', () async {
    final api = await client(MockClient((req) async {
      return http.Response(
        '{"items":[{"id":1,"content_preview":"预览","source":"clipboard",'
        '"received_at":"2026-08-02T19:00:00+08:00","platform":"macos",'
        '"os_version":"","device_model":"","app_version":"","installation_id":""}],'
        '"total":1,"page":1,"page_size":20}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }));
    final r = await api.list();
    expect(r.ok, isTrue);
    expect(r.data!.length, 1);
    expect(r.data!.first.contentPreview, '预览');
  });

  test('401 返回 fail 且携带状态', () async {
    final api = await client(MockClient((_) async =>
        http.Response('{"error":"Key 无效或已被重置"}', 401,
            headers: {'content-type': 'application/json'})));
    final r = await api.list();
    expect(r.ok, isFalse);
    expect(r.status, 401);
  });

  test('删除 204 返回 ok', () async {
    final api = await client(MockClient((req) async {
      expect(req.method, 'DELETE');
      expect(req.url.path, '/api/v1/history/9');
      return http.Response('', 204);
    }));
    final r = await api.delete(9);
    expect(r.ok, isTrue);
  });
}
