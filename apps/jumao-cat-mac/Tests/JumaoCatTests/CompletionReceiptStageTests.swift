import XCTest
@testable import JumaoCat

final class CompletionReceiptStageTests: XCTestCase {
  private func data(_ json: String) -> Data {
    Data(json.utf8)
  }

  func testCompletedReceiptSurfacesCompletedStage() {
    let stage = CompletionReceiptStage.parse(data: data("""
    {"jumaoCompletion": {"status": "completed", "goalsCompleted": ["goal:login-flow"],
     "goalsBlocked": [], "validation": [{"command": "npm test", "exitCode": 0}],
     "productionEffects": false, "remainingWork": []}}
    """))
    XCTAssertEqual(stage.kind, .completed)
    XCTAssertEqual(stage.completedGoalIds, ["goal:login-flow"])
    XCTAssertTrue(stage.message.contains("不是"), "阶段文案保持「X。不是 Y。」防误读句式")
  }

  func testBareReceiptWithoutWrapperIsTolerated() {
    let stage = CompletionReceiptStage.parse(data: data("""
    {"status": "completed", "goalsCompleted": [], "goalsBlocked": [],
     "validation": [], "productionEffects": false, "remainingWork": []}
    """))
    XCTAssertEqual(stage.kind, .completed)
  }

  func testBlockedReceiptSurfacesBlockedStageWithReasons() {
    let stage = CompletionReceiptStage.parse(data: data("""
    {"jumaoCompletion": {"status": "blocked", "goalsCompleted": [],
     "goalsBlocked": [{"goalId": "goal:login-flow", "reason": "缺少登录范围确认"}],
     "validation": [], "productionEffects": false, "remainingWork": ["等待确认"]}}
    """))
    XCTAssertEqual(stage.kind, .blocked)
    XCTAssertEqual(stage.blockedReasons, ["goal:login-flow：缺少登录范围确认"])
    XCTAssertTrue(stage.message.contains("不是失败"))
  }

  func testMalformedReceiptSurfacesInvalidStage() {
    let stage = CompletionReceiptStage.parse(data: data("{\"jumaoCompletion\": {\"status\": \"completed\", "))
    XCTAssertEqual(stage.kind, .invalid)
  }

  func testReceiptMissingRequiredFieldsIsInvalid() {
    let stage = CompletionReceiptStage.parse(data: data("""
    {"jumaoCompletion": {"status": "completed", "goalsCompleted": "goal:x"}}
    """))
    XCTAssertEqual(stage.kind, .invalid)
  }

  func testLoadReturnsNilWithoutReceiptFile() throws {
    let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("jumao-receipt-stage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    XCTAssertNil(CompletionReceiptStage.load(workspaceURL: workspace))
  }

  func testLoadReadsReceiptFromWorkspace() throws {
    let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("jumao-receipt-stage-\(UUID().uuidString)", isDirectory: true)
    let receiptURL = workspace.appendingPathComponent(CompletionReceiptStage.receiptRelativePath)
    try FileManager.default.createDirectory(
      at: receiptURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data("""
    {"jumaoCompletion": {"status": "completed", "goalsCompleted": [], "goalsBlocked": [],
     "validation": [], "productionEffects": false, "remainingWork": []}}
    """).write(to: receiptURL)
    defer { try? FileManager.default.removeItem(at: workspace) }
    XCTAssertEqual(CompletionReceiptStage.load(workspaceURL: workspace)?.kind, .completed)
  }
}
