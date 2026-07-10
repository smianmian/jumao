import XCTest
@testable import JumaoCat

final class WorkspaceBookmarkStoreTests: XCTestCase {
  func testSavesAndRestoresWorkspaceBookmark() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let workspaceURL = try makeWorkspace()
    defer { try? FileManager.default.removeItem(at: workspaceURL) }
    let bookmarkKey = "workspace-bookmark"

    let writer = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: bookmarkKey)
    let savedURL = try writer.save(workspaceURL: workspaceURL)
    XCTAssertEqual(savedURL.standardizedFileURL, workspaceURL.standardizedFileURL)
    XCTAssertNotNil(defaults.data(forKey: bookmarkKey))
    writer.stopAccessingWorkspace()

    let reader = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: bookmarkKey)
    let restoredURL = reader.restore()
    XCTAssertEqual(restoredURL?.standardizedFileURL, workspaceURL.standardizedFileURL)
    reader.stopAccessingWorkspace()
  }

  func testInvalidBookmarkRestoresToNoWorkspace() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let bookmarkKey = "workspace-bookmark"
    defaults.set(Data([0x00, 0x01]), forKey: bookmarkKey)

    let store = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: bookmarkKey)
    XCTAssertNil(store.restore())
    XCTAssertNil(defaults.data(forKey: bookmarkKey))
  }

  private func makeDefaults() throws -> (UserDefaults, String) {
    let suiteName = "JumaoCatTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    return (defaults, suiteName)
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-bookmark-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    return workspaceURL
  }
}
