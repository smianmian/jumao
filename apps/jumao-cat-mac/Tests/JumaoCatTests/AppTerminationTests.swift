import XCTest
@testable import JumaoCat

@MainActor
final class AppTerminationTests: XCTestCase {
  func testQuitCancelsPackBeforeTerminating() {
    let events = EventRecorder()
    let appState = AppState(
      taskPackRunner: RecordingTaskPackRunner(events: events),
      appTerminator: RecordingAppTerminator(events: events)
    )

    appState.quit()

    XCTAssertEqual(events.values, ["cancel pack", "terminate app"])
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
