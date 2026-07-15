import AppKit
import XCTest
@testable import JumaoCat

@MainActor
final class MenuBarInteractionControllerTests: XCTestCase {
  func testLeftClickOpensPopover() {
    let popover = RecordingPopover()
    let controller = makeController(popover: popover)

    controller.handleLeftClick()

    XCTAssertTrue(popover.isShown)
    XCTAssertEqual(popover.showCount, 1)
  }

  func testSecondLeftClickClosesPopover() {
    let popover = RecordingPopover()
    let controller = makeController(popover: popover)

    controller.handleLeftClick()
    controller.handleLeftClick()

    XCTAssertFalse(popover.isShown)
    XCTAssertEqual(popover.closeCount, 1)
  }

  func testRightClickShowsQuitMenuWithoutOpeningPopover() {
    let popover = RecordingPopover()
    let menu = RecordingContextMenu()
    let controller = MenuBarInteractionController(appState: AppState(), popover: popover, contextMenu: menu)

    controller.handleRightClick()

    XCTAssertEqual(menu.showCount, 1)
    XCTAssertFalse(popover.isShown)
    XCTAssertEqual(popover.showCount, 0)
  }

  func testQuitMenuUsesExistingSafeQuit() {
    let events = EventRecorder()
    let appState = AppState(
      taskPackRunner: RecordingTaskPackRunner(events: events),
      appTerminator: RecordingAppTerminator(events: events)
    )
    let controller = MenuBarInteractionController(
      appState: appState,
      popover: RecordingPopover(),
      contextMenu: RecordingContextMenu()
    )

    controller.quitFromMenu()

    XCTAssertEqual(events.values, ["cancel pack", "terminate app"])
  }

  func testTextEditingCommandsInstallCommandVInTheRunningMainMenu() {
    let menuItems = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
    XCTAssertTrue(
      menuItems.contains { $0.keyEquivalent == "v" && $0.keyEquivalentModifierMask.contains(.command) },
      "主菜单必须实际安装 Command + V；当前菜单：\(menuItems.map { "\($0.title)[\($0.keyEquivalent)]" })"
    )
  }

  private func makeController(popover: RecordingPopover) -> MenuBarInteractionController {
    MenuBarInteractionController(
      appState: AppState(),
      popover: popover,
      contextMenu: RecordingContextMenu()
    )
  }
}

@MainActor
private final class RecordingPopover: MenuBarPopoverControlling {
  private(set) var isShown = false
  private(set) var showCount = 0
  private(set) var closeCount = 0

  func show() {
    showCount += 1
    isShown = true
  }

  func close() {
    closeCount += 1
    isShown = false
  }
}

@MainActor
private final class RecordingContextMenu: MenuBarContextMenuPresenting {
  private(set) var showCount = 0

  func showQuitMenu() {
    showCount += 1
  }
}

@MainActor
private final class RecordingTaskPackRunner: CodexTaskPackRunning {
  private let events: EventRecorder

  init(events: EventRecorder) {
    self.events = events
  }

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void
  ) {}

  func cancel() {
    events.values.append("cancel pack")
  }
}

@MainActor
private final class RecordingAppTerminator: AppTerminating {
  private let events: EventRecorder

  init(events: EventRecorder) {
    self.events = events
  }

  func terminate() {
    events.values.append("terminate app")
  }
}

@MainActor
private final class EventRecorder {
  var values: [String] = []
}
