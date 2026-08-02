import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/history_record.dart';
import '../services/api_client.dart';
import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';
import 'manual_input_dialog.dart';
import 'settings_screen.dart';

/// 主屏幕：远端历史列表（手动刷新）、单条/多选删除、清空全部（5s 确认）、
/// 复制、手动输入、设置入口。列表不自动轮询（Spec §5.1）。
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
  List<HistoryRecord> _records = [];
  bool _loading = true;
  String? _error;

  // 多选删除 + 清空全部（5s 确认）
  final Set<int> _selected = {};
  bool _selectionMode = false;
  bool _clearConfirming = false;
  int _clearCountdown = 0;
  Timer? _clearTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  /// 清空全部需 5 秒倒计时确认（Spec §6.2 对齐 Web 交互；Spec §2.2 对齐 Key 重置）。
  void _startClearCountdown() {
    setState(() {
      _clearConfirming = true;
      _clearCountdown = 5;
    });
    _clearTimer?.cancel();
    _clearTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _clearCountdown = _clearCountdown > 0 ? _clearCountdown - 1 : 0;
      });
      if (_clearCountdown == 0) _clearTimer?.cancel();
    });
  }

  void _cancelClearCountdown() {
    _clearTimer?.cancel();
    setState(() {
      _clearConfirming = false;
      _clearCountdown = 0;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final r = await widget.api.batchDelete(_selected.toList());
    if (!mounted) return;
    if (r.ok) {
      setState(() => _selected.clear());
      await _load();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.error ?? '删除失败')));
    }
  }

  Future<void> _clearAll() async {
    final r = await widget.api.clear();
    if (!mounted) return;
    _cancelClearCountdown();
    if (r.ok) {
      setState(() => _selected.clear());
      await _load();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.error ?? '清空失败')));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await widget.api.list();
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        _records = r.data ?? [];
        _loading = false;
      });
    } else {
      setState(() {
        _error = r.error;
        _loading = false;
      });
    }
  }

  Future<void> _delete(int id) async {
    final r = await widget.api.delete(id);
    if (!mounted) return;
    if (r.ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.error ?? '删除失败')));
    }
  }

  Future<void> _copy(HistoryRecord record) async {
    // 列表只有预览，复制需拉取完整正文（复制是用户显式本机操作）。
    final r = await widget.api.detail(record.id);
    if (!mounted || !r.ok) return;
    await Clipboard.setData(ClipboardData(text: r.data!.content ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  Future<void> _openManualInput() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const ManualInputDialog(),
    );
    if (text == null || !mounted) return;
    final ok = await widget.uploader.uploadText(text, source: 'manual');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '已上传' : '上传失败或内容为空'),
    ));
    await _load(); // 本设备成功上传后更新当前列表（Spec §5.1）
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(
        settings: widget.settings,
        monitor: widget.monitor,
        desktop: widget.desktop,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DriftClip 历史'),
        actions: [
          IconButton(
            tooltip: _selectionMode ? '完成选择' : '多选删除',
            icon: Icon(_selectionMode ? Icons.check : Icons.checklist),
            onPressed: () => setState(() {
              _selectionMode = !_selectionMode;
              if (!_selectionMode) _selected.clear();
            }),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '手动输入',
        onPressed: _openManualInput,
        child: const Icon(Icons.edit),
      ),
      body: Column(
        children: [
          // 401 状态横幅：需要更新 Key（Spec §4.1）
          ValueListenableBuilder<bool>(
            valueListenable: widget.uploader.needsNewKey,
            builder: (context, needsNewKey, _) => needsNewKey
                ? MaterialBanner(
                    backgroundColor: Colors.amber.shade100,
                    content: const Text('Key 无效或已被重置，请在设置中更新'),
                    actions: [
                      TextButton(
                        onPressed: () => widget.uploader.needsNewKey.value = false,
                        child: const Text('知道了'),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          if (_selectionMode) _buildBulkBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 选择模式下的批量操作栏：全选、删除所选、清空全部（5s 倒计时确认）。
  Widget _buildBulkBar() {
    final allSelected = _records.isNotEmpty && _selected.length == _records.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (_) => setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                _selected.addAll(_records.map((r) => r.id));
              }
            }),
          ),
          const Text('全选'),
          const Spacer(),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => _deleteSelected(),
              child: Text('删除所选（${_selected.length}）'),
            ),
          if (_clearConfirming)
            _clearCountdown > 0
                ? ElevatedButton(
                    onPressed: null,
                    child: Text('清空全部（$_clearCountdown}s）'),
                  )
                : ElevatedButton(
                    key: const ValueKey('confirm-clear'),
                    onPressed: () => _clearAll(),
                    child: const Text('确认清空全部'),
                  )
          else
            ElevatedButton(
              key: const ValueKey('start-clear'),
              onPressed: _startClearCountdown,
              child: const Text('清空全部'),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_records.isEmpty) {
      return const Center(child: Text('暂无历史记录'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _records.length,
        itemBuilder: (context, i) => _recordCard(_records[i]),
      ),
    );
  }

  Widget _recordCard(HistoryRecord record) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _selectionMode
            ? Checkbox(
                key: ValueKey('record-select-${record.id}'),
                value: _selected.contains(record.id),
                onChanged: (_) => setState(() {
                  if (!_selected.add(record.id)) {
                    _selected.remove(record.id);
                  }
                }),
              )
            : null,
        title: Text(record.contentPreview,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${record.platform} · ${record.source} · ${record.receivedAt}'
          '${record.deviceModel.isNotEmpty ? ' · ${record.deviceModel}' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(record),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(record.id),
            ),
          ],
        ),
        onTap: () => _showDetail(record),
      ),
    );
  }

  Future<void> _showDetail(HistoryRecord record) async {
    final r = await widget.api.detail(record.id);
    if (!mounted) return;
    final d = r.ok ? r.data! : record;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${d.platform} · ${d.receivedAt}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(d.content ?? d.contentPreview),
              const SizedBox(height: 8),
              Text(
                '来源：${d.source}\nIP：${d.publicIp ?? '-'}\n'
                '系统：${d.osVersion}\n型号：${d.deviceModel}\n'
                '版本：${d.appVersion}\n安装 ID：${d.installationId}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
