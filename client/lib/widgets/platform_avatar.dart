import 'package:flutter/material.dart';

import '../theme.dart';

/// 平台头像：按平台着色的圆角图标块。
///
/// 复用于列表卡片、详情面板、命令面板等多处，集中维护平台→(图标, 颜色) 映射。
class PlatformAvatar extends StatelessWidget {
  final String platform;
  final double size;

  const PlatformAvatar({super.key, required this.platform, this.size = 32});

  /// 平台 → (图标, 颜色) 映射；颜色来自令牌单源，集中避免散落到各处。
  static (IconData, Color) lookup(BuildContext context, String platform) {
    final p = AppPalette.of(context);
    switch (platform.toLowerCase()) {
      case 'macos':
        return (Icons.laptop_mac_rounded, p.platformGray);
      case 'windows':
        return (Icons.laptop_windows_rounded, p.platformBlue);
      case 'linux':
        return (Icons.laptop_rounded, p.platformAmber);
      case 'android':
        return (Icons.android_rounded, p.platformGreen);
      case 'ios':
        return (Icons.phone_iphone_rounded, p.platformTeal);
      case 'web':
        return (Icons.language_rounded, p.platformPurple);
      default:
        return (Icons.devices_other_rounded, p.platformNeutral);
    }
  }

  /// 平台缩写徽标（用于紧凑列表行）。
  static String shortName(String platform) {
    switch (platform.toLowerCase()) {
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Win';
      case 'linux':
        return 'Linux';
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'web':
        return 'Web';
      default:
        return platform.isEmpty ? '未知' : platform;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = lookup(context, platform);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}
