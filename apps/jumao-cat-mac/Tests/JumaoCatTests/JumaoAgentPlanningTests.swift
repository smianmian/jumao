import AppKit
import XCTest
@testable import JumaoCat

@MainActor
final class JumaoAgentPlanningTests: XCTestCase {
  func testRunnerUsesEventsJSONLAndForceArgumentsForUnicodeWorkspace() {
    let workspace = URL(fileURLWithPath: "/tmp/喝水 App")
    XCTAssertEqual(
      JumaoAgentPlanRunner.arguments(for: workspace, force: false),
      ["plan", "/tmp/喝水 App", "--events-jsonl"]
    )
    XCTAssertEqual(
      JumaoAgentPlanRunner.arguments(for: workspace, force: true),
      ["plan", "/tmp/喝水 App", "--events-jsonl", "--force"]
    )
  }

  func testNewProjectConfirmationAutomaticallyStartsPlan() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    await completeNewProjectInterview(in: fixture.appState)

    XCTAssertEqual(fixture.runner.calls.count, 1)
    XCTAssertEqual(fixture.runner.calls[0].workspaceURL.standardizedFileURL, fixture.workspaceURL.standardizedFileURL)
    XCTAssertFalse(fixture.runner.calls[0].force)
    XCTAssertTrue(fixture.appState.isAgentPlanning)
    XCTAssertEqual(fixture.appState.menuBarActivity, .working)
  }

  func testExistingProjectConfirmationAutomaticallyStartsPlan() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }

    let schema = JumaoInterviewSchema(schemaVersion: 2, questions: []).focused(for: .existingProject)
    fixture.appState.beginInterview(with: schema)
    fixture.appState.updateInterviewAnswer("让保存按钮有明确反馈", for: "existingProject.requestedChange")
    XCTAssertTrue(fixture.appState.advanceInterviewQuestion())
    fixture.appState.confirmFocusedInterviewUnderstanding()
    await Task.yield()

    XCTAssertEqual(fixture.runner.calls.count, 1)
    XCTAssertFalse(fixture.runner.calls[0].force)
    XCTAssertTrue(fixture.appState.isAgentPlanning)
  }

  func testRealEventsUpdateGroupsAndAgentCountsWithoutFakeProgress() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    await completeNewProjectInterview(in: fixture.appState)

    fixture.runner.emit(startEvent())
    fixture.runner.emit(groupEvent("group.started", groupID: "direction_entity", groupCounts: .zero))
    fixture.runner.emit(agentEvent(status: .completed, completed: 1))
    fixture.runner.emit(groupEvent(
      "group.completed",
      groupID: "direction_entity",
      groupCounts: JumaoAgentCounts(completed: 1, skipped: 4, blocked: 0, failed: 0)
    ))

    let session = try XCTUnwrap(fixture.appState.agentPlanningSession)
    XCTAssertEqual(session.groups.count, 8)
    XCTAssertEqual(session.groups[0].status, .completed)
    XCTAssertEqual(session.groups[0].agents.first?.status, .completed)
    XCTAssertEqual(session.counts.completed, 1)
  }

  func testRepeatedStartDoesNotLaunchASecondProcess() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    await completeNewProjectInterview(in: fixture.appState)

    fixture.appState.rerunAgentPlanning()
    fixture.appState.retryAgentPlanning()

    XCTAssertEqual(fixture.runner.calls.count, 1)
    XCTAssertEqual(fixture.appState.agentPlanningSession?.phase, .running)
  }

  func testSwitchingWorkspaceDiscardsLateEventsAndCompletion() async throws {
    let chooser = MutablePlanWorkspaceChooser()
    let fixture = try Fixture(workspaceChooser: chooser)
    defer { fixture.cleanUp() }
    await completeNewProjectInterview(in: fixture.appState)
    let second = try fixture.makeSecondWorkspace(named: "第二个 项目")
    chooser.nextURL = second
    fixture.appState.chooseWorkspace()

    fixture.runner.emit(startEvent(runID: "old-run"))
    fixture.loader.result = .loaded(finalSession(workspaceURL: fixture.workspaceURL))
    fixture.runner.complete(.finished)

    XCTAssertEqual(fixture.appState.workspaceURL?.standardizedFileURL, second.standardizedFileURL)
    XCTAssertNotEqual(fixture.appState.agentPlanningSession?.runId, "old-run")
  }

  func testOpeningWorkspaceRestoresLatestRunWithoutStartingPlan() throws {
    let workspace = try Fixture.makeWorkspace(named: "恢复项目")
    let loader = RecordingPlanLoader(result: .loaded(finalSession(workspaceURL: workspace)))
    let fixture = try Fixture(workspaceURL: workspace, loader: loader)
    defer { fixture.cleanUp() }

    XCTAssertEqual(fixture.appState.agentPlanningSession?.runId, "run-123")
    XCTAssertEqual(fixture.appState.agentPlanningSession?.phase, .completed)
    XCTAssertTrue(fixture.runner.calls.isEmpty)
  }

  func testRerunUsesForceAndCompletionRestoresExactResult() throws {
    let workspace = try Fixture.makeWorkspace(named: "重新整理")
    let loader = RecordingPlanLoader(result: .loaded(finalSession(workspaceURL: workspace)))
    let fixture = try Fixture(workspaceURL: workspace, loader: loader)
    defer { fixture.cleanUp() }

    fixture.appState.rerunAgentPlanning()
    XCTAssertEqual(fixture.runner.calls.map(\.force), [true])
    XCTAssertEqual(fixture.appState.menuBarActivity, .working)
    fixture.runner.emit(startEvent(runID: "run-new"))
    fixture.loader.result = .loaded(finalSession(workspaceURL: workspace, runID: "run-new"))
    fixture.runner.complete(.finished)

    XCTAssertEqual(fixture.appState.agentPlanningSession?.runId, "run-new")
    XCTAssertEqual(fixture.appState.menuBarActivity, .success)
  }

  func testReusedRunShowsExistingResultWithoutAgentEvents() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    await completeNewProjectInterview(in: fixture.appState)
    fixture.runner.emit(startEvent(reused: true))
    fixture.runner.emit(completedEvent(reused: true))
    fixture.loader.result = .loaded(finalSession(workspaceURL: fixture.workspaceURL))
    fixture.runner.complete(.finished)

    XCTAssertTrue(fixture.appState.agentPlanningSession?.reused == true)
    XCTAssertEqual(fixture.appState.agentPlanningSession?.groups.count, 8)
    XCTAssertEqual(fixture.runner.emittedEvents.count, 2)
  }

  func testFailureIsVisibleRetryableAndKeepsRealActivityBinding() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    await completeNewProjectInterview(in: fixture.appState)

    fixture.runner.complete(.failed(exitCode: 7, message: "橘猫没有完成这次整理。", details: "invalid jsonl"))
    XCTAssertEqual(fixture.appState.agentPlanningSession?.phase, .failed)
    XCTAssertEqual(fixture.appState.agentPlanningSession?.errorMessage, "橘猫没有完成这次整理。")
    XCTAssertEqual(fixture.appState.menuBarActivity, .failure)

    fixture.appState.retryAgentPlanning()
    XCTAssertEqual(fixture.runner.calls.map(\.force), [false, true])
  }

  func testExpandingGroupsDoesNotStartActivityAndShutdownCancelsProcess() throws {
    let workspace = try Fixture.makeWorkspace(named: "展开小组")
    let loader = RecordingPlanLoader(result: .loaded(finalSession(workspaceURL: workspace)))
    let fixture = try Fixture(workspaceURL: workspace, loader: loader)
    defer { fixture.cleanUp(removingWorkspace: false) }

    XCTAssertEqual(fixture.appState.menuBarActivity, .idle)
    fixture.appState.toggleAgentPlanningGroups()
    XCTAssertEqual(fixture.appState.menuBarActivity, .idle)
    fixture.appState.rerunAgentPlanning()
    fixture.appState.shutdown()
    XCTAssertEqual(fixture.runner.cancelCount, 1)
    try? FileManager.default.removeItem(at: workspace)
  }

  func testCodexInstructionUsesAgentPlanAndCurrentRunArtifacts() {
    let instruction = AppState.agentPlanningCodexInstruction(runPath: ".jumao/runs/run-123")
    XCTAssertTrue(instruction.contains("tasks/jumao-agent-plan.md"))
    XCTAssertTrue(instruction.contains(".jumao/runs/run-123/planning-summary.md"))
    XCTAssertTrue(instruction.contains(".jumao/runs/run-123/task-plan.json"))
    XCTAssertFalse(instruction.contains("tasks/codex-task-pack.md"))
    XCTAssertTrue(instruction.contains("在我确认前，不要修改代码"))
  }

  func testCopyForCodexUsesShortInstructionAndCopiedActivity() throws {
    let workspace = try Fixture.makeWorkspace(named: "复制交接")
    let loader = RecordingPlanLoader(result: .loaded(finalSession(workspaceURL: workspace)))
    let fixture = try Fixture(workspaceURL: workspace, loader: loader)
    defer { fixture.cleanUp() }

    fixture.appState.copyAgentPlanningCodexInstruction()

    XCTAssertEqual(
      fixture.appState.agentPlanningCopyFeedback,
      "已复制。请在 Codex 中打开这个项目文件夹，然后粘贴发送。"
    )
    XCTAssertEqual(fixture.appState.menuBarActivity, .copied)
    XCTAssertTrue(NSPasteboard.general.string(forType: .string)?.contains("tasks/jumao-agent-plan.md") == true)
  }

  func testBundledRuntimeStreamsAndLoadsARealNewProjectPlan() async throws {
    let workspace = try Fixture.makeWorkspace(named: "真实 新项目")
    defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
    let intake = #"{"schemaVersion":1,"mode":"new_project","answers":{"idea":"记录每天喝水","features":"记录喝水并查看今天记录","platform":"iPhone"}}"#
    try intake.write(
      to: workspace.appendingPathComponent(".jumao/intake-answers.json"),
      atomically: true,
      encoding: .utf8
    )

    let events = try await runBundledPlan(workspaceURL: workspace)
    XCTAssertEqual(events.filter { $0.agentId != nil }.count, 44)
    XCTAssertEqual(events.filter { $0.event == "group.completed" }.count, 8)
    XCTAssertEqual(events.last?.state, "ready")
    guard case .loaded(let session) = JumaoAgentPlanLoader().load(workspaceURL: workspace) else {
      return XCTFail("真实 BundledRuntime 结果没有通过 App loader 验证")
    }
    XCTAssertEqual(session.groups.count, 8)
    XCTAssertEqual(session.counts.total, 44)
    XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("tasks/jumao-agent-plan.md").path))
  }

  func testBundledRuntimeRecognizesExistingSwiftSourcesAndTests() async throws {
    let workspace = try Fixture.makeWorkspace(named: "真实 Swift 项目")
    defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Sample.xcodeproj"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent("Tests"), withIntermediateDirectories: true)
    try "import SwiftUI\nstruct SaveView: View { var body: some View { Button(\"保存\") {} } }\n"
      .write(to: workspace.appendingPathComponent("Sources/SaveView.swift"), atomically: true, encoding: .utf8)
    try "import XCTest\nfinal class SaveViewTests: XCTestCase {}\n"
      .write(to: workspace.appendingPathComponent("Tests/SaveViewTests.swift"), atomically: true, encoding: .utf8)
    let intake = #"{"schemaVersion":1,"mode":"existing_project","answers":{"requestedChange":"让保存按钮显示成功反馈"}}"#
    try intake.write(to: workspace.appendingPathComponent(".jumao/intake-answers.json"), atomically: true, encoding: .utf8)

    let events = try await runBundledPlan(workspaceURL: workspace)
    XCTAssertEqual(events.last?.state, "ready")
    let plan = try String(contentsOf: workspace.appendingPathComponent("tasks/jumao-agent-plan.md"), encoding: .utf8)
    XCTAssertTrue(plan.contains("Sources/SaveView.swift"))
    XCTAssertTrue(plan.contains("Tests/SaveViewTests.swift"))
  }

  func testMalformedJSONLReturnsAVisibleRunnerFailure() async {
    let command = JumaoCLICommand(
      source: .configured,
      executableURL: URL(fileURLWithPath: "/bin/sh"),
      prefixArguments: ["-c", "printf 'not-json\\n'"]
    )
    let runner = JumaoAgentPlanRunner(resolver: FixedJumaoCLIResolver(.resolved(command)))
    let result = await withCheckedContinuation { continuation in
      runner.run(
        workspaceURL: URL(fileURLWithPath: "/tmp/任意 项目"),
        force: false,
        event: { _ in XCTFail("损坏 JSONL 不应产生进度事件") },
        completion: { continuation.resume(returning: $0) }
      )
    }
    guard case .failed(_, let message, let details) = result else {
      return XCTFail("损坏 JSONL 应返回失败")
    }
    XCTAssertEqual(message, "规划进度数据无法读取。")
    XCTAssertTrue(details.contains("JSONL"))
  }

  private func runBundledPlan(workspaceURL: URL) async throws -> [JumaoAgentPlanEvent] {
    let runtimeURL = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("BundledRuntime"))
    let command = JumaoCLICommand.bundled(at: runtimeURL)
    let runner = JumaoAgentPlanRunner(resolver: FixedJumaoCLIResolver(.resolved(command)))
    var events: [JumaoAgentPlanEvent] = []
    let result = await withCheckedContinuation { continuation in
      runner.run(
        workspaceURL: workspaceURL,
        force: false,
        event: { events.append($0) },
        completion: { continuation.resume(returning: $0) }
      )
    }
    XCTAssertEqual(result, .finished)
    return events
  }

  private func completeNewProjectInterview(in appState: AppState) async {
    let schema = JumaoInterviewSchema(schemaVersion: 2, questions: []).focused(for: .newProject)
    appState.beginInterview(with: schema)
    for (path, answer) in [
      ("newProject.idea", "记录每天喝水的 App"),
      ("newProject.features", "记录喝水并查看今天的记录"),
      ("newProject.platform", "iPhone")
    ] {
      appState.updateInterviewAnswer(answer, for: path)
      XCTAssertTrue(appState.advanceInterviewQuestion())
    }
    appState.confirmFocusedInterviewUnderstanding()
    await Task.yield()
  }
}

