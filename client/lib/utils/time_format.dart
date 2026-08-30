/// 时间展示工具。
///
/// 服务端返回的 received_at 为 RFC3339 UTC 字符串，列表卡片用相对时间
/// （刚刚 / N 分钟前），详情页用本地完整时间。解析失败时原样返回，
/// 保证展示层对异常数据有兜底。
abstract final class TimeFormat {
  /// 相对时间：1 分钟内「刚刚」，1 小时内「N 分钟前」，
  /// 当天内「N 小时前」，昨天「昨天」，今年内「M月d日」，更早「yyyy年M月d日」。
  static String relative(String? rfc3339) {
    final dt = parse(rfc3339);
    if (dt == null) return rfc3339 ?? '';
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';

    final nowDay = DateTime(now.year, now.month, now.day);
    final localDay = DateTime(local.year, local.month, local.day);
    if (nowDay.difference(localDay).inDays == 1) return '昨天';
    if (local.year == now.year) return '${local.month}月${local.day}日';
    return '${local.year}年${local.month}月${local.day}日';
  }

  /// 本地完整时间：yyyy-MM-dd HH:mm。
  static String full(String? rfc3339) {
    final dt = parse(rfc3339);
    if (dt == null) return rfc3339 ?? '';
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  static DateTime? parse(String? rfc3339) {
    if (rfc3339 == null || rfc3339.isEmpty) return null;
    return DateTime.tryParse(rfc3339);
  }
}
