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
    XCTAssertEqual(appState.projectInspectionPrimaryActionDescription, "先确认第一版要实现哪些功能。")

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
    XCTAssertEqual(appState.projectInspectionPrimaryActionDescription, "橘猫已经查看了项目结构，接下来只确认这次要修改什么。")
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
      "你想做一个什么项目？",
      "最核心的功能有哪些？",
      "当前最重要的目标是什么？",
      "准备运行在哪个平台？"
    ])
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
      "这次准备修改什么？",
      "当前遇到了什么问题或阻塞？",
      "哪些现有功能绝对不能被破坏？"
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

  private func inspection(kind: String, level: String) throws -> JumaoProjectInspection {
    try JumaoProjectInspector.decodeInspection(from: try inspectionData(kind: kind, level: level))
  }

  private func inspectionData(kind: String, level: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "workspaceKind": kind,
      "project": [
        "name": "Sample",
        "platforms": ["iOS"],
        "languages": ["Swift"],
        "buildSystems": ["Xcode"],
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
private final class DeferredProjectInspector: JumaoProjectInspecting {
  private(set) var workspaceURLs: [URL] = []
  private var completion: (@MainActor @Sendable (JumaoProjectInspectionResult) -> Void)?

  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
  ) {
    workspaceURLs.append(workspaceURL)
    self.completion = completion
  }

  func complete(_ result: JumaoProjectInspectionResult) {
    completion?(result)
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
