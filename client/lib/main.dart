import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/desktop_shell.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'screens/key_config_screen.dart';
import 'services/api_client.dart';
import 'services/clipboard_monitor.dart';
import 'services/dedup_store.dart';
import 'services/desktop_integration.dart';
import 'services/device_info.dart';
import 'services/settings_store.dart';
import 'services/upload_coordinator.dart';
import 'services/upload_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeviceInfo.init(); // 版本号以 pubspec 为唯一来源（ROADMAP P0.5）

  // 桌面端：窗口管理须在 runApp 前初始化，关窗拦截在 DesktopIntegration 中挂接
  // （ROADMAP P1.1/P1.2）。
  if (DesktopIntegration.isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'DriftClip'),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final settings = SettingsStore();
  await settings.init();
  final dedup = DedupStore();
  await dedup.init();

  // 离线上传队列（ROADMAP P1.4）：正文持久化到应用支持目录，网络恢复后补传。
  UploadQueue? queue;
  try {
    final dir = await getApplicationSupportDirectory();
    queue = UploadQueue(dir: dir);
    await queue.load();
  } catch (_) {
    queue = null; // 目录不可用时退化为 V1 的「失败即放弃」
  }

  runApp(DriftClipApp(settings: settings, dedup: dedup, queue: queue));
}

class DriftClipApp extends StatelessWidget {
  final SettingsStore settings;
  final DedupStore dedup;
  final UploadQueue? queue;

  const DriftClipApp({
    super.key,
    required this.settings,
    required this.dedup,
    this.queue,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DriftClip',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: HomeShell(settings: settings, dedup: dedup),
    );
  }
}

class HomeShell extends StatefulWidget {
  final SettingsStore settings;
  final DedupStore dedup;
  final UploadQueue? queue;

  const HomeShell({
    super.key,
    required this.settings,
    required this.dedup,
    this.queue,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final ApiClient _api;
  late final UploadCoordinator _uploader;
  late final ClipboardMonitor _monitor;
  final DesktopIntegration _desktop = DesktopIntegration();
  AppLifecycleListener? _lifecycle;
  String? _key;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(settings: widget.settings);
    _uploader = UploadCoordinator(
      api: _api,
      dedup: widget.dedup,
      settings: widget.settings,
      queue: widget.queue,
    );
    _monitor = ClipboardMonitor(
      uploader: _uploader,
      isDesktop: DesktopIntegration.isDesktop,
    );
    _key = widget.settings.apiKey;
    // 监听默认关闭，只有已配置 Key 且用户显式开启时才启动（Spec §5.2）。
    if (_key != null && _key!.isNotEmpty && widget.settings.listenEnabled) {
      _monitor.start();
    }
    // 托盘常驻与关窗拦截（ROADMAP P1.1/P1.2）。
    _desktop.init(
      monitor: _monitor,
      settings: widget.settings,
      uploader: _uploader,
    );
    // 移动端仅前台采集：后台暂停轮询、前台恢复（Spec §5.2）。
    _lifecycle = AppLifecycleListener(
      onStateChange: _monitor.handleAppLifecycle,
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _onKeySaved(String key) {
    setState(() => _key = key);
    if (widget.settings.listenEnabled) {
      _monitor.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_key == null || _key!.isEmpty) {
      return KeyConfigScreen(
        settings: widget.settings,
        uploader: _uploader,
        onSaved: _onKeySaved,
      );
    }
    // 断点 ≥720 走桌面端双栏布局（NavSidebar + HistoryContent + DetailPane）；
    // < 720 走移动端单列布局（HomeScreen，含 AppBar / FAB）。
    final width = MediaQuery.of(context).size.width;
    if (width >= 720) {
      return DesktopShell(
        settings: widget.settings,
        api: _api,
        uploader: _uploader,
        monitor: _monitor,
        desktop: _desktop,
      );
    }
    return HomeScreen(
      settings: widget.settings,
      api: _api,
      uploader: _uploader,
      monitor: _monitor,
      desktop: _desktop,
    );
  }
}
