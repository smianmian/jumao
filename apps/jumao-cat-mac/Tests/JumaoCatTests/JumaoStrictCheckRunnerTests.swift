import XCTest
@testable import JumaoCat

@MainActor
final class JumaoStrictCheckRunnerTests: XCTestCase {
  func testUsesStrictCheckArguments() {
    XCTAssertEqual(
      JumaoStrictCheckRunner.arguments(for: URL(fileURLWithPath: "/tmp/current-project")),
      ["check", "/tmp/current-project", "--strict"]
    )
  }

  func testSuccessfulCheckShowsNextStep() async throws {
    let runner = DeferredStrictCheckRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(runner: runner)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await writeInterviewAnswers(in: appState)
    appState.startProjectCheck()
    XCTAssertTrue(appState.isCheckingProject)

    runner.complete(.succeeded)
    await waitForCheckToFinish(in: appState)

    XCTAssertEqual(appState.projectCheckMessage, "检查通过\n下一步：生成 Codex 任务包")
    XCTAssertNil(appState.projectCheckError)
  }

  func testFailedCheckShowsShortChineseRetryMessage() async throws {
    let runner = DeferredStrictCheckRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(runner: runner)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await writeInterviewAnswers(in: appState)
    appState.startProjectCheck()
    runner.complete(.failed(exitCode: 1, message: "strict check output should stay out of the UI"))
    await waitForCheckToFinish(in: appState)

    XCTAssertEqual(appState.projectCheckMessage, "发现需要补充的内容")
    XCTAssertEqual(appState.projectCheckError, "请补充项目文档中的必要内容后重新检查。")
    XCTAssertTrue(appState.canStartProjectCheck)
  }

  func testDoesNotStartMultipleChecksAtOnce() async throws {
    let runner = DeferredStrictCheckRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(runner: runner)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    await writeInterviewAnswers(in: appState)
    appState.startProjectCheck()
    appState.startProjectCheck()

    XCTAssertEqual(
      runner.workspaceURLs.map { $0.resolvingSymlinksInPath() },
      [workspaceURL.resolvingSymlinksInPath()]
    )
    XCTAssertTrue(appState.isCheckingProject)
  }

  func testCheckCompletionRefreshesStatusFile() async throws {
    let runner = DeferredStrictCheckRunner()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(runner: runner)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    try writeStatus(state: "checking", in: workspaceURL)
    appState.refreshStatus()
    await writeInterviewAnswers(in: appState)
    appState.startProjectCheck()
    try writeStatus(state: "ready", in: workspaceURL)
    runner.complete(.succeeded)
    await waitForCheckToFinish(in: appState)

    XCTAssertEqual(appState.status.catState, "ready")
  }

  private func writeInterviewAnswers(in appState: AppState) async {
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
    XCTAssertEqual(appState.interviewWriteMessage, "项目问题已写入\n下一步：开始检查")
  }

  private func makeAppState(
    runner: any JumaoStrictChecking
  ) throws -> (AppState, UserDefaults, String, URL) {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-strict-check-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

    let suiteName = "JumaoCatStrictCheckTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      interviewAnswerWriter: ImmediateInterviewAnswerWriter(),
      strictCheckRunner: runner
    )
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName, workspaceURL)
  }

  private func writeStatus(state: String, in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: [
      "cat": ["state": state, "label": "检查状态", "message": "状态已更新。"]
    ])
    try data.write(to: statusURL)
  }

  private func waitForCheckToFinish(in appState: AppState) async {
    for _ in 0..<10 {
      if !appState.isCheckingProject { return }
      await Task.yield()
    }
    XCTFail("项目检查没有结束")
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
private final class DeferredStrictCheckRunner: JumaoStrictChecking {
  private(set) var workspaceURLs: [URL] = []
  private var completion: (@MainActor @Sendable (JumaoStrictCheckResult) -> Void)?

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoStrictCheckResult) -> Void
  ) {
    workspaceURLs.append(workspaceURL)
    self.completion = completion
  }

  func complete(_ result: JumaoStrictCheckResult) {
    completion?(result)
  }

  func cancel() {}
}
