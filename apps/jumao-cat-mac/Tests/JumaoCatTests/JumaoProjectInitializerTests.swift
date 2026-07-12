import XCTest
@testable import JumaoCat

final class JumaoProjectInitializerTests: XCTestCase {
  func testUsesFixedNewArguments() {
    let workspaceURL = URL(fileURLWithPath: "/tmp/My Jumao App")

    XCTAssertEqual(
      JumaoProjectInitializer.arguments(projectName: "My Jumao App", workspaceURL: workspaceURL),
      ["jumao", "new", "My Jumao App", "--dir", "/tmp/My Jumao App"]
    )
  }

  @MainActor
  func testDetectsFilesThatNewMayOverwrite() throws {
    let workspaceURL = try makeWorkspace()
    let existingFile = workspaceURL.appendingPathComponent("product/product-brief.zh-CN.md")
    try FileManager.default.createDirectory(at: existingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("已有内容".utf8).write(to: existingFile)

    XCTAssertEqual(
      JumaoProjectInitializer().conflictingFiles(in: workspaceURL),
      ["product/product-brief.zh-CN.md"]
    )
  }

  @MainActor
  func testOrdinaryWorkspaceCanStartInitialization() throws {
    let workspaceURL = try makeWorkspace()
    let initializer = RecordingProjectInitializer()
    let (appState, defaults, suiteName) = try makeAppState(
      workspaceURL: workspaceURL,
      initializer: initializer
    )
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    XCTAssertTrue(appState.canInitializeProject)
    appState.requestProjectInitialization()
    XCTAssertTrue(appState.isProjectInitializationConfirmationPresented)

    appState.confirmProjectInitialization()

    XCTAssertFalse(appState.isProjectInitializationConfirmationPresented)
    XCTAssertEqual(initializer.projectNames, [workspaceURL.lastPathComponent])
    XCTAssertEqual(
      initializer.workspaceURLs.map { $0.resolvingSymlinksInPath().path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) },
      [workspaceURL.resolvingSymlinksInPath().path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
    )
  }

  @MainActor
  func testConflictsAreShownBeforeProcessRuns() throws {
    let workspaceURL = try makeWorkspace()
    let initializer = RecordingProjectInitializer(conflicts: ["README.md"])
    let (appState, defaults, suiteName) = try makeAppState(
      workspaceURL: workspaceURL,
      initializer: initializer
    )
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.requestProjectInitialization()
    appState.confirmProjectInitialization()

    XCTAssertTrue(appState.isProjectInitializationConflictPresented)
    XCTAssertEqual(appState.projectInitializationConflictMessage, "以下文件已存在，继续后可能被覆盖：\n\n- README.md")
    XCTAssertTrue(initializer.projectNames.isEmpty)

    appState.confirmProjectInitializationWithConflicts()
    XCTAssertEqual(initializer.projectNames, [workspaceURL.lastPathComponent])
  }

  @MainActor
  func testSuccessfulInitializationShowsNextStep() async throws {
    let workspaceURL = try makeWorkspace()
    let initializer = RecordingProjectInitializer()
    let (appState, defaults, suiteName) = try makeAppState(
      workspaceURL: workspaceURL,
      initializer: initializer
    )
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.requestProjectInitialization()
    appState.confirmProjectInitialization()
    initializer.complete(.succeeded)
    await Task.yield()

    XCTAssertFalse(appState.isInitializingProject)
    XCTAssertEqual(appState.projectInitializationMessage, "项目框架已建立\n下一步：回答项目问题")
    XCTAssertNil(appState.projectInitializationError)
  }

  @MainActor
  func testFailedInitializationShowsSimpleChineseError() async throws {
    let workspaceURL = try makeWorkspace()
    let initializer = RecordingProjectInitializer()
    let (appState, defaults, suiteName) = try makeAppState(
      workspaceURL: workspaceURL,
      initializer: initializer
    )
    defer {
      appState.shutdown()
      defaults.removePersistentDomain(forName: suiteName)
    }

    appState.requestProjectInitialization()
    appState.confirmProjectInitialization()
    initializer.complete(.failed(exitCode: 1, message: "无法创建文件"))
    await Task.yield()

    XCTAssertFalse(appState.isInitializingProject)
    XCTAssertEqual(appState.projectInitializationError, "项目建立失败（退出码 1）：无法创建文件")
  }

  @MainActor
  private func makeAppState(
    workspaceURL: URL,
    initializer: any JumaoProjectInitializing
  ) throws -> (AppState, UserDefaults, String) {
    let suiteName = "JumaoCatProjectInitializerTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      throw NSError(domain: "JumaoCatTests", code: 1)
    }
    let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults, bookmarkKey: "workspace-bookmark")
    _ = try bookmarkStore.save(workspaceURL: workspaceURL)
    let appState = AppState(
      workspaceBookmarkStore: bookmarkStore,
      projectInitializer: initializer
    )
    appState.loadSavedWorkspace()
    return (appState, defaults, suiteName)
  }

  private func makeWorkspace() throws -> URL {
    let workspaceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("jumao-cat-project-initializer-tests")
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: workspaceURL)
    }
    return workspaceURL
  }
}

@MainActor
private final class RecordingProjectInitializer: JumaoProjectInitializing {
  let conflicts: [String]
  private(set) var projectNames: [String] = []
  private(set) var workspaceURLs: [URL] = []
  private var completion: (@MainActor @Sendable (JumaoProjectInitializationResult) -> Void)?

  init(conflicts: [String] = []) {
    self.conflicts = conflicts
  }

  func conflictingFiles(in workspaceURL: URL) -> [String] {
    conflicts
  }

  func run(
    projectName: String,
    workspaceURL: URL,
    completion: @escaping @MainActor @Sendable (JumaoProjectInitializationResult) -> Void
  ) {
    projectNames.append(projectName)
    workspaceURLs.append(workspaceURL)
    self.completion = completion
  }

  func complete(_ result: JumaoProjectInitializationResult) {
    completion?(result)
  }
}
