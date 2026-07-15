import XCTest
@testable import JumaoCat

@MainActor
final class JumaoProjectInspectorTests: XCTestCase {
  func testInspectUsesJSONCommandArguments() {
    XCTAssertEqual(
      JumaoProjectInspector.arguments(for: URL(fileURLWithPath: "/tmp/current-project")),
      ["inspect", "/tmp/current-project", "--json"]
    )
  }

  func testParsesInspectStdoutJSON() throws {
    let inspection = try JumaoProjectInspector.decodeInspection(from: try inspectionData(kind: "existing", level: "high"))

    XCTAssertEqual(inspection.workspaceKind, "existing")
    XCTAssertEqual(inspection.project.name, "Sample")
    XCTAssertEqual(inspection.project.platforms, ["iOS"])
    XCTAssertEqual(inspection.capabilityFit.level, "high")
  }

  func testInspectStderrIsNotShownToUser() async {
    let command = JumaoCLICommand(
      source: .configured,
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      prefixArguments: ["-c", "echo private-node-error >&2; exit 7"]
    )
    let runner = JumaoProjectInspector(resolver: FixedJumaoCLIResolver(.resolved(command)))
    let result = await withCheckedContinuation { continuation in
      runner.run(workspaceURL: URL(fileURLWithPath: "/tmp/project")) { result in
        continuation.resume(returning: result)
      }
    }

    XCTAssertEqual(result, .failed(exitCode: 7, message: "无法读取项目扫描结果，请重试。"))
  }

