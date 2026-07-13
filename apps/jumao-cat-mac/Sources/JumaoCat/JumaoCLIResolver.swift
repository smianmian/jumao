import Foundation

struct JumaoCLICommand: Equatable, Sendable {
  enum Source: Equatable, Sendable {
    case configured
    case repository
    case global
  }

  let source: Source
  let executableURL: URL
  let prefixArguments: [String]

  func arguments(for command: [String]) -> [String] {
    prefixArguments + command
  }

  static func configured(at url: URL, nodeExecutableURL: URL = defaultNodeExecutableURL) -> JumaoCLICommand {
    if url.pathExtension == "js" {
      return JumaoCLICommand(
        source: .configured,
        executableURL: nodeExecutableURL,
        prefixArguments: [url.path]
      )
    }

    return JumaoCLICommand(source: .configured, executableURL: url, prefixArguments: [])
  }

  static func repository(at url: URL, nodeExecutableURL: URL = defaultNodeExecutableURL) -> JumaoCLICommand {
    JumaoCLICommand(
      source: .repository,
      executableURL: nodeExecutableURL,
      prefixArguments: [url.path]
    )
  }

  static let global = JumaoCLICommand(
    source: .global,
    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
    prefixArguments: ["jumao"]
  )

  private static var defaultNodeExecutableURL: URL {
    let configuredPath = ProcessInfo.processInfo.environment["JUMAO_NODE_PATH"]
    let candidates = [configuredPath, "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
      .compactMap { $0 }
    let fileManager = FileManager.default
    let path = candidates.first { fileManager.isExecutableFile(atPath: $0) } ?? "/usr/bin/env"
    return URL(fileURLWithPath: path)
  }
}

enum JumaoCLIResolutionError: Equatable, Sendable {
  case globalVersionOutdated

  var userFacingMessage: String {
    switch self {
    case .globalVersionOutdated:
      return "当前安装的 Jumao 版本过旧，请更新后重试。"
    }
  }
}

enum JumaoCLIResolutionResult: Equatable, Sendable {
  case resolved(JumaoCLICommand)
  case failed(JumaoCLIResolutionError)
}

enum JumaoCLIErrorLog {
  nonisolated static func userMessage(from data: Data, fallback: String, operation: String) -> String {
    guard let text = String(data: data, encoding: .utf8) else {
      return fallback
    }

    let normalized = text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    if !normalized.isEmpty {
      NSLog("Jumao %@ stderr: %@", operation, normalized)
    }
    return fallback
  }
}

@MainActor
protocol JumaoCLIResolving: AnyObject {
  func resolve(completion: @escaping @MainActor @Sendable (JumaoCLIResolutionResult) -> Void)
}

@MainActor
final class FixedJumaoCLIResolver: JumaoCLIResolving {
  private let result: JumaoCLIResolutionResult

  init(_ result: JumaoCLIResolutionResult) {
    self.result = result
  }

  func resolve(completion: @escaping @MainActor @Sendable (JumaoCLIResolutionResult) -> Void) {
    completion(result)
  }
}

@MainActor
protocol JumaoGlobalSchemaCapabilityChecking: AnyObject {
  func check(completion: @escaping @MainActor @Sendable (Bool) -> Void)
}

@MainActor
final class JumaoCLIResolver: JumaoCLIResolving {
  private let explicitCLIURL: URL?
  private let repositoryRootURL: URL?
  private let fileExists: @Sendable (URL) -> Bool
  private let globalCapabilityChecker: any JumaoGlobalSchemaCapabilityChecking

  init(
    explicitCLIURL: URL? = JumaoCLIResolver.configuredCLIURL,
    repositoryRootURL: URL? = JumaoCLIResolver.developmentRepositoryRootURL,
    fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
    globalCapabilityChecker: any JumaoGlobalSchemaCapabilityChecking = JumaoGlobalSchemaCapabilityChecker()
  ) {
    self.explicitCLIURL = explicitCLIURL
    self.repositoryRootURL = repositoryRootURL
    self.fileExists = fileExists
    self.globalCapabilityChecker = globalCapabilityChecker
  }

  func resolve(completion: @escaping @MainActor @Sendable (JumaoCLIResolutionResult) -> Void) {
    if let explicitCLIURL {
      completion(.resolved(.configured(at: explicitCLIURL)))
      return
    }

    if let repositoryCLIURL = repositoryRootURL?.appendingPathComponent("bin/jumao.js"), fileExists(repositoryCLIURL) {
      completion(.resolved(.repository(at: repositoryCLIURL)))
      return
    }

    globalCapabilityChecker.check { isCompatible in
      completion(isCompatible ? .resolved(.global) : .failed(.globalVersionOutdated))
    }
  }

  private static var configuredCLIURL: URL? {
    guard let path = ProcessInfo.processInfo.environment["JUMAO_CLI_PATH"], !path.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  private static var developmentRepositoryRootURL: URL? {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url
  }
}

@MainActor
private final class JumaoGlobalSchemaCapabilityChecker: JumaoGlobalSchemaCapabilityChecking {
  func check(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = JumaoCLICommand.global.executableURL
    process.arguments = JumaoCLICommand.global.arguments(for: ["interview", "--schema"])
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.terminationHandler = { process in
      let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
      let standardErrorData = standardError.fileHandleForReading.readDataToEndOfFile()
      let isCompatible = process.terminationStatus == 0 && (try? JumaoInterviewSchemaLoader.decodeSchema(from: output)) != nil

      if !isCompatible, let standardErrorText = String(data: standardErrorData, encoding: .utf8), !standardErrorText.isEmpty {
        NSLog("Jumao global schema capability check failed: %@", standardErrorText)
      }

      Task { @MainActor in
        completion(isCompatible)
      }
    }

    do {
      try process.run()
    } catch {
      NSLog("Unable to start global Jumao schema capability check: %@", error.localizedDescription)
      completion(false)
    }
  }
}
