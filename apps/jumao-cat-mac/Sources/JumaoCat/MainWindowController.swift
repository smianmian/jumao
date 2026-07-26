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
    window.minSize = NSSize(width: 380, height: 430)
    window.setFrameAutosaveName("JumaoCatMainWindow")
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.contentViewController = NSHostingController(rootView: StatusPopover(appState: appState))
  }

  private var hasShownOnce = false

  func show() {
    if !hasShownOnce, !window.setFrameUsingName("JumaoCatMainWindow") {
      window.center()
    }
    hasShownOnce = true
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
