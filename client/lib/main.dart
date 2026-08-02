import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/key_config_screen.dart';
import 'services/api_client.dart';
import 'services/clipboard_monitor.dart';
import 'services/dedup_store.dart';
import 'services/desktop_integration.dart';
import 'services/settings_store.dart';
import 'services/upload_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.init();
  final dedup = DedupStore();
  await dedup.init();
  runApp(DriftClipApp(settings: settings, dedup: dedup));
}

class DriftClipApp extends StatelessWidget {
  final SettingsStore settings;
  final DedupStore dedup;

  const DriftClipApp({super.key, required this.settings, required this.dedup});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DriftClip',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: HomeShell(settings: settings, dedup: dedup),
    );
  }
}

class HomeShell extends StatefulWidget {
  final SettingsStore settings;
  final DedupStore dedup;

  const HomeShell({super.key, required this.settings, required this.dedup});

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
    _desktop.init();
    // 移动端仅前台采集：后台暂停轮询、前台恢复（Spec §5.2）。
    _lifecycle = AppLifecycleListener(onStateChange: _monitor.handleAppLifecycle);
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
    return HomeScreen(
      settings: widget.settings,
      api: _api,
      uploader: _uploader,
      monitor: _monitor,
      desktop: _desktop,
    );
  }
}