@MainActor
private final class Fixture {
  let workspaceURL: URL
  let defaults: UserDefaults
  let suiteName: String
  let runner: DeferredPlanRunner
  let loader: RecordingPlanLoader
  let appState: AppState
  private let rootURL: URL

  init(
    workspaceURL: URL? = nil,
    workspaceChooser: any WorkspaceChoosing = MutablePlanWorkspaceChooser(),
    loader: RecordingPlanLoader = RecordingPlanLoader(result: .missing)
  ) throws {
    let workspace = try workspaceURL ?? Self.makeWorkspace(named: "喝水 App 项目")
    self.workspaceURL = workspace
    rootURL = workspace.deletingLastPathComponent()
    suiteName = "JumaoAgentPlanningTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace")
    _ = try bookmarkStore.save(workspaceURL: workspace)
    runner = DeferredPlanRunner()
    self.loader = loader
    appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      workspaceChooser: workspaceChooser,
      projectInspector: IdlePlanProjectInspector(),
      interviewAnswerWriter: ImmediatePlanAnswerWriter(),
      agentPlanRunner: runner,
      agentPlanLoader: loader
    )
    appState.loadSavedWorkspace()
  }

  static func makeWorkspace(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-agent-planning-tests")
      .appendingPathComponent(UUID().uuidString)
    let workspace = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: workspace.appendingPathComponent(".jumao"), withIntermediateDirectories: true)
    let status = #"{"cat":{"state":"ready","label":"已准备","message":"测试"}}"#
    try status.write(to: workspace.appendingPathComponent(".jumao/status.json"), atomically: true, encoding: .utf8)
    return workspace
  }

  func makeSecondWorkspace(named name: String) throws -> URL {
    let workspace = rootURL.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    return workspace
  }

  func cleanUp(removingWorkspace: Bool = true) {
    appState.shutdown()
    defaults.removePersistentDomain(forName: suiteName)
    if removingWorkspace { try? FileManager.default.removeItem(at: rootURL) }
  }
}

