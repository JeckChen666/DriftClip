import 'package:flutter/material.dart';

import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';

/// 设置页：监听开关、登录自动启动、服务地址与 Key 状态。
/// 手动输入和历史查看不要求监听开启（Spec §5.2）。
class SettingsScreen extends StatefulWidget {
  final SettingsStore settings;
  final ClipboardMonitor monitor;
  final DesktopIntegration desktop;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.monitor,
    required this.desktop,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _listen = widget.settings.listenEnabled;
  late bool _autoStart = widget.settings.autoStart;

  void _toggleListen(bool v) {
    setState(() => _listen = v);
    widget.settings.setListenEnabled(v);
    if (v) {
      widget.monitor.start();
    } else {
      widget.monitor.stop();
    }
  }

  void _toggleAutoStart(bool v) {
    setState(() => _autoStart = v);
    widget.settings.setAutoStart(v);
    // 桌面端注册/注销「登录后自动启动」（默认关闭，Spec §5.3）
    widget.desktop.setAutoStart(v);
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.settings.apiKey;
    final maskedKey = key == null || key.isEmpty
        ? '未配置'
        : '${key.substring(0, 5)}…（已配置）';
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('剪贴板监听'),
            subtitle: const Text('开启后持续采集系统剪贴板文本（桌面端常驻时生效）'),
            value: _listen,
            onChanged: _toggleListen,
          ),
          SwitchListTile(
            title: const Text('登录后自动启动'),
            subtitle: const Text('桌面端，默认关闭'),
            value: _autoStart,
            onChanged: _toggleAutoStart,
          ),
          ListTile(
            title: const Text('服务地址'),
            subtitle: Text(widget.settings.apiBaseUrl),
          ),
          ListTile(
            title: const Text('Key'),
            subtitle: Text(maskedKey),
            trailing: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('重新配置'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '手动输入与历史查看不要求开启监听。'
              '监听仅在应用运行/前台时生效，后台持续监听取决于系统限制。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
