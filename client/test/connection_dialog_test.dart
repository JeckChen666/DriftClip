import 'package:driftclip_client/screens/settings_screen.dart';
import 'package:driftclip_client/services/api_client.dart';
import 'package:driftclip_client/services/clipboard_monitor.dart';
import 'package:driftclip_client/services/desktop_integration.dart';
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

  // 构造设置页 + 已配置的连接（dc_old_key / http://stored:8080）。
  Future<SettingsStore> harness(
    WidgetTester tester, {
    required http.Client client,
  }) async {
    SharedPreferences.setMockInitialValues({
      'api_base_url': 'http://stored:8080',
      'api_key': 'dc_old_key',
    });
    final settings = SettingsStore();
    await settings.init();
    final dedup = DedupStore();
    await dedup.init();
    final uploader = UploadCoordinator(
      api: ApiClient(settings: settings, client: client),
      dedup: dedup,
      settings: settings,
      platform: 'macos',
      osVersion: '',
      deviceModel: '',
      appVersion: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: settings,
          monitor: ClipboardMonitor(uploader: uploader, isDesktop: false),
          desktop: DesktopIntegration(),
          uploader: uploader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('连接区合并为单个「编辑连接」入口，弹窗预填服务地址与 Key', (tester) async {
    await harness(
      tester,
      client: MockClient((req) async => http.Response('{"items": []}', 200)),
    );

    // 两个旧行都不再带按钮，只有卡片区一个「编辑连接」
    expect(find.text('编辑'), findsNothing);
    expect(find.text('重新配置'), findsNothing);
    expect(find.text('编辑连接'), findsOneWidget);
    expect(find.text('http://stored:8080'), findsOneWidget);
    expect(find.text('dc_ol…（已配置）'), findsOneWidget);

    await tester.tap(find.text('编辑连接'));
    await tester.pumpAndSettle();

    expect(find.text('编辑连接'), findsNWidgets(2)); // 按钮保持 + 弹窗标题
    expect(find.widgetWithText(TextField, '服务地址'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Key'), findsOneWidget);
  });

  testWidgets('弹窗保存：先校验连通性，成功后持久化并提示', (tester) async {
    await harness(
      tester,
      client: MockClient((req) async {
        expect(req.url.host, 'newhost');
        expect(req.headers['authorization'], 'Bearer dc_new_key');
        return http.Response('{"items": []}', 200);
      }),
    );

    await tester.tap(find.text('编辑连接'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '服务地址'),
      'http://newhost:26000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Key'),
      'dc_new_key',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('连接成功，配置已保存'), findsOneWidget);
    final prefs = SharedPreferences.getInstance();
    expect((await prefs).getString('api_key'), 'dc_new_key');
    expect((await prefs).getString('api_base_url'), 'http://newhost:26000');
  });

  testWidgets('弹窗保存失败：显示原因、弹窗不关闭、配置不变', (tester) async {
    await harness(
      tester,
      client: MockClient((req) async {
        throw http.ClientException('refused');
      }),
    );

    await tester.tap(find.text('编辑连接'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '服务地址'),
      'http://unreachable:1',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('无法连接服务器，请检查服务地址与网络'), findsOneWidget);
    expect(find.widgetWithText(TextField, '服务地址'), findsOneWidget);
    final prefs = SharedPreferences.getInstance();
    expect((await prefs).getString('api_key'), 'dc_old_key');
    expect((await prefs).getString('api_base_url'), 'http://stored:8080');
  });
}
