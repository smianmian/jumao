import XCTest
@testable import JumaoCat

final class StatusFileWatcherTests: XCTestCase {
  func testStatusFileChangeTriggersRefresh() throws {
    let workspaceURL = try makeWorkspace(withStatusFile: false, hasJumaoDirectory: false)
    let changed = expectation(description: "status file change")
    let watcher = StatusFileWatcher(debounceInterval: .milliseconds(50)) {
      changed.fulfill()
    }
    watcher.start(watching: workspaceURL)
    defer { watcher.stop() }

    try writeStatus(in: workspaceURL)
    wait(for: [changed], timeout: 2)
  }

  func testStatusFileModificationTriggersRefresh() throws {
    let workspaceURL = try makeWorkspace(withStatusFile: true)
    let changed = expectation(description: "status file modification")
    let watcher = StatusFileWatcher(debounceInterval: .milliseconds(50)) {
      changed.fulfill()
    }
    watcher.start(watching: workspaceURL)
    defer { watcher.stop() }

    try writeStatus(in: workspaceURL)
    wait(for: [changed], timeout: 2)
  }

  func testStatusFileDeletionTriggersRefreshAndReaderFallsBack() throws {
    let workspaceURL = try makeWorkspace(withStatusFile: true)
    let changed = expectation(description: "status file deletion")
    let watcher = StatusFileWatcher(debounceInterval: .milliseconds(50)) {
      changed.fulfill()
    }
    watcher.start(watching: workspaceURL)
    defer { watcher.stop() }

    try FileManager.default.removeItem(at: statusURL(in: workspaceURL))
    wait(for: [changed], timeout: 2)

    guard case .missingStatusFile = StatusReader().read(workspaceURL: workspaceURL) else {
      return XCTFail("Expected status to fall back after deletion.")
    }
  }

  func testSwitchingWorkspaceStopsOldListener() throws {
    let firstWorkspaceURL = try makeWorkspace(withStatusFile: true)
    let secondWorkspaceURL = try makeWorkspace(withStatusFile: true)
    let oldWorkspaceChanged = expectation(description: "old workspace must not notify")
    oldWorkspaceChanged.isInverted = true
    let newWorkspaceChanged = expectation(description: "new workspace change")
    var shouldExpectNewWorkspace = false
    let watcher = StatusFileWatcher(debounceInterval: .milliseconds(50)) {
      if shouldExpectNewWorkspace {
        newWorkspaceChanged.fulfill()
      } else {
        oldWorkspaceChanged.fulfill()
      }
    }
    watcher.start(watching: firstWorkspaceURL)
    watcher.start(watching: secondWorkspaceURL)
    defer { watcher.stop() }

    try writeStatus(in: firstWorkspaceURL)
    wait(for: [oldWorkspaceChanged], timeout: 0.3)

    shouldExpectNewWorkspace = true
    try writeStatus(in: secondWorkspaceURL)
    wait(for: [newWorkspaceChanged], timeout: 2)
  }

  private func makeWorkspace(withStatusFile: Bool, hasJumaoDirectory: Bool = true) throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-watcher-tests")
      .appendingPathComponent(UUID().uuidString)
    let directoryURL = workspaceURL.appendingPathComponent(".jumao", isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    if hasJumaoDirectory {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
    if withStatusFile {
      try writeStatus(in: workspaceURL)
    }
    addTeardownBlock {
      try? FileManager.default.removeItem(at: workspaceURL)
    }
    return workspaceURL
  }

  private func statusURL(in workspaceURL: URL) -> URL {
    workspaceURL.appendingPathComponent(".jumao/status.json")
  }

  private func writeStatus(in workspaceURL: URL) throws {
    try FileManager.default.createDirectory(
      at: workspaceURL.appendingPathComponent(".jumao", isDirectory: true),
      withIntermediateDirectories: true
    )
    try #"{"cat":{"state":"ready","label":"可以继续","message":"可以继续做一个小任务。"}}"#
      .write(to: statusURL(in: workspaceURL), atomically: true, encoding: .utf8)
  }
}
