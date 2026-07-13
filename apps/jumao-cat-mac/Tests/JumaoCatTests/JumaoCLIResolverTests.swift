import XCTest
@testable import JumaoCat

@MainActor
final class JumaoCLIResolverTests: XCTestCase {
  func testBundleRuntimeIsPreferredOverRepositoryAndGlobalCLI() throws {
    let runtime = try BundledRuntimeFixture()
    defer { runtime.cleanUp() }
    let repositoryRoot = URL(fileURLWithPath: "/tmp/jumao-repository")
    let runtimeURL = runtime.url
    let runtimePath = runtimeURL.path
    let repositoryCLIURL = repositoryRoot.appendingPathComponent("bin/jumao.js")
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = makeResolver(
      bundledRuntimeURL: runtimeURL,
      repositoryRootURL: repositoryRoot,
      fileExists: { url in url == runtimeURL || url.path.hasPrefix(runtimePath) || url == repositoryCLIURL },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.bundled(at: runtimeURL)))
    XCTAssertEqual(capabilityChecker.checkCount, 0)
  }

  func testApplicationBundleUsesBundledRuntime() {
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = JumaoCLIResolver(
      explicitCLIURL: nil,
      repositoryRootURL: nil,
      globalCapabilityChecker: capabilityChecker
    )

    guard case .resolved(let command) = resolve(resolver) else {
      return XCTFail("应用 Bundle 中的内置运行时未被解析")
    }
    XCTAssertEqual(command.source, .bundled)
    XCTAssertEqual(capabilityChecker.checkCount, 0)
  }

  func testManifestArchitectureMismatchIsRejected() throws {
    let runtime = try BundledRuntimeFixture(architecture: "x86_64")
    defer { runtime.cleanUp() }

    XCTAssertEqual(resolve(makeResolver(bundledRuntimeURL: runtime.url)), .failed(.bundledRuntimeInvalid))
  }

  func testMissingBundledNodeIsRejected() throws {
    let runtime = try BundledRuntimeFixture(includeNode: false)
    defer { runtime.cleanUp() }

    XCTAssertEqual(resolve(makeResolver(bundledRuntimeURL: runtime.url)), .failed(.bundledRuntimeInvalid))
  }

  func testNonExecutableBundledNodeIsRejected() throws {
    let runtime = try BundledRuntimeFixture(nodeIsExecutable: false)
    defer { runtime.cleanUp() }

    XCTAssertEqual(resolve(makeResolver(bundledRuntimeURL: runtime.url)), .failed(.bundledRuntimeInvalid))
  }

  func testMissingBundledCLIIsRejected() throws {
    let runtime = try BundledRuntimeFixture(includeCLI: false)
    defer { runtime.cleanUp() }

    XCTAssertEqual(resolve(makeResolver(bundledRuntimeURL: runtime.url)), .failed(.bundledRuntimeInvalid))
  }

  func testCorruptedBundledManifestFailsSafely() throws {
    let runtime = try BundledRuntimeFixture()
    defer { runtime.cleanUp() }
    try Data("not json".utf8).write(to: runtime.url.appendingPathComponent("runtime-manifest.json"))

    XCTAssertEqual(resolve(makeResolver(bundledRuntimeURL: runtime.url)), .failed(.bundledRuntimeInvalid))
    XCTAssertEqual(
      JumaoCLIResolutionError.bundledRuntimeInvalid.userFacingMessage,
      "Jumao 内置运行时无效，请重新生成后重试。"
    )
  }

  func testMissingBundleRuntimeFallsBackToRepositoryCLI() {
    let repositoryRoot = URL(fileURLWithPath: "/tmp/jumao-repository")
    let repositoryCLIURL = repositoryRoot.appendingPathComponent("bin/jumao.js")
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = makeResolver(
      bundledRuntimeURL: URL(fileURLWithPath: "/tmp/missing-bundled-runtime"),
      repositoryRootURL: repositoryRoot,
      fileExists: { $0 == repositoryCLIURL },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.repository(at: repositoryCLIURL)))
    XCTAssertEqual(capabilityChecker.checkCount, 0)
  }

  func testMissingBundleAndRepositoryFallsBackToCompatibleGlobalCLI() {
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = makeResolver(
      bundledRuntimeURL: nil,
      repositoryRootURL: URL(fileURLWithPath: "/tmp/missing-jumao-repository"),
      fileExists: { _ in false },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.global))
    XCTAssertEqual(capabilityChecker.checkCount, 1)
  }

  func testConfiguredCLIIsPreferredOverBundledRuntime() throws {
    let runtime = try BundledRuntimeFixture()
    defer { runtime.cleanUp() }
    let configuredCLIURL = URL(fileURLWithPath: "/tmp/custom-jumao.js")
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = makeResolver(
      explicitCLIURL: configuredCLIURL,
      bundledRuntimeURL: runtime.url,
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.configured(at: configuredCLIURL)))
    XCTAssertEqual(capabilityChecker.checkCount, 0)
  }

  func testIncompatibleGlobalCLIIsRejected() {
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: false)
    let resolver = makeResolver(
      bundledRuntimeURL: nil,
      repositoryRootURL: nil,
      fileExists: { _ in false },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .failed(.globalVersionOutdated))
  }

  func testAllJumaoCommandsUseBundledNodeAndCLI() throws {
    let runtime = try BundledRuntimeFixture()
    defer { runtime.cleanUp() }
    let workspaceURL = URL(fileURLWithPath: "/tmp/project")
    let answersURL = URL(fileURLWithPath: "/tmp/answers.json")
    let command = try XCTUnwrap(resolvedCommand(makeResolver(bundledRuntimeURL: runtime.url)))
    let expectedPrefix = [runtime.url.appendingPathComponent("jumao/bin/jumao.js").path]

    XCTAssertEqual(command.source, .bundled)
    XCTAssertEqual(command.executableURL, runtime.url.appendingPathComponent("node/node"))
    XCTAssertEqual(command.prefixArguments, expectedPrefix)
    XCTAssertEqual(
      command.arguments(for: JumaoProjectInitializer.arguments(projectName: "项目", workspaceURL: workspaceURL)),
      expectedPrefix + ["new", "项目", "--dir", "/tmp/project"]
    )
    XCTAssertEqual(command.arguments(for: JumaoInterviewSchemaLoader.arguments()), expectedPrefix + ["interview", "--schema"])
    XCTAssertEqual(
      command.arguments(for: JumaoInterviewAnswerWriter.arguments(workspaceURL: workspaceURL, answersURL: answersURL, force: false)),
      expectedPrefix + ["interview", "/tmp/project", "--answers", "/tmp/answers.json"]
    )
    XCTAssertEqual(command.arguments(for: JumaoStrictCheckRunner.arguments(for: workspaceURL)), expectedPrefix + ["check", "/tmp/project", "--strict"])
    XCTAssertEqual(command.arguments(for: JumaoProjectInspector.arguments(for: workspaceURL)), expectedPrefix + ["inspect", "/tmp/project", "--json"])
    XCTAssertEqual(command.arguments(for: CodexTaskPackRunner.arguments(for: workspaceURL)), expectedPrefix + ["pack", "/tmp/project", "--target", "codex"])
  }

  private func makeResolver(
    explicitCLIURL: URL? = nil,
    bundledRuntimeURL: URL?,
    repositoryRootURL: URL? = nil,
    fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
    globalCapabilityChecker: any JumaoGlobalSchemaCapabilityChecking = RecordingGlobalCapabilityChecker(result: false)
  ) -> JumaoCLIResolver {
    JumaoCLIResolver(
      explicitCLIURL: explicitCLIURL,
      bundledRuntimeURL: bundledRuntimeURL,
      repositoryRootURL: repositoryRootURL,
      fileExists: fileExists,
      runtimeArchitecture: { "arm64" },
      globalCapabilityChecker: globalCapabilityChecker
    )
  }

  private func resolve(_ resolver: any JumaoCLIResolving) -> JumaoCLIResolutionResult {
    var result: JumaoCLIResolutionResult?
    resolver.resolve { result = $0 }
    return try! XCTUnwrap(result)
  }

  private func resolvedCommand(_ resolver: any JumaoCLIResolving) -> JumaoCLICommand? {
    guard case .resolved(let command) = resolve(resolver) else { return nil }
    return command
  }
}

