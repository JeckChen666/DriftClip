import 'package:flutter/material.dart';

import 'brand_title.dart';
import 'platform_avatar.dart';
import 'status_chip.dart';

/// 桌面端左侧导航栏（240 宽）。
///
/// 内容自上而下：
/// 1. 品牌头
/// 2. 监听状态指示（点击进设置）
/// 3. 主导航：全部
/// 4. 按平台筛选（含计数）
/// 5. 底部快捷入口：设置 / 手动输入
///
/// 自身无业务状态：所有选中/计数由父级（DesktopShell）注入。
/// 多选是「编辑动作」而非导航视角，入口放在列表工具栏，不在此处。
class NavSidebar extends StatelessWidget {
  /// 当前选中的平台筛选；null 表示「全部」。
  final String? selectedPlatform;

  /// 选中/取消平台筛选。
  final ValueChanged<String?> onPlatformChanged;

  /// 总条数（用于「全部」项右侧计数）。
  final int totalCount;

  /// 各平台条目数。
  final Map<String, int> platformCounts;

  /// 监听状态（用于监听 chip 颜色与点击行为）。
  final bool listening;

  /// 进入设置。
  final VoidCallback onOpenSettings;

  /// 弹出手动输入。
  final VoidCallback onManualInput;

  /// 刷新当前列表。
  final VoidCallback onRefresh;

  const NavSidebar({
    super.key,
    required this.selectedPlatform,
    required this.onPlatformChanged,
    required this.totalCount,
    required this.platformCounts,
    required this.listening,
    required this.onOpenSettings,
    required this.onManualInput,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canvas = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: canvas,
        border: Border(
          right: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(child: _buildScrollBody(context)),
          const Divider(height: 1),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrandTitle(iconSize: 30, titleSize: 19, showSubtitle: false),
          const SizedBox(height: 14),
          Row(
            children: [
              StatusChip(listening: listening, dense: true),
              const Spacer(),
              _iconAction(
                tooltip: '刷新',
                icon: Icons.refresh_rounded,
                onPressed: onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScrollBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(scheme, '主导航'),
          _NavItem(
            icon: Icons.all_inbox_rounded,
            label: '全部',
            count: totalCount,
            selected: selectedPlatform == null,
            onTap: () => onPlatformChanged(null),
          ),
          const SizedBox(height: 8),
          _sectionLabel(scheme, '按平台'),
          ..._platformItems(),
        ],
      ),
    );
  }

  /// 平台筛选项：固定 6 个常见平台 + 计数；空计数仍显示（保持布局稳定）。
  List<Widget> _platformItems() {
    const order = ['macos', 'windows', 'linux', 'android', 'ios', 'web'];
    return order.map((p) {
      final count = platformCounts[p] ?? 0;
      final (icon, color) = PlatformAvatar.lookup(p);
      return _PlatformNavItem(
        icon: icon,
        color: color,
        label: PlatformAvatar.shortName(p),
        count: count,
        selected: selectedPlatform == p,
        onTap: () => onPlatformChanged(selectedPlatform == p ? null : p),
      );
    }).toList();
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FooterButton(
            icon: Icons.edit_rounded,
            label: '手动输入',
            shortcut: '⌘N',
            onPressed: onManualInput,
          ),
          const SizedBox(height: 4),
          _FooterButton(
            icon: Icons.settings_outlined,
            label: '设置',
            shortcut: '⌘,',
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }
}

/// 通用导航项：图标 + 标签 + 计数；选中态高亮。
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 平台筛选项：平台色点 + 平台名 + 计数。
class _PlatformNavItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PlatformNavItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    color: selected
                        ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部快捷按钮：图标 + 标签 + 快捷键提示。
class _FooterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String shortcut;
  final VoidCallback onPressed;

  const _FooterButton({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
              _ShortcutHint(text: shortcut),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快捷键提示标签（仿 macOS 风格圆角）。
class _ShortcutHint extends StatelessWidget {
  final String text;

  const _ShortcutHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: scheme.outlineVariant, width: 0.6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
