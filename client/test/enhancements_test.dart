// P05 增强：桌面关闭行为决策、剪贴板监听前后台生命周期。
import 'package:driftclip_client/services/api_client.dart';
import 'package:driftclip_client/services/clipboard_monitor.dart';
import 'package:driftclip_client/services/dedup_store.dart';
import 'package:driftclip_client/services/desktop_integration.dart';
import 'package:driftclip_client/services/settings_store.dart';
import 'package:driftclip_client/services/upload_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UploadCoordinator> _makeUploader() async {
  SharedPreferences.setMockInitialValues({'api_key': 'k'});
  final settings = SettingsStore();
  await settings.init();
  final dedup = DedupStore();
  await dedup.init();
  final api = ApiClient(settings: settings, client: MockClient((_) async =>
      http.Response('{"id":1}', 201,
          headers: {'content-type': 'application/json'})));
  return UploadCoordinator(api: api, dedup: dedup, settings: settings);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopIntegration.shouldCloseToTray', () {
    test('开启监听时关闭主窗口 → 最小化到托盘继续监听（Spec §5.3）', () {
      if (!DesktopIntegration.isDesktop) {
        // 非桌面环境跳过（当前测试宿主机为 macOS，桌面）
        return;
      }
      expect(DesktopIntegration.shouldCloseToTray(listening: true), isTrue);
      expect(DesktopIntegration.shouldCloseToTray(listening: false), isFalse);
    });
  });

  group('ClipboardMonitor 前后台生命周期', () {
    test('移动端：后台暂停采集，回到前台恢复（Spec §5.2）', () async {
      final m = ClipboardMonitor(
        uploader: await _makeUploader(),
        isDesktop: false,
      );
      m.start();
      expect(m.isPolling, isTrue);

      m.handleAppLifecycle(AppLifecycleState.paused);
      expect(m.isPolling, isFalse, reason: '移动端后台不应持续监听');

      m.handleAppLifecycle(AppLifecycleState.resumed);
      expect(m.isPolling, isTrue, reason: '回到前台恢复采集');

      m.stop();
    });

    test('桌面端：常驻监听不受前后台影响', () async {
      final m = ClipboardMonitor(
        uploader: await _makeUploader(),
        isDesktop: true,
      );
      m.start();
      expect(m.isPolling, isTrue);

      m.handleAppLifecycle(AppLifecycleState.paused);
      expect(m.isPolling, isTrue, reason: '桌面端常驻时继续监听');

      m.stop();
    });
  });
}
