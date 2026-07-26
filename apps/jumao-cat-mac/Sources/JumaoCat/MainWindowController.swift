import AppKit
import SwiftUI

@MainActor
protocol MainWindowControlling: AnyObject {
  func show()
}

@MainActor
final class MainWindowController: NSObject, MainWindowControlling {
  private let window: NSWindow

  init(appState: AppState) {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()

    window.title = "Jumao Cat"
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.contentViewController = NSHostingController(rootView: StatusPopover(appState: appState))
  }

  func show() {
    window.center()
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
