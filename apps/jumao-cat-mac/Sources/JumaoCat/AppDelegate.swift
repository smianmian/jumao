import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appState = AppState()
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    item.button?.image = JumaoMenuBarIcon.makeImage(for: appState.status.catState)
    item.button?.target = self
    item.button?.action = #selector(togglePopover(_:))
    item.button?.toolTip = "Jumao Cat"

    popover.behavior = .transient
    popover.contentSize = NSSize(width: 360, height: 500)
    popover.contentViewController = NSHostingController(rootView: StatusPopover(appState: appState))

    appState.$status
      .receive(on: RunLoop.main)
      .sink { [weak self] status in
        self?.statusItem?.button?.image = JumaoMenuBarIcon.makeImage(for: status.catState)
      }
      .store(in: &cancellables)

    appState.loadSavedWorkspace()
  }

  @objc private func togglePopover(_ sender: NSStatusBarButton) {
    appState.refreshStatus()

    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    appState.shutdown()
  }
}
