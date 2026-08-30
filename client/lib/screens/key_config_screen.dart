import 'package:flutter/material.dart';

import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';

/// Key 配置页：设置服务地址与访问 Key。
/// 保存新 Key 时清除本地去重摘要（Spec §4.2：更换 Key 时清除摘要）。
class KeyConfigScreen extends StatefulWidget {
  final SettingsStore settings;
  final UploadCoordinator uploader;
  final ValueChanged<String> onSaved;

  const KeyConfigScreen({
    super.key,
    required this.settings,
    required this.uploader,
    required this.onSaved,
  });

  @override
  State<KeyConfigScreen> createState() => _KeyConfigScreenState();
}

class _KeyConfigScreenState extends State<KeyConfigScreen> {
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _obscureKey = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.settings.apiBaseUrl;
  }

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
    setState(() => _error = null);
    await widget.settings.setApiBaseUrl(_urlController.text.trim());
    // 更换 Key → 清除去重摘要（Spec §4.2）
    await widget.uploader.onKeyChanged();
    await widget.settings.setApiKey(key);
    widget.onSaved(key);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 品牌区：图标 + 标题 + 说明
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.content_paste_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '连接 DriftClip',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在 Web 端「Key 管理」页生成 Key 并填入此处，'
                    '服务地址默认本机开发地址。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 表单区
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              labelText: '服务地址',
                              hintText: 'http://127.0.0.1:8080',
                              prefixIcon: Icon(Icons.dns_rounded, size: 18),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _keyController,
                            obscureText: _obscureKey,
                            onSubmitted: (_) => _save(),
                            decoration: InputDecoration(
                              labelText: 'Key',
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                size: 18,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 16,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: scheme.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _save,
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
