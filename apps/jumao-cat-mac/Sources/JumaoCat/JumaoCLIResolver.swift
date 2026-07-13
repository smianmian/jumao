import Foundation

struct JumaoCLICommand: Equatable, Sendable {
  enum Source: Equatable, Sendable {
    case configured
    case bundled
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

  static func bundled(at runtimeURL: URL) -> JumaoCLICommand {
    JumaoCLICommand(
      source: .bundled,
      executableURL: runtimeURL.appendingPathComponent("node/node"),
      prefixArguments: [runtimeURL.appendingPathComponent("jumao/bin/jumao.js").path]
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
  case bundledRuntimeInvalid
  case globalVersionOutdated

  var userFacingMessage: String {
    switch self {
    case .bundledRuntimeInvalid:
      return "Jumao 内置运行时无效，请重新生成后重试。"
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
  private static let bundledRuntimeSchemaVersion = 1
  private static let bundledNodeVersion = "24.18.0"

  private let explicitCLIURL: URL?
  private let bundledRuntimeURL: URL?
  private let repositoryRootURL: URL?
  private let fileExists: @Sendable (URL) -> Bool
  private let isExecutable: @Sendable (URL) -> Bool
  private let runtimeArchitecture: @Sendable () -> String
  private let globalCapabilityChecker: any JumaoGlobalSchemaCapabilityChecking

  init(
    explicitCLIURL: URL? = JumaoCLIResolver.configuredCLIURL,
    bundledRuntimeURL: URL? = JumaoCLIResolver.bundledRuntimeURL,
    repositoryRootURL: URL? = JumaoCLIResolver.developmentRepositoryRootURL,
    fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
    isExecutable: @escaping @Sendable (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
    runtimeArchitecture: @escaping @Sendable () -> String = { JumaoCLIResolver.currentArchitecture() },
    globalCapabilityChecker: any JumaoGlobalSchemaCapabilityChecking = JumaoGlobalSchemaCapabilityChecker()
  ) {
    self.explicitCLIURL = explicitCLIURL
    self.bundledRuntimeURL = bundledRuntimeURL
    self.repositoryRootURL = repositoryRootURL
    self.fileExists = fileExists
    self.isExecutable = isExecutable
    self.runtimeArchitecture = runtimeArchitecture
    self.globalCapabilityChecker = globalCapabilityChecker
  }

  func resolve(completion: @escaping @MainActor @Sendable (JumaoCLIResolutionResult) -> Void) {
    if let explicitCLIURL {
      completion(.resolved(.configured(at: explicitCLIURL)))
      return
    }

    switch bundledRuntimeResolution() {
    case .resolved(let command):
      completion(.resolved(command))
      return
    case .invalid:
      completion(.failed(.bundledRuntimeInvalid))
      return
    case .unavailable:
      break
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

  private static var bundledRuntimeURL: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("BundledRuntime", isDirectory: true)
  }

  nonisolated private static func currentArchitecture() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unsupported"
    #endif
  }

  private static var developmentRepositoryRootURL: URL? {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
      url.deleteLastPathComponent()
    }
    return url
  }

  private func bundledRuntimeResolution() -> BundledRuntimeResolution {
    guard let bundledRuntimeURL else { return .unavailable }
    guard fileExists(bundledRuntimeURL) else { return .unavailable }

    let manifestURL = bundledRuntimeURL.appendingPathComponent("runtime-manifest.json")
    let nodeURL = bundledRuntimeURL.appendingPathComponent("node/node")
    let cliURL = bundledRuntimeURL.appendingPathComponent("jumao/bin/jumao.js")
    guard fileExists(manifestURL),
          isExecutable(nodeURL),
          fileExists(cliURL),
          let manifest = try? JSONDecoder().decode(BundledRuntimeManifest.self, from: Data(contentsOf: manifestURL)),
          manifest.schemaVersion == Self.bundledRuntimeSchemaVersion,
          manifest.nodeVersion == Self.bundledNodeVersion,
          manifest.architecture == runtimeArchitecture() else {
      return .invalid
    }

    return .resolved(.bundled(at: bundledRuntimeURL))
  }
}

private struct BundledRuntimeManifest: Decodable {
  let schemaVersion: Int
  let nodeVersion: String
  let architecture: String
}

private enum BundledRuntimeResolution {
  case unavailable
  case invalid
  case resolved(JumaoCLICommand)
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
