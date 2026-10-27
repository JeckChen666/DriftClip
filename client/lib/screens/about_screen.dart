import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_info.dart';

/// 关于页：品牌信息、版本号与 GitHub 开源仓库入口。
///
/// 布局与设置页同构（居中 640 宽 + 分组卡片），保证两页视觉一致。
class AboutScreen extends StatelessWidget {
  /// GitHub 开源仓库地址：与 Web 端页脚、连接引导中的 Releases 链接同源
  /// （仓库根目录即本仓库，见 git remote origin）。
  static const String repoUrl = 'https://github.com/JeckChen666/DriftClip';

  const AboutScreen({super.key});

  /// 复制仓库地址。客户端未引入 url_launcher（仅为展示型页面新增跨平台
  /// 依赖不划算），点击复制 + 粘贴是零依赖且各平台行为一致的替代方案。
  void _copyRepoUrl(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: repoUrl));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('仓库地址已复制：$repoUrl')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // 品牌区：Logo + 名称 + 版本号。版本号唯一来源是 pubspec，
              // 由 main() 启动时经 DeviceInfo.init() 读取（ROADMAP P0.5）。
              Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/branding/driftclip-logo.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'DriftClip',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '版本 ${DeviceInfo.appVersion()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionHeader('开源'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.code_rounded,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  title: const Text('GitHub 开源仓库'),
                  subtitle: const Text(repoUrl),
                  // 行级点击 + 尾部复制图标双提示：整行都可点，不只图标。
                  trailing: Icon(
                    Icons.content_copy_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  onTap: () => _copyRepoUrl(context),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'DriftClip 是一款跨设备剪贴板同步工具，基于 MIT 协议开源。'
                  '欢迎在 GitHub 提交 Issue 反馈问题，或提交 PR 参与共建。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组标题：与设置页 `_SectionHeader` 同款样式（该类为文件私有，无法复用）。
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
