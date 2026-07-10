import XCTest
@testable import JumaoCat

final class CodexTaskPackCopierTests: XCTestCase {
  @MainActor
  func testNoSelectedWorkspaceDisablesTaskPackCopyButton() {
    XCTAssertFalse(AppState().canCopyLatestTaskPack)
  }

  @MainActor
  func testEmptyStatusTaskPackDisablesCopyButton() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try writeStatus(latestTaskPack: "", in: workspaceURL)
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertFalse(appState.canCopyLatestTaskPack)
  }

  @MainActor
  func testSuccessfulTaskPackCopyShowsCopiedFeedback() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try writeStatus(latestTaskPack: "tasks/codex-task-pack.md", in: workspaceURL)
    let (appState, defaults, suiteName) = try makeAppState(
      workspaceURL: workspaceURL,
      taskPackCopier: StaticTaskPackCopier(result: .copied)
    )
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.copyLatestTaskPack()

    XCTAssertEqual(appState.taskPackCopyFeedback, "已复制")
    XCTAssertTrue(appState.taskPackCopySucceeded)
  }

  func testCopiesInternalRelativeUTF8TaskPack() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    _ = try writeTextFile("tasks/codex-task-pack.md", text: "# Codex Task Pack\n", in: workspaceURL)
    var copiedText: String?
    let copier = CodexTaskPackCopier { text in
      copiedText = text
      return true
    }

    let result = copier.copy(taskPackPath: "tasks/codex-task-pack.md", workspaceURL: workspaceURL)

    XCTAssertEqual(result, .copied)
    XCTAssertEqual(copiedText, "# Codex Task Pack\n")
  }

  func testAllowsInternalAbsoluteTaskPackPath() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let taskPackURL = try writeTextFile("tasks/codex-task-pack.md", text: "task", in: workspaceURL)
    let copier = CodexTaskPackCopier { _ in true }

    XCTAssertEqual(copier.copy(taskPackPath: taskPackURL.path, workspaceURL: workspaceURL), .copied)
  }

  func testRejectsEmptyPath() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: " ", workspaceURL: workspaceURL), .emptyPath)
  }

  func testRejectsPathTraversalOutsideWorkspace() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: "../outside.md", workspaceURL: workspaceURL), .outsideWorkspace)
  }

  func testRejectsExternalAbsolutePath() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let externalURL = FileManager.default.temporaryDirectory.appendingPathComponent("external-task-pack.md")

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: externalURL.path, workspaceURL: workspaceURL), .outsideWorkspace)
  }

  func testRejectsSymlinkThatEscapesWorkspace() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let externalURL = try writeExternalFile()
    defer { try? FileManager.default.removeItem(at: externalURL) }
    let linkURL = workspaceURL.appendingPathComponent("tasks/external.md")
    try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalURL)

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: "tasks/external.md", workspaceURL: workspaceURL), .outsideWorkspace)
  }

  func testRejectsMissingTaskPack() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: "tasks/missing.md", workspaceURL: workspaceURL), .missingFile)
  }

  func testRejectsDirectory() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try FileManager.default.createDirectory(
      at: workspaceURL.appendingPathComponent("tasks", isDirectory: true),
      withIntermediateDirectories: true
    )

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: "tasks", workspaceURL: workspaceURL), .directory)
  }

  func testRejectsTaskPackLargerThanFiveMegabytes() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let taskPackURL = workspaceURL.appendingPathComponent("tasks/large.md")
    try FileManager.default.createDirectory(at: taskPackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x61, count: CodexTaskPackCopier.maximumFileSize + 1).write(to: taskPackURL)

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: "tasks/large.md", workspaceURL: workspaceURL), .tooLarge)
  }

  func testRejectsNonUTF8TaskPack() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let taskPackURL = workspaceURL.appendingPathComponent("tasks/binary.md")
    try FileManager.default.createDirectory(at: taskPackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data([0xff, 0xfe]).write(to: taskPackURL)

    XCTAssertEqual(CodexTaskPackCopier().copy(taskPackPath: "tasks/binary.md", workspaceURL: workspaceURL), .invalidUTF8)
  }

  func testReportsPasteboardWriteFailure() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    _ = try writeTextFile("tasks/codex-task-pack.md", text: "task", in: workspaceURL)
    let copier = CodexTaskPackCopier { _ in false }

    XCTAssertEqual(copier.copy(taskPackPath: "tasks/codex-task-pack.md", workspaceURL: workspaceURL), .pasteboardFailed)
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-task-pack-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    return workspaceURL
  }

  private func writeTextFile(_ relativePath: String, text: String, in workspaceURL: URL) throws -> URL {
    let fileURL = workspaceURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  private func writeExternalFile() throws -> URL {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-external-task-pack-\(UUID().uuidString).md")
    try "external".write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  @MainActor
  private func makeAppState(
    workspaceURL: URL,
    taskPackCopier: any TaskPackCopying = CodexTaskPackCopier()
  ) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatTaskPackTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore, taskPackCopier: taskPackCopier)
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName)
  }

  private func writeStatus(latestTaskPack: String, in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let contents: [String: Any] = [
      "cat": [
        "state": "packed",
        "label": "任务包已生成",
        "message": "任务包已生成。"
      ],
      "artifacts": [
        "latestTaskPack": latestTaskPack
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: contents)
    try data.write(to: statusURL)
  }
}

private struct StaticTaskPackCopier: TaskPackCopying {
  let result: TaskPackCopyResult

  func copy(taskPackPath: String, workspaceURL: URL) -> TaskPackCopyResult {
    result
  }
}
