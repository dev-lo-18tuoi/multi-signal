// SignalManagerApp.swift — app native của Signal Manager (macOS).
// Được compile CỤC BỘ lúc cài đặt (swiftc trong Command Line Tools) nên không
// dính Gatekeeper. Gồm 2 phần:
//   1. Cửa sổ dashboard (WKWebView nạp server local qua chế độ --url)
//   2. Menu bar 🦆: điều khiển nhanh account (mở/focus, tắt, mở tất cả) mà
//      không cần mở dashboard. Đóng cửa sổ → app sống tiếp trên menu bar.

import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
  var window: NSWindow?
  var statusItem: NSStatusItem!
  // Thẻ tên nổi: hiện account đang focus để không nhắn lộn
  var badgePanel: NSPanel?
  var badgeLabel: NSTextField?
  var pidProfile: [Int32: String] = [:]   // pid Signal → target profile
  var runningCount = 0
  let palette = ["#3A76F0", "#34C759", "#FF9F0A", "#FF453A",
                 "#BF5AF2", "#5AC8FA", "#E6B800", "#FF2D55"]

  var resources: String { Bundle.main.resourcePath ?? "" }
  var enginePath: String { resources + "/signal-manager.sh" }
  var metaPath: String {
    NSHomeDirectory() + "/Library/Application Support/Signal Manager/meta.json"
  }

  func applicationDidFinishLaunching(_ note: Notification) {
    // icon vịt thường trực trên thanh menu, kèm số account đang chạy (🦆2)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "🦆"
    let menu = NSMenu()
    menu.delegate = self
    statusItem.menu = menu

    updateBadge()
    Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
      self.updateBadge()
    }

    // theo dõi cửa sổ đang focus mỗi giây (rẻ: chỉ hỏi NSWorkspace)
    makeBadgePanel()
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      self.refreshFocusBadge()
    }

    showDashboard()
  }

  // ===== Thẻ tên nổi (chống nhắn lộn account) =====

  private func makeBadgePanel() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 30),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let label = NSTextField(labelWithString: "")
    label.font = .boldSystemFont(ofSize: 13)
    label.textColor = .white
    label.alignment = .center
    label.wantsLayer = true
    label.layer?.cornerRadius = 9
    label.layer?.masksToBounds = true
    panel.contentView = label
    badgePanel = panel
    badgeLabel = label
  }

  private func nsColor(hex: String) -> NSColor {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    guard let v = UInt32(h, radix: 16) else { return .systemBlue }
    return NSColor(
      red: CGFloat((v >> 16) & 0xFF) / 255,
      green: CGFloat((v >> 8) & 0xFF) / 255,
      blue: CGFloat(v & 0xFF) / 255, alpha: 0.95)
  }

  // pid Signal → target profile ("default" / tên) — tra ps 1 lần rồi cache
  private func profileFor(pid: Int32) -> String {
    if let cached = pidProfile[pid] { return cached }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-p", "\(pid)", "-o", "command="]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "default" }
    p.waitUntilExit()
    let cmd = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8) ?? ""
    var target = "default"
    if let r = cmd.range(of: "--user-data-dir=") {
      let dir = cmd[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
      if let last = dir.components(separatedBy: "/").last, last.hasPrefix("Signal-") {
        target = String(last.dropFirst("Signal-".count))
      }
    }
    pidProfile[pid] = target
    return target
  }

  private func metaEntry(_ name: String) -> [String: Any] {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
          let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    else { return [:] }
    let key = name == "default" ? "__default__" : name
    return (m[key] as? [String: Any]) ?? [:]
  }

  private func refreshFocusBadge() {
    guard let front = NSWorkspace.shared.frontmostApplication,
          front.bundleIdentifier == "org.whispersystems.signal-desktop"
    else {
      badgePanel?.orderOut(nil)
      statusItem.button?.title = runningCount > 0 ? "🦆\(runningCount)" : "🦆"
      return
    }
    let target = profileFor(pid: front.processIdentifier)
    let meta = metaEntry(target)
    let disp = (meta["nickname"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      ?? (target == "default" ? "Signal chính" : target)
    let idx = ((target.hashValue % palette.count) + palette.count) % palette.count
    let colorHex = (meta["color"] as? String).flatMap { $0.isEmpty ? nil : $0 }
      ?? palette[idx]

    statusItem.button?.title = "🦆‣\(disp)"
    guard let panel = badgePanel, let label = badgeLabel else { return }
    label.stringValue = "  🔒 \(disp)  "
    label.layer?.backgroundColor = nsColor(hex: colorHex).cgColor
    label.sizeToFit()
    let size = NSSize(width: label.frame.width + 16, height: 30)
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      panel.setFrame(NSRect(x: f.maxX - size.width - 18,
                            y: f.maxY - size.height - 6,
                            width: size.width, height: size.height), display: true)
    }
    label.frame = NSRect(origin: .zero, size: size)
    panel.orderFrontRegardless()
  }

  // cập nhật số account đang chạy trên icon menu bar (chạy nền, không chặn UI)
  func updateBadge() {
    DispatchQueue.global(qos: .utility).async {
      let out = self.engineRead(["state", "--fast"])
      var running = 0
      if let d = out.data(using: .utf8),
         let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
        running = arr.filter { ($0["running"] as? Bool) ?? false }.count
      }
      DispatchQueue.main.async {
        self.runningCount = running
        // khi đang focus Signal, tiêu đề menu bar do refreshFocusBadge quản
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            != "org.whispersystems.signal-desktop" {
          self.statusItem.button?.title = running > 0 ? "🦆\(running)" : "🦆"
        }
      }
    }
  }

  // ===== Cửa sổ dashboard =====

  func showDashboard() {
    NSApp.setActivationPolicy(.regular)
    if let w = window {
      w.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    guard let url = dashboardURL() else {
      let alert = NSAlert()
      alert.messageText = "Không khởi động được Signal Manager"
      alert.informativeText = "Server dashboard không phản hồi. Thử mở lại app, hoặc xem log tại ~/Library/Application Support/Signal Manager/server.log"
      alert.runModal()
      return
    }
    let rect = NSRect(x: 0, y: 0, width: 1120, height: 780)
    let w = NSWindow(
      contentRect: rect,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    w.title = "Signal Manager"
    w.minSize = NSSize(width: 720, height: 480)
    w.isReleasedWhenClosed = false
    w.delegate = self
    let web = WKWebView(frame: rect)
    web.autoresizingMask = [.width, .height]
    w.contentView = web
    web.load(URLRequest(url: url))
    w.center()
    w.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = w
  }

  // đóng cửa sổ → ẩn khỏi Dock, sống tiếp trên menu bar
  func windowWillClose(_ notification: Notification) {
    window = nil
    NSApp.setActivationPolicy(.accessory)
  }

  // bấm icon trong Dock/Launchpad khi app đang chạy → hiện lại dashboard
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag { showDashboard() }
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

  // Gọi server helper ở chế độ --url: đảm bảo server chạy rồi in URL kèm token.
  private func dashboardURL() -> URL? {
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

  // ===== Engine helpers =====

  // chạy engine và CHỜ lấy kết quả (chỉ dùng cho lệnh nhanh như state --fast)
  private func engineRead(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [enginePath] + args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    p.waitUntilExit()
    let d = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: d, encoding: .utf8) ?? ""
  }

  // chạy engine KHÔNG chờ (mở/tắt account) — menu phản hồi tức thì
  private func engineFire(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [enginePath] + args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
  }

  // ===== Menu bar =====

  private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  // dựng lại menu mỗi lần mở — trạng thái account luôn tươi
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    var metaRaw: [String: Any] = [:]
    if let d = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
       let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
      metaRaw = m
    }

    var profiles: [[String: Any]] = []
    if let data = engineRead(["state", "--fast"]).data(using: .utf8),
       let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
      profiles = arr
    }

    if profiles.isEmpty {
      let item = NSMenuItem(title: "Không đọc được danh sách account", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }

    for p in profiles {
      let name = p["name"] as? String ?? ""
      let running = p["running"] as? Bool ?? false
      let isDefault = p["is_default"] as? Bool ?? false
      let nick = (metaRaw[name] as? [String: Any])?["nickname"] as? String ?? ""
      let disp = nick.isEmpty ? (isDefault ? "Signal chính" : name) : nick
      let item = NSMenuItem(
        title: (running ? "🟢 " : "⚪️ ") + disp,
        action: #selector(openAccount(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = isDefault ? "default" : name
      item.toolTip = running ? "Đang chạy — bấm để focus cửa sổ" : "Bấm để mở"
      menu.addItem(item)
    }

    menu.addItem(.separator())
    menu.addItem(makeItem("▶ Mở tất cả", #selector(openAll)))
    menu.addItem(makeItem("⏹ Tắt tất cả", #selector(quitAll)))
    menu.addItem(.separator())
    menu.addItem(makeItem("🦆 Mở bảng điều khiển", #selector(openDash)))
    menu.addItem(.separator())
    menu.addItem(makeItem("Thoát Signal Manager", #selector(quitApp)))

    updateBadge()   // tiện thể làm tươi số đếm mỗi lần mở menu
  }

  @objc private func openAccount(_ sender: NSMenuItem) {
    if let target = sender.representedObject as? String {
      engineFire(["open", target])
    }
  }
  @objc private func openAll() { engineFire(["open", "all"]) }
  @objc private func quitAll() { engineFire(["quit", "all"]) }
  @objc private func openDash() { showDashboard() }
  @objc private func quitApp() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu chính tối thiểu để có ⌘Q / ⌘W chuẩn macOS
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(
  title: "Thoát Signal Manager",
  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
appItem.submenu = appMenu
let windowItem = NSMenuItem()
mainMenu.addItem(windowItem)
let windowMenu = NSMenu(title: "Cửa sổ")
windowMenu.addItem(NSMenuItem(
  title: "Đóng cửa sổ",
  action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
windowItem.submenu = windowMenu
app.mainMenu = mainMenu

app.run()
