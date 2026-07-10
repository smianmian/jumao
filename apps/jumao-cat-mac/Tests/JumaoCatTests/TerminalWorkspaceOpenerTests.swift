import XCTest
@testable import JumaoCat

final class TerminalWorkspaceOpenerTests: XCTestCase {
  func testPassesWorkspaceToMacOSTerminal() throws {
    let workspaceURL = try makeWorkspace(withJumaoDirectory: false)
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    var launchedTerminalURL: URL?
    var openedWorkspaceURL: URL?
    let opener = MacTerminalWorkspaceOpener(
      terminalURLProvider: { terminalURL },
      openTerminal: { applicationURL, directoryURL, completion in
        launchedTerminalURL = applicationURL
        openedWorkspaceURL = directoryURL
        completion(true)
      }
    )
    let result = TerminalOpenResultRecorder()

    opener.open(workspaceURL: workspaceURL) { result.set($0) }

    XCTAssertEqual(launchedTerminalURL, terminalURL)
    XCTAssertEqual(openedWorkspaceURL?.resolvingSymlinksInPath(), workspaceURL.resolvingSymlinksInPath())
    XCTAssertEqual(result.value, .opened)
  }

  func testReportsMissingWorkspaceDirectory() {
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-missing-terminal-workspace-\(UUID().uuidString)")
    let opener = MacTerminalWorkspaceOpener(
      terminalURLProvider: { nil },
      openTerminal: { _, _, _ in XCTFail("不应尝试打开终端") }
    )
    let result = TerminalOpenResultRecorder()

    opener.open(workspaceURL: missingURL) { result.set($0) }

    XCTAssertEqual(result.value, .missingDirectory)
  }

  @MainActor
  func testNoSelectedWorkspaceDisablesTerminalButton() {
    XCTAssertFalse(AppState().canOpenTerminal)
  }

  @MainActor
  func testWorkspaceWithoutJumaoDirectoryDisablesTerminalButton() throws {
    let workspaceURL = try makeWorkspace(withJumaoDirectory: false)
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertFalse(appState.canOpenTerminal)
  }

  @MainActor
  func testOpenTerminalUsesCurrentWorkspace() async throws {
    let workspaceURL = try makeWorkspace(withJumaoDirectory: true)
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let opener = RecordingTerminalWorkspaceOpener(result: .opened)
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL, terminalWorkspaceOpener: opener)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.openWorkspaceInTerminal()
    await waitForTerminalOpenToFinish(in: appState)

    XCTAssertEqual(
      opener.openedWorkspaceURLs.map { $0.resolvingSymlinksInPath() },
      [workspaceURL.resolvingSymlinksInPath()]
    )
    XCTAssertNil(appState.terminalOpenError)
  }

  @MainActor
  func testTerminalFailureShowsClearError() async throws {
    let workspaceURL = try makeWorkspace(withJumaoDirectory: true)
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let opener = RecordingTerminalWorkspaceOpener(result: .failed)
    let (appState, defaults, suiteName) = try makeAppState(workspaceURL: workspaceURL, terminalWorkspaceOpener: opener)
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.openWorkspaceInTerminal()
    await waitForTerminalOpenToFinish(in: appState)

    XCTAssertEqual(appState.terminalOpenError, "无法打开 macOS 终端。")
  }

  private func makeWorkspace(withJumaoDirectory: Bool) throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-terminal-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

    if withJumaoDirectory {
      try FileManager.default.createDirectory(
        at: workspaceURL.appendingPathComponent(".jumao", isDirectory: true),
        withIntermediateDirectories: true
      )
    }

    return workspaceURL
  }

  @MainActor
  private func makeAppState(
    workspaceURL: URL,
    terminalWorkspaceOpener: any TerminalWorkspaceOpening = RecordingTerminalWorkspaceOpener(result: .opened)
  ) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatTerminalTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      terminalWorkspaceOpener: terminalWorkspaceOpener
    )
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName)
  }

  @MainActor
  private func waitForTerminalOpenToFinish(in appState: AppState) async {
    for _ in 0..<10 {
      if !appState.isOpeningTerminal {
        return
      }
      await Task.yield()
    }

    XCTFail("终端没有完成打开")
  }
}

private final class RecordingTerminalWorkspaceOpener: TerminalWorkspaceOpening {
  private(set) var openedWorkspaceURLs: [URL] = []
  let result: TerminalWorkspaceOpenResult

  init(result: TerminalWorkspaceOpenResult) {
    self.result = result
  }

  func open(workspaceURL: URL, completion: @escaping @Sendable (TerminalWorkspaceOpenResult) -> Void) {
    openedWorkspaceURLs.append(workspaceURL)
    completion(result)
  }
}

private final class TerminalOpenResultRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: TerminalWorkspaceOpenResult?

  var value: TerminalWorkspaceOpenResult? {
    lock.withLock { storedValue }
  }

  func set(_ value: TerminalWorkspaceOpenResult) {
    lock.withLock {
      storedValue = value
    }
  }
}
