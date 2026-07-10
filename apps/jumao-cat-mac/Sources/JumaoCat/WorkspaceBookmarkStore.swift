import Foundation

final class WorkspaceBookmarkStore {
  private let defaults: UserDefaults
  private let bookmarkKey: String
  private var activeWorkspaceURL: URL?
  private var isAccessingSecurityScopedResource = false

  init(defaults: UserDefaults = .standard, bookmarkKey: String = "JumaoCat.SelectedWorkspaceBookmark") {
    self.defaults = defaults
    self.bookmarkKey = bookmarkKey
  }

  deinit {
    stopAccessingWorkspace()
  }

  func save(workspaceURL: URL) throws -> URL {
    let bookmark = try workspaceURL.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    defaults.set(bookmark, forKey: bookmarkKey)
    startAccessingWorkspace(workspaceURL)
    return workspaceURL
  }

  func restore() -> URL? {
    guard let bookmark = defaults.data(forKey: bookmarkKey) else {
      return nil
    }

    var isStale = false

    do {
      let workspaceURL = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        refreshBookmark(for: workspaceURL)
      }

      startAccessingWorkspace(workspaceURL)
      return workspaceURL
    } catch {
      clear()
      return nil
    }
  }

  func stopAccessingWorkspace() {
    guard let activeWorkspaceURL else { return }

    if isAccessingSecurityScopedResource {
      activeWorkspaceURL.stopAccessingSecurityScopedResource()
    }

    self.activeWorkspaceURL = nil
    isAccessingSecurityScopedResource = false
  }

  func clear() {
    stopAccessingWorkspace()
    defaults.removeObject(forKey: bookmarkKey)
  }

  private func startAccessingWorkspace(_ workspaceURL: URL) {
    if activeWorkspaceURL?.standardizedFileURL == workspaceURL.standardizedFileURL {
      return
    }

    stopAccessingWorkspace()
    activeWorkspaceURL = workspaceURL
    isAccessingSecurityScopedResource = workspaceURL.startAccessingSecurityScopedResource()
  }

  private func refreshBookmark(for workspaceURL: URL) {
    guard let bookmark = try? workspaceURL.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) else {
      return
    }

    defaults.set(bookmark, forKey: bookmarkKey)
  }
}
