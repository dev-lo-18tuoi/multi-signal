// signal-manager-app.swift — cửa sổ native cho Signal Manager (macOS).
// Được compile CỤC BỘ lúc cài đặt (swiftc trong Command Line Tools) nên không
// dính Gatekeeper. Nhiệm vụ: đảm bảo server dashboard chạy (qua chế độ --url
// của signal_manager_server.py nằm cùng Resources) rồi hiển thị nó trong
// WKWebView — trải nghiệm app thật: cửa sổ riêng, menu bar, ⌘Q.

import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

  func applicationDidFinishLaunching(_ note: Notification) {
    guard let url = dashboardURL() else {
      let alert = NSAlert()
      alert.messageText = "Không khởi động được Signal Manager"
      alert.informativeText = "Server dashboard không phản hồi. Thử mở lại app, hoặc xem log tại ~/Library/Application Support/Signal Manager/server.log"
      alert.runModal()
      NSApp.terminate(nil)
      return
    }

    let rect = NSRect(x: 0, y: 0, width: 1120, height: 780)
    window = NSWindow(
      contentRect: rect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "Signal Manager"
    window.minSize = NSSize(width: 720, height: 480)

    let web = WKWebView(frame: rect)
    web.autoresizingMask = [.width, .height]
    window.contentView = web
    web.load(URLRequest(url: url))

    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  // Gọi server helper ở chế độ --url: đảm bảo server chạy rồi in URL kèm token.
  private func dashboardURL() -> URL? {
    guard let resources = Bundle.main.resourcePath else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["python3", resources + "/signal_manager_server.py", "--url"]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do { try proc.run() } catch { return nil }
    proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let raw = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return nil }
    return URL(string: raw)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu tối thiểu để có ⌘Q chuẩn macOS
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(
  title: "Thoát Signal Manager",
  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appItem.submenu = appMenu
app.mainMenu = mainMenu

app.run()
