import XCTest
@testable import JumaoCat

final class WorkspaceFolderOpenerTests: XCTestCase {
  @MainActor
  func testOpenSelectedWorkspaceClearsError() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let opener = RecordingWorkspaceOpener(result: .opened)
    let appState = try makeAppState(workspaceURL: workspaceURL, opener: opener)
    defer { appState.shutdown() }

    appState.openWorkspaceInFinder()

    XCTAssertEqual(opener.openedURLs.map { $0.resolvingSymlinksInPath() }, [workspaceURL.resolvingSymlinksInPath()])
    XCTAssertNil(appState.workspaceOpenError)
  }

  @MainActor
  func testMissingWorkspaceShowsClearError() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let opener = RecordingWorkspaceOpener(result: .missingDirectory)
    let appState = try makeAppState(workspaceURL: workspaceURL, opener: opener)
    defer { appState.shutdown() }

    appState.openWorkspaceInFinder()

    XCTAssertEqual(opener.openedURLs.map { $0.resolvingSymlinksInPath() }, [workspaceURL.resolvingSymlinksInPath()])
    XCTAssertEqual(appState.workspaceOpenError, "项目目录不存在，无法在 Finder 中打开。")
  }

  @MainActor
  func testFinderFailureShowsClearError() throws {
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let opener = RecordingWorkspaceOpener(result: .failed)
    let appState = try makeAppState(workspaceURL: workspaceURL, opener: opener)
    defer { appState.shutdown() }

    appState.openWorkspaceInFinder()

    XCTAssertEqual(appState.workspaceOpenError, "无法在 Finder 中打开项目目录。")
  }

  @MainActor
  func testNoSelectedWorkspaceDoesNotTryToOpenFinder() {
    let opener = RecordingWorkspaceOpener(result: .opened)
    let appState = AppState(workspaceOpener: opener)

    appState.openWorkspaceInFinder()

    XCTAssertTrue(opener.openedURLs.isEmpty)
    XCTAssertNil(appState.workspaceOpenError)
  }

  func testFinderOpenerReportsMissingDirectory() {
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-missing-workspace-\(UUID().uuidString)")

    XCTAssertEqual(FinderWorkspaceOpener().open(workspaceURL: missingURL), .missingDirectory)
  }

  @MainActor
  private func makeAppState(
    workspaceURL: URL,
    opener: RecordingWorkspaceOpener
  ) throws -> AppState {
    let suiteName = "JumaoCatTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(workspaceBookmarkStore: bookmarkStore, workspaceOpener: opener)
    appState.loadSavedWorkspace()
    defaults.removePersistentDomain(forName: suiteName)
    return appState
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-folder-opener-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    return workspaceURL
  }
}

private final class RecordingWorkspaceOpener: WorkspaceOpening {
  private(set) var openedURLs: [URL] = []
  var result: WorkspaceOpenResult

  init(result: WorkspaceOpenResult) {
    self.result = result
  }

  func open(workspaceURL: URL) -> WorkspaceOpenResult {
    openedURLs.append(workspaceURL)
    return result
  }
}
