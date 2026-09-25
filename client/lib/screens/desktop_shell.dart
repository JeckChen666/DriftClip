import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/history_record.dart';
import '../screens/settings_screen.dart';
import '../services/api_client.dart';
import '../services/clipboard_monitor.dart';
import '../services/desktop_integration.dart';
import '../services/settings_store.dart';
import '../services/upload_coordinator.dart';
import '../widgets/detail_pane.dart';
import '../widgets/history_content.dart';
import '../widgets/nav_sidebar.dart';

/// 桌面端 Shell：左 NavSidebar + 中 HistoryContent + 右 DetailPane。
///
/// 状态：
/// - [selectedId] 选中条目 id，驱动 DetailPane。
/// - [platformFilter] 平台筛选，传给 HistoryContent。
/// - 多选模式由 HistoryContent 内部持有，入口在其工具栏的「选择」按钮。
class DesktopShell extends StatefulWidget {
  final SettingsStore settings;
  final ApiClient api;
  final UploadCoordinator uploader;
  final ClipboardMonitor monitor;
  final DesktopIntegration desktop;

  const DesktopShell({
    super.key,
    required this.settings,
    required this.api,
    required this.uploader,
    required this.monitor,
    required this.desktop,
  });

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  /// 选中条目 id 通知器；同时驱动 DetailPane 与列表卡片高亮。
  final ValueNotifier<int?> _selectedId = ValueNotifier(null);

  /// 平台筛选；与搜索是 AND 关系。
  String? _platformFilter;

  /// HistoryContent 同步过来的全量记录，驱动 NavSidebar 计数。
  /// 不能在 build 里读 _contentKey.currentState：列表异步加载/刷新只重绘
  /// HistoryContent 自身，不会触发本组件重建，计数会停留在旧值。
  List<HistoryRecord> _records = const [];

  /// 用于命令面板回写到 HistoryContent（refresh / manualInput / focusSearch）。
  final GlobalKey<HistoryContentState> _contentKey =
      GlobalKey<HistoryContentState>();

  /// 设置返回后递增，强制 NavSidebar 重读 settings（监听开关状态）。
  int _settingsTick = 0;

  @override
  void dispose() {
    _selectedId.dispose();
    super.dispose();
  }

  // —— 选择相关 ————————————————————————————————————————

  void _closeDetail() {
    _selectedId.value = null;
  }

  // —— HistoryContent 状态同步 ————————————————————————————

  void _onRecordsChanged(List<HistoryRecord> records) {
    if (!mounted) return;
    setState(() => _records = records);
  }

  // —— 入口 —————————————————————————————————————————————

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          monitor: widget.monitor,
          desktop: widget.desktop,
          uploader: widget.uploader,
        ),
      ),
    );
    if (mounted) setState(() => _settingsTick++);
  }

  void _openManualInput() => _contentKey.currentState?.requestManualInput();

  void _refresh() => _contentKey.currentState?.requestRefresh();

  void _focusSearch() => _contentKey.currentState?.focusSearch();

  // —— 详情面板回调 ——————————————————————————————————

  Future<void> _onDetailCopy(HistoryRecord record) async {
    // 复制逻辑已在 DetailPane 内部完成（含 snackbar）。
    // 记录集合不变，无需刷新；侧边栏计数由 onRecordsChanged 保持实时。
  }

  Future<void> _onDetailDelete(int id) async {
    final r = await widget.api.delete(id);
    if (!mounted) return;
    if (r.ok) {
      _contentKey.currentState?.requestRefresh();
      _closeDetail();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(r.error ?? '删除失败')));
    }
  }

  // —— 平台计数（左侧栏展示） ————————————————————————————

  Map<String, int> _platformCounts(List<HistoryRecord> records) {
    final m = <String, int>{
      'macos': 0,
      'windows': 0,
      'linux': 0,
      'android': 0,
      'ios': 0,
      'web': 0,
    };
    for (final r in records) {
      final k = r.platform.toLowerCase();
      if (m.containsKey(k)) m[k] = m[k]! + 1;
    }
    return m;
  }

  // —— 构建 ————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    final allRecords = _records;
    final platformCounts = _platformCounts(allRecords);

    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              ValueListenableBuilder<int?>(
                valueListenable: _selectedId,
                builder: (context, id, _) {
                  // 窄桌面窗口展开详情时暂时收起导航，给正文保留可读宽度。
                  // 关闭详情后恢复原平台筛选和导航位置。
                  if (id != null && MediaQuery.sizeOf(context).width < 1040) {
                    return const SizedBox.shrink();
                  }
                  return NavSidebar(
                    key: ValueKey('nav-$_settingsTick'),
                    selectedPlatform: _platformFilter,
                    onPlatformChanged: (p) =>
                        setState(() => _platformFilter = p),
                    totalCount: allRecords.length,
                    platformCounts: platformCounts,
                    listening: widget.settings.listenEnabled,
                    onOpenSettings: _openSettings,
                    onManualInput: _openManualInput,
                    onRefresh: _refresh,
                  );
                },
              ),
              Expanded(
                child: HistoryContent(
                  key: _contentKey,
                  settings: widget.settings,
                  api: widget.api,
                  uploader: widget.uploader,
                  monitor: widget.monitor,
                  desktop: widget.desktop,
                  compact: true,
                  selectedId: _selectedId,
                  platformFilter: _platformFilter,
                  onOpenSettings: _openSettings,
                  onRecordsChanged: _onRecordsChanged,
                ),
              ),
              ValueListenableBuilder<int?>(
                valueListenable: _selectedId,
                builder: (context, id, _) {
                  if (id == null) return const SizedBox.shrink();
                  return DetailPane(
                    api: widget.api,
                    selectedId: _selectedId,
                    previewLookup: _lookupPreview,
                    onCopy: _onDetailCopy,
                    onDelete: _onDetailDelete,
                    onClose: _closeDetail,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 列表条目 id → 完整 record；用于详情面板先显示 preview 再异步拉详情。
  HistoryRecord? _lookupPreview(int id) {
    final state = _contentKey.currentState;
    if (state == null) return null;
    for (final r in state.records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// 全局快捷键：macOS 用 meta（⌘），其他平台用 ctrl。
  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final isMac = _isMac();
    return {
      // ⌘/Ctrl+N：手动输入
      SingleActivator(LogicalKeyboardKey.keyN, meta: isMac, control: !isMac):
          _openManualInput,
      // ⌘/Ctrl+R：刷新
      SingleActivator(LogicalKeyboardKey.keyR, meta: isMac, control: !isMac):
          _refresh,
      // ⌘/Ctrl+,：设置
      SingleActivator(LogicalKeyboardKey.comma, meta: isMac, control: !isMac):
          _openSettings,
      // ⌘/Ctrl+F：聚焦搜索
      SingleActivator(LogicalKeyboardKey.keyF, meta: isMac, control: !isMac):
          _focusSearch,
      // Esc：关闭详情面板
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (_selectedId.value != null) {
          _closeDetail();
        } else {
          Navigator.of(context).maybePop();
        }
      },
    };
  }

  static bool _isMac() {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
