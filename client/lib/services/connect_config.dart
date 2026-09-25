/// 连接配置导入（ROADMAP P2.4）：解析 Web 端 Key 管理页二维码/「复制完整配置」
/// 生成的 `driftclip://connect?server=…&key=…` 配置串。
/// 剪贴板导入与移动端扫码共用同一格式。
class ConnectConfig {
  final String server;
  final String key;

  const ConnectConfig({required this.server, required this.key});

  static ConnectConfig? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'driftclip') return null;
    if (uri.host.toLowerCase() != 'connect') return null;
    final server = uri.queryParameters['server']?.trim() ?? '';
    final key = uri.queryParameters['key']?.trim() ?? '';
    if (server.isEmpty || key.isEmpty) return null;
    return ConnectConfig(server: server, key: key);
  }
}
