import XCTest
@testable import JumaoCat

final class JumaoInterviewSchemaLoaderTests: XCTestCase {
  func testUsesFixedSchemaArguments() {
    XCTAssertEqual(
      JumaoInterviewSchemaLoader.arguments(),
      ["interview", "--schema"]
    )
  }

  func testDecodesTwentyOneQuestionsFromSchemaJSON() throws {
    let schema = try JumaoInterviewSchemaLoader.decodeSchema(from: makeSchemaData(questionCount: 21))

    XCTAssertEqual(schema.schemaVersion, 1)
    XCTAssertEqual(schema.questions.count, 21)
    XCTAssertEqual(schema.questions.first?.title, "主要用户是谁？")
  }

  func testDecodesOptionalGuidanceAndExample() throws {
    let data = Data(#"{"schemaVersion":1,"questions":[{"id":"primaryUser","answerPath":"primaryUser","title":"主要用户是谁？","description":"说明","guidance":"填写指引","example":"填写示例","placeholder":"输入例子","inputType":"text","required":true,"order":1}]}"#.utf8)

    let schema = try JumaoInterviewSchemaLoader.decodeSchema(from: data)

    XCTAssertEqual(schema.questions.first?.guidance, "填写指引")
    XCTAssertEqual(schema.questions.first?.example, "填写示例")
    XCTAssertEqual(schema.questions.first?.placeholder, "输入例子")
  }

  func testOldSchemaWithoutGuidanceAndExampleStillDecodes() throws {
    let data = Data(#"{"schemaVersion":1,"questions":[{"id":"question1","answerPath":"question1","title":"旧问题","description":"说明","inputType":"text","required":true,"order":1}]}"#.utf8)
    let schema = try JumaoInterviewSchemaLoader.decodeSchema(from: data)

    XCTAssertNil(schema.questions.first?.guidance)
    XCTAssertNil(schema.questions.first?.example)
    XCTAssertNil(schema.questions.first?.placeholder)
    XCTAssertEqual(schema.stages, [JumaoInterviewSchema.legacyStage])
  }

  func testRejectsInvalidSchemaJSON() {
    XCTAssertThrowsError(try JumaoInterviewSchemaLoader.decodeSchema(from: Data("不是 JSON".utf8)))
  }

  @MainActor
  func testIncompatibleGlobalCLIShowsShortChineseError() async {
    let loader = JumaoInterviewSchemaLoader(
      resolver: FixedJumaoCLIResolver(.failed(.globalVersionOutdated))
    )
    let expectation = expectation(description: "schema result")

    loader.run { result in
      XCTAssertEqual(
        result,
        .failed(exitCode: nil, message: "当前安装的 Jumao 版本过旧，请更新后重试。")
      )
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 1)
  }

  @MainActor
  func testRepositoryCLIReadsCurrentTwentyOneQuestionSchema() async {
    let loader = JumaoInterviewSchemaLoader(
      resolver: JumaoCLIResolver(bundledRuntimeURL: nil, repositoryRootURL: repositoryRootURL)
    )
    let expectation = expectation(description: "schema result")

    loader.run { result in
      guard case .succeeded(let schema) = result else {
        XCTFail("仓库内 CLI 应返回问题 schema：\(result)")
        expectation.fulfill()
        return
      }
      XCTAssertEqual(schema.schemaVersion, 2)
      XCTAssertEqual(schema.questions.count, 21)
      XCTAssertEqual(schema.questions.first?.title, "最先会来用的人是谁？")
      XCTAssertEqual(schema.stages.map(\.id), ["idea", "prototype", "release"])
      XCTAssertEqual(schema.stages.map { stage in
        schema.questions.filter { $0.stage == stage.id }.count
      }, [5, 10, 6])
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 5)
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

  private var repositoryRootURL: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url
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
