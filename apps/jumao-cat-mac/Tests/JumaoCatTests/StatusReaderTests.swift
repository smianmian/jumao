import XCTest
@testable import JumaoCat

final class StatusReaderTests: XCTestCase {
  func testUnselectedWorkspaceUsesSleepingIcon() {
    XCTAssertEqual(WorkspaceStatus.unselected.catState, "sleeping")
    XCTAssertEqual(WorkspaceStatus.unselected.label, "还没有选择项目")
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
      "blockedGroupCount": 6
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
