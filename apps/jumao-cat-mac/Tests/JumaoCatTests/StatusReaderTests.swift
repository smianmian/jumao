import XCTest
@testable import JumaoCat

final class StatusReaderTests: XCTestCase {
  func testUnselectedWorkspaceUsesSleepingIcon() {
    XCTAssertEqual(WorkspaceStatus.unselected.catState, "sleeping")
    XCTAssertEqual(WorkspaceStatus.unselected.label, "待命")
    XCTAssertEqual(WorkspaceStatus.unselected.message, "项目尚未开始检查")
  }

  func testUserFacingStateTextUsesChineseMappings() {
    let expected = [
      "sleeping": CatStatePresentation(label: "待命", message: "项目尚未开始检查"),
      "checking": CatStatePresentation(label: "检查中", message: "橘猫正在分析项目目标、边界和风险"),
      "blocked": CatStatePresentation(label: "存在阻塞", message: "发现关键问题，处理后才能继续"),
      "ready": CatStatePresentation(label: "准备完成", message: "项目检查已通过，可以生成任务包"),
      "packed": CatStatePresentation(label: "任务包已生成", message: "任务已经整理完成，可以交给 Codex 执行")
    ]

    for (state, presentation) in expected {
      XCTAssertEqual(CatStatePresentation.forState(state), presentation)
    }
  }

  func testUnknownStateUsesChineseLabelAndKeepsRawCodeInMessage() {
    let presentation = CatStatePresentation.forState("investigating")

    XCTAssertEqual(presentation.label, "未知状态")
    XCTAssertEqual(presentation.message, "原始状态码：investigating")
  }

  func testProjectReadinessDoesNotAppearBeforeSelectingWorkspace() {
    XCTAssertNil(WorkspaceStatus.unselected.projectReadiness)
  }

  func testProjectReadinessForMissingStatusFileWaitsForCheck() {
    XCTAssertEqual(
      WorkspaceStatus.missingStatusFile.projectReadiness,
      ProjectReadiness(percentage: 10, stage: "等待检查", rawState: nil)
    )
  }

  func testProjectReadinessMapsEveryCatState() {
    let expected = [
      "sleeping": ProjectReadiness(percentage: 20, stage: "待命", rawState: nil),
      "checking": ProjectReadiness(percentage: 40, stage: "正在检查", rawState: nil),
      "blocked": ProjectReadiness(percentage: 60, stage: "处理关键阻塞", rawState: nil),
      "ready": ProjectReadiness(percentage: 90, stage: "可以生成任务包", rawState: nil),
      "packed": ProjectReadiness(percentage: 100, stage: "准备完成", rawState: nil)
    ]

    for (state, readiness) in expected {
      XCTAssertEqual(ProjectReadiness.forState(state), readiness)
    }
  }

  func testUnknownProjectReadinessKeepsRawStateCode() {
    XCTAssertEqual(
      ProjectReadiness.forState("investigating"),
      ProjectReadiness(percentage: 20, stage: "未知阶段", rawState: "investigating")
    )
  }

  func testPackedProjectReadinessDropsWhenGroupsAreBlocked() {
    XCTAssertEqual(
      ProjectReadiness.forState("packed", blockedGroupCount: 6),
      ProjectReadiness(percentage: 80, stage: "任务包已生成，仍需处理阻塞", rawState: nil)
    )
  }

  func testPackedProjectReadinessReachesCompletionWithoutBlockedGroups() {
    XCTAssertEqual(
      ProjectReadiness.forState("packed", blockedGroupCount: 0),
      ProjectReadiness(percentage: 100, stage: "准备完成", rawState: nil)
    )
  }

  func testBlockedGroupsNeverReportFullReadiness() {
    for state in ["sleeping", "checking", "blocked", "ready", "packed"] {
      XCTAssertLessThan(
        ProjectReadiness.forState(state, blockedGroupCount: 6).percentage,
        100,
        "Expected \(state) with blocked groups to stay below 100%."
      )
    }
  }

  func testAgentTeamUsesStatusAgentBoardCounts() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(fullStatusJSON, in: workspaceURL)

    let overview = StatusReader().read(workspaceURL: workspaceURL).agentTeamOverview

