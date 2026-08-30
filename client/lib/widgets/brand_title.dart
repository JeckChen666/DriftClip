import 'package:flutter/material.dart';

/// 品牌标题：应用 Logo + 应用名 + 副标题。
///
/// 复用于移动端 AppBar、桌面端 NavSidebar 顶部；可调图标尺寸和是否显示副标题。
class BrandTitle extends StatelessWidget {
  final double iconSize;
  final bool showSubtitle;
  final double titleSize;

  const BrandTitle({
    super.key,
    this.iconSize = 32,
    this.showSubtitle = true,
    this.titleSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/driftclip-logo.png',
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'DriftClip',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            if (showSubtitle)
              Text(
                '剪贴板历史',
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                  height: 1.0,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
