import XCTest
@testable import JumaoCat

@MainActor
final class InterviewDraftStoreTests: XCTestCase {
  func testAutoSaveWritesWorkspaceDraftWithUserOnlyPermissions() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let appState = fixture.makeAppState()
    defer { appState.shutdown() }

    appState.beginInterview(with: schema(questionCount: 2))
    appState.updateInterviewAnswer("独立开发者", for: "question1")
    try await Task.sleep(nanoseconds: 650_000_000)

    guard case .loaded(let draft) = fixture.draftStore.load(for: fixture.workspaceURLs[0]) else {
      return XCTFail("应自动保存草稿")
    }
    XCTAssertEqual(draft.schemaVersion, 1)
    XCTAssertEqual(draft.currentQuestionIndex, 0)
    XCTAssertEqual(draft.answers["question1"], "独立开发者")
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.draftStore.draftURL(for: fixture.workspaceURLs[0]).path)
    XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
  }

  func testAppStateRestoresDraftAndQuestionAfterRecreation() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let firstAppState = fixture.makeAppState()
    firstAppState.beginInterview(with: schema(questionCount: 3))
    firstAppState.updateInterviewAnswer("第一题答案", for: "question1")
    XCTAssertTrue(firstAppState.advanceInterviewQuestion())
    firstAppState.updateInterviewAnswer("第二题答案", for: "question2")
    firstAppState.hideInterview()
    firstAppState.shutdown()

    let restoredAppState = fixture.makeAppState()
    defer { restoredAppState.shutdown() }
    restoredAppState.beginInterview(with: schema(questionCount: 3))

    XCTAssertEqual(restoredAppState.interviewCurrentQuestionNumber, 2)
    XCTAssertEqual(restoredAppState.interviewAnswers["question1"], "第一题答案")
    XCTAssertEqual(restoredAppState.interviewAnswers["question2"], "第二题答案")
  }

  func testDifferentWorkspacesKeepSeparateDraftsWhenSwitching() throws {
    let fixture = try makeFixture(workspaceCount: 2)
    defer { fixture.cleanUp() }
    let chooser = RecordingWorkspaceChooser(selection: fixture.workspaceURLs[1])
    let appState = fixture.makeAppState(workspaceChooser: chooser)
    defer { appState.shutdown() }

    appState.beginInterview(with: schema(questionCount: 2))
    appState.updateInterviewAnswer("旧项目答案", for: "question1")
    appState.hideInterview()
    appState.chooseWorkspace()

    guard case .loaded(let oldDraft) = fixture.draftStore.load(for: fixture.workspaceURLs[0]) else {
      return XCTFail("切换项目不应删除旧草稿")
    }
    XCTAssertEqual(oldDraft.answers["question1"], "旧项目答案")
    XCTAssertEqual(appState.workspaceURL?.resolvingSymlinksInPath(), fixture.workspaceURLs[1].resolvingSymlinksInPath())
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
  }

  func testSuccessfulInterviewWriteDeletesCurrentWorkspaceDraft() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let appState = fixture.makeAppState(interviewAnswerWriter: ImmediateAnswerWriter())
    defer { appState.shutdown() }

    appState.beginInterview(with: schema(questionCount: 1))
    appState.updateInterviewAnswer("已填写", for: "question1")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    appState.hideInterview()
    appState.requestInterviewWrite()
    appState.confirmInterviewWrite()
    await Task.yield()

    XCTAssertEqual(fixture.draftStore.load(for: fixture.workspaceURLs[0]), .missing)
  }

  func testCorruptedDraftFallsBackWithoutCrashing() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    try FileManager.default.createDirectory(at: fixture.draftStore.draftURL(for: fixture.workspaceURLs[0]).deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("损坏的草稿".utf8).write(to: fixture.draftStore.draftURL(for: fixture.workspaceURLs[0]))

    let appState = fixture.makeAppState()
    defer { appState.shutdown() }

    XCTAssertEqual(appState.interviewDraftError, "本地问答草稿无法读取，已忽略。")
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
  }

  func testRestoresTheSavedStageAfterRecreatingAppState() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let schema = stagedSchema()
    let firstAppState = fixture.makeAppState()
    firstAppState.beginInterview(with: schema)
    firstAppState.updateInterviewAnswer("第一题答案", for: "question1")
    XCTAssertTrue(firstAppState.advanceInterviewQuestion())
    firstAppState.updateInterviewAnswer("第二题答案", for: "question2")
    XCTAssertTrue(firstAppState.advanceInterviewQuestion())
    firstAppState.continueToNextInterviewStage()
    firstAppState.hideInterview()
    firstAppState.shutdown()

    let restoredAppState = fixture.makeAppState()
    defer { restoredAppState.shutdown() }
    restoredAppState.beginInterview(with: schema)

    XCTAssertEqual(restoredAppState.currentInterviewStage?.id, "prototype")
    XCTAssertEqual(restoredAppState.interviewCurrentQuestion?.answerPath, "question3")
  }

  func testOldDraftWithoutStageInfersStageFromCurrentQuestion() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let workspaceURL = fixture.workspaceURLs[0]
    let oldDraft = """
    {"schemaVersion":1,"workspaceIdentifier":"\(InterviewDraftStore.workspaceIdentifier(for: workspaceURL))","currentQuestionIndex":2,"answers":{},"updatedAt":0}
    """
    let draftURL = fixture.draftStore.draftURL(for: workspaceURL)
    try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(oldDraft.utf8).write(to: draftURL)

    let appState = fixture.makeAppState()
    defer { appState.shutdown() }
    appState.beginInterview(with: stagedSchema())

    XCTAssertEqual(appState.currentInterviewStage?.id, "prototype")
    XCTAssertEqual(appState.interviewCurrentQuestion?.answerPath, "question3")
  }

  func testFocusedNewProjectDraftRestoresAnswersAndPosition() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let focusedSchema = JumaoInterviewSchema(schemaVersion: 2, questions: []).focused(for: .newProject)
    let firstAppState = fixture.makeAppState()
    firstAppState.beginInterview(with: focusedSchema)
    firstAppState.updateInterviewAnswer("客户跟进工具", for: "newProject.projectSummary")
    XCTAssertTrue(firstAppState.advanceInterviewQuestion())
    firstAppState.updateInterviewAnswer("记录客户，设置提醒", for: "newProject.coreFeatures")
    firstAppState.hideInterview()
    firstAppState.shutdown()

    let restoredAppState = fixture.makeAppState()
    defer { restoredAppState.shutdown() }
    restoredAppState.beginInterview(with: focusedSchema)

    XCTAssertEqual(restoredAppState.interviewCurrentQuestionNumber, 2)
    XCTAssertEqual(restoredAppState.interviewAnswers["newProject.projectSummary"], "客户跟进工具")
    XCTAssertEqual(restoredAppState.interviewAnswers["newProject.coreFeatures"], "记录客户，设置提醒")
  }

  private func schema(questionCount: Int) -> JumaoInterviewSchema {
    JumaoInterviewSchema(
      schemaVersion: 1,
      questions: (1...questionCount).map { order in
        JumaoInterviewQuestion(
          id: "question\(order)",
          answerPath: "question\(order)",
          title: "问题 \(order)",
          description: "说明",
          inputType: "text",
          required: true,
          order: order
        )
      }
    )
  }

  private func stagedSchema() -> JumaoInterviewSchema {
    let stages = [
      JumaoInterviewStage(id: "idea", title: "想法", description: "说明", order: 1),
      JumaoInterviewStage(id: "prototype", title: "第一版", description: "说明", order: 2),
      JumaoInterviewStage(id: "release", title: "给别人使用", description: "说明", order: 3)
    ]
    let stageIDs = ["idea", "idea", "prototype", "release"]
    let questions = stageIDs.enumerated().map { index, stage in
      JumaoInterviewQuestion(
        id: "question\(index + 1)",
        answerPath: "question\(index + 1)",
        title: "问题 \(index + 1)",
        description: "说明",
        stage: stage,
        inputType: "text",
        required: true,
        order: index + 1
      )
    }
    return JumaoInterviewSchema(schemaVersion: 1, stages: stages, questions: questions)
  }

  private func makeFixture(workspaceCount: Int = 1) throws -> DraftFixture {
    try DraftFixture(workspaceCount: workspaceCount)
  }
}

