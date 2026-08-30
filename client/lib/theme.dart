import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// DriftClip 全局主题（精致专业风格）。
///
/// 品牌色与 Web 端一致（主色 #2563EB，见 web/src/index.css --accent）。
/// 设计取向：克制的中性色 + 强字重层级 + 细分隔线代替重填充 + 仅浮层加阴影。
/// 色彩令牌统一收口在 [_Palette]，组件级样式在此集中配置，
/// 各页面直接用 Theme.of(context) 派生，避免散落硬编码颜色。
abstract final class AppTheme {
  static const Color seed = Color(0xFF2563EB);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final p = _Palette.of(isDark);

    // 以 seed 生成基础 scheme，再用干净中性色覆盖关键 token，
    // 去掉默认 Material 容器色的浑浊感。
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: p.accent,
          onPrimary: p.onAccent,
          primaryContainer: p.accentSubtle,
          onPrimaryContainer: p.onAccentSubtle,
          tertiary: p.accentDeep,
          onTertiary: p.onAccent,
          surface: p.surface,
          onSurface: p.textPrimary,
          surfaceContainerHighest: p.surfaceSubtle,
          onSurfaceVariant: p.textMuted,
          outline: p.outline,
          outlineVariant: p.border,
          error: p.danger,
          onError: p.onDanger,
          errorContainer: p.dangerSubtle,
          onErrorContainer: p.onDangerSubtle,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
    );

    final textTheme = _typography(base.textTheme, p);

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.canvas,
        foregroundColor: p.textPrimary,
        surfaceTintColor: Colors.transparent,
        // 细分隔线代替阴影，与主壳体的平面语言一致。
        shape: Border(bottom: BorderSide(color: p.border)),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: p.textPrimary,
        ),
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: p.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
        // 弹窗标题用 titleMedium（17px），不再用 titleLarge（22px），避免比页面标题还大。
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          color: p.textPrimary,
        ),
        // 弹窗正文用 14px，与全局刻度一致。
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: p.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.fieldFill,
        isDense: true,
        // 锁定前缀/后缀图标区域高度，避免 M3 默认 48 把整行拉到比按钮高一截。
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 36,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.danger, width: 1.6),
        ),
        hintStyle: TextStyle(color: p.textMuted.withValues(alpha: 0.75)),
        labelStyle: TextStyle(color: p.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: p.textPrimary,
          elevation: 0,
          side: BorderSide(color: p.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: p.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(8),
          foregroundColor: p.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        backgroundColor: isDark
            ? const Color(0xFF2A2F38)
            : const Color(0xFF1F242C),
        contentTextStyle: const TextStyle(
          color: Color(0xFFF2F4F7),
          fontSize: 13.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? scheme.outline : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.success;
          }
          return isDark ? const Color(0xFF3A4150) : const Color(0xFFD6DAE1);
        }),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide.none,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textMuted,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        horizontalTitleGap: 12,
        minVerticalPadding: 4,
        // 行内文字 14px，标题用 w600 与全局对齐。
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        subtitleTextStyle: TextStyle(fontSize: 12, color: p.textMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: p.outline, width: 1.5),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: Colors.transparent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 排版：标题紧字距 + 强字重，正文/次要层级清晰。
  static TextTheme _typography(TextTheme base, _Palette p) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: p.textPrimary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: p.textPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: p.textPrimary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
      // TextField 默认输入文字走 bodyLarge；压到 14 与全局刻度对齐，
      // 避免弹窗/表单里的输入文字比卡片标题大一截。
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 14,
        color: p.textPrimary,
        height: 1.5,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 13,
        color: p.textPrimary,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        color: p.textMuted,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelSmall: base.labelSmall?.copyWith(
        letterSpacing: 0.4,
        color: p.textMuted,
      ),
    );
  }
}

/// 两端共享的色彩令牌；集中一处，避免散落硬编码。
class _Palette {
  final Color canvas;
  final Color surface;
  final Color surfaceSubtle;
  final Color fieldFill;
  final Color border;
  final Color outline;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color accentDeep;
  final Color accentSubtle;
  final Color onAccent;
  final Color onAccentSubtle;
  final Color success;
  final Color danger;
  final Color onDanger;
  final Color dangerSubtle;
  final Color onDangerSubtle;
  final Color shadow;

  const _Palette({
    required this.canvas,
    required this.surface,
    required this.surfaceSubtle,
    required this.fieldFill,
    required this.border,
    required this.outline,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.accentDeep,
    required this.accentSubtle,
    required this.onAccent,
    required this.onAccentSubtle,
    required this.success,
    required this.danger,
    required this.onDanger,
    required this.dangerSubtle,
    required this.onDangerSubtle,
    required this.shadow,
  });

  factory _Palette.of(bool isDark) {
    if (isDark) {
      return const _Palette(
        canvas: Color(0xFF0F1114),
        surface: Color(0xFF15181D),
        surfaceSubtle: Color(0xFF1E2229),
        fieldFill: Color(0xFF1A1E25),
        border: Color(0xFF262B33),
        outline: Color(0xFF39404C),
        textPrimary: Color(0xFFE9ECF1),
        textMuted: Color(0xFF9AA3B2),
        accent: Color(0xFF3B82F6),
        accentDeep: Color(0xFF2563EB),
        accentSubtle: Color(0xFF16233B),
        onAccent: Color(0xFFFFFFFF),
        onAccentSubtle: Color(0xFFBFDBFE),
        success: Color(0xFF22C55E),
        danger: Color(0xFFF87171),
        onDanger: Color(0xFF450A0A),
        dangerSubtle: Color(0xFF3A1D1F),
        onDangerSubtle: Color(0xFFFCA5A5),
        shadow: Color(0xA6000000),
      );
    }
    return const _Palette(
      canvas: Color(0xFFF7F8FA),
      surface: Color(0xFFFFFFFF),
      surfaceSubtle: Color(0xFFF3F4F6),
      fieldFill: Color(0xFFFCFCFD),
      border: Color(0xFFE4E7EC),
      outline: Color(0xFFCDD3DC),
      textPrimary: Color(0xFF17191E),
      textMuted: Color(0xFF646B77),
      accent: Color(0xFF2563EB),
      accentDeep: Color(0xFF1E40AF),
      accentSubtle: Color(0xFFEAF1FF),
      onAccent: Color(0xFFFFFFFF),
      onAccentSubtle: Color(0xFF1D4ED8),
      success: Color(0xFF16A34A),
      danger: Color(0xFFDC2626),
      onDanger: Color(0xFFFFFFFF),
      dangerSubtle: Color(0xFFFEE2E2),
      onDangerSubtle: Color(0xFFB91C1C),
      shadow: Color(0x1F1A202C),
    );
  }
}
