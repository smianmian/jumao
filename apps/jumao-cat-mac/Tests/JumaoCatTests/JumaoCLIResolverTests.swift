import XCTest
@testable import JumaoCat

@MainActor
final class JumaoCLIResolverTests: XCTestCase {
  func testRepositoryCLIIsPreferredOverGlobalCLI() {
    let repositoryRoot = URL(fileURLWithPath: "/tmp/jumao-repository")
    let repositoryCLIURL = repositoryRoot.appendingPathComponent("bin/jumao.js")
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = JumaoCLIResolver(
      repositoryRootURL: repositoryRoot,
      fileExists: { $0 == repositoryCLIURL },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.repository(at: repositoryCLIURL)))
    XCTAssertEqual(capabilityChecker.checkCount, 0)
  }

  func testMissingRepositoryCLIFallsBackToCompatibleGlobalCLI() {
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = JumaoCLIResolver(
      repositoryRootURL: URL(fileURLWithPath: "/tmp/missing-jumao-repository"),
      fileExists: { _ in false },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.global))
    XCTAssertEqual(capabilityChecker.checkCount, 1)
  }

  func testIncompatibleGlobalCLIIsRejected() {
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: false)
    let resolver = JumaoCLIResolver(
      repositoryRootURL: nil,
      fileExists: { _ in false },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .failed(.globalVersionOutdated))
    XCTAssertEqual(
      JumaoCLIResolutionError.globalVersionOutdated.userFacingMessage,
      "当前安装的 Jumao 版本过旧，请更新后重试。"
    )
  }

  func testConfiguredCLIIsPreferredOverRepositoryCLI() {
    let configuredCLIURL = URL(fileURLWithPath: "/tmp/custom-jumao.js")
    let capabilityChecker = RecordingGlobalCapabilityChecker(result: true)
    let resolver = JumaoCLIResolver(
      explicitCLIURL: configuredCLIURL,
      repositoryRootURL: URL(fileURLWithPath: "/tmp/jumao-repository"),
      fileExists: { _ in true },
      globalCapabilityChecker: capabilityChecker
    )

    XCTAssertEqual(resolve(resolver), .resolved(.configured(at: configuredCLIURL)))
    XCTAssertEqual(capabilityChecker.checkCount, 0)
  }

  func testAllJumaoCommandsUseOneResolvedCommand() {
    let command = JumaoCLICommand.repository(at: URL(fileURLWithPath: "/tmp/jumao/bin/jumao.js"))
    let workspaceURL = URL(fileURLWithPath: "/tmp/project")
    let answersURL = URL(fileURLWithPath: "/tmp/answers.json")

    XCTAssertEqual(
      command.arguments(for: JumaoProjectInitializer.arguments(projectName: "项目", workspaceURL: workspaceURL)),
      ["/tmp/jumao/bin/jumao.js", "new", "项目", "--dir", "/tmp/project"]
    )
    XCTAssertEqual(
      command.arguments(for: JumaoInterviewSchemaLoader.arguments()),
      ["/tmp/jumao/bin/jumao.js", "interview", "--schema"]
    )
    XCTAssertEqual(
      command.arguments(for: JumaoInterviewAnswerWriter.arguments(workspaceURL: workspaceURL, answersURL: answersURL, force: false)),
      ["/tmp/jumao/bin/jumao.js", "interview", "/tmp/project", "--answers", "/tmp/answers.json"]
    )
    XCTAssertEqual(
      command.arguments(for: JumaoStrictCheckRunner.arguments(for: workspaceURL)),
      ["/tmp/jumao/bin/jumao.js", "check", "/tmp/project", "--strict"]
    )
    XCTAssertEqual(
      command.arguments(for: JumaoProjectInspector.arguments(for: workspaceURL)),
      ["/tmp/jumao/bin/jumao.js", "inspect", "/tmp/project", "--json"]
    )
    XCTAssertEqual(
      command.arguments(for: CodexTaskPackRunner.arguments(for: workspaceURL)),
      ["/tmp/jumao/bin/jumao.js", "pack", "/tmp/project", "--target", "codex"]
    )
  }

  private func resolve(_ resolver: any JumaoCLIResolving) -> JumaoCLIResolutionResult {
    var result: JumaoCLIResolutionResult?
    resolver.resolve { result = $0 }
    return try! XCTUnwrap(result)
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
