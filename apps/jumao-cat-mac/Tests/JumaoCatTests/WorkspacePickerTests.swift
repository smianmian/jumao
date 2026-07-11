import AppKit
import XCTest
@testable import JumaoCat

final class WorkspacePickerTests: XCTestCase {
  @MainActor
  func testPanelAllowsAnySingleDirectoryWithoutFilteringNavigation() {
    let startingURL = FileManager.default.homeDirectoryForCurrentUser
    let panel = MacWorkspaceChooser().makePanel(startingAt: startingURL)

    XCTAssertEqual(panel.message, "选择你的项目文件夹")
    XCTAssertEqual(panel.directoryURL?.standardizedFileURL, startingURL.standardizedFileURL)
    XCTAssertFalse(panel.canChooseFiles)
    XCTAssertTrue(panel.canChooseDirectories)
    XCTAssertFalse(panel.allowsMultipleSelection)
    XCTAssertNil(panel.delegate)
    XCTAssertTrue(panel.allowedContentTypes.isEmpty)
  }

  @MainActor
  func testOrdinaryDirectoryWithoutStatusFileIsAccepted() throws {
    let workspaceURL = try makeWorkspace()
    let chooser = RecordingWorkspaceChooser(selectedURL: workspaceURL)
    let (appState, defaults, suiteName) = try makeAppState(chooser: chooser)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.chooseWorkspace()

    XCTAssertEqual(appState.workspaceURL?.standardizedFileURL, workspaceURL.standardizedFileURL)
    XCTAssertEqual(appState.status.label, "这个项目还没有完成检查")
    XCTAssertEqual(appState.status.projectReadiness, .waitingForCheck)
    XCTAssertEqual(chooser.startingURLs, [FileManager.default.homeDirectoryForCurrentUser])
  }

  @MainActor
  func testDirectoryWithStatusFileLoadsNormally() throws {
    let workspaceURL = try makeWorkspace()
    try writeStatus(in: workspaceURL)
    let chooser = RecordingWorkspaceChooser(selectedURL: workspaceURL)
    let (appState, defaults, suiteName) = try makeAppState(chooser: chooser)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.chooseWorkspace()

    XCTAssertEqual(appState.status.snapshot?.status.cat.state, "ready")
    XCTAssertEqual(appState.status.label, "准备完成")
  }

  @MainActor
  func testPreviousWorkspaceIsUsedAsPickerStartingLocation() throws {
    let previousWorkspaceURL = try makeWorkspace()
    let nextWorkspaceURL = try makeWorkspace()
    let chooser = RecordingWorkspaceChooser(selectedURL: nextWorkspaceURL)
    let (appState, defaults, suiteName) = try makeAppState(chooser: chooser)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    _ = try WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
      .save(workspaceURL: previousWorkspaceURL)
    appState.loadSavedWorkspace()
    appState.chooseWorkspace()

    XCTAssertEqual(
      chooser.startingURLs.map { $0.resolvingSymlinksInPath() },
      [previousWorkspaceURL.resolvingSymlinksInPath()]
    )
    XCTAssertEqual(appState.workspaceURL?.standardizedFileURL, nextWorkspaceURL.standardizedFileURL)
  }

  @MainActor
  private func makeAppState(
    chooser: RecordingWorkspaceChooser
  ) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    return (
      AppState(workspaceBookmarkStore: bookmarkStore, workspaceChooser: chooser),
      defaults,
      suiteName
    )
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-picker-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: workspaceURL)
    }
    return workspaceURL
  }

  private func writeStatus(in workspaceURL: URL) throws {
    let jumaoURL = workspaceURL.appendingPathComponent(".jumao", isDirectory: true)
    try FileManager.default.createDirectory(at: jumaoURL, withIntermediateDirectories: true)
    try #"{"cat":{"state":"ready","label":"可以继续","message":"可以继续做一个小任务。"}}"#
      .write(to: jumaoURL.appendingPathComponent("status.json"), atomically: true, encoding: .utf8)
  }
}

@MainActor
private final class RecordingWorkspaceChooser: WorkspaceChoosing {
  let selectedURL: URL?
  private(set) var startingURLs: [URL] = []

  init(selectedURL: URL?) {
    self.selectedURL = selectedURL
  }

  func chooseWorkspace(startingAt directoryURL: URL) -> URL? {
    startingURLs.append(directoryURL)
    return selectedURL
  }
}
