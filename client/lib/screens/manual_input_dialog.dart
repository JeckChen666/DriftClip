import 'package:flutter/material.dart';

/// 手动输入对话框：提交后由 UploadCoordinator 处理去重与重试。
/// 去除首尾空格后为空的内容在 coordinator 中拒绝。
class ManualInputDialog extends StatefulWidget {
  const ManualInputDialog({super.key});

  @override
  State<ManualInputDialog> createState() => _ManualInputDialogState();
}

class _ManualInputDialogState extends State<ManualInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('手动输入'),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(hintText: '输入要上传的文本'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('上传'),
        ),
      ],
    );
  }
}
