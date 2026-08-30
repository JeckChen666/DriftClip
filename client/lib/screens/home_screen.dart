import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';
import '../widgets/brand_title.dart';
import '../widgets/history_content.dart';
import 'settings_screen.dart';

/// 移动端主屏幕（窄屏 < 720 使用）。
///
/// 窄屏布局：Scaffold + AppBar（多选 / 刷新 / 设置）+ FAB（手动输入），
/// body 委托给 [HistoryContent]（与桌面端共用一份列表逻辑）。
class HomeScreen extends StatefulWidget {
  final SettingsStore settings;
  final ApiClient api;
  final UploadCoordinator uploader;
  final ClipboardMonitor monitor;
  final DesktopIntegration desktop;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.api,
    required this.uploader,
    required this.monitor,
    required this.desktop,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<HistoryContentState> _contentKey =
      GlobalKey<HistoryContentState>();
  bool _selectionMode = false;

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          monitor: widget.monitor,
          desktop: widget.desktop,
        ),
      ),
    );
    // 设置页可能改了监听开关，返回后刷新。
    if (mounted) setState(() {});
  }

  void _toggleSelectionMode() =>
      _contentKey.currentState?.toggleSelectionMode();

  void _refresh() => _contentKey.currentState?.requestRefresh();

  void _openManualInput() => _contentKey.currentState?.requestManualInput();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const BrandTitle(),
        actions: [
          IconButton(
            tooltip: _selectionMode ? '完成选择' : '多选删除',
            icon: Icon(_selectionMode ? Icons.check : Icons.checklist),
            onPressed: _toggleSelectionMode,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '手动输入',
        onPressed: _openManualInput,
        child: const Icon(Icons.edit),
      ),
      body: HistoryContent(
        key: _contentKey,
        settings: widget.settings,
        api: widget.api,
        uploader: widget.uploader,
        monitor: widget.monitor,
        desktop: widget.desktop,
        onSelectionModeChanged: (v) => setState(() => _selectionMode = v),
      ),
    );
  }
}
