import XCTest
@testable import JumaoCat

final class CodexTaskPackRunnerTests: XCTestCase {
  func testUsesFixedJumaoCodexPackArguments() {
    let workspaceURL = URL(fileURLWithPath: "/tmp/My Jumao App")

    XCTAssertEqual(
      CodexTaskPackRunner.arguments(for: workspaceURL),
      ["jumao", "pack", "/tmp/My Jumao App", "--target", "codex"]
    )
  }

  @MainActor
  func testNoSelectedWorkspaceDisablesTaskPackRegeneration() {
    XCTAssertFalse(AppState().canRegenerateTaskPack)
  }

  @MainActor
  func testWorkspaceWithoutJumaoDirectoryDisablesTaskPackRegeneration() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertFalse(appState.canRegenerateTaskPack)
  }

  @MainActor
  func testRunsOnlyOneTaskPackProcessAtATime() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try writeStatus(state: "checking", in: workspaceURL)
    let runner = DeferredTaskPackRunner()
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL, taskPackRunner: runner)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.regenerateCodexTaskPack()
    appState.regenerateCodexTaskPack()

    XCTAssertTrue(appState.isRegeneratingTaskPack)
    XCTAssertEqual(
      runner.workspaceURLs.map { $0.resolvingSymlinksInPath() },
      [workspaceURL.resolvingSymlinksInPath()]
    )
  }

  @MainActor
  func testSuccessfulRegenerationRefreshesStatus() async throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try writeStatus(state: "checking", in: workspaceURL)
    let runner = DeferredTaskPackRunner()
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL, taskPackRunner: runner)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.regenerateCodexTaskPack()
    try writeStatus(state: "packed", in: workspaceURL)
    runner.complete(.succeeded)
    await waitForGenerationToFinish(in: appState)

    XCTAssertFalse(appState.isRegeneratingTaskPack)
    XCTAssertEqual(appState.status.catState, "packed")
    XCTAssertNil(appState.taskPackGenerationError)
  }

  @MainActor
  func testFailedRegenerationShowsExitCodeAndBriefError() async throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try writeStatus(state: "checking", in: workspaceURL)
    let runner = DeferredTaskPackRunner()
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL, taskPackRunner: runner)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.regenerateCodexTaskPack()
    runner.complete(.failed(exitCode: 2, message: "strict gate failed"))
    await waitForGenerationToFinish(in: appState)

    XCTAssertEqual(appState.taskPackGenerationError, "任务包生成失败（退出码 2）：strict gate failed")
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-task-pack-runner-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    return workspaceURL
  }

  @MainActor
  private func makeAppState(
    workspaceURL: URL,
    taskPackRunner: any CodexTaskPackRunning = DeferredTaskPackRunner()
  ) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatTaskPackRunnerTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore, taskPackRunner: taskPackRunner)
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName)
  }

  private func writeStatus(state: String, in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let contents: [String: Any] = [
      "cat": [
        "state": state,
        "label": "任务包状态",
        "message": "任务包状态已更新。"
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: contents)
    try data.write(to: statusURL)
  }

  @MainActor
  private func waitForGenerationToFinish(in appState: AppState) async {
    for _ in 0..<10 {
      if !appState.isRegeneratingTaskPack {
        return
      }
      await Task.yield()
    }

    XCTFail("任务包生成没有结束")
  }
}

@MainActor
private final class DeferredTaskPackRunner: CodexTaskPackRunning {
  private(set) var workspaceURLs: [URL] = []
  private var completion: (@MainActor @Sendable (CodexTaskPackRunResult) -> Void)?

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (CodexTaskPackRunResult) -> Void
  ) {
    workspaceURLs.append(workspaceURL)
    self.completion = completion
  }

  func complete(_ result: CodexTaskPackRunResult) {
    completion?(result)
  }
}