private final class BundledRuntimeFixture {
  let rootURL: URL
  let url: URL

  init(
    schemaVersion: Int = 1,
    nodeVersion: String = "24.18.0",
    architecture: String = "arm64",
    includeNode: Bool = true,
    nodeIsExecutable: Bool = true,
    includeCLI: Bool = true
  ) throws {
    rootURL = FileManager.default.temporaryDirectory.appendingPathComponent("jumao-bundled-runtime-tests/\(UUID().uuidString)")
    url = rootURL.appendingPathComponent("BundledRuntime", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let manifest = """
    {"schemaVersion":\(schemaVersion),"nodeVersion":"\(nodeVersion)","jumaoVersion":"0.2.4","architecture":"\(architecture)"}
    """
    try Data(manifest.utf8).write(to: url.appendingPathComponent("runtime-manifest.json"))

    if includeNode {
      let nodeURL = url.appendingPathComponent("node/node")
      try FileManager.default.createDirectory(at: nodeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: nodeURL)
      try FileManager.default.setAttributes([.posixPermissions: nodeIsExecutable ? 0o555 : 0o644], ofItemAtPath: nodeURL.path)
    }

    if includeCLI {
      let cliURL = url.appendingPathComponent("jumao/bin/jumao.js")
      try FileManager.default.createDirectory(at: cliURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: cliURL)
    }
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: rootURL)
  }
}

@MainActor
private final class RecordingGlobalCapabilityChecker: JumaoGlobalSchemaCapabilityChecking {
  private let result: Bool
  private(set) var checkCount = 0

  init(result: Bool) {
    self.result = result
  }

  func check(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
    checkCount += 1
    completion(result)
  }
}