@MainActor
private final class DeferredPlanRunner: JumaoAgentPlanRunning {
  struct Call { let workspaceURL: URL; let force: Bool }
  private(set) var calls: [Call] = []
  private(set) var emittedEvents: [JumaoAgentPlanEvent] = []
  private(set) var cancelCount = 0
  private var eventHandler: (@MainActor @Sendable (JumaoAgentPlanEvent) -> Void)?
  private var completion: (@MainActor @Sendable (JumaoAgentPlanRunResult) -> Void)?
  var isRunning: Bool { completion != nil }

  func run(
    workspaceURL: URL,
    force: Bool,
    event: @escaping @MainActor @Sendable (JumaoAgentPlanEvent) -> Void,
    completion: @escaping @MainActor @Sendable (JumaoAgentPlanRunResult) -> Void
  ) {
    calls.append(Call(workspaceURL: workspaceURL, force: force))
    eventHandler = event
    self.completion = completion
  }

  func emit(_ event: JumaoAgentPlanEvent) {
    emittedEvents.append(event)
    eventHandler?(event)
  }

  func complete(_ result: JumaoAgentPlanRunResult) {
    let callback = completion
    completion = nil
    callback?(result)
  }

  func cancel() {
    guard isRunning else { return }
    cancelCount += 1
    complete(.cancelled)
  }
}

