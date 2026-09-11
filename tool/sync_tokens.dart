// DriftClip 设计令牌同步脚本
// 单源：tokens/tokens.json
// 输出：client/lib/theme/_palette.g.dart 与 web/src/tokens.generated.css
//
// 用法：
//   dart run tool/sync_tokens.dart            # 生成
//   dart run tool/sync_tokens.dart --check    # 校验（CI 用）

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final checkOnly = args.contains('--check');

  final repoRoot = _findRepoRoot();
  final tokensFile = File('$repoRoot/tokens/tokens.json');
  if (!tokensFile.existsSync()) {
    stderr.writeln('❌ 找不到 ${tokensFile.path}');
    exit(1);
  }

  final Map<String, dynamic> tokens =
      jsonDecode(tokensFile.readAsStringSync()) as Map<String, dynamic>;

  final flutterOut = _generateFlutterPalette(tokens, repoRoot: repoRoot);
  final cssOut = _generateCssTokens(tokens, repoRoot: repoRoot);

  final flutterPath = '$repoRoot/client/lib/theme/_palette.g.dart';
  final cssPath = '$repoRoot/web/src/tokens.generated.css';

  if (checkOnly) {
    var drift = false;

    final currentFlutter = File(flutterPath).existsSync()
        ? _formatDart(File(flutterPath).readAsStringSync())
        : '';
    final expectedFlutter = _formatDart(flutterOut);
    final currentCss = File(cssPath).existsSync()
        ? File(cssPath).readAsStringSync()
        : '';

    if (currentFlutter != expectedFlutter) {
      stderr.writeln(
        '❌ $flutterPath 与 tokens.json 不一致；请运行 dart run tool/sync_tokens.dart',
      );
      drift = true;
    }
    if (currentCss != cssOut) {
      stderr.writeln(
        '❌ $cssPath 与 tokens.json 不一致；请运行 dart run tool/sync_tokens.dart',
      );
      drift = true;
    }
    if (drift) exit(1);
    stdout.writeln('✅ tokens 已同步');
    return;
  }

  File(flutterPath).writeAsStringSync(_formatDart(flutterOut));
  File(cssPath).writeAsStringSync(cssOut);

  stdout.writeln('✅ 写入 $flutterPath');
  stdout.writeln('✅ 写入 $cssPath');
}

/// 通过 dart format 子进程把生成出来的 Dart 代码规整，
/// 避免生成器未格式化的产出与已 format 的版本产生无意义 diff。
String _formatDart(String source) {
  final tmp = File('${Directory.systemTemp.path}/_palette.g.dart.fmt.tmp');
  tmp.writeAsStringSync(source);
  try {
    final check = Process.runSync(
      'dart',
      ['format', '--output=none', '--set-exit-if-changed', tmp.path],
    );
    if (check.exitCode == 0) return source;
    final fixed = Process.runSync('dart', ['format', tmp.path]);
    if (fixed.exitCode != 0) return source;
    return tmp.readAsStringSync();
  } finally {
    if (tmp.existsSync()) tmp.deleteSync();
  }
}

/// 仓库根目录 = 当前脚本上溯到包含 pubspec.yaml 与 tokens/ 的目录
String _findRepoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/tokens/tokens.json').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('未找到仓库根目录（应包含 tokens/tokens.json）');
    }
    dir = parent;
  }
}

/// 把 hex 字符串归一为 8 位（带 alpha），便于 Dart Color(0xAARRGGBB)
String _normalizeHex(String hex) {
  var h = hex.replaceFirst('#', '').toUpperCase();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) {
    throw FormatException('无法解析的颜色: $hex');
  }
  return h;
}

/// camelCase → kebab-case（仅保留 a-z0-9 与 -）
String _toKebab(String s) => s
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]}-${m[2]}')
    .toLowerCase();

/// 按 a→z 排键，让生成文件稳定（git diff 友好）
List<MapEntry<String, dynamic>> _sorted(Map<String, dynamic> m) {
  final keys = m.keys.toList()..sort();
  return [for (final k in keys) MapEntry(k, m[k])];
}

