import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published private(set) var workspaceURL: URL?
  @Published private(set) var status: WorkspaceStatus = .unselected
  @Published private(set) var workspaceOpenError: String?
  @Published private(set) var agentReportOpenError: String?
  @Published private(set) var taskPackCopyFeedback: String?
  @Published private(set) var taskPackCopySucceeded = false
  @Published private(set) var isRegeneratingTaskPack = false
  @Published private(set) var taskPackGenerationError: String?
  @Published private(set) var isOpeningTerminal = false
  @Published private(set) var terminalOpenError: String?
  @Published private(set) var isInitializingProject = false
  @Published private(set) var projectInitializationMessage: String?
  @Published private(set) var projectInitializationError: String?
  @Published private(set) var isLoadingInterviewSchema = false
  @Published private(set) var interviewSchema: JumaoInterviewSchema?
  @Published private(set) var interviewSchemaError: String?
  @Published private(set) var interviewAnswers: [String: String] = [:]
  @Published private(set) var interviewCurrentQuestionIndex = 0
  @Published private(set) var interviewValidationMessage: String?
  @Published private(set) var isInterviewComplete = false
  @Published private(set) var isWritingInterviewAnswers = false
  @Published private(set) var interviewWriteMessage: String?
  @Published private(set) var interviewWriteError: String?
  @Published var isProjectInitializationConfirmationPresented = false
  @Published var isProjectInitializationConflictPresented = false
  @Published var isInterviewPresented = false
  @Published var isInterviewWriteConfirmationPresented = false
  @Published var isInterviewOverwriteConfirmationPresented = false

  private let statusReader = StatusReader()
  private let workspaceBookmarkStore: WorkspaceBookmarkStore
  private let workspaceChooser: any WorkspaceChoosing
  private let workspaceOpener: any WorkspaceOpening
  private let agentReportOpener: any AgentReportOpening
  private let taskPackCopier: any TaskPackCopying
  private let taskPackRunner: any CodexTaskPackRunning
  private let terminalWorkspaceOpener: any TerminalWorkspaceOpening
  private let projectInitializer: any JumaoProjectInitializing
  private let interviewSchemaLoader: any JumaoInterviewSchemaLoading
  private let interviewAnswerWriter: any JumaoInterviewAnswerWriting
  private let appTerminator: any AppTerminating
  private var projectInitializationConflicts: [String] = []
  private var interviewDocumentsToOverwrite: [String] = []
  private var taskPackCopyFeedbackToken = UUID()
  private lazy var statusWatcher = StatusFileWatcher { [weak self] in
    Task { @MainActor [weak self] in
      self?.refreshStatus()
    }
  }

  init(
    workspaceBookmarkStore: WorkspaceBookmarkStore = WorkspaceBookmarkStore(),
    workspaceChooser: any WorkspaceChoosing = MacWorkspaceChooser(),
    workspaceOpener: any WorkspaceOpening = FinderWorkspaceOpener(),
    agentReportOpener: any AgentReportOpening = FinderAgentReportOpener(),
    taskPackCopier: any TaskPackCopying = CodexTaskPackCopier(),
    taskPackRunner: any CodexTaskPackRunning = CodexTaskPackRunner(),
    terminalWorkspaceOpener: any TerminalWorkspaceOpening = MacTerminalWorkspaceOpener(),
    projectInitializer: any JumaoProjectInitializing = JumaoProjectInitializer(),
    interviewSchemaLoader: any JumaoInterviewSchemaLoading = JumaoInterviewSchemaLoader(),
    interviewAnswerWriter: any JumaoInterviewAnswerWriting = JumaoInterviewAnswerWriter(),
    appTerminator: any AppTerminating = MacAppTerminator()
  ) {
    self.workspaceBookmarkStore = workspaceBookmarkStore
    self.workspaceChooser = workspaceChooser
    self.workspaceOpener = workspaceOpener
    self.agentReportOpener = agentReportOpener
    self.taskPackCopier = taskPackCopier
    self.taskPackRunner = taskPackRunner
    self.terminalWorkspaceOpener = terminalWorkspaceOpener
    self.projectInitializer = projectInitializer
    self.interviewSchemaLoader = interviewSchemaLoader
    self.interviewAnswerWriter = interviewAnswerWriter
    self.appTerminator = appTerminator
  }

  var workspacePath: String {
    workspaceURL?.path ?? "还没有选择项目"
  }

  var projectName: String {
    if let name = status.snapshot?.status.workspace.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }

    return workspaceURL?.lastPathComponent ?? "Jumao Cat"
  }

  var statusFileModificationDate: Date? {
    status.snapshot?.fileModificationDate
  }

  var canOpenAgentReport: Bool {
    guard workspaceURL != nil, let reportPath = status.snapshot?.status.artifacts.agentReport else {
      return false
    }

    return !reportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canCopyLatestTaskPack: Bool {
    guard workspaceURL != nil, let taskPackPath = status.snapshot?.status.artifacts.latestTaskPack else {
      return false
    }

    return !taskPackPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canRegenerateTaskPack: Bool {
    !isRegeneratingTaskPack && hasValidWorkspace
  }

  var canOpenTerminal: Bool {
    !isOpeningTerminal && hasValidWorkspace
  }

  var canInitializeProject: Bool {
    guard !isInitializingProject,
          let workspaceURL,
          isDirectory(workspaceURL) else {
      return false
    }

    return projectInitializer.conflictingFiles(in: workspaceURL).count < JumaoProjectInitializer.targetFiles.count
  }

  var canAnswerProjectQuestions: Bool {
    workspaceURL != nil && !canInitializeProject && !isLoadingInterviewSchema
  }

  var interviewQuestions: [JumaoInterviewQuestion] {
    interviewSchema?.questions.sorted { $0.order < $1.order } ?? []
  }

  var interviewCurrentQuestion: JumaoInterviewQuestion? {
    guard interviewQuestions.indices.contains(interviewCurrentQuestionIndex) else { return nil }
    return interviewQuestions[interviewCurrentQuestionIndex]
  }

  var interviewCurrentQuestionNumber: Int {
    interviewCurrentQuestionIndex + 1
  }

  var canGoToPreviousInterviewQuestion: Bool {
    interviewCurrentQuestionIndex > 0
  }

  var isLastInterviewQuestion: Bool {
    !interviewQuestions.isEmpty && interviewCurrentQuestionIndex == interviewQuestions.count - 1
  }

  var interviewInputHint: String? {
    interviewCurrentQuestion?.inputType == "list" ? "请使用逗号分隔多个项目。" : nil
  }

  var interviewOverwriteMessage: String {
    let files = interviewDocumentsToOverwrite.map { "- \($0)" }.joined(separator: "\n")
    return "以下项目文档已有内容，确认后将覆盖：\n\n\(files)"
  }

  var projectInitializationConflictMessage: String {
    let files = projectInitializationConflicts.map { "- \($0)" }.joined(separator: "\n")
    return "以下文件已存在，继续后可能被覆盖：\n\n\(files)"
  }

  private var hasValidWorkspace: Bool {
    guard let workspaceURL else { return false }
    var isDirectory: ObjCBool = false
    let jumaoDirectoryURL = workspaceURL.appendingPathComponent(".jumao", isDirectory: true)
    return FileManager.default.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
      && FileManager.default.fileExists(atPath: jumaoDirectoryURL.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  func loadSavedWorkspace() {
    guard let workspaceURL = workspaceBookmarkStore.restore() else {
      self.workspaceURL = nil
      status = .unselected
      workspaceOpenError = nil
      agentReportOpenError = nil
      clearTaskPackCopyFeedback()
      taskPackGenerationError = nil
      terminalOpenError = nil
      clearProjectInitializationFeedback()
      return
    }

    activateWorkspace(workspaceURL)
  }

  func chooseWorkspace() {
    let startingURL = workspaceURL ?? FileManager.default.homeDirectoryForCurrentUser
    guard let url = workspaceChooser.chooseWorkspace(startingAt: startingURL) else {
      return
    }

    statusWatcher.stop()

    do {
      let securedWorkspaceURL = try workspaceBookmarkStore.save(workspaceURL: url)
      activateWorkspace(securedWorkspaceURL)
    } catch {
      workspaceURL = nil
      status = .failed("无法保存项目目录访问权限：\(error.localizedDescription)")
      workspaceOpenError = nil
      agentReportOpenError = nil
      clearTaskPackCopyFeedback()
      taskPackGenerationError = nil
      terminalOpenError = nil
      clearProjectInitializationFeedback()
    }
  }

  func refreshStatus() {
    guard let workspaceURL else {
      status = .unselected
      return
    }

    status = statusReader.read(workspaceURL: workspaceURL)
  }

  func openWorkspaceInFinder() {
    guard let workspaceURL else {
      return
    }

    agentReportOpenError = nil
    clearTaskPackCopyFeedback()

    switch workspaceOpener.open(workspaceURL: workspaceURL) {
    case .opened:
      workspaceOpenError = nil
    case .missingDirectory:
      workspaceOpenError = "项目目录不存在，无法在 Finder 中打开。"
    case .failed:
      workspaceOpenError = "无法在 Finder 中打开项目目录。"
    }
  }

  func openAgentReport() {
    guard let workspaceURL,
          let reportPath = status.snapshot?.status.artifacts.agentReport,
          !reportPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    workspaceOpenError = nil
    clearTaskPackCopyFeedback()

    switch agentReportOpener.open(agentReportPath: reportPath, workspaceURL: workspaceURL) {
    case .opened:
      agentReportOpenError = nil
    case .emptyPath:
      agentReportOpenError = "治理报告路径为空。"
    case .outsideWorkspace:
      agentReportOpenError = "治理报告必须位于当前项目目录内。"
    case .missingFile:
      agentReportOpenError = "治理报告文件不存在。"
    case .directory:
      agentReportOpenError = "治理报告路径指向的是目录，无法打开。"
    case .failed:
      agentReportOpenError = "无法打开治理报告。"
    }
  }

  func copyLatestTaskPack() {
    guard let workspaceURL,
          let taskPackPath = status.snapshot?.status.artifacts.latestTaskPack,
          !taskPackPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    workspaceOpenError = nil
    agentReportOpenError = nil

    switch taskPackCopier.copy(taskPackPath: taskPackPath, workspaceURL: workspaceURL) {
    case .copied:
      showCopiedTaskPackFeedback()
    case .emptyPath:
      showTaskPackCopyError("Codex 任务包路径为空。")
    case .outsideWorkspace:
      showTaskPackCopyError("Codex 任务包必须位于当前项目目录内。")
    case .missingFile:
      showTaskPackCopyError("Codex 任务包文件不存在。")
    case .directory:
      showTaskPackCopyError("Codex 任务包路径指向的是目录，无法复制。")
    case .notRegularFile:
      showTaskPackCopyError("Codex 任务包不是普通文件，无法复制。")
    case .tooLarge:
      showTaskPackCopyError("Codex 任务包超过 5 MB，无法复制。")
    case .readFailed:
      showTaskPackCopyError("无法读取 Codex 任务包。")
    case .invalidUTF8:
      showTaskPackCopyError("Codex 任务包不是 UTF-8 文本，无法复制。")
    case .pasteboardFailed:
      showTaskPackCopyError("无法写入剪贴板。")
    }
  }

  func regenerateCodexTaskPack() {
    guard canRegenerateTaskPack, let workspaceURL else {
      return
    }

    isRegeneratingTaskPack = true
    taskPackGenerationError = nil

    taskPackRunner.run(workspaceURL: workspaceURL) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishTaskPackGeneration(result)
      }
    }
  }

  func openWorkspaceInTerminal() {
    guard canOpenTerminal, let workspaceURL else {
      return
    }

    isOpeningTerminal = true
    terminalOpenError = nil

    terminalWorkspaceOpener.open(workspaceURL: workspaceURL) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishOpeningTerminal(result)
      }
    }
  }

  func requestProjectInitialization() {
    guard canInitializeProject else { return }
    projectInitializationError = nil
    isProjectInitializationConfirmationPresented = true
  }

  func confirmProjectInitialization() {
    isProjectInitializationConfirmationPresented = false
    guard canInitializeProject, let workspaceURL else { return }

    projectInitializationConflicts = projectInitializer.conflictingFiles(in: workspaceURL)
    if !projectInitializationConflicts.isEmpty {
      isProjectInitializationConflictPresented = true
      return
    }

    runProjectInitialization(in: workspaceURL)
  }

  func confirmProjectInitializationWithConflicts() {
    isProjectInitializationConflictPresented = false
    guard canInitializeProject, let workspaceURL else { return }
    runProjectInitialization(in: workspaceURL)
  }

  func answerProjectQuestions() {
    guard canAnswerProjectQuestions else { return }

    if interviewSchema != nil {
      isInterviewPresented = true
      return
    }

    isLoadingInterviewSchema = true
    interviewSchemaError = nil
    interviewSchemaLoader.run { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishLoadingInterviewSchema(result)
      }
    }
  }

  func shutdown() {
    statusWatcher.stop()
    workspaceBookmarkStore.stopAccessingWorkspace()
    taskPackRunner.cancel()
  }

  func quit() {
    shutdown()
    appTerminator.terminate()
  }

  func beginInterview(with schema: JumaoInterviewSchema) {
    interviewSchema = schema
    let validAnswerPaths = Set(schema.questions.map(\.answerPath))
    interviewAnswers = interviewAnswers.filter { validAnswerPaths.contains($0.key) }
    interviewCurrentQuestionIndex = min(interviewCurrentQuestionIndex, max(schema.questions.count - 1, 0))
    interviewValidationMessage = nil
    interviewWriteMessage = nil
    interviewWriteError = nil
    isInterviewPresented = true
  }

  func interviewAnswerBinding(for answerPath: String) -> Binding<String> {
    Binding(
      get: { self.interviewAnswers[answerPath] ?? "" },
      set: { self.updateInterviewAnswer($0, for: answerPath) }
    )
  }

  func updateInterviewAnswer(_ answer: String, for answerPath: String) {
    interviewAnswers[answerPath] = answer
    interviewValidationMessage = nil
    interviewWriteError = nil
  }

  func goToPreviousInterviewQuestion() {
    guard canGoToPreviousInterviewQuestion else { return }
    interviewCurrentQuestionIndex -= 1
    interviewValidationMessage = nil
  }

  @discardableResult
  func advanceInterviewQuestion() -> Bool {
    guard validateCurrentInterviewQuestion() else { return false }

    if isLastInterviewQuestion {
      isInterviewComplete = true
    } else {
      interviewCurrentQuestionIndex += 1
      interviewValidationMessage = nil
    }
    return true
  }

  func requestInterviewWrite() {
    guard isInterviewComplete, !isWritingInterviewAnswers, workspaceURL != nil else { return }
    interviewWriteError = nil
    isInterviewWriteConfirmationPresented = true
  }

  func confirmInterviewWrite() {
    isInterviewWriteConfirmationPresented = false
    guard let workspaceURL, let interviewSchema else { return }

    interviewDocumentsToOverwrite = interviewAnswerWriter.documentsWithContent(in: workspaceURL)
    if !interviewDocumentsToOverwrite.isEmpty {
      isInterviewOverwriteConfirmationPresented = true
      return
    }

    runInterviewWrite(in: workspaceURL, schema: interviewSchema, force: false)
  }

  func confirmInterviewOverwrite() {
    isInterviewOverwriteConfirmationPresented = false
    guard let workspaceURL, let interviewSchema else { return }
    runInterviewWrite(in: workspaceURL, schema: interviewSchema, force: true)
  }

  private func activateWorkspace(_ workspaceURL: URL) {
    statusWatcher.stop()
    self.workspaceURL = workspaceURL
    workspaceOpenError = nil
    agentReportOpenError = nil
    clearTaskPackCopyFeedback()
    taskPackGenerationError = nil
    terminalOpenError = nil
    clearProjectInitializationFeedback()
    refreshStatus()
    statusWatcher.start(watching: workspaceURL)
  }

  private func showCopiedTaskPackFeedback() {
    let token = UUID()
    taskPackCopyFeedbackToken = token
    taskPackCopyFeedback = "已复制"
    taskPackCopySucceeded = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      Task { @MainActor [weak self] in
        guard self?.taskPackCopyFeedbackToken == token else { return }
        self?.taskPackCopyFeedback = nil
        self?.taskPackCopySucceeded = false
      }
    }
  }

  private func showTaskPackCopyError(_ message: String) {
    taskPackCopyFeedbackToken = UUID()
    taskPackCopyFeedback = message
    taskPackCopySucceeded = false
  }

  private func clearTaskPackCopyFeedback() {
    taskPackCopyFeedbackToken = UUID()
    taskPackCopyFeedback = nil
    taskPackCopySucceeded = false
  }

  private func finishTaskPackGeneration(_ result: CodexTaskPackRunResult) {
    isRegeneratingTaskPack = false

    switch result {
    case .succeeded:
      taskPackGenerationError = nil
      refreshStatus()
    case .failed(let exitCode, let message):
      let code = exitCode.map(String.init) ?? "无法启动"
      taskPackGenerationError = "任务包生成失败（退出码 \(code)）：\(message)"
    }
  }

  private func finishOpeningTerminal(_ result: TerminalWorkspaceOpenResult) {
    isOpeningTerminal = false

    switch result {
    case .opened:
      terminalOpenError = nil
    case .missingDirectory:
      terminalOpenError = "项目目录不存在，无法打开终端。"
    case .terminalUnavailable:
      terminalOpenError = "找不到 macOS 终端。"
    case .failed:
      terminalOpenError = "无法打开 macOS 终端。"
    }
  }

  private func runProjectInitialization(in workspaceURL: URL) {
    isInitializingProject = true
    projectInitializationMessage = nil
    projectInitializationError = nil

    projectInitializer.run(projectName: workspaceURL.lastPathComponent, workspaceURL: workspaceURL) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishProjectInitialization(result)
      }
    }
  }

  private func finishProjectInitialization(_ result: JumaoProjectInitializationResult) {
    isInitializingProject = false

    switch result {
    case .succeeded:
      projectInitializationError = nil
      projectInitializationMessage = "项目框架已建立\n下一步：回答项目问题"
      refreshStatus()
    case .failed(let exitCode, let message):
      let code = exitCode.map(String.init) ?? "无法启动"
      projectInitializationError = "项目建立失败（退出码 \(code)）：\(message)"
    }
  }

  private func finishLoadingInterviewSchema(_ result: JumaoInterviewSchemaLoadResult) {
    isLoadingInterviewSchema = false

    switch result {
    case .succeeded(let schema):
      interviewSchemaError = nil
      beginInterview(with: schema)
    case .failed(let exitCode, let message):
      let code = exitCode.map(String.init) ?? "无法启动"
      interviewSchema = nil
      interviewSchemaError = "读取项目问题失败（退出码 \(code)）：\(message)"
    }
  }

  private func runInterviewWrite(in workspaceURL: URL, schema: JumaoInterviewSchema, force: Bool) {
    isWritingInterviewAnswers = true
    interviewWriteMessage = nil
    interviewWriteError = nil

    interviewAnswerWriter.run(
      workspaceURL: workspaceURL,
      questions: schema.questions,
      answers: interviewAnswers,
      force: force
    ) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishInterviewWrite(result)
      }
    }
  }

  private func finishInterviewWrite(_ result: JumaoInterviewAnswerWriteResult) {
    isWritingInterviewAnswers = false

    switch result {
    case .succeeded:
      interviewWriteError = nil
      interviewWriteMessage = "项目问题已写入\n下一步：开始检查"
      interviewAnswers = [:]
    case .failed(let exitCode, let message):
      let code = exitCode.map(String.init) ?? "无法启动"
      interviewWriteError = "写入项目问题失败（退出码 \(code)）：\(message)"
    }
  }

  private func clearProjectInitializationFeedback() {
    isInitializingProject = false
    projectInitializationMessage = nil
    projectInitializationError = nil
    isProjectInitializationConfirmationPresented = false
    isProjectInitializationConflictPresented = false
    projectInitializationConflicts = []
    isLoadingInterviewSchema = false
    interviewSchema = nil
    interviewSchemaError = nil
    interviewAnswers = [:]
    interviewCurrentQuestionIndex = 0
    interviewValidationMessage = nil
    isInterviewComplete = false
    isWritingInterviewAnswers = false
    interviewWriteMessage = nil
    interviewWriteError = nil
    isInterviewWriteConfirmationPresented = false
    isInterviewOverwriteConfirmationPresented = false
    interviewDocumentsToOverwrite = []
    isInterviewPresented = false
  }

  private func validateCurrentInterviewQuestion() -> Bool {
    guard let question = interviewCurrentQuestion else { return false }
    guard question.required else { return true }
    guard !(interviewAnswers[question.answerPath] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      interviewValidationMessage = "请先填写这道必填问题。"
      return false
    }
    return true
  }

  private func isDirectory(_ url: URL) -> Bool {
    var directory = ObjCBool(false)
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
  }
}
