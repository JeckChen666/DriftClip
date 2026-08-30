import 'package:flutter/material.dart';

/// 手动输入对话框：提交后由 UploadCoordinator 处理去重与重试。
/// 去除首尾空格后为空的内容在 coordinator 中拒绝。
class ManualInputDialog extends StatefulWidget {
  /// 初始文本：用于在外部唤起时预填（例如从命令面板选择了一条历史）。
  final String initialText;

  const ManualInputDialog({super.key, this.initialText = ''});

  @override
  State<ManualInputDialog> createState() => _ManualInputDialogState();
}

class _ManualInputDialogState extends State<ManualInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      // 紧凑档：默认 horizontal:40 / vertical:24 在桌面端过宽。
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      actionsPadding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      title: Row(
        children: [
          // 24×24 与 14px 标题文字比例接近；之前 28×28 在弹窗里显重。
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.edit_rounded,
              size: 14,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          const Text('手动输入'),
        ],
      ),
      content: TextField(
        controller: _controller,
        // 3-4 行初始高度，避免占满整个弹窗。
        maxLines: 4,
        minLines: 3,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入要上传的文本',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        // 两按钮统一 36h，与卡片内按钮节奏一致；
        // 否则 FilledButton(36) 与 TextButton(32) 同列会出现 4px 高差。
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          icon: const Icon(Icons.upload_rounded, size: 14),
          label: const Text('上传'),
        ),
      ],
    );
  }
}
