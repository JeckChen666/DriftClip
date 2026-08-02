import 'dart:convert';

import 'package:driftclip_client/screens/home_screen.dart';
import 'package:driftclip_client/screens/key_config_screen.dart';
import 'package:driftclip_client/screens/manual_input_dialog.dart';
import 'package:driftclip_client/services/api_client.dart';
import 'package:driftclip_client/services/clipboard_monitor.dart';
import 'package:driftclip_client/services/dedup_store.dart';
import 'package:driftclip_client/services/desktop_integration.dart';
import 'package:driftclip_client/services/settings_store.dart';
import 'package:driftclip_client/services/upload_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyConfigScreen', () {
    testWidgets('保存 Key 后调用 onSaved 并持久化、清除去重摘要', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsStore();
      await settings.init();
      final dedup = DedupStore();
      await dedup.init();
      await dedup.update('old-hash');
      final api = ApiClient(settings: settings, client: MockClient((_) async =>
          http.Response('{"id":1}', 201,
              headers: {'content-type': 'application/json'})));
      final up = UploadCoordinator(api: api, dedup: dedup, settings: settings);

      String? savedKey;
      await tester.pumpWidget(MaterialApp(
        home: KeyConfigScreen(
          settings: settings,
          uploader: up,
          onSaved: (k) => savedKey = k,
        ),
      ));

      await tester.enterText(find.byType(TextField).at(1), 'dc_xyz');
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(savedKey, 'dc_xyz');
      expect(settings.apiKey, 'dc_xyz');
      expect(dedup.lastHash, isNull); // 换 Key 清除摘要（Spec §4.2）
    });

    testWidgets('空 Key 不允许保存', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsStore();
      await settings.init();
      final dedup = DedupStore();
      await dedup.init();
      final api = ApiClient(settings: settings, client: MockClient((_) async =>
          http.Response('{}', 200,
              headers: {'content-type': 'application/json'})));
      final up = UploadCoordinator(api: api, dedup: dedup, settings: settings);

      await tester.pumpWidget(MaterialApp(
        home: KeyConfigScreen(
          settings: settings,
          uploader: up,
          onSaved: (_) => fail('空 Key 不应保存'),
        ),
      ));
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('请粘贴 Web 端生成的 Key'), findsOneWidget);
    });
  });

  group('HomeScreen', () {
    testWidgets('渲染历史列表并可单条删除', (tester) async {
      SharedPreferences.setMockInitialValues({'api_key': 'dc_test'});
      final settings = SettingsStore();
      await settings.init();
      final dedup = DedupStore();
      await dedup.init();

      final requests = <http.Request>[];
      final api = ApiClient(
        settings: settings,
        client: MockClient((req) async {
          requests.add(req);
          if (req.method == 'DELETE') return http.Response('', 204);
          if (req.url.path == '/api/v1/history') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 1,
                    'content_preview': '预览内容',
                    'source': 'clipboard',
                    'received_at': '2026-08-02T19:00:00+08:00',
                    'platform': 'macos',
                    'os_version': '15',
                    'device_model': 'MacBook',
                    'app_version': '1.0.0',
                    'installation_id': 'i',
                  }
                ],
                'total': 1,
                'page': 1,
                'page_size': 20,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"error":"not found"}', 404,
              headers: {'content-type': 'application/json'});
        }),
      );
      final up = UploadCoordinator(api: api, dedup: dedup, settings: settings);
      final monitor = ClipboardMonitor(uploader: up);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          settings: settings,
          api: api,
          uploader: up,
          monitor: monitor,
          desktop: DesktopIntegration(),
        ),
      ));
      // 等待列表异步加载完成
      await tester.pumpAndSettle();

      expect(find.text('预览内容'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(
        requests.any((r) => r.method == 'DELETE' && r.url.path == '/api/v1/history/1'),
        isTrue,
      );
    });

    testWidgets('多选删除调用 batch-delete', (tester) async {
      SharedPreferences.setMockInitialValues({'api_key': 'dc_test'});
      final settings = SettingsStore();
      await settings.init();
      final dedup = DedupStore();
      await dedup.init();
      final requests = <http.Request>[];
      final api = ApiClient(
        settings: settings,
        client: MockClient((req) async {
          requests.add(req);
          if (req.url.path == '/api/v1/history/batch-delete') {
            return http.Response('{"deleted":1}', 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path == '/api/v1/history') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 1,
                    'content_preview': '第一条',
                    'source': 'clipboard',
                    'received_at': '2026-08-02T19:00:00+08:00',
                    'platform': 'macos',
                    'os_version': '',
                    'device_model': '',
                    'app_version': '',
                    'installation_id': '',
                  },
                  {
                    'id': 2,
                    'content_preview': '第二条',
                    'source': 'manual',
                    'received_at': '2026-08-02T19:00:01+08:00',
                    'platform': 'windows',
                    'os_version': '',
                    'device_model': '',
                    'app_version': '',
                    'installation_id': '',
                  }
                ],
                'total': 2,
                'page': 1,
                'page_size': 20,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"error":"x"}', 404,
              headers: {'content-type': 'application/json'});
        }),
      );
      final up = UploadCoordinator(api: api, dedup: dedup, settings: settings);
      final monitor = ClipboardMonitor(uploader: up);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          settings: settings,
          api: api,
          uploader: up,
          monitor: monitor,
          desktop: DesktopIntegration(),
        ),
      ));
      await tester.pumpAndSettle();

      // 进入选择模式并勾选第一条
      await tester.tap(find.byTooltip('多选删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-select-1')));
      await tester.pump();

      await tester.tap(find.text('删除所选（1）'));
      await tester.pumpAndSettle();

      expect(
        requests.any((r) => r.url.path == '/api/v1/history/batch-delete'),
        isTrue,
      );
    });

    testWidgets('清空全部需 5 秒倒计时确认', (tester) async {
      SharedPreferences.setMockInitialValues({'api_key': 'dc_test'});
      final settings = SettingsStore();
      await settings.init();
      final dedup = DedupStore();
      await dedup.init();
      final requests = <http.Request>[];
      final api = ApiClient(
        settings: settings,
        client: MockClient((req) async {
          requests.add(req);
          if (req.url.path == '/api/v1/history/clear') {
            return http.Response('{"deleted":1}', 200,
                headers: {'content-type': 'application/json'});
          }
          if (req.url.path == '/api/v1/history') {
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 1,
                    'content_preview': '待清空',
                    'source': 'clipboard',
                    'received_at': '2026-08-02T19:00:00+08:00',
                    'platform': 'macos',
                    'os_version': '',
                    'device_model': '',
                    'app_version': '',
                    'installation_id': '',
                  }
                ],
                'total': 1,
                'page': 1,
                'page_size': 20,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{"error":"x"}', 404,
              headers: {'content-type': 'application/json'});
        }),
      );
      final up = UploadCoordinator(api: api, dedup: dedup, settings: settings);
      final monitor = ClipboardMonitor(uploader: up);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          settings: settings,
          api: api,
          uploader: up,
          monitor: monitor,
          desktop: DesktopIntegration(),
        ),
      ));
      await tester.pumpAndSettle();

      // 进入选择模式（清空按钮在选择栏内）
      await tester.tap(find.byTooltip('多选删除'));
      await tester.pumpAndSettle();

      // 倒计时期间按钮不可点击
      await tester.tap(find.byKey(const ValueKey('start-clear')));
      await tester.pump();
      expect(find.textContaining('清空全部（'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-clear')), findsNothing);

      // 5 秒后出现「确认清空全部」
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-clear')));
      await tester.pumpAndSettle();

      expect(
        requests.any((r) => r.url.path == '/api/v1/history/clear'),
        isTrue,
      );
    });
  });

  group('ManualInputDialog', () {
    testWidgets('提交返回输入的文本', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const ManualInputDialog(),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '手动文本');
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();
      expect(result, '手动文本');
    });
  });
}
