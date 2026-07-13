import XCTest
@testable import JumaoCat

@MainActor
final class JumaoInterviewAnswerWriterTests: XCTestCase {
  func testBuildsNestedAnswersFromAnswerPaths() {
    let answers = JumaoInterviewAnswerWriter.makeAnswers(
      questions: [
        question(answerPath: "primaryUser"),
        question(answerPath: "mainScreen.name"),
        question(answerPath: "mainScreen.userGoal"),
        question(answerPath: "mustDo", inputType: "list")
      ],
      answers: [
        "primaryUser": "创作者",
        "mainScreen.name": "项目页",
        "mainScreen.userGoal": "完成设置",
        "mustDo": "填写信息，确认范围、开始检查"
      ]
    )

    XCTAssertEqual(answers["primaryUser"] as? String, "创作者")
    XCTAssertEqual(answers["mustDo"] as? [String], ["填写信息", "确认范围", "开始检查"])
    let mainScreen = answers["mainScreen"] as? [String: Any]
    XCTAssertEqual(mainScreen?["name"] as? String, "项目页")
    XCTAssertEqual(mainScreen?["userGoal"] as? String, "完成设置")
  }

  func testSplitsListAnswersWithChineseAndEnglishSeparators() {
    XCTAssertEqual(
      JumaoInterviewAnswerWriter.splitListAnswer(" 第一项，第二项、 第三项, ,  "),
      ["第一项", "第二项", "第三项"]
    )
  }

  func testForceAddsForceArgumentToInterviewProcess() {
    XCTAssertEqual(
      JumaoInterviewAnswerWriter.arguments(
        workspaceURL: URL(fileURLWithPath: "/tmp/current-project"),
        answersURL: URL(fileURLWithPath: "/tmp/answers.json"),
        force: true
      ),
      ["interview", "/tmp/current-project", "--answers", "/tmp/answers.json", "--force"]
    )
  }

  func testTemporaryAnswersAreDeletedAfterSuccessfulProcess() async throws {
    try await assertTemporaryAnswersAreDeleted(executableURL: URL(fileURLWithPath: "/usr/bin/true"), expectedResult: .succeeded)
  }

  func testTemporaryAnswersAreDeletedAfterFailedProcess() async throws {
    try await assertTemporaryAnswersAreDeleted(
      executableURL: URL(fileURLWithPath: "/usr/bin/false"),
      expectedResult: .failed(exitCode: 1, message: "无法写入项目问题。")
    )
  }

  func testSuccessfulWriteClearsDraftAnswers() async throws {
    let writer = RecordingInterviewAnswerWriter()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(writer: writer)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: workspaceURL)
    }

    completeInterview(in: appState)
    appState.requestInterviewWrite()
    appState.confirmInterviewWrite()

    XCTAssertEqual(writer.calls.map(\.force), [false])
    writer.complete(.succeeded)
    await Task.yield()

    XCTAssertEqual(appState.interviewWriteMessage, "项目问题已写入\n下一步：开始检查")
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
    XCTAssertNil(appState.interviewWriteError)
  }

  func testExistingDocumentsRequireExplicitOverwriteConfirmation() async throws {
    let writer = RecordingInterviewAnswerWriter(documentsWithContent: ["product/product-brief.zh-CN.md"])
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(writer: writer)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: workspaceURL)
    }

    completeInterview(in: appState)
    appState.requestInterviewWrite()
    appState.confirmInterviewWrite()

    XCTAssertTrue(appState.isInterviewOverwriteConfirmationPresented)
    XCTAssertTrue(writer.calls.isEmpty)
    XCTAssertEqual(appState.interviewOverwriteMessage, "以下项目文档已有内容，确认后将覆盖：\n\n- product/product-brief.zh-CN.md")

    appState.confirmInterviewOverwrite()
    XCTAssertEqual(writer.calls.map(\.force), [true])
    writer.complete(.succeeded)
    await Task.yield()
  }

  func testFailedWriteKeepsDraftAnswersForRetry() async throws {
    let writer = RecordingInterviewAnswerWriter()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(writer: writer)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: workspaceURL)
    }

    completeInterview(in: appState)
    appState.requestInterviewWrite()
    appState.confirmInterviewWrite()
    writer.complete(.failed(exitCode: 1, message: "权限不足"))
    await Task.yield()

    XCTAssertEqual(appState.interviewAnswers["primaryUser"], "创作者")
    XCTAssertEqual(appState.interviewWriteError, "写入项目问题失败（退出码 1）：权限不足")
  }

  private func assertTemporaryAnswersAreDeleted(
    executableURL: URL,
    expectedResult: JumaoInterviewAnswerWriteResult
  ) async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let writer = JumaoInterviewAnswerWriter(
      executableURL: executableURL,
      command: nil,
      temporaryDirectory: temporaryDirectory
    )
    let expectation = expectation(description: "process completion")

    writer.run(
      workspaceURL: temporaryDirectory,
      questions: [question(answerPath: "primaryUser")],
      answers: ["primaryUser": "创作者"],
      force: false
    ) { result in
      XCTAssertEqual(result, expectedResult)
      expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 2)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path), [])
  }

  private func completeInterview(in appState: AppState) {
    appState.beginInterview(with: JumaoInterviewSchema(schemaVersion: 1, questions: [question(answerPath: "primaryUser")]))
    appState.updateInterviewAnswer("创作者", for: "primaryUser")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertTrue(appState.isInterviewComplete)
  }

  private func makeAppState(
    writer: any JumaoInterviewAnswerWriting
  ) throws -> (AppState, UserDefaults, String, URL) {
    let workspaceURL = try makeTemporaryDirectory()
    let suiteName = "JumaoCatInterviewAnswerWriterTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore, interviewAnswerWriter: writer)
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName, workspaceURL)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-interview-answer-writer-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func question(answerPath: String, inputType: String = "text") -> JumaoInterviewQuestion {
    JumaoInterviewQuestion(
      id: answerPath,
      answerPath: answerPath,
      title: "问题",
      description: "说明",
      inputType: inputType,
      required: true,
      order: 1
    )
  }
}

@MainActor
private final class RecordingInterviewAnswerWriter: JumaoInterviewAnswerWriting {
  struct Call {
    let workspaceURL: URL
    let questions: [JumaoInterviewQuestion]
    let answers: [String: String]
    let force: Bool
  }

  let existingDocuments: [String]
  private(set) var calls: [Call] = []
  private var completion: (@MainActor @Sendable (JumaoInterviewAnswerWriteResult) -> Void)?

  init(documentsWithContent: [String] = []) {
    existingDocuments = documentsWithContent
  }

  func documentsWithContent(in workspaceURL: URL) -> [String] {
    existingDocuments
  }

  func run(
    workspaceURL: URL,
    questions: [JumaoInterviewQuestion],
    answers: [String: String],
    force: Bool,
    completion: @escaping @MainActor @Sendable (JumaoInterviewAnswerWriteResult) -> Void
  ) {
    calls.append(Call(workspaceURL: workspaceURL, questions: questions, answers: answers, force: force))
    self.completion = completion
  }

  func complete(_ result: JumaoInterviewAnswerWriteResult) {
    completion?(result)
  }
}
