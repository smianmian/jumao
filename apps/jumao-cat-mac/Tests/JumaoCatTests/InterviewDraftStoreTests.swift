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
    try await Task.sleep(nanoseconds: 250_000_000)
    XCTAssertEqual(fixture.draftStore.load(for: fixture.workspaceURLs[0]), .missing)
    try await Task.sleep(nanoseconds: 400_000_000)

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

  func testMultilineChineseEnglishAndEmojiAnswerIsSavedAndRestoredUnchanged() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let original = "第一行中文，English punctuation! 😺\n第二行保留换行。"
    let firstAppState = fixture.makeAppState()
    firstAppState.beginInterview(with: schema(questionCount: 1))
    firstAppState.updateInterviewAnswer(original, for: "question1")
    try await Task.sleep(nanoseconds: 650_000_000)
    firstAppState.hideInterview()
    firstAppState.shutdown()

    guard case .loaded(let draft) = fixture.draftStore.load(for: fixture.workspaceURLs[0]) else {
      return XCTFail("多行输入应保存为草稿")
    }
    XCTAssertEqual(draft.answers["question1"], original)

    let restoredAppState = fixture.makeAppState()
    defer { restoredAppState.shutdown() }
    restoredAppState.beginInterview(with: schema(questionCount: 1))
    XCTAssertEqual(restoredAppState.interviewAnswers["question1"], original)
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
    appState.beginInterview(with: schema(questionCount: 1))

    XCTAssertEqual(appState.interviewDraftError, "本地问答草稿无法读取，已清除。")
    XCTAssertEqual(appState.interviewErrorDetails, "操作：读取问答草稿\n退出码：无法启动\n原因：草稿文件不是有效的 JSON。")
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
    XCTAssertEqual(fixture.draftStore.load(for: fixture.workspaceURLs[0]), .missing)

    appState.beginInterview(with: schema(questionCount: 1))
    XCTAssertNil(appState.interviewDraftError)
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

  func testFocusedNewProjectLegacyDraftMigratesAnswersAndPosition() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let workspaceURL = fixture.workspaceURLs[0]
    try fixture.draftStore.save(
      InterviewDraft(
        schemaVersion: 2,
        workspaceIdentifier: InterviewDraftStore.workspaceIdentifier(for: workspaceURL),
        currentQuestionIndex: 2,
        answers: [
          "newProject.projectSummary": "客户跟进工具",
          "newProject.coreFeatures": "记录客户，设置提醒",
          "newProject.primaryGoal": "每天能完成一次客户跟进",
          "newProject.targetPlatform": "Mac"
        ],
        updatedAt: Date()
      ),
      for: workspaceURL
    )
    guard case .loaded = fixture.draftStore.loadLegacy(for: workspaceURL) else {
      return XCTFail("旧草稿应可被读取")
    }

    let restoredAppState = fixture.makeFocusedNewProjectAppState()
    defer { restoredAppState.shutdown() }
    restoredAppState.startProjectInterview()
    await Task.yield()

    XCTAssertTrue(restoredAppState.shouldOfferInterviewDraftRecovery)
    XCTAssertTrue(restoredAppState.interviewAnswers.isEmpty)
    restoredAppState.continueInterviewDraftRecovery()

    XCTAssertEqual(restoredAppState.interviewCurrentQuestionNumber, 1)
    XCTAssertEqual(restoredAppState.interviewAnswers["newProject.idea"], "客户跟进工具")
    XCTAssertEqual(restoredAppState.interviewAnswers["newProject.features"], "记录客户，设置提醒")
    XCTAssertEqual(restoredAppState.interviewAnswers["newProject.platform"], "Mac")
    XCTAssertNil(restoredAppState.interviewAnswers["newProject.projectSummary"])
  }

  func testFocusedNewProjectLegacyPlatformRequiresReselection() async throws {
    let legacyAnswers = [
      ("newProject.platform", "iPhone / iPad"),
      ("newProject.targetPlatform", "iPad"),
      ("newProject.targetPlatform", "Android"),
      ("newProject.platform", "Android 手机"),
      ("newProject.targetPlatform", "Android 平板"),
      ("newProject.platform", "Windows")
    ]
    for (answerPath, legacyPlatform) in legacyAnswers {
      let fixture = try makeFixture()
      defer { fixture.cleanUp() }
      let workspaceURL = fixture.workspaceURLs[0]
      try fixture.draftStore.save(
        InterviewDraft(
          schemaVersion: 2,
          workspaceIdentifier: InterviewDraftStore.workspaceIdentifier(for: workspaceURL),
          currentQuestionIndex: 2,
          answers: [answerPath: legacyPlatform],
          updatedAt: Date()
        ),
        for: workspaceURL
      )
      guard case .loaded = fixture.draftStore.loadLegacy(for: workspaceURL) else {
        return XCTFail("旧草稿应可被读取")
      }

      let restoredAppState = fixture.makeFocusedNewProjectAppState()
      defer { restoredAppState.shutdown() }
      restoredAppState.startProjectInterview()
      await Task.yield()

      XCTAssertTrue(restoredAppState.shouldOfferInterviewDraftRecovery)
      restoredAppState.continueInterviewDraftRecovery()

      XCTAssertNil(restoredAppState.interviewAnswers["newProject.platform"], legacyPlatform)
      XCTAssertEqual(
        restoredAppState.interviewPlatformMigrationMessage,
        "之前草稿中的平台选项已不再支持，请重新选择。",
        legacyPlatform
      )

      restoredAppState.updateInterviewAnswer("iPhone", for: "newProject.platform")
      XCTAssertNil(restoredAppState.interviewPlatformMigrationMessage, legacyPlatform)
    }
  }

  func testFocusedDraftRecoveryIsScopedToWorkspaceAndRequiresUserChoice() async throws {
    let fixture = try makeFixture(workspaceCount: 2)
    defer { fixture.cleanUp() }
    let chooser = RecordingWorkspaceChooser(selection: fixture.workspaceURLs[1])
    let appState = fixture.makeFocusedNewProjectAppState(workspaceChooser: chooser)
    defer { appState.shutdown() }

    appState.startProjectInterview()
    await Task.yield()
    appState.updateInterviewAnswer("项目 A 的想法", for: "newProject.idea")
    appState.hideInterview()

    appState.chooseWorkspace()
    appState.startProjectInterview()
    await Task.yield()

    XCTAssertEqual(appState.workspaceURL?.standardizedFileURL, fixture.workspaceURLs[1].standardizedFileURL)
    XCTAssertFalse(appState.shouldOfferInterviewDraftRecovery)
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 1)
    XCTAssertTrue(appState.interviewAnswers.isEmpty)

    chooser.setSelection(fixture.workspaceURLs[0])
    appState.chooseWorkspace()
    appState.startProjectInterview()
    await Task.yield()

    XCTAssertTrue(appState.shouldOfferInterviewDraftRecovery)
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
    appState.continueInterviewDraftRecovery()
    XCTAssertEqual(appState.interviewAnswers["newProject.idea"], "项目 A 的想法")
  }

  func testFocusedDraftAfterAppRestartOnlyOffersRecoveryForTheSavedWorkspace() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let firstAppState = fixture.makeFocusedNewProjectAppState()
    firstAppState.startProjectInterview()
    await Task.yield()
    firstAppState.updateInterviewAnswer("重启后继续的想法", for: "newProject.idea")
    firstAppState.hideInterview()
    firstAppState.shutdown()

    let restoredAppState = fixture.makeFocusedNewProjectAppState()
    defer { restoredAppState.shutdown() }
    restoredAppState.startProjectInterview()
    await Task.yield()

    XCTAssertTrue(restoredAppState.shouldOfferInterviewDraftRecovery)
    XCTAssertTrue(restoredAppState.interviewAnswers.isEmpty)
    restoredAppState.continueInterviewDraftRecovery()
    XCTAssertEqual(restoredAppState.interviewAnswers["newProject.idea"], "重启后继续的想法")
  }

  func testRestartingFocusedDraftDeletesOnlyCurrentScopedDraft() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let workspaceURL = fixture.workspaceURLs[0]
    let schemaVersion = 2
    try fixture.draftStore.save(
      InterviewDraft(
        schemaVersion: schemaVersion,
        workspaceIdentifier: InterviewDraftStore.workspaceIdentifier(
          for: workspaceURL,
          mode: .newProject,
          schemaVersion: schemaVersion
        ),
        mode: .newProject,
        currentQuestionIndex: 1,
        answers: ["newProject.idea": "未完成的想法"],
        updatedAt: Date()
      ),
      for: workspaceURL
    )
    let appState = fixture.makeFocusedNewProjectAppState()
    defer { appState.shutdown() }

    appState.startProjectInterview()
    await Task.yield()
    XCTAssertTrue(appState.shouldOfferInterviewDraftRecovery)
    appState.restartInterviewDraftRecovery()

    XCTAssertFalse(appState.shouldOfferInterviewDraftRecovery)
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 1)
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
    XCTAssertEqual(
      fixture.draftStore.load(for: workspaceURL, mode: .newProject, schemaVersion: schemaVersion),
      .missing
    )
  }

  func testScopedDraftsDoNotCollideForSameFolderNameModeOrSchema() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let first = fixture.rootURL.appendingPathComponent("first/SameName", isDirectory: true)
    let second = fixture.rootURL.appendingPathComponent("second/SameName", isDirectory: true)
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

    let draft = InterviewDraft(
      schemaVersion: 2,
      workspaceIdentifier: InterviewDraftStore.workspaceIdentifier(for: first, mode: .newProject, schemaVersion: 2),
      mode: .newProject,
      currentQuestionIndex: 0,
      answers: ["newProject.idea": "只属于第一个文件夹"],
      updatedAt: Date()
    )
    try fixture.draftStore.save(draft, for: first)

    XCTAssertEqual(fixture.draftStore.load(for: first, mode: .newProject, schemaVersion: 2), .loaded(draft))
    XCTAssertEqual(fixture.draftStore.load(for: second, mode: .newProject, schemaVersion: 2), .missing)
    XCTAssertEqual(fixture.draftStore.load(for: first, mode: .existingProject, schemaVersion: 2), .missing)
    XCTAssertEqual(fixture.draftStore.load(for: first, mode: .newProject, schemaVersion: 3), .missing)
  }

  func testCompletedScopedDraftIsDiscardedInsteadOfRestored() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let workspaceURL = fixture.workspaceURLs[0]
    try fixture.draftStore.save(
      InterviewDraft(
        schemaVersion: 2,
        workspaceIdentifier: InterviewDraftStore.workspaceIdentifier(for: workspaceURL, mode: .newProject, schemaVersion: 2),
        mode: .newProject,
        currentQuestionIndex: 2,
        answers: ["newProject.idea": "已完成"],
        isInterviewComplete: true,
        updatedAt: Date()
      ),
      for: workspaceURL
    )
    let appState = fixture.makeFocusedNewProjectAppState()
    defer { appState.shutdown() }

    appState.startProjectInterview()
    await Task.yield()

    XCTAssertFalse(appState.shouldOfferInterviewDraftRecovery)
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 1)
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
    XCTAssertEqual(fixture.draftStore.load(for: workspaceURL, mode: .newProject, schemaVersion: 2), .missing)
  }

  func testSuccessfulFocusedWriteDeletesScopedDraft() async throws {
    let fixture = try makeFixture()
    defer { fixture.cleanUp() }
    let workspaceURL = fixture.workspaceURLs[0]
    let appState = fixture.makeFocusedNewProjectAppState(interviewAnswerWriter: ImmediateAnswerWriter())
    defer { appState.shutdown() }

    appState.startProjectInterview()
    await Task.yield()
    appState.updateInterviewAnswer("喝水记录", for: "newProject.idea")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    appState.updateInterviewAnswer("记录喝水并查看今天的记录", for: "newProject.features")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    appState.updateInterviewAnswer("iPhone", for: "newProject.platform")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    appState.confirmFocusedInterviewUnderstanding()
    await Task.yield()

    XCTAssertNotNil(appState.focusedPlanningResult)
    XCTAssertTrue(appState.interviewAnswers.isEmpty)
    XCTAssertEqual(fixture.draftStore.load(for: workspaceURL, mode: .newProject, schemaVersion: 2), .missing)
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

  func makeFocusedNewProjectAppState(
    workspaceChooser: any WorkspaceChoosing = RecordingWorkspaceChooser(selection: nil),
    interviewAnswerWriter: any JumaoInterviewAnswerWriting = ImmediateAnswerWriter()
  ) -> AppState {
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      workspaceChooser: workspaceChooser,
      projectInspector: ImmediateDraftProjectInspector(),
      interviewSchemaLoader: ImmediateDraftInterviewSchemaLoader(),
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
  private var selection: URL?

  init(selection: URL?) {
    self.selection = selection
  }

  func chooseWorkspace(startingAt url: URL) -> URL? {
    selection
  }

  func setSelection(_ selection: URL?) {
    self.selection = selection
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

@MainActor
private final class ImmediateDraftProjectInspector: JumaoProjectInspecting {
  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
  ) {
    completion(.succeeded(JumaoProjectInspection(
      schemaVersion: 1,
      workspaceKind: "new",
      project: .init(
        name: workspaceURL.lastPathComponent,
        platforms: [],
        languages: [],
        buildSystems: [],
        hasSourceCode: false,
        hasTests: false,
        hasJumaoFiles: false
      ),
      capabilityFit: .init(level: "limited", primaryFocus: "ios_native", message: ""),
      evidence: [],
      unknowns: [],
      recommendedIntake: .init(mode: "new", questions: [])
    )))
  }

  func cancel() {}
}

@MainActor
private final class ImmediateDraftInterviewSchemaLoader: JumaoInterviewSchemaLoading {
  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void) {
    completion(.succeeded(JumaoInterviewSchema(schemaVersion: 2, questions: [])))
  }
}