    XCTAssertEqual(overview?.triggeredAgentCount, 27)
    XCTAssertEqual(overview?.activeGroupCount, 8)
    XCTAssertEqual(overview?.blockedGroupCount, 6)
  }

  func testAgentTeamShowsExplicitZeroCounts() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(#"{"cat":{"state":"ready","label":"可以继续","message":"可以继续做一个小任务。"},"agentBoard":{"triggeredAgentCount":0,"activeGroupCount":0,"blockedGroupCount":0}}"#, in: workspaceURL)

    let overview = StatusReader().read(workspaceURL: workspaceURL).agentTeamOverview

    XCTAssertEqual(overview?.triggeredAgentCount, 0)
    XCTAssertEqual(overview?.activeGroupCount, 0)
    XCTAssertEqual(overview?.blockedGroupCount, 0)
  }

  func testAgentTeamUsesZeroDefaultsWhenAgentBoardIsMissing() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(#"{"cat":{"state":"ready","label":"可以继续","message":"可以继续做一个小任务。"}}"#, in: workspaceURL)

    let overview = StatusReader().read(workspaceURL: workspaceURL).agentTeamOverview

    XCTAssertEqual(overview?.triggeredAgentCount, 0)
    XCTAssertEqual(overview?.activeGroupCount, 0)
    XCTAssertEqual(overview?.blockedGroupCount, 0)
  }

  func testAgentTeamOnlyAppearsWhenStatusFileLoadsSuccessfully() {
    XCTAssertNil(WorkspaceStatus.unselected.agentTeamOverview)
    XCTAssertNil(WorkspaceStatus.missingStatusFile.agentTeamOverview)
    XCTAssertNil(WorkspaceStatus.failed("读取失败").agentTeamOverview)
  }

  func testCheckingAgentTeamShowsActivityMarker() {
    let overview = AgentTeamOverview(agentBoard: .empty, catState: "checking")

    XCTAssertTrue(overview.showsCheckingActivity)
  }

  func testNonCheckingAgentTeamsDoNotShowActivityMarker() {
    for state in ["sleeping", "blocked", "ready", "packed", "unknown"] {
      XCTAssertFalse(AgentTeamOverview(agentBoard: .empty, catState: state).showsCheckingActivity)
    }
  }

  func testMissingStatusFileIsDistinctFromUnselectedWorkspace() throws {
    let workspaceURL = try makeWorkspace()
    let status = StatusReader().read(workspaceURL: workspaceURL)

    guard case .missingStatusFile = status else {
      return XCTFail("Expected missing status file state.")
    }
  }

  func testReadsCompleteStatusAndFileModificationDate() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(fullStatusJSON, in: workspaceURL)

    let result = StatusReader().read(workspaceURL: workspaceURL)

    guard case .loaded(let snapshot) = result else {
      return XCTFail("Expected loaded status.")
    }

    XCTAssertEqual(snapshot.status.workspace.name, "AI Note")
    XCTAssertEqual(snapshot.status.cat.state, "packed")
    XCTAssertEqual(snapshot.status.agentBoard.triggeredAgentCount, 27)
    XCTAssertEqual(snapshot.status.blockers.count, 4)
    XCTAssertEqual(snapshot.status.nextSafeTask, "先完成数据删除规则。")
    XCTAssertEqual(snapshot.status.artifacts.latestTaskPack, "tasks/codex-task-pack.md")
    XCTAssertEqual(snapshot.status.lastRun.command, "pack")
    XCTAssertNotNil(snapshot.fileModificationDate)
  }

  func testUsesDefaultsForMissingOptionalFields() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(#"{"cat":{"state":"ready","label":"可以继续","message":"可以继续做一个小任务。"}}"#, in: workspaceURL)

    let result = StatusReader().read(workspaceURL: workspaceURL)

    guard case .loaded(let snapshot) = result else {
      return XCTFail("Expected loaded status.")
    }

    XCTAssertEqual(snapshot.status.agentBoard.triggeredAgentCount, 0)
    XCTAssertTrue(snapshot.status.blockers.isEmpty)
    XCTAssertEqual(snapshot.status.nextSafeTask, "")
    XCTAssertEqual(snapshot.status.artifacts.agentReport, "")
    XCTAssertTrue(snapshot.status.agentBoard.groups.isEmpty)
  }

  func testReadsEightAgentGroupsFromStatus() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(fullStatusJSON, in: workspaceURL)

    let groups = StatusReader().read(workspaceURL: workspaceURL).snapshot?.status.agentBoard.groups

    XCTAssertEqual(groups?.count, 8)
    XCTAssertEqual(groups?.first?.id, "direction_entity")
    XCTAssertEqual(groups?.first?.name, "方向与主体 Agent 组")
    XCTAssertEqual(groups?.first?.triggeredAgentCount, 1)
  }

  func testAgentGroupUsesChineseStateLabels() {
    XCTAssertEqual(AgentGroupStatePresentation.label(for: "idle"), "未召集")
    XCTAssertEqual(AgentGroupStatePresentation.label(for: "triggered"), "已召集")
    XCTAssertEqual(AgentGroupStatePresentation.label(for: "blocked"), "存在阻塞")
    XCTAssertEqual(AgentGroupStatePresentation.label(for: "future_state"), "未知状态")
  }

  func testBlockedAgentGroupKeepsItsMessage() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(fullStatusJSON, in: workspaceURL)

    let groups = StatusReader().read(workspaceURL: workspaceURL).snapshot?.status.agentBoard.groups
    let dataPrivacy = groups?.first { $0.id == "data_privacy" }

    XCTAssertEqual(dataPrivacy?.state, "blocked")
    XCTAssertEqual(dataPrivacy?.stateLabel, "存在阻塞")
    XCTAssertEqual(dataPrivacy?.message, "先补数据保存、删除和第三方工具边界")
  }

  func testReportsInvalidJSON() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus("not json", in: workspaceURL)

    guard case .failed = StatusReader().read(workspaceURL: workspaceURL) else {
      return XCTFail("Expected invalid JSON state.")
    }
  }

  func testKeepsUnknownCatStateAndLetsIconFallBackToSleeping() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(#"{"cat":{"state":"investigating","label":"正在调查","message":"这是未来状态。"}}"#, in: workspaceURL)

    let result = StatusReader().read(workspaceURL: workspaceURL)

    XCTAssertEqual(result.catState, "investigating")
    XCTAssertEqual(JumaoMenuBarIcon.assetName(for: result.catState), "JumaoSleepingTemplate")
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-status-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: workspaceURL)
    }
    return workspaceURL
  }

  private func writeStatus(_ contents: String, in workspaceURL: URL) throws {
    let directoryURL = workspaceURL.appendingPathComponent(".jumao", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try contents.write(
      to: directoryURL.appendingPathComponent("status.json"),
      atomically: true,
      encoding: .utf8
    )
  }

  private let fullStatusJSON = #"""
  {
    "schemaVersion": "0.2.3",
    "jumaoVersion": "0.2.4",
    "updatedAt": "2026-07-10T10:00:00Z",
    "workspace": { "name": "AI Note", "path": "/tmp/ai-note" },
    "cat": {
      "state": "packed",
      "label": "任务包已生成",
      "message": "任务包已生成，但仍需先处理关键门禁。"
    },
    "agentBoard": {
      "triggeredAgentCount": 27,
      "activeGroupCount": 8,
      "blockedGroupCount": 6,
      "groups": [
        { "id": "direction_entity", "name": "方向与主体 Agent 组", "state": "triggered", "triggeredAgentCount": 1, "message": "" },
        { "id": "product_design", "name": "产品与设计 Agent 组", "state": "triggered", "triggeredAgentCount": 3, "message": "" },
        { "id": "tech_development", "name": "技术与开发 Agent 组", "state": "blocked", "triggeredAgentCount": 4, "message": "先补账号、服务端、密钥或构建边界" },
        { "id": "data_privacy", "name": "数据与隐私 Agent 组", "state": "blocked", "triggeredAgentCount": 5, "message": "先补数据保存、删除和第三方工具边界" },
        { "id": "compliance_health", "name": "合规与健康声明 Agent 组", "state": "blocked", "triggeredAgentCount": 4, "message": "先补合规、健康声明或证据边界" },
        { "id": "platform_qualification", "name": "上架与平台资质 Agent 组", "state": "blocked", "triggeredAgentCount": 5, "message": "先补发布、审核或平台材料" },
        { "id": "revenue_operations", "name": "收费与运营 Agent 组", "state": "blocked", "triggeredAgentCount": 3, "message": "先补收费、退款和对账规则" },
        { "id": "release_incident", "name": "发布与事故 Agent 组", "state": "blocked", "triggeredAgentCount": 2, "message": "先补测试、发布清单和回滚计划" }
      ]
    },
    "blockers": [
      { "title": "数据与隐私", "message": "先补数据保存和删除规则", "source": "governance/codex-agent-gates.md" },
      { "title": "发布材料", "message": "先补发布清单", "source": "governance/codex-agent-gates.md" },
      { "title": "账号边界", "message": "先补 SDK 说明", "source": "governance/codex-agent-gates.md" },
      { "title": "健康声明", "message": "先补风险提示", "source": "governance/codex-agent-gates.md" }
    ],
    "nextSafeTask": "先完成数据删除规则。",
    "artifacts": {
      "agentReport": "governance/agent-review-report.md",
      "agentFindings": "governance/agent-findings.json",
      "codexGates": "governance/codex-agent-gates.md",
      "latestTaskPack": "tasks/codex-task-pack.md"
    },
    "lastRun": { "command": "pack", "target": "codex", "ok": true }
  }
  """#
}
