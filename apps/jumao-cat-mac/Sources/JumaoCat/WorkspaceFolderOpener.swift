import AppKit
import Foundation

enum WorkspaceOpenResult: Equatable {
  case opened
  case missingDirectory
  case failed
}

protocol WorkspaceOpening {
  func open(workspaceURL: URL) -> WorkspaceOpenResult
}

struct FinderWorkspaceOpener: WorkspaceOpening {
  func open(workspaceURL: URL) -> WorkspaceOpenResult {
    guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
      return .missingDirectory
    }

    return NSWorkspace.shared.open(workspaceURL) ? .opened : .failed
  }
}
