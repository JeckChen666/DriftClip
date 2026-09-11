import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/history_record.dart';
import '../screens/manual_input_dialog.dart';
import '../screens/settings_screen.dart';
import '../services/api_client.dart';
import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';
import '../utils/time_format.dart';
import 'meta_row.dart';
import 'platform_avatar.dart';
import 'status_chip.dart';

/// 历史内容区：工具栏 + 列表 + 空/错态 + 批量操作。
///
/// 复用方：
/// - 移动端 [HomeScreen]：包在 Scaffold + AppBar + FAB 里使用（compact=false）。
/// - 桌面端 [DesktopShell]：嵌入 NavSidebar 与 DetailPane 之间（compact=true）。
///
/// compact=true 时：
/// - 工具栏简化、搜索框紧凑；
/// - 卡片采用高密度样式；
/// - 点击条目更新 [selectedId]，由父级展示右侧详情面板，而非弹 Dialog。
class HistoryContent extends StatefulWidget {
  final SettingsStore settings;
  final ApiClient api;
  final UploadCoordinator uploader;
  final ClipboardMonitor monitor;
  final DesktopIntegration desktop;

  /// 桌面端选中条目 id 通知器；非空时点击列表条目会更新它。
  final ValueNotifier<int?>? selectedId;

  /// 桌面端紧凑布局模式。
  final bool compact;

  /// 桌面端平台筛选；与搜索是 AND 关系。
  final String? platformFilter;

  /// 桌面端用于命令面板回写操作的回调；为空时使用默认 Navigator 行为。
  final VoidCallback? onOpenSettings;

  /// 多选模式变化通知：用于父级（移动端 AppBar / 桌面端 NavSidebar）同步 UI。
  final ValueChanged<bool>? onSelectionModeChanged;

  /// 记录集合变化通知：加载/刷新后记录有增减时回调，
  /// 供父级（桌面端 DesktopShell）刷新 NavSidebar 计数。
  final ValueChanged<List<HistoryRecord>>? onRecordsChanged;

  const HistoryContent({
    super.key,
    required this.settings,
    required this.api,
    required this.uploader,
    required this.monitor,
    required this.desktop,
    this.selectedId,
    this.compact = false,
    this.platformFilter,
    this.onOpenSettings,
    this.onSelectionModeChanged,
    this.onRecordsChanged,
  });

  @override
  State<HistoryContent> createState() => HistoryContentState();
}

class HistoryContentState extends State<HistoryContent> {
  List<HistoryRecord> _records = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _query = '';

  // 多选删除 + 清空全部（5s 确认）
  final Set<int> _selected = {};
  bool _selectionMode = false;
  bool _clearConfirming = false;
  int _clearCountdown = 0;
  Timer? _clearTimer;

  // 桌面端搜索框焦点，便于命令面板的「跳到搜索」快捷键。
  final FocusNode _searchFocus = FocusNode();

