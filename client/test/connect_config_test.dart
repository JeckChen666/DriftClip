import 'package:driftclip_client/services/connect_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析 Web 端生成的完整连接配置', () {
    final cfg = ConnectConfig.tryParse(
      'driftclip://connect?server=http%3A%2F%2F192.168.1.5%3A8080&key=dc_abc123',
    );
    expect(cfg, isNotNull);
    expect(cfg!.server, 'http://192.168.1.5:8080');
    expect(cfg.key, 'dc_abc123');
  });

  test('容忍前后空白与大小写 scheme/host', () {
    final cfg = ConnectConfig.tryParse(
      '  DRIFTCLIP://CONNECT/?server=http://x:8080&key=k  ',
    );
    expect(cfg, isNotNull);
    expect(cfg!.server, 'http://x:8080');
  });

  test('非配置串返回 null', () {
    expect(ConnectConfig.tryParse('http://127.0.0.1:8080'), isNull);
    expect(ConnectConfig.tryParse('driftclip://other?server=x&key=k'), isNull);
    expect(ConnectConfig.tryParse('driftclip://connect?server=x'), isNull);
    expect(ConnectConfig.tryParse(''), isNull);
  });
}
