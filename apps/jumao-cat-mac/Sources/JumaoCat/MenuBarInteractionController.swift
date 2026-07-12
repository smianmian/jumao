import Foundation

@MainActor
protocol MenuBarPopoverControlling: AnyObject {
  var isShown: Bool { get }
  func show()
  func close()
}

@MainActor
protocol MenuBarContextMenuPresenting: AnyObject {
  func showQuitMenu()
}

@MainActor
final class MenuBarInteractionController {
  private let appState: AppState
  private let popover: any MenuBarPopoverControlling
  private let contextMenu: any MenuBarContextMenuPresenting

  init(
    appState: AppState,
    popover: any MenuBarPopoverControlling,
    contextMenu: any MenuBarContextMenuPresenting
  ) {
    self.appState = appState
    self.popover = popover
    self.contextMenu = contextMenu
  }

  func handleLeftClick() {
    appState.refreshStatus()
    if popover.isShown {
      popover.close()
    } else {
      popover.show()
    }
  }

  func handleRightClick() {
    contextMenu.showQuitMenu()
  }

  func quitFromMenu() {
    appState.quit()
  }
}
