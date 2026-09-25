import 'package:flutter/material.dart';

import 'key_config_screen.dart';
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
  }

  void _toggleAutoStart(bool v) {
    setState(() => _autoStart = v);
    widget.settings.setAutoStart(v);
    // 桌面端注册/注销「登录后自动启动」（默认关闭，Spec §5.3）
    widget.desktop.setAutoStart(v);
  }

  /// 弹窗编辑服务地址；取消返回 null，保存返回输入值。
  Future<void> _editBaseUrl() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _BaseUrlDialog(initial: widget.settings.apiBaseUrl),
    );
    if (url == null || !mounted) return;
    await widget.settings.setApiBaseUrl(url);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('服务地址已更新：${widget.settings.apiBaseUrl}')),
      );
    }
  }

  /// 重新进入 Key 配置页修改服务地址与 Key。
  /// 保存本身已持久化（ApiClient 每次请求动态读取），返回后仅刷新本页展示。
  Future<void> _reconfigure() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KeyConfigScreen(
          settings: widget.settings,
          uploader: widget.uploader,
          onSaved: (_) {},
        ),
      ),
    );
    if (mounted) setState(() {});
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
                    trailing: TextButton(
                      onPressed: _editBaseUrl,
                      child: const Text('编辑'),
                    ),
                  ),
                  const Divider(height: 1, indent: 46),
                  _SettingRow(
                    icon: Icons.key_rounded,
                    title: 'Key',
                    subtitle: maskedKey,
                    trailing: TextButton(
                      onPressed: _reconfigure,
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

/// 服务地址编辑弹窗：校验 http(s) URL 形态，取消返回 null，保存返回输入值。
class _BaseUrlDialog extends StatefulWidget {
  final String initial;

  const _BaseUrlDialog({required this.initial});

  @override
  State<_BaseUrlDialog> createState() => _BaseUrlDialogState();
}

class _BaseUrlDialogState extends State<_BaseUrlDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final url = _controller.text.trim();
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        (scheme != 'http' && scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _error = '请输入 http(s)://主机[:端口] 形式的地址');
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改服务地址'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: '服务地址',
          hintText: 'http://127.0.0.1:8080',
          prefixIcon: const Icon(Icons.dns_rounded, size: 20),
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
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
