import XCTest
@testable import JumaoCat

@MainActor
final class StatusFileActivityBindingTests: XCTestCase {
  func testHistoricalCheckingStatusIsStaticWhenAppStarts() throws {
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(initialState: "checking")
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    XCTAssertEqual(appState.status.catState, "checking")
    XCTAssertEqual(appState.menuBarActivity, .idle)
  }

  func testLiveDoctorOrPackStatusTransitionStartsAndFinishesWorking() throws {
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(initialState: "ready")
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    try writeStatus(state: "checking", in: workspaceURL)
    appState.refreshStatusAfterFileChange()
    XCTAssertEqual(appState.menuBarActivity, .working)

    try writeStatus(state: "packed", in: workspaceURL)
    appState.refreshStatusAfterFileChange()
    XCTAssertEqual(appState.menuBarActivity, .success)
  }

  func testAgentRuleMatchesDoNotStartWorking() throws {
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(initialState: "ready")
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    try writeStatus(state: "ready", includesMatchedAgents: true, in: workspaceURL)
    appState.refreshStatusAfterFileChange()

    XCTAssertEqual(appState.status.snapshot?.status.agentBoard.triggeredAgentCount, 2)
    XCTAssertEqual(appState.menuBarActivity, .idle)
  }

  private func makeAppState(initialState: String) throws -> (AppState, UserDefaults, String, URL) {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-status-activity-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try writeStatus(state: initialState, in: workspaceURL)

    let suiteName = "JumaoCatStatusActivityTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore)
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName, workspaceURL)
  }

  private func writeStatus(
    state: String,
    includesMatchedAgents: Bool = false,
    in workspaceURL: URL
  ) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var contents: [String: Any] = [
      "cat": ["state": state, "label": "状态", "message": "状态更新。"]
    ]
    if includesMatchedAgents {
      contents["agentBoard"] = [
        "triggeredAgentCount": 2,
        "activeGroupCount": 1,
        "blockedGroupCount": 0
      ]
    }
    try JSONSerialization.data(withJSONObject: contents).write(to: statusURL)
  }

  private func cleanUp(_ appState: AppState, _ defaults: UserDefaults, _ suiteName: String, _ workspaceURL: URL) {
    appState.shutdown()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: workspaceURL)
  }
}