  func testEmptyAndNewProjectsShowNewProjectEntry() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.succeeded(try inspection(kind: "empty", level: "limited")))
    XCTAssertEqual(appState.projectInspectionPrimaryActionTitle, "开始规划新项目")
    XCTAssertEqual(appState.projectInspectionPrimaryActionDescription, "先用几句白话整理要做的第一版。")

    appState.rescanProject()
    inspector.complete(.succeeded(try inspection(kind: "new", level: "limited")))
    XCTAssertEqual(appState.projectInspectionPrimaryActionTitle, "开始规划新项目")
  }

  func testExistingProjectShowsChangeEntry() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.succeeded(try inspection(kind: "existing", level: "limited")))

    XCTAssertEqual(appState.projectInspectionKindTitle, "已有项目")
    XCTAssertEqual(appState.projectInspectionPrimaryActionTitle, "开始梳理这次改动")
    XCTAssertEqual(appState.projectInspectionPrimaryActionDescription, "橘猫已经查看了当前文件夹，接下来只确认这次要修改什么。")
  }

  func testAmbiguousFolderRequiresAnExplicitProjectTypeChoice() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.succeeded(try inspection(kind: "unknown", level: "limited")))

    XCTAssertTrue(appState.needsProjectInterviewModeSelection)
    XCTAssertNil(appState.projectInspectionPrimaryActionTitle)
    appState.chooseProjectInterviewMode(.newProject)
    XCTAssertEqual(appState.projectInspectionPrimaryActionTitle, "开始规划新项目")
    appState.chooseProjectInterviewMode(.existingProject)
    XCTAssertEqual(appState.projectInspectionPrimaryActionTitle, "开始梳理这次改动")
  }

  func testSwitchingPythonProjectToEmptyFolderClearsOldInspectionAndInterview() async throws {
    let inspector = DeferredProjectInspector()
    let loader = DeferredProjectInterviewSchemaLoader()
    let fixture = try makeWorkspaceSwitchFixture(inspector: inspector, interviewSchemaLoader: loader)
    defer { fixture.cleanUp() }

    inspector.complete(.succeeded(try inspection(
      kind: "existing",
      level: "limited",
      platforms: ["Backend"],
      languages: ["Python"],
      buildSystems: ["pip"]
    )), at: 0)
    fixture.appState.startProjectInterview()
    loader.complete(.succeeded(sourceSchema()))
    await Task.yield()
    fixture.appState.updateInterviewAnswer("修复导入", for: "existingProject.requestedChange")

    fixture.chooser.select(fixture.emptyWorkspaceURL)
    fixture.appState.chooseWorkspace()

    XCTAssertTrue(fixture.appState.isInspectingProject)
    XCTAssertNil(fixture.appState.projectInspection)
    XCTAssertNil(fixture.appState.interviewSchema)
    XCTAssertNil(fixture.appState.interviewMode)
    XCTAssertTrue(fixture.appState.interviewAnswers.isEmpty)
    XCTAssertEqual(fixture.appState.interviewCurrentQuestionIndex, 0)

    inspector.complete(.succeeded(try inspection(kind: "empty", level: "limited")), at: 1)
    XCTAssertEqual(fixture.appState.projectInspectionPrimaryActionTitle, "开始规划新项目")
    XCTAssertFalse(fixture.appState.projectInspection?.project.platforms.contains("Backend") ?? true)
    XCTAssertFalse(fixture.appState.projectInspection?.project.languages.contains("Python") ?? true)

    fixture.appState.startProjectInterview()
    loader.complete(.succeeded(sourceSchema()))
    await Task.yield()
    XCTAssertEqual(fixture.appState.interviewCurrentQuestion?.title, "你想做个什么？")
  }

  func testLateInspectionResultCannotOverrideTheCurrentWorkspace() throws {
    let inspector = DeferredProjectInspector()
    let fixture = try makeWorkspaceSwitchFixture(inspector: inspector)
    defer { fixture.cleanUp() }

    fixture.chooser.select(fixture.emptyWorkspaceURL)
    fixture.appState.chooseWorkspace()
    inspector.complete(.succeeded(try inspection(kind: "empty", level: "limited")), at: 1)
    inspector.complete(.succeeded(try inspection(kind: "existing", level: "limited", platforms: ["Backend"], languages: ["Python"])), at: 0)

    XCTAssertEqual(fixture.appState.workspaceURL?.standardizedFileURL, fixture.emptyWorkspaceURL.standardizedFileURL)
    XCTAssertEqual(fixture.appState.projectInspection?.workspaceKind, "empty")
    XCTAssertFalse(fixture.appState.projectInspection?.project.languages.contains("Python") ?? true)
  }

  func testSwitchingIOSProjectToEmptyFolderDoesNotKeepIOSOrSwift() throws {
    let inspector = DeferredProjectInspector()
    let fixture = try makeWorkspaceSwitchFixture(inspector: inspector)
    defer { fixture.cleanUp() }

    inspector.complete(.succeeded(try inspection(kind: "existing", level: "high", platforms: ["iOS"], languages: ["Swift"])), at: 0)
    fixture.chooser.select(fixture.emptyWorkspaceURL)
    fixture.appState.chooseWorkspace()
    inspector.complete(.succeeded(try inspection(kind: "empty", level: "limited", platforms: [], languages: [], buildSystems: [])), at: 1)

    XCTAssertEqual(fixture.appState.projectInspection?.workspaceKind, "empty")
    XCTAssertTrue(fixture.appState.projectInspection?.project.platforms.isEmpty ?? false)
    XCTAssertTrue(fixture.appState.projectInspection?.project.languages.isEmpty ?? false)
  }

  func testRapidWorkspaceSwitchesOnlyAcceptTheNewestInspection() throws {
    let inspector = DeferredProjectInspector()
    let fixture = try makeWorkspaceSwitchFixture(inspector: inspector)
    defer { fixture.cleanUp() }

    fixture.chooser.select(fixture.emptyWorkspaceURL)
    fixture.appState.chooseWorkspace()
    fixture.chooser.select(fixture.thirdWorkspaceURL)
    fixture.appState.chooseWorkspace()

    inspector.complete(.succeeded(try inspection(kind: "existing", level: "high", platforms: ["iOS"], languages: ["Swift"])), at: 2)
    inspector.complete(.succeeded(try inspection(kind: "empty", level: "limited")), at: 1)
    inspector.complete(.succeeded(try inspection(kind: "existing", level: "limited", platforms: ["Backend"], languages: ["Python"])), at: 0)

    XCTAssertEqual(fixture.appState.workspaceURL?.standardizedFileURL, fixture.thirdWorkspaceURL.standardizedFileURL)
    XCTAssertEqual(fixture.appState.projectInspection?.project.platforms, ["iOS"])
    XCTAssertEqual(fixture.appState.projectInspection?.project.languages, ["Swift"])
  }

  func testNewProjectEntryOpensFocusedInterviewImmediately() async throws {
    let inspector = DeferredProjectInspector()
    let loader = DeferredProjectInterviewSchemaLoader()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector, interviewSchemaLoader: loader)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.succeeded(try inspection(kind: "new", level: "limited")))
    appState.startProjectInterview()

    XCTAssertTrue(appState.isInterviewPresented)
    XCTAssertTrue(appState.isLoadingInterviewSchema)
    XCTAssertEqual(loader.runCount, 1)

    loader.complete(.succeeded(sourceSchema()))
    await Task.yield()

    XCTAssertEqual(appState.interviewMode, .newProject)
    XCTAssertEqual(appState.interviewQuestions.map(\.title), [
      "你想做个什么？",
      "你希望它能做哪些事？",
      "你想先在哪儿用它？"
    ])
    XCTAssertFalse(appState.interviewQuestions.map(\.title).contains("最核心的功能有哪些？"))
    XCTAssertFalse(appState.interviewQuestions.map(\.title).contains("当前最重要的目标是什么？"))
    XCTAssertEqual(appState.interviewQuestions.last?.description, "先选一个，之后还可以再增加其他版本。")
    XCTAssertEqual(appState.interviewQuestions.last?.options, ["iPhone", "Mac", "网页", "还没想好"])
    XCTAssertNil(appState.interviewAnswers["newProject.platform"])
    XCTAssertNil(appState.interviewInspectionContext)
  }

  func testExistingProjectEntryUsesDifferentQuestionsAndCarriesInspection() async throws {
    let inspector = DeferredProjectInspector()
    let loader = DeferredProjectInterviewSchemaLoader()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector, interviewSchemaLoader: loader)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    let existingInspection = try inspection(kind: "existing", level: "high")
    inspector.complete(.succeeded(existingInspection))
    appState.startProjectInterview()
    loader.complete(.succeeded(sourceSchema()))
    await Task.yield()

    XCTAssertEqual(appState.interviewMode, .existingProject)
    XCTAssertEqual(appState.interviewQuestions.map(\.title), [
      "这次你想让它变成什么样？"
    ])
    XCTAssertEqual(appState.interviewInspectionContext, existingInspection)
    XCTAssertEqual(appState.interviewInspectionSummary, "已携带扫描结果：Sample · iOS · Swift")
  }

  func testRepeatedProjectEntryClickDoesNotLoadOrOpenDuplicateInterview() throws {
    let inspector = DeferredProjectInspector()
    let loader = DeferredProjectInterviewSchemaLoader()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector, interviewSchemaLoader: loader)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.succeeded(try inspection(kind: "new", level: "limited")))
    appState.startProjectInterview()
    appState.startProjectInterview()

    XCTAssertTrue(appState.isInterviewPresented)
    XCTAssertEqual(loader.runCount, 1)
  }

  func testIOSAndNonIOSCapabilityMessagesDoNotBlockContinuation() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.succeeded(try inspection(kind: "existing", level: "high")))
    XCTAssertEqual(appState.projectInspectionCapabilityMessage, "橘猫对这个项目类型比较熟悉，当前更擅长 Swift、SwiftUI 与 Xcode 项目。")

    appState.rescanProject()
    inspector.complete(.succeeded(try inspection(kind: "existing", level: "limited")))
    XCTAssertEqual(appState.projectInspectionCapabilityMessage, "橘猫目前更擅长 iOS 原生 App。这个项目仍然可以梳理，但部分建议和检查可能不完整。")
    XCTAssertTrue(appState.canContinueFromProjectInspection)
  }

  func testFailedInspectionCanBeRetried() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    inspector.complete(.failed(exitCode: 1, message: "无法读取项目扫描结果，请重试。"))
    XCTAssertEqual(appState.projectInspectionError, "无法读取项目扫描结果，请重试。")

    appState.rescanProject()
    XCTAssertEqual(inspector.workspaceURLs.count, 2)
    XCTAssertTrue(appState.isInspectingProject)
  }

  func testExistingStatusFileKeepsStatusPanelAndDoesNotInspect() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector, writesStatus: true)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    XCTAssertFalse(appState.status.isMissingStatusFile)
    XCTAssertNil(appState.projectInspection)
    XCTAssertEqual(inspector.workspaceURLs.count, 0)
  }

  func testUnreadableStatusFileFallsBackToInspection() throws {
    let inspector = DeferredProjectInspector()
    let (appState, defaults, suiteName, workspaceURL) = try makeAppState(inspector: inspector, invalidStatus: true)
    defer { cleanUp(appState, defaults, suiteName, workspaceURL) }

    XCTAssertTrue(appState.shouldShowProjectInspection)
    XCTAssertEqual(inspector.workspaceURLs.count, 1)
  }

  private func makeAppState(
    inspector: DeferredProjectInspector,
    interviewSchemaLoader: any JumaoInterviewSchemaLoading = ImmediateProjectInterviewSchemaLoader(),
    writesStatus: Bool = false,
    invalidStatus: Bool = false
  ) throws -> (AppState, UserDefaults, String, URL) {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-inspector-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    if writesStatus { try writeStatus(in: workspaceURL) }
    if invalidStatus { try writeInvalidStatus(in: workspaceURL) }

    let suiteName = "JumaoCatInspectorTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      projectInspector: inspector,
      interviewSchemaLoader: interviewSchemaLoader
    )
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName, workspaceURL)
  }

  private func makeWorkspaceSwitchFixture(
    inspector: DeferredProjectInspector,
    interviewSchemaLoader: any JumaoInterviewSchemaLoading = ImmediateProjectInterviewSchemaLoader()
  ) throws -> WorkspaceSwitchFixture {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-workspace-switch-tests")
      .appendingPathComponent(UUID().uuidString)
    let existingWorkspaceURL = rootURL.appendingPathComponent("existing")
    let emptyWorkspaceURL = rootURL.appendingPathComponent("empty")
    let thirdWorkspaceURL = rootURL.appendingPathComponent("third")
    try FileManager.default.createDirectory(at: existingWorkspaceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: emptyWorkspaceURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: thirdWorkspaceURL, withIntermediateDirectories: true)

    let suiteName = "JumaoCatWorkspaceSwitchTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: existingWorkspaceURL)
    let chooser = MutableWorkspaceChooser()
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      workspaceChooser: chooser,
      projectInspector: inspector,
      interviewSchemaLoader: interviewSchemaLoader
    )
    appState.loadSavedWorkspace()
    return WorkspaceSwitchFixture(
      rootURL: rootURL,
      existingWorkspaceURL: existingWorkspaceURL,
      emptyWorkspaceURL: emptyWorkspaceURL,
      thirdWorkspaceURL: thirdWorkspaceURL,
      defaults: defaults,
      suiteName: suiteName,
      appState: appState,
      chooser: chooser
    )
  }

  private func inspection(
    kind: String,
    level: String,
    platforms: [String] = ["iOS"],
    languages: [String] = ["Swift"],
    buildSystems: [String] = ["Xcode"]
  ) throws -> JumaoProjectInspection {
    try JumaoProjectInspector.decodeInspection(
      from: try inspectionData(kind: kind, level: level, platforms: platforms, languages: languages, buildSystems: buildSystems)
    )
  }

  private func inspectionData(
    kind: String,
    level: String,
    platforms: [String] = ["iOS"],
    languages: [String] = ["Swift"],
    buildSystems: [String] = ["Xcode"]
  ) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "workspaceKind": kind,
      "project": [
        "name": "Sample",
        "platforms": platforms,
        "languages": languages,
        "buildSystems": buildSystems,
        "hasSourceCode": true,
        "hasTests": true,
        "hasJumaoFiles": false
      ],
      "capabilityFit": ["level": level, "primaryFocus": "ios_native", "message": "CLI message"],
      "evidence": [["kind": "project_file", "file": "Sample.xcodeproj", "detail": "检测到 Xcode 工程"]],
      "unknowns": [],
      "recommendedIntake": [
        "mode": kind == "existing" ? "existing_project" : "new_project",
        "questions": []
      ]
    ])
  }

  private func sourceSchema() -> JumaoInterviewSchema {
    JumaoInterviewSchema(schemaVersion: 2, questions: [])
  }

  private func writeStatus(in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: [
      "cat": ["state": "ready", "label": "已准备", "message": "已有项目状态。"]
    ])
    try data.write(to: statusURL)
  }

  private func writeInvalidStatus(in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not JSON".utf8).write(to: statusURL)
  }

  private func cleanUp(_ appState: AppState, _ defaults: UserDefaults, _ suiteName: String, _ workspaceURL: URL) {
    appState.shutdown()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: workspaceURL)
  }
}

