import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'theme/_palette.g.dart';

/// DriftClip 全局主题（精致专业风格）。
///
/// 品牌色与 Web 端一致（主色 #2563EB，见 web/src/index.css --accent）。
/// 设计取向：克制的中性色 + 强字重层级 + 细分隔线代替重填充 + 仅浮层加阴影。
/// 色彩令牌统一收口在 [Palette]（由 tokens/tokens.json 经 tool/sync_tokens.dart 生成），
/// 组件级样式在此集中配置，各页面直接用 Theme.of(context) 派生，避免散落硬编码颜色。
abstract final class AppTheme {
  static const Color seed = Color(0xFF2563EB);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final p = isDark ? Palette.dark() : Palette.light();

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
          outline: p.borderStrong,
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
        toolbarHeight: 56,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: p.surface,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: p.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        // 弹窗标题用 titleMedium（16px），不再用 titleLarge（20px），避免比页面标题还大。
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          color: p.textPrimary,
        ),
        // 弹窗正文用 13px，与全局刻度一致。
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: p.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.fieldFill,
        isDense: true,
        // 锁定前缀/后缀图标区域高度，避免 M3 默认 48 把整行拉到比按钮高一截。
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 32,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.danger, width: 1.6),
        ),
        hintStyle: TextStyle(color: p.textMuted.withValues(alpha: 0.75)),
        labelStyle: TextStyle(color: p.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: p.textPrimary,
          elevation: 0,
          side: BorderSide(color: p.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: p.accent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          padding: const EdgeInsets.all(6),
          foregroundColor: p.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        backgroundColor: p.snackBar,
        contentTextStyle: TextStyle(color: p.snackBarText, fontSize: 12.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          return p.switchTrackOff;
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        horizontalTitleGap: 10,
        minVerticalPadding: 2,
        // 行内文字 13px，标题用 w600 与全局对齐。
        titleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        subtitleTextStyle: TextStyle(fontSize: 11, color: p.textMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: p.borderStrong, width: 1.4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
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
  static TextTheme _typography(TextTheme base, Palette p) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: p.textPrimary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: p.textPrimary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: p.textPrimary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
      // TextField 默认输入文字走 bodyLarge；压到 13 与全局刻度对齐，
      // 避免弹窗/表单里的输入文字比卡片标题大一截。
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 13,
        color: p.textPrimary,
        height: 1.5,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 12,
        color: p.textPrimary,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 11,
        color: p.textMuted,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 12,
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