// —— Flutter _palette.g.dart ——————————————————————————————————————

String _generateFlutterPalette(
  Map<String, dynamic> tokens, {
  required String repoRoot,
}) {
  final colors = tokens['color'] as Map<String, dynamic>;
  final colorRaw = tokens['colorRaw'] as Map<String, dynamic>;

  final dartKeys = <String>[];
  final lightExprs = <String>[];
  final darkExprs = <String>[];

  for (final entry in _sorted(colors)) {
    final key = entry.key;
    final light = (entry.value as Map<String, dynamic>)['light'] as String;
    final dark = (entry.value as Map<String, dynamic>)['dark'] as String;
    dartKeys.add('  final Color $key;');
    lightExprs.add('        $key: Color(0x${_normalizeHex(light)}),');
    darkExprs.add('        $key: Color(0x${_normalizeHex(dark)}),');
  }

  // colorRaw 拆成两类：
  //  - 成对键（xxxLight/xxxDark）→ 生成单一字段 xxx，按亮暗取值；
  //  - 单值键 → 生成同名字段，亮暗同值。
  final pairedRaw = <String, List<String>>{};
  final singleRaw = <String, String>{};
  for (final entry in _sorted(colorRaw)) {
    final key = entry.key;
    final v = entry.value as String;
    if (key.endsWith('Light')) {
      final base = key.substring(0, key.length - 5);
      pairedRaw.putIfAbsent(base, () => ['', ''])[0] = v;
    } else if (key.endsWith('Dark')) {
      final base = key.substring(0, key.length - 4);
      pairedRaw.putIfAbsent(base, () => ['', ''])[1] = v;
    } else {
      singleRaw[key] = v;
    }
  }
  final rawFields = <String>[for (final base in pairedRaw.keys.toList()..sort()) base]
    ..addAll(singleRaw.keys.toList()..sort());

  final lightRawExprs = <String>[];
  final darkRawExprs = <String>[];
  for (final field in rawFields) {
    if (pairedRaw.containsKey(field)) {
      final pair = pairedRaw[field]!;
      lightRawExprs.add('        $field: Color(0x${_normalizeHex(pair[0])}),');
      darkRawExprs.add('        $field: Color(0x${_normalizeHex(pair[1])}),');
    } else {
      final v = singleRaw[field]!;
      lightRawExprs.add('        $field: Color(0x${_normalizeHex(v)}),');
      darkRawExprs.add('        $field: Color(0x${_normalizeHex(v)}),');
    }
  }

  final ring = tokens['ring'] as Map<String, dynamic>;
  final shadowSm = tokens['shadowSm'] as Map<String, dynamic>;

  final buffer = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT.')
    ..writeln('// Source: tokens/tokens.json')
    ..writeln('// Run: dart run tool/sync_tokens.dart')
    ..writeln('')
    ..writeln("import 'package:flutter/painting.dart';")
    ..writeln('')
    ..writeln('/// DriftClip 设计令牌（精致专业风）单源生成版本。')
    ..writeln(
      '/// 同时产出 Flutter `_palette.g.dart` 与 Web `tokens.generated.css`。',
    )
    ..writeln('class Palette {')
    ..writeln(dartKeys.join('\n'))
    ..writeln('')
    ..writeln('  /// 焦点环 / 投影 / 平台色等不在 ColorScheme 派生里的辅助 token。')
    ..writeln(
      rawFields.map((f) => '  final Color $f;').join('\n'),
    )
    ..writeln('')
    ..writeln('  const Palette({')
    ..writeln('    required this.canvas,')
    ..writeln('    required this.surface,')
    ..writeln('    required this.surfaceSubtle,')
    ..writeln('    required this.fieldFill,')
    ..writeln('    required this.border,')
    ..writeln('    required this.borderStrong,')
    ..writeln('    required this.textPrimary,')
    ..writeln('    required this.textMuted,')
    ..writeln('    required this.accent,')
    ..writeln('    required this.accentDeep,')
    ..writeln('    required this.accentHover,')
    ..writeln('    required this.accentSubtle,')
    ..writeln('    required this.onAccent,')
    ..writeln('    required this.onAccentSubtle,')
    ..writeln('    required this.success,')
    ..writeln('    required this.danger,')
    ..writeln('    required this.dangerHover,')
    ..writeln('    required this.dangerSubtle,')
    ..writeln('    required this.onDanger,')
    ..writeln('    required this.onDangerSubtle,')
    ..writeln('    required this.warnBg,')
    ..writeln('    required this.warnBorder,')
    ..writeln('    required this.warnText,')
    ..writeln('    required this.shadow,')
    ..writeln(
      rawFields.map((f) => '    required this.$f,').join('\n'),
    )
    ..writeln('  });')
    ..writeln('')
    ..writeln('  factory Palette.light() => const Palette(')
    ..writeln(lightExprs.join('\n'))
    ..writeln(lightRawExprs.join('\n'))
    ..writeln('      );')
    ..writeln('')
    ..writeln('  factory Palette.dark() => const Palette(')
    ..writeln(darkExprs.join('\n'))
    ..writeln(darkRawExprs.join('\n'))
    ..writeln('      );')
    ..writeln('}');

  return buffer.toString();
}

