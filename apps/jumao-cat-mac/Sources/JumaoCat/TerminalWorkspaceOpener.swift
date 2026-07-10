import AppKit
import Foundation

enum TerminalWorkspaceOpenResult: Equatable, Sendable {
  case opened
  case missingDirectory
  case terminalUnavailable
  case failed
}

protocol TerminalWorkspaceOpening {
  func open(workspaceURL: URL, completion: @escaping @Sendable (TerminalWorkspaceOpenResult) -> Void)
}

final class MacTerminalWorkspaceOpener: TerminalWorkspaceOpening {
  private let terminalURLProvider: () -> URL?
  private let openTerminal: (URL, URL, @escaping @Sendable (Bool) -> Void) -> Void

  init(
    terminalURLProvider: @escaping () -> URL? = {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    },
    openTerminal: @escaping (URL, URL, @escaping @Sendable (Bool) -> Void) -> Void = { terminalURL, workspaceURL, completion in
      NSWorkspace.shared.open(
        [workspaceURL],
        withApplicationAt: terminalURL,
        configuration: NSWorkspace.OpenConfiguration()
      ) { _, error in
        completion(error == nil)
      }
    }
  ) {
    self.terminalURLProvider = terminalURLProvider
    self.openTerminal = openTerminal
  }

  func open(workspaceURL: URL, completion: @escaping @Sendable (TerminalWorkspaceOpenResult) -> Void) {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      completion(.missingDirectory)
      return
    }

    guard let terminalURL = terminalURLProvider() else {
      completion(.terminalUnavailable)
      return
    }

    openTerminal(terminalURL, workspaceURL) { didOpen in
      completion(didOpen ? .opened : .failed)
    }
  }
}
