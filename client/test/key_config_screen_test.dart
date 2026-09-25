import 'package:driftclip_client/screens/key_config_screen.dart';
import 'package:driftclip_client/services/api_client.dart';
import 'package:driftclip_client/services/dedup_store.dart';
import 'package:driftclip_client/services/settings_store.dart';
import 'package:driftclip_client/services/upload_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> harness(
    WidgetTester tester, {
    required http.Client Function() mockClient,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsStore();
    await settings.init();
    final dedup = DedupStore();
    await dedup.init();
    final uploader = UploadCoordinator(
      api: ApiClient(settings: settings, client: mockClient()),
      dedup: dedup,
      settings: settings,
      platform: 'macos',
      osVersion: '',
      deviceModel: '',
      appVersion: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: KeyConfigScreen(
          settings: settings,
          uploader: uploader,
          onSaved: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('保存前校验连通性：成功则入库并提示连接成功', (tester) async {
    var historyRequested = false;
    await harness(
      tester,
      mockClient:
          () => MockClient((req) async {
            if (req.method == 'GET' && req.url.path == '/api/v1/history') {
              historyRequested = true;
              expect(req.url.toString(), startsWith('http://47.96.90.99:26000'));
              expect(req.headers['authorization'], 'Bearer dc_good_key');
              return http.Response('{"items": [], "total": 0}', 200);
            }
            return http.Response('{"error": "not found"}', 404);
          }),
    );

    await tester.enterText(
      find.widgetWithText(TextField, '服务地址'),
      'http://47.96.90.99:26000',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'dc_good_key');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(historyRequested, isTrue, reason: '保存前应实际请求服务端校验');
    expect(find.textContaining('连接成功，配置已保存'), findsOneWidget);
    final prefs = SharedPreferences.getInstance();
    expect((await prefs).getString('api_key'), 'dc_good_key');
    expect((await prefs).getString('api_base_url'), 'http://47.96.90.99:26000');
  });

  testWidgets('校验失败：显示原因，不写入任何配置', (tester) async {
    await harness(
      tester,
      mockClient:
          () => MockClient((req) async {
            throw http.ClientException('连接被拒绝');
          }),
    );

    await tester.enterText(
      find.widgetWithText(TextField, '服务地址'),
      'http://127.0.0.1:8080',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'dc_any');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('无法连接服务器，请检查服务地址与网络'), findsOneWidget);
    expect(find.textContaining('连接成功'), findsNothing);
    final prefs = SharedPreferences.getInstance();
    expect((await prefs).getString('api_key'), isNull);
    expect((await prefs).getString('api_base_url'), isNull);
  });

  testWidgets('Key 无效（401）：提示 Key 无效，不写入配置', (tester) async {
    await harness(
      tester,
      mockClient:
          () => MockClient((req) async {
            // 含中文的响应体必须声明 UTF-8，否则 http.Response 构造即抛
            // （默认 Latin-1 编码），真实服务端响应均带 charset=utf-8。
            return http.Response(
              '{"error": "无效的 Key"}',
              401,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'dc_bad');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Key 无效'), findsOneWidget);
    final prefs = SharedPreferences.getInstance();
    expect((await prefs).getString('api_key'), isNull);
  });
}
