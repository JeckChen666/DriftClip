import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/connect_config.dart';
import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';

/// Key 配置页：设置服务地址与访问 Key。
/// 支持三种配置方式：手动填写、剪贴板导入、移动端扫码（ROADMAP P2.4）。
/// 保存前先实际请求服务端验证连通性，成功才持久化并提示；失败就地显示原因。
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
  bool _checking = false;
  String? _error;

  // 扫码仅在有摄像头的移动端提供。
  bool get _scanSupported => Platform.isAndroid || Platform.isIOS;

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

  /// 把解析出的配置填入表单（不自动保存，仍走保存前连通性校验）。
  void _applyConfig(ConnectConfig cfg) {
    setState(() {
      _urlController.text = cfg.server;
      _keyController.text = cfg.key;
      _error = null;
    });
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final cfg = ConnectConfig.tryParse(data?.text ?? '');
    if (cfg == null) {
      setState(() {
        _error =
            '剪贴板中没有有效的 DriftClip 配置，请先在 Web 端「Key 管理」页复制完整配置';
      });
      return;
    }
    _applyConfig(cfg);
  }

  Future<void> _scanQr() async {
    final cfg = await Navigator.of(context).push<ConnectConfig>(
      MaterialPageRoute<ConnectConfig>(
        fullscreenDialog: true,
        builder: (_) => const _ScanScreen(),
      ),
    );
    if (cfg == null || !mounted) return;
    _applyConfig(cfg);
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
    // 保存前先实际请求服务端验证连通性，立刻反馈配置是否可用（而非静默失败）。
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
    widget.onSaved(key);
    if (!mounted) return;
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('连接成功，配置已保存（${widget.settings.apiBaseUrl}）'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 品牌区：图标 + 标题 + 说明
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.content_paste_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '连接 DriftClip',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '在 Web 端「Key 管理」页复制完整配置后点下方按钮导入，'
                    '或手动填写服务地址与 Key。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // 表单区
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _importFromClipboard,
                                  icon: const Icon(
                                    Icons.content_paste_rounded,
                                    size: 15,
                                  ),
                                  label: const Text('从剪贴板导入'),
                                ),
                              ),
                              if (_scanSupported) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _scanQr,
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                      size: 15,
                                    ),
                                    label: const Text('扫码导入'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              labelText: '服务地址',
                              hintText: 'http://127.0.0.1:8080',
                              prefixIcon: Icon(Icons.dns_rounded, size: 16),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _keyController,
                            obscureText: _obscureKey,
                            onSubmitted: (_) => _save(),
                            decoration: InputDecoration(
                              labelText: 'Key',
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                size: 16,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? '显示 Key' : '隐藏 Key',
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size: 16,
                                ),
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
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
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: scheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _checking ? null : _save,
                            child: Text(_checking ? '连接中…' : '保存'),
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

/// 扫码导入：识别 Web 端 Key 管理页二维码中的连接配置。
class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _done = false;

  void _handleDetect(BarcodeCapture capture) {
    if (_done || !mounted) return;
    for (final barcode in capture.barcodes) {
      final cfg = ConnectConfig.tryParse(barcode.rawValue ?? '');
      if (cfg != null) {
        _done = true;
        Navigator.of(context).pop(cfg);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描连接二维码')),
      body: MobileScanner(
        onDetect: _handleDetect,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '无法启动相机（$error）\n请检查相机权限，或改用「从剪贴板导入」',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