private final class RecordingPlanLoader: JumaoAgentPlanLoading, @unchecked Sendable {
  var result: JumaoAgentPlanLoadResult
  init(result: JumaoAgentPlanLoadResult) { self.result = result }
  func load(workspaceURL: URL) -> JumaoAgentPlanLoadResult { result }
}

@MainActor
private final class ImmediatePlanAnswerWriter: JumaoInterviewAnswerWriting {
  func documentsWithContent(in workspaceURL: URL) -> [String] { [] }
  func run(
    workspaceURL: URL,
    questions: [JumaoInterviewQuestion],
    answers: [String: String],
    force: Bool,
    completion: @escaping @MainActor @Sendable (JumaoInterviewAnswerWriteResult) -> Void
  ) { completion(.succeeded) }
}

@MainActor
private final class IdlePlanProjectInspector: JumaoProjectInspecting {
  func run(
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInspectionResult) -> Void
  ) {}
  func cancel() {}
}

private final class MutablePlanWorkspaceChooser: WorkspaceChoosing {
  var nextURL: URL?
  func chooseWorkspace(startingAt url: URL) -> URL? { nextURL }
}

private func planGroups() -> [JumaoAgentGroupDescriptor] {
  [
    ("direction_entity", "方向与主体 Agent 组", 5),
    ("product_design", "产品与设计 Agent 组", 7),
    ("tech_development", "技术与开发 Agent 组", 6),
    ("data_privacy", "数据与隐私 Agent 组", 6),
    ("compliance_health", "合规与健康声明 Agent 组", 5),
    ("platform_qualification", "上架与平台资质 Agent 组", 5),
    ("revenue_operations", "收费与运营 Agent 组", 4),
    ("release_incident", "发布与事故 Agent 组", 6)
  ].map { JumaoAgentGroupDescriptor(groupId: $0.0, groupName: $0.1, totalAgents: $0.2) }
}