@MainActor
private final class WorkspaceSwitchFixture {
  let rootURL: URL
  let existingWorkspaceURL: URL
  let emptyWorkspaceURL: URL
  let thirdWorkspaceURL: URL
  let defaults: UserDefaults
  let suiteName: String
  let appState: AppState
  let chooser: MutableWorkspaceChooser

  init(
    rootURL: URL,
    existingWorkspaceURL: URL,
    emptyWorkspaceURL: URL,
    thirdWorkspaceURL: URL,
    defaults: UserDefaults,
    suiteName: String,
    appState: AppState,
    chooser: MutableWorkspaceChooser
  ) {
    self.rootURL = rootURL
    self.existingWorkspaceURL = existingWorkspaceURL
    self.emptyWorkspaceURL = emptyWorkspaceURL
    self.thirdWorkspaceURL = thirdWorkspaceURL
    self.defaults = defaults
    self.suiteName = suiteName
    self.appState = appState
    self.chooser = chooser
  }

  func cleanUp() {
    appState.shutdown()
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: rootURL)
  }
}

@MainActor
private final class MutableWorkspaceChooser: WorkspaceChoosing {
  private var selection: URL?

  func select(_ workspaceURL: URL) {
    selection = workspaceURL
  }

  func chooseWorkspace(startingAt url: URL) -> URL? {
    selection
  }
}

@MainActor
private final class DeferredProjectInspector: JumaoProjectInspecting {
  private(set) var workspaceURLs: [URL] = []
  private var completions: [(@MainActor @Sendable (JumaoProjectInspectionResult) -> Void)] = []

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
  ) {
    workspaceURLs.append(workspaceURL)
    completions.append(completion)
  }

  func complete(_ result: JumaoProjectInspectionResult, at index: Int? = nil) {
    let target = index ?? completions.indices.last
    guard let target, completions.indices.contains(target) else { return }
    completions[target](result)
  }

  func cancel() {}
}

@MainActor
private final class DeferredProjectInterviewSchemaLoader: JumaoInterviewSchemaLoading {
  private(set) var runCount = 0
  private var completion: (@MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void)?

  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void) {
    runCount += 1
    self.completion = completion
  }

  func complete(_ result: JumaoInterviewSchemaLoadResult) {
    completion?(result)
  }
}

@MainActor
private final class ImmediateProjectInterviewSchemaLoader: JumaoInterviewSchemaLoading {
  func run(completion: @escaping @MainActor @Sendable (JumaoInterviewSchemaLoadResult) -> Void) {
    completion(.succeeded(JumaoInterviewSchema(schemaVersion: 2, questions: [])))
  }
}
