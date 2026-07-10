import AppKit
import Foundation

enum AgentReportOpenResult: Equatable {
  case opened
  case emptyPath
  case outsideWorkspace
  case missingFile
  case directory
  case failed
}

protocol AgentReportOpening {
  func open(agentReportPath: String, workspaceURL: URL) -> AgentReportOpenResult
}

struct FinderAgentReportOpener: AgentReportOpening {
  private let openFile: (URL) -> Bool

  init(openFile: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
    self.openFile = openFile
  }

  func open(agentReportPath: String, workspaceURL: URL) -> AgentReportOpenResult {
    let path = agentReportPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      return .emptyPath
    }

    let candidateURL: URL
    if (path as NSString).isAbsolutePath {
      candidateURL = URL(fileURLWithPath: path)
    } else {
      candidateURL = workspaceURL.appendingPathComponent(path)
    }

    let resolvedWorkspaceURL = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedReportURL = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
    guard isInsideWorkspace(resolvedReportURL, workspaceURL: resolvedWorkspaceURL) else {
      return .outsideWorkspace
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolvedReportURL.path, isDirectory: &isDirectory) else {
      return .missingFile
    }

    guard !isDirectory.boolValue else {
      return .directory
    }

    return openFile(resolvedReportURL) ? .opened : .failed
  }

  private func isInsideWorkspace(_ fileURL: URL, workspaceURL: URL) -> Bool {
    let workspaceComponents = workspaceURL.pathComponents
    let fileComponents = fileURL.pathComponents
    return fileComponents.starts(with: workspaceComponents)
  }
}
