import 'dart:io';

import 'package:driftclip_client/services/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('driftclip_queue_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('入队后 peek/removeFirst 按先进先出顺序工作', () async {
    final q = UploadQueue(dir: dir);
    await q.enqueue('first', 'clipboard');
    await q.enqueue('second', 'manual');

    expect(q.length, 2);
    expect(q.peekFirst()!.content, 'first');

    await q.removeFirst();
    expect(q.peekFirst()!.content, 'second');
    expect(q.peekFirst()!.source, 'manual');
  });

  test('队列跨实例持久化（模拟应用重启）', () async {
    final q1 = UploadQueue(dir: dir);
    await q1.enqueue('persist-me', 'clipboard');

    final q2 = UploadQueue(dir: dir);
    await q2.load();
    expect(q2.length, 1);
    expect(q2.peekFirst()!.content, 'persist-me');
  });

  test('超过上限丢最旧并返回 false（ROADMAP P1.4）', () async {
    final q = UploadQueue(dir: dir, maxItems: 2);
    expect(await q.enqueue('a', 'clipboard'), isTrue);
    expect(await q.enqueue('b', 'clipboard'), isTrue);
    expect(await q.enqueue('c', 'clipboard'), isFalse, reason: 'a 被丢弃');

    final q2 = UploadQueue(dir: dir);
    await q2.load();
    expect(q2.length, 2);
    expect(q2.peekFirst()!.content, 'b');
  });

  test('队列文件损坏时按空队列处理，不抛异常', () async {
    await File(
      '${dir.path}${Platform.pathSeparator}upload_queue.json',
    ).writeAsString('{not json');
    final q = UploadQueue(dir: dir);
    await q.load();
    expect(q.isEmpty, isTrue);
    expect(await q.enqueue('ok', 'clipboard'), isTrue);
  });
}