// —— Web tokens.generated.css ————————————————————————————————————————

String _generateCssTokens(
  Map<String, dynamic> tokens, {
  required String repoRoot,
}) {
  final colors = tokens['color'] as Map<String, dynamic>;
  final colorRaw = tokens['colorRaw'] as Map<String, dynamic>;
  final ring = tokens['ring'] as Map<String, dynamic>;
  final shadowSm = tokens['shadowSm'] as Map<String, dynamic>;
  final radius = tokens['radius'] as Map<String, dynamic>;
  final control = tokens['control'] as Map<String, dynamic>;
  final icon = tokens['icon'] as Map<String, dynamic>;

  final lightBuf = StringBuffer();
  final darkBuf = StringBuffer();

  for (final entry in _sorted(colors)) {
    final key = _toKebab(entry.key);
    final light = (entry.value as Map<String, dynamic>)['light'] as String;
    final dark = (entry.value as Map<String, dynamic>)['dark'] as String;
    lightBuf.writeln('  --$key: ${light.toLowerCase()};');
    darkBuf.writeln('    --$key: ${dark.toLowerCase()};');
  }

  lightBuf
    ..writeln('  --ring: ${ring['light']};')
    ..writeln('  --shadow-sm: ${shadowSm['light']};');
  darkBuf
    ..writeln('    --ring: ${ring['dark']};')
    ..writeln('    --shadow-sm: ${shadowSm['dark']};');

  // 形状（半径），暗色不变
  for (final entry in _sorted(radius)) {
    lightBuf.writeln('  --radius-${_toKebab(entry.key)}: ${entry.value}px;');
    darkBuf.writeln('    --radius-${_toKebab(entry.key)}: ${entry.value}px;');
  }
  // 控件高度
  for (final entry in _sorted(control)) {
    lightBuf.writeln('  --control-${_toKebab(entry.key)}: ${entry.value}px;');
    darkBuf.writeln('    --control-${_toKebab(entry.key)}: ${entry.value}px;');
  }
  // 图标尺寸
  for (final entry in _sorted(icon)) {
    lightBuf.writeln('  --icon-${_toKebab(entry.key)}: ${entry.value}px;');
    darkBuf.writeln('    --icon-${_toKebab(entry.key)}: ${entry.value}px;');
  }
  // 共用 raw 色（manual 徽章、暗色备用色）
  for (final entry in _sorted(colorRaw)) {
    final key = _toKebab(entry.key);
    lightBuf.writeln('  --$key: ${(entry.value as String).toLowerCase()};');
    darkBuf.writeln('    --$key: ${(entry.value as String).toLowerCase()};');
  }

  return '''/* GENERATED FILE — DO NOT EDIT.
   Source: tokens/tokens.json
   Run: dart run tool/sync_tokens.dart */

:root {
${lightBuf.toString().trimRight()}
}

@media (prefers-color-scheme: dark) {
  :root {
${darkBuf.toString().trimRight()}
  }
}
''';
}
