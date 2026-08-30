import 'package:flutter/material.dart';

/// 监听状态指示：开启为绿色「监听中」，关闭为琥珀色「监听未开启」。
///
/// 复用于移动端工具栏顶部与桌面端 NavSidebar 顶部。
class StatusChip extends StatelessWidget {
  final bool listening;
  final VoidCallback? onTap;
  final bool dense;

  const StatusChip({
    super.key,
    required this.listening,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = listening ? const Color(0xFF16A34A) : const Color(0xFFD97706);
    final hPad = dense ? 8.0 : 10.0;
    final vPad = dense ? 2.0 : 4.0;
    final fontSize = dense ? 10.0 : 11.0;
    final dotSize = dense ? 5.0 : 7.0;

    final body = Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: dotSize, color: color),
          const SizedBox(width: 5),
          Text(
            listening ? '监听中' : '监听未开启',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: body,
    );
  }
}
