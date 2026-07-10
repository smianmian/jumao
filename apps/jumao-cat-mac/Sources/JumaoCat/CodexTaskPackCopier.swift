import AppKit
import Foundation

enum TaskPackCopyResult: Equatable {
  case copied
  case emptyPath
  case outsideWorkspace
  case missingFile
  case directory
  case notRegularFile
  case tooLarge
  case readFailed
  case invalidUTF8
  case pasteboardFailed
}

protocol TaskPackCopying {
  func copy(taskPackPath: String, workspaceURL: URL) -> TaskPackCopyResult
}

struct CodexTaskPackCopier: TaskPackCopying {
  static let maximumFileSize = 5 * 1024 * 1024

  private let writeText: (String) -> Bool

  init(writeText: @escaping (String) -> Bool = { text in
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }) {
    self.writeText = writeText
  }

  func copy(taskPackPath: String, workspaceURL: URL) -> TaskPackCopyResult {
    let path = taskPackPath.trimmingCharacters(in: .whitespacesAndNewlines)
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
    let resolvedTaskPackURL = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
    guard isInsideWorkspace(resolvedTaskPackURL, workspaceURL: resolvedWorkspaceURL) else {
      return .outsideWorkspace
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolvedTaskPackURL.path, isDirectory: &isDirectory) else {
      return .missingFile
    }

    guard !isDirectory.boolValue else {
      return .directory
    }

    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try FileManager.default.attributesOfItem(atPath: resolvedTaskPackURL.path)
    } catch {
      return .readFailed
    }

    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      return .notRegularFile
    }

    let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? -1
    guard fileSize >= 0 else {
      return .readFailed
    }
    guard fileSize <= Self.maximumFileSize else {
      return .tooLarge
    }

    let data: Data
    do {
      data = try Data(contentsOf: resolvedTaskPackURL)
    } catch {
      return .readFailed
    }

    guard data.count <= Self.maximumFileSize else {
      return .tooLarge
    }
    guard let text = String(data: data, encoding: .utf8) else {
      return .invalidUTF8
    }

    return writeText(text) ? .copied : .pasteboardFailed
  }

  private func isInsideWorkspace(_ fileURL: URL, workspaceURL: URL) -> Bool {
    let workspaceComponents = workspaceURL.pathComponents
    let fileComponents = fileURL.pathComponents
    return fileComponents.starts(with: workspaceComponents)
  }
}
