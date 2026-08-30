import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'dedup_store.dart';
import 'device_info.dart';
import 'settings_store.dart';

/// 上传编排：处理去重、重试与 401 停止（Spec §4.1、§4.2）。
///
/// 重试策略：首次立即发送 → 失败等 1s 第二次 → 再失败等 2s 第三次；
/// 任一次成功即结束并更新去重摘要；三次失败后放弃本条。
/// 401 不属于网络失败：立即停止，不重试，置 needsNewKey 状态。
class UploadCoordinator {
  final ApiClient api;
  final DedupStore dedup;
  final ValueNotifier<bool> needsNewKey;
  final SettingsStore settings;

  // 设备元数据可注入（测试用），默认真实采集。
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String appVersion;

  /// 重试延迟序列：首次失败等 delays[0]，再失败等 delays[1]；共 delays.length+1 次尝试。
  /// 默认 1s/2s（Spec §4.1），测试可注入更短间隔。
  final List<Duration> delays;

  UploadCoordinator({
    required this.api,
    required this.dedup,
    required this.settings,
    ValueNotifier<bool>? needsNewKey,
    String? platform,
    String? osVersion,
    String? deviceModel,
    String? appVersion,
    this.delays = const [Duration(seconds: 1), Duration(seconds: 2)],
  }) : needsNewKey = needsNewKey ?? ValueNotifier(false),
       platform = platform ?? DeviceInfo.platform(),
       osVersion = osVersion ?? DeviceInfo.osVersion(),
       deviceModel = deviceModel ?? DeviceInfo.deviceModel(),
       appVersion = appVersion ?? DeviceInfo.appVersion();

  static String sha256Hex(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// 上传一段文本。返回是否成功（去重跳过视为成功）。
  Future<bool> uploadText(String text, {required String source}) async {
    // 空剪贴板不上传；手动输入去除首尾空格后为空不允许提交（Spec §3.2）。
    if (text.isEmpty) return false;
    if (source == 'manual' && text.trim().isEmpty) return false;

    final hash = sha256Hex(text);
    // 去重：与最近一次成功上传的正文逐字节一致时不发请求（Spec §4.2）。
    if (hash == dedup.lastHash) return true;

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
      if (res.ok) {
        // 只有成功响应后才更新摘要；失败/超时/中断不更新（Spec §4.2）。
        await dedup.update(hash);
        return true;
      }
      if (res.status == 401) {
        // 无效 Key：立即停止上传与历史请求，不执行三次重试（Spec §4.1）。
        needsNewKey.value = true;
        return false;
      }
      if (attempt < delays.length) {
        await Future<void>.delayed(delays[attempt]);
      }
    }
    // 三次失败后放弃本条；不建立离线队列，不自动补传（Spec §4.1）。
    return false;
  }

  /// 更换 Key 时清除去重摘要（Spec §4.2）。
  Future<void> onKeyChanged() => dedup.clear();
}
