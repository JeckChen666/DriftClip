import 'package:flutter/material.dart';

import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';

/// 设置页：监听开关、登录自动启动、服务地址与 Key 状态。
/// 手动输入和历史查看不要求监听开启（Spec §5.2）。
///
/// 分组卡片搭配独立图标底色，说明文字自然换行，适配桌面与移动端。
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const _SectionHeader('同步'),
              _SectionCard(
                children: [
                  _SettingRow(
                    icon: Icons.content_paste_rounded,
                    title: '剪贴板监听',
                    subtitle: '开启后持续采集系统剪贴板文本（桌面端常驻时生效）',
                    trailing: Switch.adaptive(
                      value: _listen,
                      onChanged: _toggleListen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionHeader('启动'),
              _SectionCard(
                children: [
                  _SettingRow(
                    icon: Icons.power_settings_new_rounded,
                    title: '登录后自动启动',
                    subtitle: '桌面端，默认关闭',
                    trailing: Switch.adaptive(
                      value: _autoStart,
                      onChanged: _toggleAutoStart,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionHeader('连接'),
              _SectionCard(
                children: [
                  _SettingRow(
                    icon: Icons.dns_rounded,
                    title: '服务地址',
                    subtitle: widget.settings.apiBaseUrl,
                  ),
                  const Divider(height: 1, indent: 46),
                  _SettingRow(
                    icon: Icons.key_rounded,
                    title: 'Key',
                    subtitle: maskedKey,
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('重新配置'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '手动输入与历史查看不要求开启监听。'
                  '监听仅在应用运行/前台时生效，后台持续监听取决于系统限制。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组标题。
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 分组卡片容器：内部行共用一个圆角卡片。
class _SectionCard extends StatelessWidget {
  final List<Widget> children;

  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// 设置项单行：左图标 + 中标题副标题 + 右侧控件。
///
/// 使用最小高度并允许说明换行，兼顾窄屏和系统文字缩放。
class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}
