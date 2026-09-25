import 'dart:convert';
import 'dart:io';

import 'package:driftclip_client/services/api_client.dart';
import 'package:driftclip_client/services/dedup_store.dart';
import 'package:driftclip_client/services/settings_store.dart';
import 'package:driftclip_client/services/upload_coordinator.dart';
import 'package:driftclip_client/services/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假 HTTP：记录每个请求，并按预置的状态码队列依次响应。
class _FakeHttp {
  final List<http.Request> requests = [];
  final List<int> statuses;

  _FakeHttp([List<int>? statuses]) : statuses = statuses ?? [];

  MockClient client() => MockClient((request) async {
        requests.add(request);
        final status = statuses.isNotEmpty ? statuses.removeAt(0) : 201;
        return http.Response(
          status < 400 ? '{"id": 1}' : '{"error":"内部错误"}',
          status,
          headers: {'content-type': 'application/json'},
        );
      });
}

/// 构建依赖并返回。delays 注入毫秒级以便快速测试重试时序。
Future<(SettingsStore, DedupStore, UploadCoordinator)> _setup(
  _FakeHttp f, {
  String? key = 'dc_test_key',
  List<Duration>? delays,
  UploadQueue? queue,
}) async {
  SharedPreferences.setMockInitialValues({'api_key': key ?? ''});
  final settings = SettingsStore();
  await settings.init();
  final dedup = DedupStore();
  await dedup.init();
  final api = ApiClient(settings: settings, client: f.client());
  final up = UploadCoordinator(
    api: api,
    dedup: dedup,
    settings: settings,
    queue: queue,
    platform: 'macos',
    osVersion: 'test-os',
    deviceModel: 'TestBox',
    appVersion: '0.1.0',
    delays: delays ?? const [Duration(milliseconds: 5), Duration(milliseconds: 5)],
  );
  return (settings, dedup, up);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('去重：与最近成功上传一致时不发请求；失败不更新摘要', () async {
    // 状态码队列：第一次上传成功(201)，之后 new-content 三次都失败(500,500,500)
    final f = _FakeHttp([201, 500, 500, 500]);
    final (_, dedup, up) = await _setup(f);

    expect(await up.uploadText('hello', source: 'clipboard'), isTrue);
    expect(f.requests.length, 1);
    expect(dedup.lastHash, UploadCoordinator.sha256Hex('hello'));

    // 相同文本再次复制 → 不发请求
    expect(await up.uploadText('hello', source: 'clipboard'), isTrue);
    expect(f.requests.length, 1);

    // 新文本三次上传都失败（500）→ 不更新摘要，再次复制相同新文本会重试
    expect(await up.uploadText('new-content', source: 'clipboard'), isFalse);
    expect(dedup.lastHash, UploadCoordinator.sha256Hex('hello'));
  });

  test('重试：首次失败等 1s 第二次、再等 2s 第三次（三次后放弃）', () async {
    final f = _FakeHttp([500, 500, 201]);
    final (_, _, up) = await _setup(f);

    expect(await up.uploadText('retry-me', source: 'clipboard'), isTrue);
    expect(f.requests.length, 3); // 共三次尝试
  });

  test('连续三次失败后放弃本条', () async {
    final f = _FakeHttp([500, 500, 500]);
    final (_, dedup, up) = await _setup(f);

    expect(await up.uploadText('give-up', source: 'clipboard'), isFalse);
    expect(f.requests.length, 3);
    expect(dedup.lastHash, isNull);
  });

  test('401 立即停止，不重试，置需要新 Key 状态', () async {
    final f = _FakeHttp([401]);
    final (_, _, up) = await _setup(f);

    expect(await up.uploadText('x', source: 'clipboard'), isFalse);
    expect(f.requests.length, 1); // 仅一次，无重试
    expect(up.needsNewKey.value, isTrue);
  });

  test('超限：本地预校验不发请求，置提示（ROADMAP P0.6）', () async {
    final f = _FakeHttp();
    final (_, _, up) = await _setup(f);

    final oversized = 'a' * (UploadCoordinator.maxUploadBytes + 1);
    expect(await up.uploadText(oversized, source: 'clipboard'), isFalse);
    expect(f.requests, isEmpty);
    expect(up.rejected.value, isNotNull);
  });

  test('预校验优先使用服务端上报的上限（ROADMAP P3.3）', () async {
    final f = _FakeHttp();
    final (settings, _, up) = await _setup(f);

    await settings.setMaxClipBytes(10);
    expect(up.effectiveMaxBytes, 10);
    expect(await up.uploadText('12345678901', source: 'clipboard'), isFalse);
    expect(f.requests, isEmpty);
    expect(up.rejected.value, isNotNull);

    // 服务端上限未知时回退默认值。
    await settings.setMaxClipBytes(0);
    expect(up.effectiveMaxBytes, UploadCoordinator.maxUploadBytes);
  });

  test('413 立即停止不重试并置提示；成功后提示清除', () async {
    final f = _FakeHttp([413, 201]);
    final (_, _, up) = await _setup(f);

    expect(await up.uploadText('too-big', source: 'clipboard'), isFalse);
    expect(f.requests.length, 1); // 仅一次，无重试
    expect(up.rejected.value, isNotNull);

    // 同文本重传成功（413 未更新去重摘要，会再次发请求）→ 提示清除
    expect(await up.uploadText('too-big', source: 'clipboard'), isTrue);
    expect(f.requests.length, 2);
    expect(up.rejected.value, isNull);
  });

  test('manual 去除首尾空格为空时拒绝提交', () async {
    final f = _FakeHttp();
    final (_, _, up) = await _setup(f);

    expect(await up.uploadText('   \t ', source: 'manual'), isFalse);
    expect(f.requests, isEmpty);
  });

  test('更换 Key 时清除去重摘要', () async {
    final f = _FakeHttp([201]);
    final (_, dedup, up) = await _setup(f);
    await up.uploadText('hello', source: 'clipboard');
    expect(dedup.lastHash, isNotNull);

    await up.onKeyChanged();
    expect(dedup.lastHash, isNull);
  });

  test('默认重试延迟符合规格 1s/2s', () async {
    SharedPreferences.setMockInitialValues({'api_key': 'k'});
    final settings = SettingsStore();
    await settings.init();
    final dedup = DedupStore();
    await dedup.init();
    final api = ApiClient(settings: settings, client: _FakeHttp().client());
    final up = UploadCoordinator(api: api, dedup: dedup, settings: settings);
    expect(up.delays, const [Duration(seconds: 1), Duration(seconds: 2)]);
  });

  group('离线队列（ROADMAP P1.4）', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('coord_queue_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('网络失败入队并展示待同步数，成功上传后按序补传', () async {
      final queue = UploadQueue(dir: dir);
      await queue.load();

      // 三次失败 → 入队
      final f = _FakeHttp([500, 500, 500]);
      final (_, _, up) = await _setup(f, queue: queue);
      expect(await up.uploadText('offline-1', source: 'clipboard'), isFalse);
      expect(queue.length, 1);
      expect(up.syncStatus.value.pendingCount, 1);

      // 网络恢复：新文本成功 → 触发补传，队列清空
      f.statuses
        ..clear()
        ..addAll([201, 201]);
      expect(await up.uploadText('fresh', source: 'clipboard'), isTrue);
      expect(queue.isEmpty, isTrue);
      expect(up.syncStatus.value.pendingCount, 0);
      expect(up.syncStatus.value.lastSyncAt, isNotNull);

      // 顺序：前三次是 offline-1 的重试，然后 fresh 成功，最后补传 offline-1
      final bodies = f.requests
          .map((r) => (jsonDecode(r.body) as Map<String, dynamic>)['content'])
          .toList();
      expect(bodies, [
        'offline-1',
        'offline-1',
        'offline-1',
        'fresh',
        'offline-1',
      ]);
    });

    test('401 不入队；补传遇 401 停止并保留队列', () async {
      final queue = UploadQueue(dir: dir);
      await queue.load();

      final f = _FakeHttp([401]);
      final (_, _, up) = await _setup(f, queue: queue);
      expect(await up.uploadText('x', source: 'clipboard'), isFalse);
      expect(queue.isEmpty, isTrue, reason: 'Key 无效时不入队');
      expect(up.needsNewKey.value, isTrue);

      // 队列中已有内容时补传遇 401：停止，保留队列等新 Key
      await queue.enqueue('waiting', 'clipboard');
      f.statuses
        ..clear()
        ..addAll([401]);
      await up.flushQueue();
      expect(queue.length, 1);
      expect(f.requests.length, 2); // 第一次上传 + 一次补传尝试
    });

    test('补传遇 413 丢弃该条并继续后续条目', () async {
      final queue = UploadQueue(dir: dir);
      await queue.load();
      await queue.enqueue('bad-oversize', 'clipboard');
      await queue.enqueue('good-one', 'clipboard');

      // fresh 成功(201) → 补传：bad-oversize 413 丢弃 → good-one 成功(201)
      final f = _FakeHttp([201, 413, 201]);
      final (_, _, up) = await _setup(f, queue: queue);

      expect(await up.uploadText('fresh', source: 'clipboard'), isTrue);
      expect(queue.isEmpty, isTrue);
      expect(up.rejected.value, isNotNull);
    });

    test('未启用队列时失败即放弃（V1 行为兼容）', () async {
      final f = _FakeHttp([500, 500, 500]);
      final (_, _, up) = await _setup(f);
      expect(await up.uploadText('x', source: 'clipboard'), isFalse);
      expect(up.syncStatus.value.pendingCount, 0);
    });
  });
}
