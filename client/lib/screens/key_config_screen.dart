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
    return Scaffold(
      appBar: AppBar(title: const Text('配置 DriftClip')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在 Web 端「Key 管理」页生成 Key 并填入此处。'
              '服务地址默认本机开发地址。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'http://127.0.0.1:8080',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(labelText: 'Key'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
