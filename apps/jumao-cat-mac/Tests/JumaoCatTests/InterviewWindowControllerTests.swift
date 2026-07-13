import XCTest
@testable import JumaoCat

@MainActor
final class InterviewWindowControllerTests: XCTestCase {
  func testInterviewWindowIsNonModal() {
    let controller = InterviewWindowController(appState: AppState())

    XCTAssertTrue(controller.isNonModal)
  }

  func testOpenInterviewWindowDoesNotPreventMenuBarQuitAction() {
    let events = WindowEventRecorder()
    let appState = AppState(
      taskPackRunner: WindowRecordingTaskPackRunner(events: events),
      appTerminator: WindowRecordingAppTerminator(events: events)
    )
    let interviewWindow = InterviewWindowController(appState: appState)
    let contextMenu = WindowRecordingContextMenu()
    let menuBarController = MenuBarInteractionController(
      appState: appState,
      popover: WindowRecordingPopover(),
      contextMenu: contextMenu
    )

    interviewWindow.show()
    menuBarController.handleRightClick()
    menuBarController.quitFromMenu()
    interviewWindow.hide()

    XCTAssertTrue(interviewWindow.isNonModal)
    XCTAssertEqual(contextMenu.showCount, 1)
    XCTAssertEqual(events.values, ["cancel pack", "terminate app"])
  }
}

@MainActor
private final class WindowRecordingPopover: MenuBarPopoverControlling {
  var isShown = false
  func show() { isShown = true }
  func close() { isShown = false }
}

@MainActor
private final class WindowRecordingContextMenu: MenuBarContextMenuPresenting {
  private(set) var showCount = 0
  func showQuitMenu() { showCount += 1 }
}

@MainActor
private final class WindowRecordingTaskPackRunner: CodexTaskPackRunning {
  private let events: WindowEventRecorder
  init(events: WindowEventRecorder) { self.events = events }
  func run(workspaceURL: URL, completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void) {}
  func cancel() { events.values.append("cancel pack") }
}

@MainActor
private final class WindowRecordingAppTerminator: AppTerminating {
  private let events: WindowEventRecorder
  init(events: WindowEventRecorder) { self.events = events }
  func terminate() { events.values.append("terminate app") }
}

@MainActor
private final class WindowEventRecorder {
  var values: [String] = []
}
