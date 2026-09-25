import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'dedup_store.dart';
import 'device_info.dart';
import 'settings_store.dart';
import 'upload_queue.dart';

/// 同步状态快照（ROADMAP P1.5）：待补传条数与最近一次成功同步时间，
/// 供托盘菜单与界面状态展示。
class SyncStatus {
  final int pendingCount;
  final DateTime? lastSyncAt;

  const SyncStatus({this.pendingCount = 0, this.lastSyncAt});
}

enum _UploadOutcome { success, networkFailure, unauthorized, tooLarge }

/// 上传编排：处理去重、重试、离线队列与 401/413 停止（Spec §4.1、§4.2）。
///
/// 重试策略：首次立即发送 → 失败等 1s 第二次 → 再失败等 2s 第三次；
/// 任一次成功即结束并更新去重摘要。三次失败后不再静默丢弃：
/// 正文进入本地离线队列，成功上传或周期到达时补传（ROADMAP P1.4）。
/// 401 与 413 不属于网络失败：立即停止不重试；401 置 needsNewKey（不入队），
/// 413 置 rejected 提示（ROADMAP P0.6）。
class UploadCoordinator {
  /// 单条正文上限的兜底默认值（服务端默认 100 KiB）。连接校验成功后
  /// 以服务端 meta 上报的实际上限为准（ROADMAP P3.3）。
  static const int maxUploadBytes = 100 * 1024;

  /// 当前生效的单条上限：优先服务端上报值。
  int get effectiveMaxBytes =>
      settings.maxClipBytes > 0 ? settings.maxClipBytes : maxUploadBytes;

  /// 队列非空时的补传重试周期。
  static const Duration defaultFlushInterval = Duration(seconds: 30);

  final ApiClient api;
  final DedupStore dedup;
  final ValueNotifier<bool> needsNewKey;

  /// 最近一次因超限/队列满被拒的提示文案；非空时 UI 显示横幅，上传成功后清除。
  final ValueNotifier<String?> rejected;

  /// 同步状态（待补传条数 / 最近成功时间），UI 与托盘菜单读取。
  final ValueNotifier<SyncStatus> syncStatus = ValueNotifier(
    const SyncStatus(),
  );

  final SettingsStore settings;

  /// 本地离线队列；null 表示未启用（此时退化为 V1 的失败即放弃）。
  final UploadQueue? queue;
  final Duration flushInterval;

  // 设备元数据可注入（测试用），默认真实采集。
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String appVersion;

  /// 重试延迟序列：首次失败等 delays[0]，再失败等 delays[1]；共 delays.length+1 次尝试。
  /// 默认 1s/2s（Spec §4.1），测试可注入更短间隔。
  final List<Duration> delays;

  Timer? _flushTimer;
  bool _flushing = false;

  UploadCoordinator({
    required this.api,
    required this.dedup,
    required this.settings,
    this.queue,
    ValueNotifier<bool>? needsNewKey,
    ValueNotifier<String>? rejected,
    this.flushInterval = defaultFlushInterval,
    String? platform,
    String? osVersion,
    String? deviceModel,
    String? appVersion,
    this.delays = const [Duration(seconds: 1), Duration(seconds: 2)],
  }) : needsNewKey = needsNewKey ?? ValueNotifier(false),
       rejected = rejected ?? ValueNotifier(null),
       platform = platform ?? DeviceInfo.platform(),
       osVersion = osVersion ?? DeviceInfo.osVersion(),
       deviceModel = deviceModel ?? DeviceInfo.deviceModel(),
       appVersion = appVersion ?? DeviceInfo.appVersion();