  // 前台自动静默刷新：每 3s 触发一次 _refresh()（不切 spinner，保留列表上下文）。
  // 移动端切后台时由 AppLifecycleListener 暂停，回到前台再恢复；
  // 桌面端窗口没有后台状态，initState 启动后持续运行。
  Timer? _autoRefreshTimer;
  AppLifecycleListener? _lifecycle;
  static const Duration _autoRefreshInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _load();
    _startAutoRefresh();
    _lifecycle = AppLifecycleListener(onStateChange: _handleLifecycle);
    // 桌面端选中态由父级的 selectedId 驱动，列表需要跟着重绘才能显示高亮。
    widget.selectedId?.addListener(_onSelectedChanged);
  }

  @override
  void didUpdateWidget(covariant HistoryContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      oldWidget.selectedId?.removeListener(_onSelectedChanged);
      widget.selectedId?.addListener(_onSelectedChanged);
    }
  }

  void _onSelectedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.selectedId?.removeListener(_onSelectedChanged);
    _autoRefreshTimer?.cancel();
    _lifecycle?.dispose();
    _clearTimer?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  // —— 命令面板 / 父级调用的对外动作 ————————————————————————————

  /// 触发刷新（命令面板 / 快捷键）。
  void requestRefresh() => _load();

  /// 聚焦搜索框（Cmd/Ctrl+F）。
  void focusSearch() => _searchFocus.requestFocus();

  /// 弹出手动输入对话框（命令面板 / 快捷键）。
  Future<void> requestManualInput() => _openManualInput();

  /// 当前过滤后的快照，供命令面板 / 详情面板使用。
  List<HistoryRecord> get visibleRecords => _filtered;

  /// 全量原始记录，供 NavSidebar 平台计数使用。
  List<HistoryRecord> get records => List.unmodifiable(_records);

  /// 当前是否处于多选模式，供父级同步入口按钮状态。
  bool get selectionMode => _selectionMode;

  /// 切换多选模式（桌面端工具栏「选择」/ 移动端 AppBar 触发）。
  void toggleSelectionMode() {
    final next = !_selectionMode;
    setState(() {
      _selectionMode = next;
      if (!_selectionMode) _selected.clear();
    });
    widget.onSelectionModeChanged?.call(next);
  }

  /// 记录变化签名：内容未变时不通知父级，避免 3s 静默刷新造成父级冗余重建。
  String? _lastNotifiedSignature;

  String _recordsSignature(List<HistoryRecord> rs) =>
      rs.map((r) => '${r.id}:${r.platform.toLowerCase()}').join(',');

  void _notifyRecordsChanged() {
    final signature = _recordsSignature(_records);
    if (signature == _lastNotifiedSignature) return;
    _lastNotifiedSignature = signature;
    widget.onRecordsChanged?.call(records);
  }

  // —— 状态方法 ——————————————————————————————————————————

  /// 清空全部需 5 秒倒计时确认（Spec §6.2 对齐 Web 交互；§2.2 对齐 Key 重置）。
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
      _snack(r.error ?? '删除失败');
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
      _snack(r.error ?? '清空失败');
    }
  }

  // —— 自动静默刷新（前台 3s） ——————————————————————————————

  /// 启动/重建自动刷新定时器。
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      _autoRefreshInterval,
      (_) => _autoRefresh(),
    );
  }

  /// 停止自动刷新（移到后台时调用）。
  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// 生命周期变化：前台恢复时启动，后台暂停时停止。
  void _handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  /// 静默拉取最新列表：不切整屏 spinner，避免干扰用户。
  /// 已有下拉刷新在进行时跳过，避免并发请求。
  Future<void> _autoRefresh() async {
    if (!mounted || _refreshing || _loading) return;
    await _refresh();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _refreshing = false;
      _error = null;
    });
    final r = await widget.api.list();
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        _records = r.data ?? [];
        _loading = false;
      });
      _notifyRecordsChanged();
    } else {
      setState(() {
        _error = r.error;
        _loading = false;
      });
    }
  }

  /// 下拉刷新：不整屏切 spinner，保留列表上下文。
  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final r = await widget.api.list();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      if (r.ok) {
        _records = r.data ?? [];
        _error = null;
      } else {
        _error = r.error;
      }
    });
    if (r.ok) _notifyRecordsChanged();
  }

  Future<void> _delete(int id) async {
    // 桌面端：若删除的是当前选中的条目，清掉 selectedId 让详情面板关闭。
    if (widget.selectedId?.value == id) {
      widget.selectedId?.value = null;
    }
    final r = await widget.api.delete(id);
    if (!mounted) return;
    if (r.ok) {
      await _load();
    } else {
      _snack(r.error ?? '删除失败');
    }
  }

  Future<void> _copy(HistoryRecord record) async {
    // 列表只有预览，复制需拉取完整正文（复制是用户显式本机操作）。
    final r = await widget.api.detail(record.id);
    if (!mounted || !r.ok) return;
    await Clipboard.setData(ClipboardData(text: r.data!.content ?? ''));
    if (mounted) {
      _snack('已复制到剪贴板');
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
    _snack(ok ? '已上传' : '上传失败或内容为空');
    await _load(); // 本设备成功上传后更新当前列表（Spec §5.1）
  }

  Future<void> _openSettings() async {
    if (widget.onOpenSettings != null) {
      widget.onOpenSettings!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          monitor: widget.monitor,
          desktop: widget.desktop,
        ),
      ),
    );
    // 设置页可能改动了监听开关，返回后刷新状态指示。
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<HistoryRecord> get _filtered {
    final q = _query.trim().toLowerCase();
    final pf = widget.platformFilter?.toLowerCase();
    return _records.where((r) {
      if (pf != null && r.platform.toLowerCase() != pf) return false;
      if (q.isEmpty) return true;
      return r.contentPreview.toLowerCase().contains(q) ||
          r.source.toLowerCase().contains(q) ||
          r.deviceModel.toLowerCase().contains(q) ||
          r.platform.toLowerCase().contains(q);
    }).toList();
  }

  // —— 构建 ————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 401 状态横幅：需要更新 Key（Spec §4.1）
        ValueListenableBuilder<bool>(
          valueListenable: widget.uploader.needsNewKey,
          builder: (context, needsNewKey, _) => needsNewKey
              ? _NeedsKeyBanner(
                  onDismiss: () => widget.uploader.needsNewKey.value = false,
                )
              : const SizedBox.shrink(),
        ),
        _buildToolbar(),
        if (_selectionMode) _buildBulkBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  /// 工具栏：监听状态 + 搜索框；compact 模式搜索框旁放「选择」入口。
  Widget _buildToolbar() {
    final pad = widget.compact
        ? const EdgeInsets.fromLTRB(16, 8, 16, 6)
        : const EdgeInsets.fromLTRB(14, 2, 14, 6);
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact) ...[
            Row(
              children: [
                StatusChip(
                  listening: widget.settings.listenEnabled,
                  onTap: _openSettings,
                ),
                const Spacer(),
                Text(
                  _query.trim().isNotEmpty
                      ? '匹配 ${_filtered.length} / 共 ${_records.length} 条'
                      : '共 ${_records.length} 条',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索剪贴板历史…',
                    prefixIcon: const Icon(Icons.search, size: 15),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            icon: const Icon(Icons.close, size: 14),
                            onPressed: () => setState(() => _query = ''),
                          ),
                  ),
                ),
              ),
              if (widget.compact) ...[
                const SizedBox(width: 8),
                _selectionToggle(),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 多选入口（桌面端工具栏）：默认低调描边，激活后浅 accent 底强调。
  /// 紧凑档高度 32，与工具栏搜索框对齐。
  Widget _selectionToggle() {
    final scheme = Theme.of(context).colorScheme;
    if (_selectionMode) {
      return Tooltip(
        message: '退出多选',
        child: FilledButton.tonalIcon(
          onPressed: toggleSelectionMode,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 14),
          label: const Text('完成'),
        ),
      );
    }
    return Tooltip(
      message: '多选删除',
      child: OutlinedButton.icon(
        onPressed: toggleSelectionMode,
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: scheme.outlineVariant),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        icon: const Icon(Icons.checklist_rounded, size: 14),
        label: const Text('选择'),
      ),
    );
  }

  /// 选择模式下的批量操作栏：全选、删除所选、清空全部（5s 倒计时确认）。
  Widget _buildBulkBar() {
    final allSelected =
        _filtered.isNotEmpty && _selected.length == _filtered.length;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (_) => setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                _selected.addAll(_filtered.map((r) => r.id));
              }
            }),
          ),
          const Text('全选'),
          const Spacer(),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _deleteSelected,
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                minimumSize: const Size(0, 32),
              ),
              child: Text('删除所选（${_selected.length}）'),
            ),
          if (_clearConfirming)
            _clearCountdown > 0
                ? FilledButton.tonal(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text('清空全部（${_clearCountdown}s）'),
                  )
                : FilledButton(
                    key: const ValueKey('confirm-clear'),
                    onPressed: _clearAll,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('确认清空全部'),
                  )
          else
            FilledButton.tonal(
              key: const ValueKey('start-clear'),
              onPressed: _startClearCountdown,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
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
      return _ErrorState(message: _error!, onRetry: _load);
    }
    final items = _filtered;
    if (items.isEmpty) {
      return _EmptyState(searching: _query.trim().isNotEmpty, onRefresh: _load);
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 16 : 14,
              4,
              widget.compact ? 16 : 14,
              80,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _recordCard(
              items[i],
              isSelected: widget.selectedId?.value == items[i].id,
            ),
          ),
        ),
        if (_refreshing)
          Positioned(
            top: 6,
            right: 16,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }

  /// 列表卡片：compact 模式采用更高密度与选中态描边。
  Widget _recordCard(HistoryRecord record, {required bool isSelected}) {
    if (widget.compact) return _compactCard(record, isSelected: isSelected);
    return _regularCard(record);
  }

  Widget _regularCard(HistoryRecord record) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showDetail(record),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectionMode) ...[
                Checkbox(
                  key: ValueKey('record-select-${record.id}'),
                  value: _selected.contains(record.id),
                  onChanged: (_) => setState(() {
                    if (!_selected.add(record.id)) {
                      _selected.remove(record.id);
                    }
                  }),
                ),
                const SizedBox(width: 4),
              ],
              PlatformAvatar(platform: record.platform),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.contentPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _metaLine(record),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_selectionMode) ...[
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '复制',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copy(record),
                ),
                IconButton(
                  tooltip: '删除',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: () => _delete(record.id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 桌面端高密度卡片：干净表面 + 1px 细边框，悬停加深边框并提亮底色，
  /// 选中态浅 accent 底 + accent 描边。
  Widget _compactCard(HistoryRecord record, {required bool isSelected}) {
    final scheme = Theme.of(context).colorScheme;
    final (platformIcon, platformColor) = PlatformAvatar.lookup(
      context,
      record.platform,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _HoverAware(
        builder: (context, hovered) => Material(
          color: isSelected ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: scheme.onSurface.withValues(alpha: 0.03),
            onTap: () {
              if (_selectionMode) {
                setState(() {
                  if (!_selected.add(record.id)) _selected.remove(record.id);
                });
                return;
              }
              // 桌面端点击：通知父级展示右侧详情面板。
              widget.selectedId?.value = record.id;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                // 三态边框：选中 > 悬停 > 静默，层级递减。
                border: Border.all(
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.55)
                      : hovered
                      ? scheme.outline
                      : scheme.outlineVariant,
                  width: isSelected ? 1.2 : 1,
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧平台标识：30 圆角图标块（颜色 + 图标双重信号）。
                    // 与 NavSidebar 平台项样式保持一致，视觉语言统一。
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: platformColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          platformIcon,
                          size: 17,
                          color: platformColor,
                        ),
                      ),
                    ),
                    if (_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 6),
                        child: Checkbox(
                          value: _selected.contains(record.id),
                          onChanged: (_) => setState(() {
                            if (!_selected.add(record.id)) {
                              _selected.remove(record.id);
                            }
                          }),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.contentPreview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _metaLine(record),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 桌面端操作：颜色交给 iconButtonTheme，悬停自动提亮。
                    if (!_selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '复制',
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              onPressed: () => _copy(record),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                              ),
                              onPressed: () => _delete(record.id),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 元信息行：相对时间 · 设备 · 来源 · 平台。
  String _metaLine(HistoryRecord record) {
    final parts = <String>[
      TimeFormat.relative(record.receivedAt),
      PlatformAvatar.shortName(record.platform),
      if (record.deviceModel.isNotEmpty) record.deviceModel,
    ];
    final line = parts.join(' · ');
    return record.source.isEmpty ? line : '$line · ${record.source}';
  }

  /// 移动端使用的弹窗详情；桌面端由右侧 [DetailPane] 替代。
  Future<void> _showDetail(HistoryRecord record) async {
    final r = await widget.api.detail(record.id);
    if (!mounted) return;
    final d = r.ok ? r.data! : record;
    final scheme = Theme.of(context).colorScheme;
    // 移动端用可拖拽底部弹层：拇指够得着、长内容能滚动、下拉即关，
    // 比居中 AlertDialog 更贴近手机端的操作习惯。
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (context, controller) => Column(
          children: [
            // 拖拽把手：告诉用户这是可拉动的面板。
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  PlatformAvatar(platform: d.platform, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.platform.isEmpty ? 'DriftClip' : d.platform,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          TimeFormat.full(d.receivedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: SelectableText(
                      d.content ?? d.contentPreview,
                      style: const TextStyle(fontSize: 12.5, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MetaRow(
                    icon: Icons.travel_explore,
                    label: '来源',
                    value: d.source.isEmpty ? '-' : d.source,
                  ),
                  MetaRow(
                    icon: Icons.public,
                    label: 'IP',
                    value: d.publicIp ?? '-',
                  ),
                  MetaRow(
                    icon: Icons.memory,
                    label: '系统',
                    value: d.osVersion.isEmpty ? '-' : d.osVersion,
                  ),
                  MetaRow(
                    icon: Icons.devices_other,
                    label: '型号',
                    value: d.deviceModel.isEmpty ? '-' : d.deviceModel,
                  ),
                  MetaRow(
                    icon: Icons.info_outline,
                    label: '版本',
                    value: d.appVersion.isEmpty ? '-' : d.appVersion,
                  ),
                  MetaRow(
                    icon: Icons.fingerprint,
                    label: '安装 ID',
                    value: d.installationId,
                    monospace: true,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _delete(d.id);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 15),
                      label: const Text('删除'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _copy(d);
                      },
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: const Text('复制'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 401 需要更新 Key 的横幅。
class _NeedsKeyBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const _NeedsKeyBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Key 无效或已被重置，请在设置中更新',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(onPressed: onDismiss, child: const Text('知道了')),
        ],
      ),
    );
  }
}

/// 空状态：首次无记录 / 搜索无结果两种文案。
class _EmptyState extends StatelessWidget {
  final bool searching;
  final VoidCallback onRefresh;

  const _EmptyState({required this.searching, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
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
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : Icons.content_paste_off_rounded,
                size: 20,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              searching ? '没有匹配的内容' : '暂无历史记录',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              searching ? '换个关键词试试' : '复制文本后会自动同步到这里',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载失败状态。
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
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
                color: scheme.errorContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 20,
                color: scheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '加载失败',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把指针悬停状态暴露给 builder，供卡片在 hover 时切换边框/底色。
/// 独立成 StatefulWidget 是为了让每张卡片各自持有状态，
/// 不用在列表 build 中反复创建 ValueNotifier。
class _HoverAware extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;

  const _HoverAware({required this.builder});

  @override
  State<_HoverAware> createState() => _HoverAwareState();
}

class _HoverAwareState extends State<_HoverAware> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
