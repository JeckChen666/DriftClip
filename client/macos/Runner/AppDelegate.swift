import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关窗后是否退出由 Flutter 侧决定（开启监听时隐藏到托盘继续捕获，ROADMAP P1.2）。
    return false
  }

  // 关窗隐藏后点击 Dock 图标重新显示主窗口。
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      NotificationCenter.default.post(name: NSNotification.Name("driftclip.reopen"), object: nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
