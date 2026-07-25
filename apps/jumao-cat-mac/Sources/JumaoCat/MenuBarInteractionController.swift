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
  private let mainWindow: any MainWindowControlling
  private let contextMenu: any MenuBarContextMenuPresenting

  init(
    appState: AppState,
    popover: any MenuBarPopoverControlling,
    mainWindow: any MainWindowControlling,
    contextMenu: any MenuBarContextMenuPresenting
  ) {
    self.appState = appState
    self.popover = popover
    self.mainWindow = mainWindow
    self.contextMenu = contextMenu
  }

  func handleLeftClick() {
    appState.refreshStatus()
    popover.close()
    mainWindow.show()
  }

  func handleRightClick() {
    contextMenu.showQuitMenu()
  }

  func quitFromMenu() {
    appState.quit()
  }
}
