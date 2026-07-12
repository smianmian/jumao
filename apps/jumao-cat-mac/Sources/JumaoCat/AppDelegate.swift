import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appState = AppState()
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var menuBarInteraction: MenuBarInteractionController?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    item.button?.image = JumaoMenuBarIcon.makeImage(for: appState.status.catState)
    item.button?.imageScaling = .scaleProportionallyDown
    item.button?.target = self
    item.button?.action = #selector(handleStatusItemClick(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    item.button?.toolTip = "Jumao Cat"

    popover.behavior = .transient
    let hostingController = NSHostingController(rootView: StatusPopover(appState: appState))
    hostingController.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hostingController

    if let button = item.button {
      let popoverController = StatusPopoverController(popover: popover, button: button)
      let contextMenu = StatusBarQuitMenuPresenter(button: button, target: self, action: #selector(quitFromMenu))
      menuBarInteraction = MenuBarInteractionController(
        appState: appState,
        popover: popoverController,
        contextMenu: contextMenu
      )
    }
    configureQuitShortcut()

    appState.$status
      .receive(on: RunLoop.main)
      .sink { [weak self] status in
        self?.statusItem?.button?.image = JumaoMenuBarIcon.makeImage(for: status.catState)
      }
      .store(in: &cancellables)

    appState.loadSavedWorkspace()
  }

  @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      menuBarInteraction?.handleRightClick()
    } else {
      menuBarInteraction?.handleLeftClick()
    }
  }

  @objc private func quitFromMenu() {
    menuBarInteraction?.quitFromMenu()
  }

  private func configureQuitShortcut() {
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    let quitItem = NSMenuItem(title: "退出 Jumao Cat", action: #selector(quitFromMenu), keyEquivalent: "q")
    quitItem.keyEquivalentModifierMask = .command
    quitItem.target = self
    appMenu.addItem(quitItem)
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)
    NSApp.mainMenu = mainMenu
  }

  func applicationWillTerminate(_ notification: Notification) {
    appState.shutdown()
  }
}

@MainActor
private final class StatusPopoverController: MenuBarPopoverControlling {
  private let popover: NSPopover
  private weak var button: NSStatusBarButton?

  init(popover: NSPopover, button: NSStatusBarButton) {
    self.popover = popover
    self.button = button
  }

  var isShown: Bool {
    popover.isShown
  }

  func show() {
    guard let button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  func close() {
    popover.performClose(nil)
  }
}

@MainActor
private final class StatusBarQuitMenuPresenter: MenuBarContextMenuPresenting {
  private weak var button: NSStatusBarButton?
  private weak var target: AnyObject?
  private let action: Selector

  init(button: NSStatusBarButton, target: AnyObject, action: Selector) {
    self.button = button
    self.target = target
    self.action = action
  }

  func showQuitMenu() {
    guard let button, let event = NSApp.currentEvent else { return }

    let menu = NSMenu()
    let quitItem = NSMenuItem(title: "退出 Jumao Cat", action: action, keyEquivalent: "")
    quitItem.target = target
    menu.addItem(quitItem)
    NSMenu.popUpContextMenu(menu, with: event, for: button)
  }
}
