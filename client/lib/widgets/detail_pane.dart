import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/history_record.dart';
import '../services/api_client.dart';
import '../utils/time_format.dart';
import 'meta_row.dart';
import 'platform_avatar.dart';

/// 桌面端右侧详情面板（360 宽）。
///
/// 订阅 [selectedId]：变化时拉取 api.detail 获取完整正文。
/// 选中前展示空态提示；选中后展示平台头 + 完整正文 + 元信息行。
class DetailPane extends StatefulWidget {
  final ApiClient api;
  final ValueNotifier<int?> selectedId;

  /// 通过 id 在列表里查 preview；为空时只显示 id 占位。
  final HistoryRecord? Function(int id)? previewLookup;

  /// 复制成功后通知父级显示 snackbar。
  final Future<void> Function(HistoryRecord record) onCopy;

  /// 删除成功后通知父级刷新列表。
  final Future<void> Function(int id) onDelete;

  /// 关闭面板（Esc / 关闭按钮）。
  final VoidCallback onClose;

  const DetailPane({
    super.key,
    required this.api,
    required this.selectedId,
    required this.previewLookup,
    required this.onCopy,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends State<DetailPane> {
  HistoryRecord? _record;
  String? _fullContent;
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    widget.selectedId.addListener(_handleSelectedIdChanged);
    _handleSelectedIdChanged();
  }

  @override
  void dispose() {
    widget.selectedId.removeListener(_handleSelectedIdChanged);
    super.dispose();
  }

  Future<void> _handleSelectedIdChanged() async {
    final id = widget.selectedId.value;
    if (id == null) {
      setState(() {
        _record = null;
        _fullContent = null;
        _loadingDetail = false;
      });
      return;
    }
    // 先用 preview 顶上去，避免右侧空白。
    final preview = widget.previewLookup?.call(id);
    setState(() {
      _record = preview;
      _fullContent = null;
      _loadingDetail = preview != null;
    });
    final r = await widget.api.detail(id);
    if (!mounted) return;
    if (widget.selectedId.value != id) return; // 用户已切换到其他条目
    setState(() {
      _loadingDetail = false;
      if (r.ok && r.data != null) {
        _record = r.data;
        _fullContent = r.data!.content;
      }
    });
  }

  Future<void> _copyCurrent() async {
    final r = _record;
    if (r == null) return;
    final text = _fullContent ?? r.contentPreview;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
    // 通知父级触发其内部计数刷新等。
    await widget.onCopy(r);
  }

  Future<void> _deleteCurrent() async {
    final r = _record;
    if (r == null) return;
    await widget.onDelete(r.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 360,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          left: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: SafeArea(
        left: false,
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '详情',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '关闭详情（Esc）',
            icon: const Icon(Icons.close_rounded, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final r = _record;
    if (r == null) {
      return _buildEmptyState();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPlatformHeader(r),
          const SizedBox(height: 18),
          _buildContentBlock(r),
          const SizedBox(height: 18),
          _buildMetaList(r),
          const SizedBox(height: 12),
          _buildActions(r),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.touch_app_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '选择条目查看详情',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformHeader(HistoryRecord r) {
    final scheme = Theme.of(context).colorScheme;
    final (_, color) = PlatformAvatar.lookup(context, r.platform);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlatformAvatar(platform: r.platform, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.platform.isEmpty ? 'DriftClip' : r.platform,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                TimeFormat.full(r.receivedAt),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContentBlock(HistoryRecord r) {
    final scheme = Theme.of(context).colorScheme;
    final text = _fullContent ?? r.contentPreview;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Stack(
        children: [
          SelectableText(
            text,
            style: const TextStyle(fontSize: 14, height: 1.55),
          ),
          if (_loadingDetail)
            Positioned(
              top: 0,
              right: 0,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetaList(HistoryRecord r) {
    return Column(
      children: [
        MetaRow(
          icon: Icons.travel_explore,
          label: '来源',
          value: r.source.isEmpty ? '-' : r.source,
        ),
        MetaRow(
          icon: Icons.public,
          label: 'IP',
          value: r.publicIp ?? '-',
          monospace: true,
        ),
        MetaRow(
          icon: Icons.memory,
          label: '系统',
          value: r.osVersion.isEmpty ? '-' : r.osVersion,
        ),
        MetaRow(
          icon: Icons.devices_other,
          label: '型号',
          value: r.deviceModel.isEmpty ? '-' : r.deviceModel,
        ),
        MetaRow(
          icon: Icons.info_outline,
          label: '版本',
          value: r.appVersion.isEmpty ? '-' : r.appVersion,
        ),
        MetaRow(
          icon: Icons.fingerprint,
          label: '安装 ID',
          value: r.installationId,
          monospace: true,
        ),
      ],
    );
  }

  Widget _buildActions(HistoryRecord r) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _copyCurrent,
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: const Text('复制'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _deleteCurrent,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            label: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
