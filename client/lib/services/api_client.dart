import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/history_record.dart';
import 'settings_store.dart';

/// API 统一结果：ok 表示成功；fail 携带 HTTP 状态码与错误信息。
/// status 为 null 表示网络错误（无法连接）。
class ApiResult<T> {
  final bool ok;
  final int? status;
  final T? data;
  final String? error;

  const ApiResult.ok(this.data) : ok = true, status = null, error = null;
  const ApiResult.fail(this.status, this.error) : ok = false, data = null;
}

/// 上传请求体（对齐 P01 API 契约）。
class HistoryDraft {
  final String content;
  final String source; // 'clipboard' | 'manual'
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String appVersion;
  final String installationId;

  const HistoryDraft({
    required this.content,
    required this.source,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
    required this.appVersion,
    required this.installationId,
  });

  Map<String, dynamic> toJson() => {
    'content': content,
    'source': source,
    'platform': platform,
    'os_version': osVersion,
    'device_model': deviceModel,
    'app_version': appVersion,
    'installation_id': installationId,
  };
}

/// REST 客户端：全部请求携带 Bearer Key；204 无响应体；错误统一 ApiResult。
class ApiClient {
  final SettingsStore settings;
  final http.Client _client;

  ApiClient({required this.settings, http.Client? client})
    : _client = client ?? http.Client();

  Uri _uri(String path) => Uri.parse('${settings.apiBaseUrl}$path');

  Future<ApiResult<dynamic>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final key = settings.apiKey;
    if (key == null || key.isEmpty) {
      return const ApiResult.fail(401, '未配置 Key');
    }
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $key',
    };
    try {
      final http.Response res;
      switch (method) {
        case 'GET':
          res = await _client.get(_uri(path), headers: headers);
        case 'DELETE':
          res = await _client.delete(_uri(path), headers: headers);
        default:
          res = await _client.post(
            _uri(path),
            headers: headers,
            body: jsonEncode(body),
          );
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (res.body.isEmpty) return const ApiResult.ok(null);
        return ApiResult.ok(jsonDecode(res.body));
      }
      String? msg;
      try {
        final decoded = jsonDecode(res.body);
        msg = (decoded as Map<String, dynamic>)['error'] as String?;
      } catch (_) {
        // 忽略解析失败，使用默认错误信息
      }
      return ApiResult.fail(res.statusCode, msg ?? '请求失败（${res.statusCode}）');
    } on http.ClientException {
      return const ApiResult.fail(null, '网络错误，请检查服务地址');
    }
  }

  Future<ApiResult<int>> upload(HistoryDraft draft) async {
    final r = await _send('POST', '/api/v1/history', body: draft.toJson());
    if (!r.ok) return ApiResult.fail(r.status, r.error);
    final id = (r.data as Map<String, dynamic>)['id'] as num;
    return ApiResult.ok(id.toInt());
  }

  Future<ApiResult<List<HistoryRecord>>> list() async {
    final r = await _send('GET', '/api/v1/history');
    if (!r.ok) return ApiResult.fail(r.status, r.error);
    final items = (r.data as Map<String, dynamic>)['items'] as List;
    return ApiResult.ok(
      items
          .map((e) => HistoryRecord.fromListJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<ApiResult<HistoryRecord>> detail(int id) async {
    final r = await _send('GET', '/api/v1/history/$id');
    if (!r.ok) return ApiResult.fail(r.status, r.error);
    return ApiResult.ok(
      HistoryRecord.fromDetailJson(r.data as Map<String, dynamic>),
    );
  }

  Future<ApiResult<void>> delete(int id) async {
    final r = await _send('DELETE', '/api/v1/history/$id');
    if (!r.ok) return ApiResult.fail(r.status, r.error);
    return const ApiResult.ok(null);
  }

  /// 批量删除。返回实际删除条数。
  Future<ApiResult<int>> batchDelete(List<int> ids) async {
    final r = await _send(
      'POST',
      '/api/v1/history/batch-delete',
      body: {'ids': ids},
    );
    if (!r.ok) return ApiResult.fail(r.status, r.error);
    return ApiResult.ok(
      ((r.data as Map<String, dynamic>)['deleted'] as num).toInt(),
    );
  }

  /// 清空全部历史。返回实际删除条数。
  Future<ApiResult<int>> clear() async {
    final r = await _send('POST', '/api/v1/history/clear');
    if (!r.ok) return ApiResult.fail(r.status, r.error);
    return ApiResult.ok(
      ((r.data as Map<String, dynamic>)['deleted'] as num).toInt(),
    );
  }

  /// 用给定服务地址与 Key 校验连通性（GET /api/v1/history，8 秒超时）。
  /// 用于 Key 配置保存前的即时反馈；不读取也不修改已持久化的配置。
  /// 返回错误描述；成功返回 null。
  Future<String?> validate({
    required String baseUrl,
    required String key,
  }) async {
    final uri = Uri.tryParse('$baseUrl/api/v1/history');
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null || (scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return '服务地址格式不正确';
    }
    try {
      final res = await _client
          .get(uri, headers: {'Authorization': 'Bearer $key'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _fetchMeta(baseUrl);
        return null;
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return '连接成功但 Key 无效（HTTP ${res.statusCode}），请检查 Key';
      }
      String? msg;
      try {
        final decoded = jsonDecode(res.body);
        msg = (decoded as Map<String, dynamic>)['error'] as String?;
      } catch (_) {
        // 忽略解析失败，使用默认错误信息
      }
      return msg ?? '服务器返回 HTTP ${res.statusCode}';
    } on TimeoutException {
      return '连接超时，请检查服务地址与端口';
    } catch (_) {
      return '无法连接服务器，请检查服务地址与网络';
    }
  }

  /// 连接成功后读取 GET /api/v1/meta（公开端点）：记录服务端版本与
  /// 单条正文字节上限，供上传预校验与排查使用（ROADMAP P3.3）。
  /// meta 属增强信息，读取失败不影响校验结果。
  Future<void> _fetchMeta(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/meta');
      final res = await _client
          .get(uri, headers: {'Authorization': 'Bearer ${settings.apiKey}'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final meta = jsonDecode(res.body) as Map<String, dynamic>;
      final version = meta['version'];
      if (version is String && version.isNotEmpty) {
        await settings.setServerVersion(version);
      }
      final maxBytes = meta['max_clipboard_text_bytes'];
      if (maxBytes is num && maxBytes > 0) {
        await settings.setMaxClipBytes(maxBytes.toInt());
      }
    } catch (_) {
      // 忽略：meta 缺失或格式变化不影响连接
    }
  }
}
