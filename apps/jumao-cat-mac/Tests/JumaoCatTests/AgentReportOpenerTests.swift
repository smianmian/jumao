import XCTest
@testable import JumaoCat

final class AgentReportOpenerTests: XCTestCase {
  @MainActor
  func testNoSelectedWorkspaceDisablesReportButton() {
    XCTAssertFalse(AppState().canOpenAgentReport)
  }

  @MainActor
  func testEmptyStatusReportDisablesReportButton() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try writeStatus(agentReport: "", in: workspaceURL)
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertFalse(appState.canOpenAgentReport)
  }

  func testOpensInternalRelativeReport() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let reportURL = try writeFile("governance/agent-review-report.md", in: workspaceURL)
    var openedURL: URL?
    let opener = FinderAgentReportOpener { url in
      openedURL = url
      return true
    }

    let result = opener.open(agentReportPath: "governance/agent-review-report.md", workspaceURL: workspaceURL)

    XCTAssertEqual(result, .opened)
    XCTAssertEqual(openedURL?.resolvingSymlinksInPath(), reportURL.resolvingSymlinksInPath())
  }

  func testAllowsInternalAbsoluteReportPath() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let reportURL = try writeFile("governance/agent-review-report.md", in: workspaceURL)
    let opener = FinderAgentReportOpener { _ in true }

    XCTAssertEqual(opener.open(agentReportPath: reportURL.path, workspaceURL: workspaceURL), .opened)
  }

  func testRejectsEmptyPath() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }

    XCTAssertEqual(FinderAgentReportOpener().open(agentReportPath: "  ", workspaceURL: workspaceURL), .emptyPath)
  }

  func testRejectsParentTraversalOutsideWorkspace() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }

    XCTAssertEqual(FinderAgentReportOpener().open(agentReportPath: "../outside.md", workspaceURL: workspaceURL), .outsideWorkspace)
  }

  func testRejectsExternalAbsolutePath() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let externalURL = FileManager.default.temporaryDirectory.appendingPathComponent("external-report.md")

    XCTAssertEqual(FinderAgentReportOpener().open(agentReportPath: externalURL.path, workspaceURL: workspaceURL), .outsideWorkspace)
  }

  func testRejectsSymlinkThatEscapesWorkspace() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let externalURL = try writeExternalFile()
    defer { try? FileManager.default.removeItem(at: externalURL) }
    let linkURL = workspaceURL.appendingPathComponent("governance/external-report.md")
    try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalURL)

    XCTAssertEqual(FinderAgentReportOpener().open(agentReportPath: "governance/external-report.md", workspaceURL: workspaceURL), .outsideWorkspace)
  }

  func testRejectsMissingReport() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }

    XCTAssertEqual(FinderAgentReportOpener().open(agentReportPath: "governance/missing.md", workspaceURL: workspaceURL), .missingFile)
  }

  func testRejectsDirectory() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    try FileManager.default.createDirectory(
      at: workspaceURL.appendingPathComponent("governance", isDirectory: true),
      withIntermediateDirectories: true
    )

    XCTAssertEqual(FinderAgentReportOpener().open(agentReportPath: "governance", workspaceURL: workspaceURL), .directory)
  }

  func testReportsFinderOpenFailure() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    _ = try writeFile("governance/agent-review-report.md", in: workspaceURL)
    let opener = FinderAgentReportOpener { _ in false }

    XCTAssertEqual(opener.open(agentReportPath: "governance/agent-review-report.md", workspaceURL: workspaceURL), .failed)
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-agent-report-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    return workspaceURL
  }

  private func writeFile(_ relativePath: String, in workspaceURL: URL) throws -> URL {
    let fileURL = workspaceURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "# Agent Report\n".write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  private func writeExternalFile() throws -> URL {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-external-report-\(UUID().uuidString).md")
    try "# External Report\n".write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
  }

  @MainActor
  private func makeAppState(workspaceURL: URL) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore)
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName)
  }

  private func writeStatus(agentReport: String, in workspaceURL: URL) throws {
    let statusURL = workspaceURL.appendingPathComponent(".jumao/status.json")
    try FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #"{"cat":{"state":"ready","label":"可以继续","message":"可以继续做一个小任务。"},"artifacts":{"agentReport":"\#(agentReport)"}}"#
      .write(to: statusURL, atomically: true, encoding: .utf8)
  }
}