private func planEvent(
  _ name: String,
  runID: String = "run-123",
  groupID: String? = nil,
  agentID: String? = nil,
  agentStatus: String? = nil,
  completed: Int = 0,
  skipped: Int = 0,
  blocked: Int = 0,
  failed: Int = 0,
  groupCounts: JumaoAgentCounts? = nil,
  state: String? = nil,
  reused: Bool = false,
  groups: [JumaoAgentGroupDescriptor]? = nil
) -> JumaoAgentPlanEvent {
  JumaoAgentPlanEvent(
    schemaVersion: 1,
    runId: runID,
    timestamp: "2026-07-16T00:00:00.000Z",
    event: name,
    groupId: groupID,
    groupName: groupID == nil ? nil : "方向与主体 Agent 组",
    agentId: agentID,
    agentName: agentID == nil ? nil : "项目负责人 / 创始人 Agent",
    agentStatus: agentStatus,
    completedAgents: completed,
    skippedAgents: skipped,
    blockedAgents: blocked,
    failedAgents: failed,
    totalAgents: 44,
    groupCounts: groupCounts,
    summary: "真实摘要",
    skippedReason: agentStatus == "skipped" ? "当前职责无关" : nil,
    state: state,
    reused: reused,
    runPath: name.hasPrefix("run.") && name != "run.started" ? ".jumao/runs/\(runID)" : nil,
    error: nil,
    groups: groups
  )
}

