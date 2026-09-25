import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    setupDesktopChannel(flutterViewController)
    setupReopenHandling()

    super.awakeFromNib()
  }

  /// 登录自启动（ROADMAP P1.3）：launch_at_startup 插件没有 macOS 原生实现，
  /// 原生侧用 SMAppService（macOS 13+）实现 'driftclip/desktop' 通道。
  /// 真机验证：系统设置 → 通用 → 登录项中应出现 DriftClip；验证后可移除本说明。
  private func setupDesktopChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "driftclip/desktop",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        if call.method == "isLoginItemEnabled" {
          result(false)
        } else {
          result(FlutterError(code: "unsupported", message: "需要 macOS 13+", details: nil))
        }
        return
      }
      switch call.method {
      case "setLoginItemEnabled":
        guard let args = call.arguments as? [String: Any],
              let enabled = args["enabled"] as? Bool else {
          result(FlutterError(code: "bad_args", message: "缺少 enabled 参数", details: nil))
          return
        }
        let service = SMAppService.mainApp
        do {
          // SMAppService 的 Swift 接口为同步 throws 风格（register()/unregister()）。
          if enabled {
            try service.register()
          } else {
            try service.unregister()
          }
          result(enabled)
        } catch {
          result(FlutterError(code: "sm_error", message: error.localizedDescription, details: nil))
        }
      case "isLoginItemEnabled":
        result(SMAppService.mainApp.status == .enabled)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 关窗隐藏到托盘后，Dock 图标点击（applicationShouldHandleReopen）唤起主窗口。
  private func setupReopenHandling() {
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("driftclip.reopen"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}
