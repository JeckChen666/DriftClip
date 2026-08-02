import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'upload_coordinator.dart';

/// 剪贴板监听器。
///
/// 桌面端在应用常驻时周期性轮询 `Clipboard.getData`（Flutter 无通用
/// 「剪贴板变更事件」，轮询是最小可行方案）。
/// 移动端仅前台读取（Spec §5.2）：退到后台暂停轮询，回到前台恢复；
/// 不做后台持续监听，也不做默认输入法。
class ClipboardMonitor {
  static const pollInterval = Duration(seconds: 2);

  final UploadCoordinator uploader;
  final bool isDesktop;

  Timer? _timer;
  bool _listening = false;
  bool _appInForeground = true;
  String? _lastSeen;

  ClipboardMonitor({required this.uploader, this.isDesktop = true});

  bool get listening => _listening;

  /// 当前是否正在轮询（移动端后台暂停时与 listening 不同）。
  @visibleForTesting
  bool get isPolling => _timer != null;

  void start() {
    if (_listening) return;
    _listening = true;
    _syncTimer();
  }

  void stop() {
    _listening = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 应用前后台变化：移动端后台暂停采集，回到前台恢复（Spec §5.2）。
  /// 桌面端常驻监听不受前后台影响。
  void handleAppLifecycle(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
    if (!isDesktop) {
      _syncTimer();
    }
  }

  /// 桌面端始终轮询；移动端仅在应用前台且监听开启时轮询。
  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (_listening && (isDesktop || _appInForeground)) {
      _timer = Timer.periodic(pollInterval, (_) => _poll());
    }
  }

  Future<void> _poll() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    await handleClipboardText(data?.text);
  }

  /// 处理一次剪贴板文本。单独抽出便于测试（避免真实剪贴板依赖）。
  @visibleForTesting
  Future<void> handleClipboardText(String? text) async {
    if (text == null || text.isEmpty) return;
    if (text == _lastSeen) return; // 同一段文本不重复处理
    _lastSeen = text;
    await uploader.uploadText(text, source: 'clipboard');
  }
}