@MainActor
private final class DraftFixture {
  let rootURL: URL
  let workspaceURLs: [URL]
  let defaults: UserDefaults
  let suiteName: String
  let bookmarkStore: WorkspaceBookmarkStore
  let draftStore: InterviewDraftStore

  init(workspaceCount: Int) throws {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("jumao-cat-draft-tests/\(UUID().uuidString)")
    let workspaceURLs = (1...workspaceCount).map { rootURL.appendingPathComponent("workspace-\($0)") }
    self.rootURL = rootURL
    self.workspaceURLs = workspaceURLs
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    for workspaceURL in workspaceURLs {
      try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }
    suiteName = "JumaoCatDraftTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    self.defaults = defaults
    bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURLs[0])
    draftStore = InterviewDraftStore(directoryURL: rootURL.appendingPathComponent("Application Support/JumaoCat/InterviewDrafts"))
  }

  func makeAppState(
    workspaceChooser: any WorkspaceChoosing = RecordingWorkspaceChooser(selection: nil),
    interviewAnswerWriter: any JumaoInterviewAnswerWriting = ImmediateAnswerWriter()
  ) -> AppState {
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      workspaceChooser: workspaceChooser,
      interviewAnswerWriter: interviewAnswerWriter,
      interviewDraftStore: draftStore
    )
    appState.loadSavedWorkspace()
    return appState
  }

  func cleanUp() {
    bookmarkStore.stopAccessingWorkspace()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: rootURL)
  }
}

@MainActor
private final class RecordingWorkspaceChooser: WorkspaceChoosing {
  private let selection: URL?

  init(selection: URL?) {
    self.selection = selection
  }

  func chooseWorkspace(startingAt url: URL) -> URL? {
    selection
  }
}

@MainActor
private final class ImmediateAnswerWriter: JumaoInterviewAnswerWriting {
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
