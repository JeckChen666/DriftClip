import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'theme/_palette.g.dart';

export 'theme/_palette.g.dart' show Palette;

/// 把令牌 [Palette] 挂到 ThemeData.extensions 上，
/// 让平台色、状态色等不在 ColorScheme 里的令牌也能通过 `Theme.of(context)` 取到，
/// 避免组件重新硬编码颜色。
class AppPalette extends ThemeExtension<AppPalette> {
  final Palette palette;

  const AppPalette(this.palette);

  /// 取当前主题的令牌；若宿主 ThemeData 未注册扩展（如测试里的裸 MaterialApp），
  /// 按亮暗度回退到默认 Palette，避免组件因缺少扩展而崩溃。
  static Palette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>()?.palette ??
        (theme.brightness == Brightness.dark
            ? Palette.dark()
            : Palette.light());
  }

  @override
  AppPalette copyWith({Palette? palette}) =>
      AppPalette(palette ?? this.palette);

  /// 亮暗切换时直接跳变即可：令牌是离散集合，不做逐色插值。
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      t < 0.5 ? this : (other as AppPalette? ?? this);
}

/// DriftClip 全局主题（精致专业风格）。
///
/// 品牌色与 Web 端一致（主色 #2563EB，见 web/src/index.css --accent）。
/// 设计取向：中性画布 + 舒展间距 + 柔和圆角 + 清晰的蓝色交互层级。
/// 色彩令牌统一收口在 [Palette]（由 tokens/tokens.json 经 tool/sync_tokens.dart 生成），
/// 组件级样式在此集中配置，各页面直接用 Theme.of(context) 派生，避免散落硬编码颜色。
abstract final class AppTheme {
  /// 种子色直接取自令牌单源，避免与 tokens.json 漂移。
  static Color get seed => Palette.light().accent;

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
      extensions: [AppPalette(p)],
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
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        // 弹窗是浮层，允许一层柔和投影把它从画布上抬起来。
        elevation: 12,
        shadowColor: p.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.danger, width: 1.6),
        ),
        hintStyle: TextStyle(color: p.textMuted.withValues(alpha: 0.75)),
        labelStyle: TextStyle(color: p.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ).copyWith(
              // hover 走 accentHover 令牌；按下时叠一层浅白，替代 M3 默认的灰色水波。
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? p.accentHover
                    : p.accent,
              ),
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              foregroundColor: p.textPrimary,
              elevation: 0,
              side: BorderSide(color: p.borderStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ).copyWith(
              // hover 时边框与文字同时提亮，给出可点击的即时反馈。
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? BorderSide(color: p.accent, width: 1.2)
                    : BorderSide(color: p.borderStrong),
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? p.accent
                    : p.textPrimary,
              ),
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
        style:
            IconButton.styleFrom(
              minimumSize: const Size(32, 32),
              padding: const EdgeInsets.all(6),
              foregroundColor: p.textMuted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ).copyWith(
              // hover 时图标转为主文字色并铺一层极淡底色，让工具图标可发现。
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? p.textPrimary
                    : p.textMuted,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? p.textPrimary.withValues(alpha: 0.06)
                    : Colors.transparent,
              ),
            ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        backgroundColor: p.snackBar,
        contentTextStyle: TextStyle(color: p.snackBarText, fontSize: 12.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
        subtitleTextStyle: TextStyle(fontSize: 11, color: p.textMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        fontSize: 22,
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
      // 表单与正文保持相近字号，提升长时间阅读的舒适度。
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
        fontSize: 11,
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
