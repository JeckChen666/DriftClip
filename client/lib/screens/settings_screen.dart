import 'dart:async';

import 'package:flutter/material.dart';

import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';

/// 设置页：监听开关、登录自动启动、服务地址与 Key 状态。
/// 手动输入和历史查看不要求监听开启（Spec §5.2）。
///
/// 分组卡片搭配独立图标底色，说明文字自然换行，适配桌面与移动端。
class SettingsScreen extends StatefulWidget {
  final SettingsStore settings;
  final ClipboardMonitor monitor;
  final DesktopIntegration desktop;
  final UploadCoordinator uploader;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.monitor,
    required this.desktop,
    required this.uploader,
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
    // 同步托盘菜单文案（ROADMAP P1.5）
    unawaited(widget.desktop.setListening(v));
  }

  void _toggleAutoStart(bool v) {
    setState(() => _autoStart = v);
    widget.settings.setAutoStart(v);
    // 桌面端注册/注销「登录后自动启动」（默认关闭，Spec §5.3）
    widget.desktop.setAutoStart(v);
  }

  /// 弹窗编辑连接（服务地址 + Key 一起改）：保存前校验连通性，
  /// 成功后刷新本页展示并提示。取消返回 false。
  Future<void> _editConnection() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ConnectionDialog(
        settings: widget.settings,
        uploader: widget.uploader,
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('连接成功，配置已保存（${widget.settings.apiBaseUrl}）'),
      ),
    );
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
              // 仅桌面端展示（macOS 走原生 SMAppService 通道，ROADMAP P1.3）；
              // 移动端无自启动概念，隐藏。
              if (DesktopIntegration.supportsAutoStart) ...[
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
              ],
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
                  ),
                  const Divider(height: 1, indent: 46),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _editConnection,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('编辑连接'),
                      ),
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

/// 连接编辑弹窗：服务地址与 Key 一起编辑，保存前校验连通性。
/// 保存成功 pop(true)；取消/关闭 pop(false)。
class _ConnectionDialog extends StatefulWidget {
  final SettingsStore settings;
  final UploadCoordinator uploader;

  const _ConnectionDialog({required this.settings, required this.uploader});

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final _urlController = TextEditingController(
    text: widget.settings.apiBaseUrl,
  );
  late final _keyController = TextEditingController(
    text: widget.settings.apiKey ?? '',
  );
  bool _obscureKey = true;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _error = '请粘贴 Web 端生成的 Key');
      return;
    }
    setState(() {
      _error = null;
      _checking = true;
    });
    final problem = await widget.uploader.saveConnection(
      baseUrl: _urlController.text.trim(),
      key: key,
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _checking = false;
        _error = problem;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑连接'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '服务地址',
              hintText: 'http://127.0.0.1:8080',
              prefixIcon: Icon(Icons.dns_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyController,
            obscureText: _obscureKey,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Key',
              prefixIcon: const Icon(Icons.key_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: Text(_checking ? '连接中…' : '保存'),
        ),
      ],
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
