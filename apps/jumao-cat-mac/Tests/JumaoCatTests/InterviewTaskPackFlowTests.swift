import XCTest
@testable import JumaoCat

@MainActor
final class InterviewTaskPackFlowTests: XCTestCase {
  func testPassingCheckEnablesTaskPackGeneration() async throws {
    let strictRunner = DeferredInterviewStrictCheckRunner()
    let packRunner = DeferredInterviewTaskPackRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(
      strictRunner: strictRunner,
      packRunner: packRunner
    )
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await passProjectCheck(in: appState, strictRunner: strictRunner)

    XCTAssertTrue(appState.hasPassedProjectCheck)
    XCTAssertTrue(appState.canGenerateInterviewTaskPack)
    XCTAssertEqual(appState.projectCheckMessage, "检查通过\n下一步：生成 Codex 任务包")
  }

  func testUsesExistingTaskPackRunnerForCurrentWorkspace() async throws {
    let strictRunner = DeferredInterviewStrictCheckRunner()
    let packRunner = DeferredInterviewTaskPackRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(
      strictRunner: strictRunner,
      packRunner: packRunner
    )
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await passProjectCheck(in: appState, strictRunner: strictRunner)
    appState.generateInterviewTaskPack()

    XCTAssertEqual(appState.menuBarActivity, .working)

    XCTAssertEqual(
      packRunner.workspaceURLs.map { $0.resolvingSymlinksInPath() },
      [workspaceURL.resolvingSymlinksInPath()]
    )
  }

  func testDoesNotRunTaskPackTwice() async throws {
    let strictRunner = DeferredInterviewStrictCheckRunner()
    let packRunner = DeferredInterviewTaskPackRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(
      strictRunner: strictRunner,
      packRunner: packRunner
    )
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await passProjectCheck(in: appState, strictRunner: strictRunner)
    appState.generateInterviewTaskPack()
    appState.generateInterviewTaskPack()

    XCTAssertEqual(packRunner.workspaceURLs.count, 1)
    XCTAssertTrue(appState.isGeneratingInterviewTaskPack)
  }

  func testSuccessfulGenerationRefreshesStatusAndReturnsToMainPanel() async throws {
    let strictRunner = DeferredInterviewStrictCheckRunner()
    let packRunner = DeferredInterviewTaskPackRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(
      strictRunner: strictRunner,
      packRunner: packRunner
    )
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await passProjectCheck(in: appState, strictRunner: strictRunner)
    appState.generateInterviewTaskPack()
    try writeStatus(state: "packed", latestTaskPack: "tasks/codex-task-pack.md", in: workspaceURL)
    packRunner.complete(.succeeded)
    await waitForTaskPackToFinish(in: appState)

    XCTAssertEqual(appState.status.catState, "packed")
    XCTAssertFalse(appState.isInterviewPresented)
    XCTAssertEqual(appState.interviewTaskPackMessage, "任务包已生成")
    XCTAssertTrue(appState.canCopyLatestTaskPack)
    XCTAssertEqual(appState.menuBarActivity, .success)
  }

  func testFailedGenerationShowsRetryAndCanRunAgain() async throws {
    let strictRunner = DeferredInterviewStrictCheckRunner()
    let packRunner = DeferredInterviewTaskPackRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(
      strictRunner: strictRunner,
      packRunner: packRunner
    )
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await passProjectCheck(in: appState, strictRunner: strictRunner)
    appState.generateInterviewTaskPack()
    packRunner.complete(.failed(exitCode: 1, message: "long terminal output"))
    await waitForTaskPackToFinish(in: appState)

    XCTAssertEqual(appState.interviewTaskPackError, "任务包生成失败，请确认项目内容后重试。")
    XCTAssertTrue(appState.canGenerateInterviewTaskPack)
    XCTAssertEqual(appState.menuBarActivity, .failure)

    appState.generateInterviewTaskPack()
    XCTAssertEqual(packRunner.workspaceURLs.count, 2)
  }

  private func passProjectCheck(
    in appState: AppState,
    strictRunner: DeferredInterviewStrictCheckRunner
  ) async {
    let schema = JumaoInterviewSchema(schemaVersion: 1, questions: [
      JumaoInterviewQuestion(
        id: "primaryUser",
        answerPath: "primaryUser",
        title: "主要用户是谁？",
        description: "说明",
        inputType: "text",
        required: true,
        order: 1
      )
    ])
    appState.beginInterview(with: schema)
    appState.updateInterviewAnswer("创作者", for: "primaryUser")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    appState.requestInterviewWrite()
    appState.confirmInterviewWrite()

    for _ in 0..<10 where appState.interviewWriteMessage == nil {
      await Task.yield()
    }
    appState.startProjectCheck()
    strictRunner.complete(.succeeded)
    for _ in 0..<10 where appState.isCheckingProject {
      await Task.yield()
    }
  }

  private func makeAppState(
    strictRunner: any JumaoStrictChecking,
    packRunner: any CodexTaskPackRunning
  ) throws -> (AppState, UserDefaults, String, URL) {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-interview-task-pack-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    try writeStatus(state: "ready", latestTaskPack: "", in: workspaceURL)

    let suiteName = "JumaoCatInterviewTaskPackTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      taskPackRunner: packRunner,
      interviewAnswerWriter: ImmediateInterviewAnswerWriter(),
      strictCheckRunner: strictRunner
    )
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName, workspaceURL)
  }

  private func writeStatus(state: String, latestTaskPack: String, in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: [
      "cat": ["state": state, "label": "任务包已生成", "message": "可以继续使用任务包。"],
      "artifacts": ["latestTaskPack": latestTaskPack]
    ])
    try data.write(to: statusURL)
  }

  private func waitForTaskPackToFinish(in appState: AppState) async {
    for _ in 0..<10 {
      if !appState.isGeneratingInterviewTaskPack { return }
      await Task.yield()
    }
    XCTFail("任务包生成没有结束")
  }

  private func cleanUp(_ appState: AppState, _ defaults: UserDefaults, _ suiteName: String, _ workspaceURL: URL) {
    appState.shutdown()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: workspaceURL)
  }
}

@MainActor
private final class ImmediateInterviewAnswerWriter: JumaoInterviewAnswerWriting {
  func documentsWithContent(in workspaceURL: URL) -> [String] { [] }

  func run(
    workspaceURL: URL,
    questions: [JumaoInterviewQuestion],
    answers: [String: String],
    force: Bool,
    completion: @escaping @MainActor @Sendable (JumaoInterviewAnswerWriteResult) -> Void
  ) {
    completion(.succeeded)
  }
}

@MainActor
private final class DeferredInterviewStrictCheckRunner: JumaoStrictChecking {
  private var completion: (@MainActor @Sendable (JumaoStrictCheckResult) -> Void)?

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoStrictCheckResult) -> Void
  ) {
    self.completion = completion
  }

  func complete(_ result: JumaoStrictCheckResult) {
    completion?(result)
  }

  func cancel() {}
}

@MainActor
private final class DeferredInterviewTaskPackRunner: CodexTaskPackRunning {
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

  func cancel() {}
}