private func startEvent(runID: String = "run-123", reused: Bool = false) -> JumaoAgentPlanEvent {
  planEvent("run.started", runID: runID, reused: reused, groups: planGroups())
}

private func completedEvent(reused: Bool = false) -> JumaoAgentPlanEvent {
  planEvent("run.completed", completed: 11, skipped: 33, state: "ready", reused: reused)
}

private func groupEvent(
  _ name: String,
  groupID: String,
  groupCounts: JumaoAgentCounts
) -> JumaoAgentPlanEvent {
  planEvent(
    name,
    groupID: groupID,
    completed: groupCounts.completed,
    skipped: groupCounts.skipped,
    blocked: groupCounts.blocked,
    failed: groupCounts.failed,
    groupCounts: groupCounts
  )
}

private func agentEvent(status: JumaoAgentProgressStatus, completed: Int) -> JumaoAgentPlanEvent {
  planEvent(
    "agent.\(status.rawValue)",
    groupID: "direction_entity",
    agentID: "founder_decision",
    agentStatus: status.rawValue,
    completed: completed,
    groupCounts: JumaoAgentCounts(completed: completed, skipped: 0, blocked: 0, failed: 0)
  )
}

private func finalSession(workspaceURL: URL, runID: String = "run-123") -> JumaoAgentPlanningSession {
  let groups = planGroups().map { descriptor in
    JumaoAgentGroupProgress(
      id: descriptor.groupId,
      name: descriptor.groupName,
      totalAgents: descriptor.totalAgents,
      status: .completed,
      counts: JumaoAgentCounts(completed: 1, skipped: descriptor.totalAgents - 1, blocked: 0, failed: 0),
      summary: "真实小组摘要",
      agents: []
    )
  }
  return JumaoAgentPlanningSession(
    phase: .completed,
    workspaceIdentifier: workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path,
    runId: runID,
    runPath: ".jumao/runs/\(runID)",
    state: "ready",
    reused: false,
    counts: JumaoAgentCounts(completed: 11, skipped: 33, blocked: 0, failed: 0),
    totalAgents: 44,
    groups: groups,
    request: "记录每天喝水",
    understanding: "第一阶段先记录喝水并查看今天的记录。",
    errorMessage: nil,
    errorDetails: nil
  )
}
