import 'dart:convert';
import 'dart:io';

/// 待补传的一条剪贴板内容。
class QueuedUpload {
  final String content;
  final String source; // 'clipboard' | 'manual'
  final DateTime createdAt;

  const QueuedUpload({
    required this.content,
    required this.source,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'content': content,
    'source': source,
    'created_at': createdAt.toIso8601String(),
  };

  factory QueuedUpload.fromJson(Map<String, dynamic> json) => QueuedUpload(
    content: json['content'] as String,
    source: json['source'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// 离线上传队列（ROADMAP P1.4）：
/// 上传最终失败的正文持久化到本地 JSON 文件，网络/服务恢复后按序补传，
/// 不再像 V1 那样「三次失败即静默丢弃」。
///
/// - 上限 [maxItems] 条，超限丢最旧并返回 false 由调用方提示；
/// - 文件写入采用「临时文件 + rename」，进程中断不损坏既有队列；
/// - 队列只存正文与来源，不存设备元数据（补传时按当次环境重取）。
class UploadQueue {
  final Directory dir;
  final int maxItems;

  File get _file =>
      File('${dir.path}${Platform.pathSeparator}upload_queue.json');

  final List<QueuedUpload> _items = [];
  bool _loaded = false;

  UploadQueue({required this.dir, this.maxItems = 500});

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  /// 从磁盘加载（重复调用安全）。文件不存在或损坏时从空队列开始。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (!await _file.exists()) return;
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List) return;
      _items
        ..clear()
        ..addAll([
          for (final e in decoded)
            QueuedUpload.fromJson(e as Map<String, dynamic>),
        ]);
    } catch (_) {
      // 队列文件损坏不阻塞主流程：按空队列处理
      _items.clear();
    }
  }

  QueuedUpload? peekFirst() =>
      _loaded && _items.isNotEmpty ? _items.first : null;

  /// 入队。返回 true 表示正常入队；返回 false 表示队列已满、最旧一条被丢弃。
  Future<bool> enqueue(String content, String source) async {
    await load();
    var overflowed = false;
    if (_items.length >= maxItems) {
      _items.removeAt(0);
      overflowed = true;
    }
    _items.add(
      QueuedUpload(
        content: content,
        source: source,
        createdAt: DateTime.now(),
      ),
    );
    await _persist();
    return !overflowed;
  }

  Future<void> removeFirst() async {
    if (_items.isEmpty) return;
    _items.removeAt(0);
    await _persist();
  }

  Future<void> _persist() async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode([for (final i in _items) i.toJson()]),
      flush: true,
    );
    await tmp.rename(_file.path);
  }
}
