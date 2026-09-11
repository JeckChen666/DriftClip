// GENERATED FILE — DO NOT EDIT.
// Source: tokens/tokens.json
// Run: dart run tool/sync_tokens.dart

import 'package:flutter/painting.dart';

/// DriftClip 设计令牌（精致专业风）单源生成版本。
/// 同时产出 Flutter `_palette.g.dart` 与 Web `tokens.generated.css`。
class Palette {
  final Color accent;
  final Color accentDeep;
  final Color accentHover;
  final Color accentSubtle;
  final Color border;
  final Color borderStrong;
  final Color canvas;
  final Color danger;
  final Color dangerHover;
  final Color dangerSubtle;
  final Color fieldFill;
  final Color onAccent;
  final Color onAccentSubtle;
  final Color onDanger;
  final Color onDangerSubtle;
  final Color shadow;
  final Color success;
  final Color surface;
  final Color surfaceSubtle;
  final Color textMuted;
  final Color textPrimary;
  final Color warnBg;
  final Color warnBorder;
  final Color warnText;

  /// 焦点环 / 投影 / 平台色等不在 ColorScheme 派生里的辅助 token。
  final Color snackBar;
  final Color switchTrackOff;
  final Color accentPurpleBorder;
  final Color accentPurpleText;
  final Color platformAmber;
  final Color platformBlue;
  final Color platformGray;
  final Color platformGreen;
  final Color platformNeutral;
  final Color platformPurple;
  final Color platformTeal;
  final Color snackBarText;
  final Color statusAmber;
  final Color statusGreen;

  const Palette({
    required this.canvas,
    required this.surface,
    required this.surfaceSubtle,
    required this.fieldFill,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.accentDeep,
    required this.accentHover,
    required this.accentSubtle,
    required this.onAccent,
    required this.onAccentSubtle,
    required this.success,
    required this.danger,
    required this.dangerHover,
    required this.dangerSubtle,
    required this.onDanger,
    required this.onDangerSubtle,
    required this.warnBg,
    required this.warnBorder,
    required this.warnText,
    required this.shadow,
    required this.snackBar,
    required this.switchTrackOff,
    required this.accentPurpleBorder,
    required this.accentPurpleText,
    required this.platformAmber,
    required this.platformBlue,
    required this.platformGray,
    required this.platformGreen,
    required this.platformNeutral,
    required this.platformPurple,
    required this.platformTeal,
    required this.snackBarText,
    required this.statusAmber,
    required this.statusGreen,
  });

  factory Palette.light() => const Palette(
    accent: Color(0xFF2563EB),
    accentDeep: Color(0xFF1E40AF),
    accentHover: Color(0xFF1D4ED8),
    accentSubtle: Color(0xFFEAF1FF),
    border: Color(0xFFE4E7EC),
    borderStrong: Color(0xFFCDD3DC),
    canvas: Color(0xFFF7F8FA),
    danger: Color(0xFFDC2626),
    dangerHover: Color(0xFFB91C1C),
    dangerSubtle: Color(0xFFFEE2E2),
    fieldFill: Color(0xFFFCFCFD),
    onAccent: Color(0xFFFFFFFF),
    onAccentSubtle: Color(0xFF1D4ED8),
    onDanger: Color(0xFFFFFFFF),
    onDangerSubtle: Color(0xFFB91C1C),
    shadow: Color(0x1F1A202C),
    success: Color(0xFF16A34A),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF3F4F6),
    textMuted: Color(0xFF646B77),
    textPrimary: Color(0xFF17191E),
    warnBg: Color(0xFFFFF7E6),
    warnBorder: Color(0xFFF5C96B),
    warnText: Color(0xFF8A5A00),
    snackBar: Color(0xFF1F242C),
    switchTrackOff: Color(0xFFD6DAE1),
    accentPurpleBorder: Color(0xFFC4B5FD),
    accentPurpleText: Color(0xFF7C3AED),
    platformAmber: Color(0xFFF59E0B),
    platformBlue: Color(0xFF2563EB),
    platformGray: Color(0xFF64748B),
    platformGreen: Color(0xFF16A34A),
    platformNeutral: Color(0xFF6B7280),
    platformPurple: Color(0xFF8B5CF6),
    platformTeal: Color(0xFF0D9488),
    snackBarText: Color(0xFFF2F4F7),
    statusAmber: Color(0xFFD97706),
    statusGreen: Color(0xFF16A34A),
  );

  factory Palette.dark() => const Palette(
    accent: Color(0xFF3B82F6),
    accentDeep: Color(0xFF2563EB),
    accentHover: Color(0xFF60A5FA),
    accentSubtle: Color(0xFF16233B),
    border: Color(0xFF262B33),
    borderStrong: Color(0xFF39404C),
    canvas: Color(0xFF0F1114),
    danger: Color(0xFFF87171),
    dangerHover: Color(0xFFFCA5A5),
    dangerSubtle: Color(0xFF3A1D1F),
    fieldFill: Color(0xFF1A1E25),
    onAccent: Color(0xFFFFFFFF),
    onAccentSubtle: Color(0xFFBFDBFE),
    onDanger: Color(0xFF450A0A),
    onDangerSubtle: Color(0xFFFCA5A5),
    shadow: Color(0xA6000000),
    success: Color(0xFF22C55E),
    surface: Color(0xFF15181D),
    surfaceSubtle: Color(0xFF1E2229),
    textMuted: Color(0xFF9AA3B2),
    textPrimary: Color(0xFFE9ECF1),
    warnBg: Color(0xFF2B2415),
    warnBorder: Color(0xFF8A6D2F),
    warnText: Color(0xFFF0C674),
    snackBar: Color(0xFF2A2F38),
    switchTrackOff: Color(0xFF3A4150),
    accentPurpleBorder: Color(0xFFC4B5FD),
    accentPurpleText: Color(0xFF7C3AED),
    platformAmber: Color(0xFFF59E0B),
    platformBlue: Color(0xFF2563EB),
    platformGray: Color(0xFF64748B),
    platformGreen: Color(0xFF16A34A),
    platformNeutral: Color(0xFF6B7280),
    platformPurple: Color(0xFF8B5CF6),
    platformTeal: Color(0xFF0D9488),
    snackBarText: Color(0xFFF2F4F7),
    statusAmber: Color(0xFFD97706),
    statusGreen: Color(0xFF16A34A),
  );
}
