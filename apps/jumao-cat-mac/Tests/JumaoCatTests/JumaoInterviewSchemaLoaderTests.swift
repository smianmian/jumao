import XCTest
@testable import JumaoCat

final class JumaoInterviewSchemaLoaderTests: XCTestCase {
  func testUsesFixedSchemaArguments() {
    XCTAssertEqual(
      JumaoInterviewSchemaLoader.arguments(),
      ["jumao", "interview", "--schema"]
    )
  }

  func testDecodesTwentyTwoQuestionsFromSchemaJSON() throws {
    let schema = try JumaoInterviewSchemaLoader.decodeSchema(from: makeSchemaData(questionCount: 22))

    XCTAssertEqual(schema.schemaVersion, 1)
    XCTAssertEqual(schema.questions.count, 22)
    XCTAssertEqual(schema.questions.first?.title, "主要用户是谁？")
  }

  func testRejectsInvalidSchemaJSON() {
    XCTAssertThrowsError(try JumaoInterviewSchemaLoader.decodeSchema(from: Data("不是 JSON".utf8)))
  }

  @MainActor
  func testSchemaCLIExecutionFailureShowsChineseError() async throws {
    let workspaceURL = try makeEstablishedWorkspace()
    let loader = RecordingInterviewSchemaLoader()
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL, loader: loader)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: workspaceURL)
    }

    XCTAssertTrue(appState.canAnswerProjectQuestions)
    appState.answerProjectQuestions()
    XCTAssertTrue(appState.isLoadingInterviewSchema)

    loader.complete(.failed(exitCode: 1, message: "找不到 jumao"))
    await Task.yield()

    XCTAssertFalse(appState.isLoadingInterviewSchema)
    XCTAssertFalse(appState.isInterviewPresented)
    XCTAssertEqual(appState.interviewSchemaError, "读取项目问题失败（退出码 1）：找不到 jumao")
  }

  private func makeSchemaData(questionCount: Int) throws -> Data {
    let questions = (1...questionCount).map { order in
      JumaoInterviewQuestion(
        id: "question\(order)",
        answerPath: "question\(order)",
        title: order == 1 ? "主要用户是谁？" : "问题 \(order)",
        description: "问题说明 \(order)",
        inputType: "text",
        required: true,
        order: order
      )
    }
    return try JSONEncoder().encode(JumaoInterviewSchema(schemaVersion: 1, questions: questions))
  }

  @MainActor
  private func makeAppState(
    workspaceURL: URL,
    loader: any JumaoInterviewSchemaLoading
  ) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatInterviewSchemaTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore, interviewSchemaLoader: loader)
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName)
  }

  @MainActor
  private func makeEstablishedWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-interview-schema-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

    for file in JumaoProjectInitializer.targetFiles {
      let fileURL = workspaceURL.appendingPathComponent(file)
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: fileURL)
    }

    return workspaceURL
  }
}

@MainActor
private final class RecordingInterviewSchemaLoader: JumaoInterviewSchemaLoading {
  private var completion: (@MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void)?

  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void) {
    self.completion = completion
  }

  func complete(_ result: JumaoInterviewSchemaLoadResult) {
    completion?(result)
  }
}