  static String sha256Hex(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static String _humanLimit(int bytes) =>
      bytes >= 1024 ? '${(bytes / 1024).round()} KiB' : '$bytes 字节';

  /// 上传一段文本。返回是否成功（去重跳过视为成功；失败已入离线队列）。
  Future<bool> uploadText(String text, {required String source}) async {
    // 空剪贴板不上传；手动输入去除首尾空格后为空不允许提交（Spec §3.2）。
    if (text.isEmpty) return false;
    if (source == 'manual' && text.trim().isEmpty) return false;

    final hash = sha256Hex(text);
    // 去重：与最近一次成功上传的正文逐字节一致时不发请求（Spec §4.2）。
    if (hash == dedup.lastHash) return true;

    // 本地字节预校验（ROADMAP P0.6）：超限必然被服务端拒绝，不发请求直接提示。
    final limit = effectiveMaxBytes;
    if (utf8.encode(text).length > limit) {
      rejected.value = '内容超过单条上限（${_humanLimit(limit)}），未上传';
      return false;
    }

    final (outcome, message) = await _uploadWithRetry(text, source);
    switch (outcome) {
      case _UploadOutcome.success:
        // 只有成功响应后才更新摘要；失败/超时/中断不更新（Spec §4.2）。
        await dedup.update(hash);
        rejected.value = null;
        _noteSuccess();
        // 网络恢复的信号：顺手补传此前失败入队的内容。
        await flushQueue();
        return true;
      case _UploadOutcome.unauthorized:
        // 无效 Key：立即停止上传与历史请求，不执行三次重试（Spec §4.1）。
        needsNewKey.value = true;
        return false;
      case _UploadOutcome.tooLarge:
        // 超限重试也必然失败：立即停止并明确提示（ROADMAP P0.6）。
        rejected.value = message ?? '内容超过服务端单条上限，未上传';
        return false;
      case _UploadOutcome.networkFailure:
        await _enqueue(text, source);
        return false;
    }
  }

  /// 尝试按序补传离线队列（成功上传后 / 周期到达时调用）。
  /// 401 停止并保留队列等新 Key；网络失败保留队列等恢复；413 丢弃该条并提示。
  Future<void> flushQueue() async {
    final q = queue;
    if (q == null || _flushing || q.isEmpty) return;
    _flushing = true;
    try {
      while (!q.isEmpty) {
        final item = q.peekFirst()!;
        final (outcome, message) = await _uploadWithRetry(
          item.content,
          item.source,
        );
        switch (outcome) {
          case _UploadOutcome.success:
            await q.removeFirst();
            await dedup.update(sha256Hex(item.content));
            _noteSuccess();
            continue;
          case _UploadOutcome.unauthorized:
            needsNewKey.value = true;
            return;
          case _UploadOutcome.tooLarge:
            await q.removeFirst();
            rejected.value = message ?? '内容超过服务端单条上限，已跳过';
            continue;
          case _UploadOutcome.networkFailure:
            return;
        }
      }
    } finally {
      _flushing = false;
      _updatePending();
      if (q.isEmpty) _stopFlushTimer();
    }
  }

  /// 按当前重试策略上传一次（含三次重试）。只返回结果，不入队。
  Future<(_UploadOutcome, String?)> _uploadWithRetry(
    String text,
    String source,
  ) async {
    for (var attempt = 0; attempt <= delays.length; attempt++) {
      final res = await api.upload(
        HistoryDraft(
          content: text,
          source: source,
          platform: platform,
          osVersion: osVersion,
          deviceModel: deviceModel,
          appVersion: appVersion,
          installationId: settings.installationId(),
        ),
      );
      if (res.ok) return (_UploadOutcome.success, null);
      if (res.status == 401) return (_UploadOutcome.unauthorized, res.error);
      if (res.status == 413) return (_UploadOutcome.tooLarge, res.error);
      if (attempt < delays.length) {
        await Future<void>.delayed(delays[attempt]);
      }
    }
    return (_UploadOutcome.networkFailure, null);
  }

  Future<void> _enqueue(String text, String source) async {
    final q = queue;
    if (q == null) return; // 未启用离线队列：维持 V1「失败即放弃」
    final accepted = await q.enqueue(text, source);
    if (!accepted) {
      rejected.value = '待同步队列已满（${q.maxItems} 条），最早的内容已被丢弃';
    }
    _updatePending();
    _ensureFlushTimer();
  }

  void _noteSuccess() {
    syncStatus.value = SyncStatus(
      pendingCount: queue?.length ?? 0,
      lastSyncAt: DateTime.now(),
    );
  }

  void _updatePending() {
    syncStatus.value = SyncStatus(
      pendingCount: queue?.length ?? 0,
      lastSyncAt: syncStatus.value.lastSyncAt,
    );
  }

  void _ensureFlushTimer() {
    _flushTimer ??= Timer.periodic(flushInterval, (_) {
      unawaited(flushQueue());
    });
  }

  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// 更换 Key 时清除去重摘要（Spec §4.2）。
  Future<void> onKeyChanged() => dedup.clear();

  /// 保存连接配置（服务地址 + Key）：先实际请求服务端校验连通性，
  /// 成功才持久化；失败返回错误描述、不改动任何配置（返回 null 表示成功）。
  /// Key 发生变化时清除去重摘要（Spec §4.2）。
  Future<String?> saveConnection({
    required String baseUrl,
    required String key,
  }) async {
    final problem = await api.validate(baseUrl: baseUrl, key: key);
    if (problem != null) return problem;
    final keyChanged = settings.apiKey != key;
    await settings.setApiBaseUrl(baseUrl);
    if (keyChanged) {
      await onKeyChanged();
    }
    await settings.setApiKey(key);
    return null;
  }
}
