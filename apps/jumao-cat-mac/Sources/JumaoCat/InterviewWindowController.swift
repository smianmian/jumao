import AppKit
import SwiftUI

@MainActor
protocol InterviewWindowControlling: AnyObject {
  func show()
  func hide()
}

@MainActor
final class InterviewWindowController: NSObject, InterviewWindowControlling, NSWindowDelegate {
  private let appState: AppState
  private let panel: NSPanel

  init(appState: AppState) {
    self.appState = appState
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    super.init()

    panel.title = "回答项目问题"
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentViewController = NSHostingController(rootView: InterviewForm(appState: appState))
  }

  var isNonModal: Bool {
    NSApp.modalWindow !== panel
  }

  func show() {
    panel.center()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func hide() {
    panel.orderOut(nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    appState.hideInterview()
    return false
  }
}
