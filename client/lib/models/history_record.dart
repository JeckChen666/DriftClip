/// 历史记录模型。列表接口返回投影（content_preview，不含完整正文/IP），
/// 详情接口返回完整 content 与 public_ip。
class HistoryRecord {
  final int id;
  final String contentPreview;
  final String source;
  final String receivedAt;
  final String platform;
  final String osVersion;
  final String deviceModel;
  final String appVersion;
  final String installationId;

  /// 仅详情接口填充。
  final String? content;
  final String? publicIp;

  const HistoryRecord({
    required this.id,
    required this.contentPreview,
    required this.source,
    required this.receivedAt,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
    required this.appVersion,
    required this.installationId,
    this.content,
    this.publicIp,
  });

  factory HistoryRecord.fromListJson(Map<String, dynamic> json) => HistoryRecord(
        id: (json['id'] as num).toInt(),
        contentPreview: (json['content_preview'] as String?) ?? '',
        source: (json['source'] as String?) ?? '',
        receivedAt: (json['received_at'] as String?) ?? '',
        platform: (json['platform'] as String?) ?? '',
        osVersion: (json['os_version'] as String?) ?? '',
        deviceModel: (json['device_model'] as String?) ?? '',
        appVersion: (json['app_version'] as String?) ?? '',
        installationId: (json['installation_id'] as String?) ?? '',
      );

  factory HistoryRecord.fromDetailJson(Map<String, dynamic> json) => HistoryRecord(
        id: (json['id'] as num).toInt(),
        contentPreview: (json['content'] as String?) ?? '',
        source: (json['source'] as String?) ?? '',
        receivedAt: (json['received_at'] as String?) ?? '',
        platform: (json['platform'] as String?) ?? '',
        osVersion: (json['os_version'] as String?) ?? '',
        deviceModel: (json['device_model'] as String?) ?? '',
        appVersion: (json['app_version'] as String?) ?? '',
        installationId: (json['installation_id'] as String?) ?? '',
        content: json['content'] as String?,
        publicIp: json['public_ip'] as String?,
      );
}
