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
  @Published private(set) var isInspectingProject = false
  @Published private(set) var projectInspection: JumaoProjectInspection?
  @Published private(set) var projectInspectionError: String?
  @Published private(set) var interviewMode: ProjectInterviewMode?
  @Published private(set) var interviewInspectionContext: JumaoProjectInspection?
  @Published private(set) var isLoadingInterviewSchema = false
  @Published private(set) var interviewSchema: JumaoInterviewSchema?
  @Published private(set) var interviewSchemaError: String?
  @Published private(set) var interviewDraftError: String?
  @Published private(set) var interviewErrorDetails: String?
  @Published private(set) var interviewErrorDetailsCopiedMessage: String?
  @Published private(set) var interviewAnswers: [String: String] = [:]
  @Published private(set) var skippedInterviewAnswerPaths = Set<String>()
  @Published private(set) var interviewCurrentStageID: String?
  @Published private(set) var interviewCurrentQuestionIndex = 0
  @Published private(set) var isCurrentInterviewStageComplete = false
  @Published private(set) var interviewValidationMessage: String?
  @Published private(set) var isInterviewComplete = false
  @Published private(set) var isWritingInterviewAnswers = false
  @Published private(set) var interviewWriteMessage: String?
  @Published private(set) var interviewWriteError: String?
  @Published private(set) var isCheckingProject = false
  @Published private(set) var projectCheckMessage: String?
  @Published private(set) var projectCheckError: String?
  @Published private(set) var isGeneratingInterviewTaskPack = false
  @Published private(set) var interviewTaskPackMessage: String?
  @Published private(set) var interviewTaskPackError: String?
  @Published private(set) var hasPassedProjectCheck = false
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
  private let projectInspector: any JumaoProjectInspecting
  private let interviewSchemaLoader: any JumaoInterviewSchemaLoading
  private let interviewAnswerWriter: any JumaoInterviewAnswerWriting
  private let strictCheckRunner: any JumaoStrictChecking
  private let interviewDraftStore: any InterviewDraftStoring
  private let appTerminator: any AppTerminating
  private var projectInitializationConflicts: [String] = []
  private var interviewDocumentsToOverwrite: [String] = []
  private var taskPackCopyFeedbackToken = UUID()
  private var interviewDraftSaveTask: Task<Void, Never>?
  private var restoredInterviewDraftNeedsStageInference = false
  private var lastInterviewWriteUsedForce = false
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
    cliResolver: any JumaoCLIResolving = JumaoCLIResolver(),
    taskPackRunner: (any CodexTaskPackRunning)? = nil,
    terminalWorkspaceOpener: any TerminalWorkspaceOpening = MacTerminalWorkspaceOpener(),
    projectInitializer: (any JumaoProjectInitializing)? = nil,
    projectInspector: (any JumaoProjectInspecting)? = nil,
    interviewSchemaLoader: (any JumaoInterviewSchemaLoading)? = nil,
    interviewAnswerWriter: (any JumaoInterviewAnswerWriting)? = nil,
    strictCheckRunner: (any JumaoStrictChecking)? = nil,
    interviewDraftStore: any InterviewDraftStoring = InterviewDraftStore(),
    appTerminator: any AppTerminating = MacAppTerminator()
  ) {
    self.workspaceBookmarkStore = workspaceBookmarkStore
    self.workspaceChooser = workspaceChooser
    self.workspaceOpener = workspaceOpener
    self.agentReportOpener = agentReportOpener
    self.taskPackCopier = taskPackCopier
    self.taskPackRunner = taskPackRunner ?? CodexTaskPackRunner(resolver: cliResolver)
    self.terminalWorkspaceOpener = terminalWorkspaceOpener
    self.projectInitializer = projectInitializer ?? JumaoProjectInitializer(resolver: cliResolver)
    self.projectInspector = projectInspector ?? JumaoProjectInspector(resolver: cliResolver)
    self.interviewSchemaLoader = interviewSchemaLoader ?? JumaoInterviewSchemaLoader(resolver: cliResolver)
    self.interviewAnswerWriter = interviewAnswerWriter ?? JumaoInterviewAnswerWriter(resolver: cliResolver)
    self.strictCheckRunner = strictCheckRunner ?? JumaoStrictCheckRunner(resolver: cliResolver)
    self.interviewDraftStore = interviewDraftStore
    self.appTerminator = appTerminator
  }

  var workspacePath: String {
    workspaceURL?.path ?? "还没有选择项目"
  }

  var projectName: String {
    if let name = status.snapshot?.status.workspace.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    if let name = projectInspection?.project.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
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
    !isRegeneratingTaskPack && !isGeneratingInterviewTaskPack && hasValidWorkspace
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

  var shouldShowProjectInspection: Bool {
    workspaceURL != nil && status.snapshot == nil
  }

  var projectInspectionKindTitle: String? {
    switch projectInspection?.workspaceKind {
    case "empty": return "空文件夹"
    case "new": return "新项目资料"
    case "existing": return "已有项目"
    default: return nil
    }
  }

  var projectInspectionPrimaryActionTitle: String? {
    switch projectInspection?.workspaceKind {
    case "empty", "new": return "开始规划新项目"
    case "existing": return "开始梳理这次改动"
    default: return nil
    }
  }

  var projectInspectionPrimaryActionDescription: String? {
    switch projectInspection?.workspaceKind {
    case "empty", "new": return "先确认第一版要实现哪些功能。"
    case "existing": return "橘猫已经查看了项目结构，接下来只确认这次要修改什么。"
    default: return nil
    }
  }

  var projectInspectionCapabilityMessage: String? {
    guard let level = projectInspection?.capabilityFit.level else { return nil }
    switch level {
    case "high":
      return "橘猫对这个项目类型比较熟悉，当前更擅长 Swift、SwiftUI 与 Xcode 项目。"
    case "limited":
      return "橘猫目前更擅长 iOS 原生 App。这个项目仍然可以梳理，但部分建议和检查可能不完整。"
    default:
      return nil
    }
  }

  var canContinueFromProjectInspection: Bool {
    projectInspection != nil
  }

  var interviewWindowTitle: String {
    switch interviewMode {
    case .newProject: return "规划新项目"
    case .existingProject: return "梳理这次改动"
    case nil: return "回答项目问题"
    }
  }

  var interviewInspectionSummary: String? {
    guard interviewMode == .existingProject, let inspection = interviewInspectionContext else { return nil }
    var parts = [inspection.project.name].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if !inspection.project.platforms.isEmpty {
      parts.append(inspection.project.platforms.joined(separator: "、"))
    }
    if !inspection.project.languages.isEmpty {
      parts.append(inspection.project.languages.joined(separator: "、"))
    }
    return parts.isEmpty ? "已携带当前项目扫描结果。" : "已携带扫描结果：\(parts.joined(separator: " · "))"
  }

  var canRetryInterviewOperation: Bool {
    !isLoadingInterviewSchema && !isWritingInterviewAnswers
      && (interviewSchemaError != nil || interviewWriteError != nil || interviewDraftError != nil)
  }

  var hasUnfinishedInterviewDraft: Bool {
    (!interviewAnswers.isEmpty || !skippedInterviewAnswerPaths.isEmpty)
      && (!isInterviewComplete || !pendingInterviewQuestions.isEmpty)
  }

  var interviewStages: [JumaoInterviewStage] {
    interviewSchema?.stages.sorted { $0.order < $1.order } ?? []
  }

  var interviewQuestions: [JumaoInterviewQuestion] {
    guard let interviewSchema else { return [] }
    let stageOrder = Dictionary(uniqueKeysWithValues: interviewStages.map { ($0.id, $0.order) })
    let fallbackStageID = interviewStages.first?.id
    return interviewSchema.questions.sorted { left, right in
      let leftOrder = left.stage.flatMap { stageOrder[$0] } ?? fallbackStageID.flatMap { stageOrder[$0] } ?? Int.max
      let rightOrder = right.stage.flatMap { stageOrder[$0] } ?? fallbackStageID.flatMap { stageOrder[$0] } ?? Int.max
      return leftOrder == rightOrder ? left.order < right.order : leftOrder < rightOrder
    }
  }

  var currentInterviewStage: JumaoInterviewStage? {
    let stageID = interviewCurrentStageID ?? interviewStages.first?.id
    return interviewStages.first { $0.id == stageID }
  }

  var currentInterviewStageQuestions: [JumaoInterviewQuestion] {
    guard let stageID = currentInterviewStage?.id else { return [] }
    return interviewQuestions.filter { questionStageID(for: $0) == stageID }
  }

  var interviewCurrentQuestion: JumaoInterviewQuestion? {
    guard interviewQuestions.indices.contains(interviewCurrentQuestionIndex) else { return nil }
    return interviewQuestions[interviewCurrentQuestionIndex]
  }

  var interviewCurrentQuestionNumber: Int {
    guard let answerPath = interviewCurrentQuestion?.answerPath else { return 1 }
    return (currentInterviewStageQuestions.firstIndex { $0.answerPath == answerPath } ?? 0) + 1
  }

  var interviewCurrentStageQuestionCount: Int {
    currentInterviewStageQuestions.count
  }

  var canGoToPreviousInterviewQuestion: Bool {
    return interviewCurrentQuestionNumber > 1
      || currentInterviewStage.flatMap { stage in
        interviewStages.firstIndex(of: stage).map { $0 > 0 }
      } == true
  }

  var isLastInterviewQuestion: Bool {
    return !currentInterviewStageQuestions.isEmpty
      && interviewCurrentQuestion?.answerPath == currentInterviewStageQuestions.last?.answerPath
  }

  var pendingInterviewQuestions: [JumaoInterviewQuestion] {
    interviewQuestions.filter { question in
      question.required && !isMeaningfulInterviewAnswer(interviewAnswers[question.answerPath] ?? "")
    }
  }

  var pendingCurrentStageInterviewQuestions: [JumaoInterviewQuestion] {
    currentInterviewStageQuestions.filter { question in
      question.required && !isMeaningfulInterviewAnswer(interviewAnswers[question.answerPath] ?? "")
    }
  }

  var canWriteCompletedInterview: Bool {
    isInterviewComplete && pendingInterviewQuestions.isEmpty && !isWritingInterviewAnswers
  }

  var interviewResumeTitle: String {
    "继续第 \(currentInterviewStage?.order ?? 1) 阶段"
  }

  var hasNextInterviewStage: Bool {
    guard let currentInterviewStage,
          let index = interviewStages.firstIndex(of: currentInterviewStage) else { return false }
    return interviewStages.indices.contains(index + 1)
  }

  var interviewInputHint: String? {
    interviewCurrentQuestion?.inputType == "list" ? "请使用逗号分隔多个项目。" : nil
  }

  var interviewOverwriteMessage: String {
    let files = interviewDocumentsToOverwrite.map { "- \($0)" }.joined(separator: "\n")
    return "以下项目文档已有内容，确认后将覆盖：\n\n\(files)"
  }

  var canStartProjectCheck: Bool {
    !isFocusedProjectInterview && interviewWriteMessage != nil && !isCheckingProject && workspaceURL != nil
  }

  var isFocusedProjectInterview: Bool {
    interviewMode != nil || interviewQuestions.contains { question in
      question.answerPath.hasPrefix("newProject.") || question.answerPath.hasPrefix("existingProject.")
    }
  }

  var canGenerateInterviewTaskPack: Bool {
    hasPassedProjectCheck && !isGeneratingInterviewTaskPack && !isRegeneratingTaskPack && workspaceURL != nil
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

    saveInterviewDraftImmediately()
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
    if shouldShowProjectInspection {
      startProjectInspectionIfNeeded(in: workspaceURL)
    } else {
      clearProjectInspection()
    }
  }

  func rescanProject() {
    guard let workspaceURL, shouldShowProjectInspection, !isInspectingProject else { return }
    projectInspection = nil
    projectInspectionError = nil
    runProjectInspection(in: workspaceURL)
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

    isInterviewPresented = true
    loadInterviewSchema()
  }

  func startProjectInterview() {
    guard let inspection = projectInspection, workspaceURL != nil else { return }

    let mode: ProjectInterviewMode = inspection.recommendedIntake.mode == "existing_project"
      ? .existingProject
      : .newProject
    let previousMode = interviewMode
    if isInterviewPresented, interviewMode == mode {
      return
    }

    interviewMode = mode
    interviewInspectionContext = mode == .existingProject ? inspection : nil
    interviewSchemaError = nil
    interviewErrorDetails = nil
    interviewErrorDetailsCopiedMessage = nil
    isInterviewPresented = true

    if interviewSchema != nil, previousMode == mode {
      return
    }

    interviewSchema = nil
    loadInterviewSchema()
  }

  func retryInterviewOperation() {
    guard canRetryInterviewOperation else { return }

    if interviewSchemaError != nil {
      loadInterviewSchema()
    } else if interviewWriteError != nil,
              let workspaceURL,
              let interviewSchema {
      runInterviewWrite(in: workspaceURL, schema: interviewSchema, force: lastInterviewWriteUsedForce)
    } else if interviewDraftError != nil {
      saveInterviewDraftImmediately()
    }
  }

  func copyInterviewErrorDetails() {
    guard let interviewErrorDetails else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    interviewErrorDetailsCopiedMessage = pasteboard.setString(interviewErrorDetails, forType: .string)
      ? "错误详情已复制"
      : "无法复制错误详情"
  }

  private func loadInterviewSchema() {
    guard !isLoadingInterviewSchema else { return }
    isLoadingInterviewSchema = true
    interviewSchemaError = nil
    interviewErrorDetails = nil
    interviewErrorDetailsCopiedMessage = nil
    interviewSchemaLoader.run { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishLoadingInterviewSchema(result)
      }
    }
  }

  func shutdown() {
    saveInterviewDraftImmediately()
    interviewDraftSaveTask?.cancel()
    interviewDraftSaveTask = nil
    statusWatcher.stop()
    workspaceBookmarkStore.stopAccessingWorkspace()
    taskPackRunner.cancel()
    strictCheckRunner.cancel()
    projectInspector.cancel()
  }

  func quit() {
    shutdown()
    appTerminator.terminate()
  }

  func beginInterview(with schema: JumaoInterviewSchema) {
    interviewSchema = schema
    let validAnswerPaths = Set(schema.questions.map(\.answerPath))
    interviewAnswers = interviewAnswers.filter { validAnswerPaths.contains($0.key) }
    skippedInterviewAnswerPaths.formIntersection(validAnswerPaths)
    if restoredInterviewDraftNeedsStageInference {
      let legacyQuestions = schema.questions.sorted { $0.order < $1.order }
      let legacyQuestion = legacyQuestions.indices.contains(interviewCurrentQuestionIndex)
        ? legacyQuestions[interviewCurrentQuestionIndex]
        : legacyQuestions.first
      interviewCurrentStageID = legacyQuestion.map(questionStageID(for:))
      if let legacyQuestion,
         let orderedIndex = interviewQuestions.firstIndex(where: { $0.answerPath == legacyQuestion.answerPath }) {
        interviewCurrentQuestionIndex = orderedIndex
      }
      isCurrentInterviewStageComplete = isInterviewComplete
      restoredInterviewDraftNeedsStageInference = false
    } else if !interviewStages.contains(where: { $0.id == interviewCurrentStageID }) {
      interviewCurrentStageID = interviewStages.first?.id
    }

    if currentInterviewStage != nil,
       let firstQuestion = currentInterviewStageQuestions.first,
       !currentInterviewStageQuestions.contains(where: { $0.answerPath == interviewCurrentQuestion?.answerPath }) {
      interviewCurrentQuestionIndex = interviewQuestions.firstIndex(where: { $0.answerPath == firstQuestion.answerPath }) ?? 0
    }
    interviewValidationMessage = nil
    interviewWriteMessage = nil
    interviewWriteError = nil
    isInterviewPresented = true
  }

  func hideInterview() {
    saveInterviewDraftImmediately()
    isInterviewPresented = false
  }

  func interviewAnswerBinding(for answerPath: String) -> Binding<String> {
    Binding(
      get: { self.interviewAnswers[answerPath] ?? "" },
      set: { self.updateInterviewAnswer($0, for: answerPath) }
    )
  }

  func updateInterviewAnswer(_ answer: String, for answerPath: String) {
    interviewAnswers[answerPath] = answer
    if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      skippedInterviewAnswerPaths.remove(answerPath)
    }
    interviewValidationMessage = nil
    interviewWriteError = nil
    scheduleInterviewDraftSave()
  }

  func goToPreviousInterviewQuestion() {
    guard canGoToPreviousInterviewQuestion else { return }
    guard let currentQuestion = interviewCurrentQuestion,
          let stageIndex = currentInterviewStageQuestions.firstIndex(where: { $0.answerPath == currentQuestion.answerPath }) else { return }

    let previousQuestion: JumaoInterviewQuestion
    if stageIndex > 0 {
      previousQuestion = currentInterviewStageQuestions[stageIndex - 1]
    } else if let currentStage = currentInterviewStage,
              let currentStageIndex = interviewStages.firstIndex(of: currentStage),
              currentStageIndex > 0 {
      let previousStage = interviewStages[currentStageIndex - 1]
      guard let lastQuestion = interviewQuestions.last(where: { questionStageID(for: $0) == previousStage.id }) else {
        return
      }
      interviewCurrentStageID = previousStage.id
      previousQuestion = lastQuestion
      isCurrentInterviewStageComplete = false
      isInterviewComplete = false
    } else {
      return
    }

    interviewCurrentQuestionIndex = interviewQuestions.firstIndex(where: { $0.answerPath == previousQuestion.answerPath }) ?? 0
    interviewValidationMessage = nil
    scheduleInterviewDraftSave()
  }

  func skipCurrentInterviewQuestion() {
    guard let question = interviewCurrentQuestion else { return }

    skippedInterviewAnswerPaths.insert(question.answerPath)
    interviewValidationMessage = nil
    if isLastInterviewQuestion {
      finishCurrentInterviewStage()
    } else {
      guard let stageIndex = currentInterviewStageQuestions.firstIndex(where: { $0.answerPath == question.answerPath }) else {
        return
      }
      let nextQuestion = currentInterviewStageQuestions[stageIndex + 1]
      interviewCurrentQuestionIndex = interviewQuestions.firstIndex(where: { $0.answerPath == nextQuestion.answerPath }) ?? 0
    }
    scheduleInterviewDraftSave()
  }

  func jumpToInterviewQuestion(_ question: JumaoInterviewQuestion) {
    guard let index = interviewQuestions.firstIndex(where: { $0.answerPath == question.answerPath }) else { return }

    interviewCurrentStageID = questionStageID(for: question)
    interviewCurrentQuestionIndex = index
    isCurrentInterviewStageComplete = false
    isInterviewComplete = false
    interviewValidationMessage = nil
    scheduleInterviewDraftSave()
  }

  func isInterviewQuestionMarkedForCompletion(_ question: JumaoInterviewQuestion) -> Bool {
    skippedInterviewAnswerPaths.contains(question.answerPath)
  }

  @discardableResult
  func advanceInterviewQuestion() -> Bool {
    guard validateCurrentInterviewQuestion() else { return false }

    if isLastInterviewQuestion {
      finishCurrentInterviewStage()
    } else {
      guard let currentQuestion = interviewCurrentQuestion,
            let stageIndex = currentInterviewStageQuestions.firstIndex(where: { $0.answerPath == currentQuestion.answerPath }) else {
        return false
      }
      let nextQuestion = currentInterviewStageQuestions[stageIndex + 1]
      interviewCurrentQuestionIndex = interviewQuestions.firstIndex(where: { $0.answerPath == nextQuestion.answerPath }) ?? 0
      interviewValidationMessage = nil
    }
    scheduleInterviewDraftSave()
    return true
  }

  func continueToNextInterviewStage() {
    guard isCurrentInterviewStageComplete,
          let currentInterviewStage,
          let currentIndex = interviewStages.firstIndex(of: currentInterviewStage),
          interviewStages.indices.contains(currentIndex + 1) else { return }

    let nextStage = interviewStages[currentIndex + 1]
    interviewCurrentStageID = nextStage.id
    interviewCurrentQuestionIndex = interviewQuestions.firstIndex { questionStageID(for: $0) == nextStage.id } ?? 0
    isCurrentInterviewStageComplete = false
    isInterviewComplete = false
    interviewValidationMessage = nil
    scheduleInterviewDraftSave()
  }

  func requestInterviewWrite() {
    guard isInterviewComplete, !isWritingInterviewAnswers, workspaceURL != nil else { return }
    guard pendingInterviewQuestions.isEmpty else {
      interviewWriteError = "还有 \(pendingInterviewQuestions.count) 题需要补充。"
      return
    }
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

  func startProjectCheck() {
    guard canStartProjectCheck, let workspaceURL else { return }

    isCheckingProject = true
    hasPassedProjectCheck = false
    projectCheckMessage = nil
    projectCheckError = nil
    interviewErrorDetails = nil
    interviewErrorDetailsCopiedMessage = nil

    strictCheckRunner.run(workspaceURL: workspaceURL) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishProjectCheck(result)
      }
    }
  }

  func generateInterviewTaskPack() {
    guard canGenerateInterviewTaskPack, let workspaceURL else { return }

    isGeneratingInterviewTaskPack = true
    interviewTaskPackError = nil
    interviewErrorDetails = nil
    interviewErrorDetailsCopiedMessage = nil

    taskPackRunner.run(workspaceURL: workspaceURL) { [weak self] result in
      Task { @MainActor [weak self] in
        self?.finishInterviewTaskPackGeneration(result)
      }
    }
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
    clearProjectInspection()
    restoreInterviewDraft(for: workspaceURL)
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

  private func startProjectInspectionIfNeeded(in workspaceURL: URL) {
    guard !isInspectingProject, projectInspection == nil, projectInspectionError == nil else { return }
    runProjectInspection(in: workspaceURL)
  }

  private func runProjectInspection(in workspaceURL: URL) {
    isInspectingProject = true
    projectInspectionError = nil
    projectInspector.run(workspaceURL: workspaceURL) { [weak self] result in
      self?.finishProjectInspection(result, for: workspaceURL)
    }
  }

  private func finishProjectInspection(_ result: JumaoProjectInspectionResult, for workspaceURL: URL) {
    guard self.workspaceURL == workspaceURL else { return }
    isInspectingProject = false

    switch result {
    case .succeeded(let inspection):
      projectInspection = inspection
      projectInspectionError = nil
    case .failed(_, let message):
      projectInspection = nil
      projectInspectionError = message
    }
  }

  private func clearProjectInspection() {
    projectInspector.cancel()
    isInspectingProject = false
    projectInspection = nil
    projectInspectionError = nil
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
      interviewErrorDetails = nil
      let shouldRemainPresented = isInterviewPresented
      beginInterview(with: interviewMode.map { schema.focused(for: $0) } ?? schema)
      if !shouldRemainPresented {
        isInterviewPresented = false
      }
    case .failed(let exitCode, let message):
      interviewSchema = nil
      if message == JumaoCLIResolutionError.globalVersionOutdated.userFacingMessage {
        interviewSchemaError = message
      } else {
        let code = exitCode.map(String.init) ?? "无法启动"
        interviewSchemaError = "读取项目问题失败（退出码 \(code)）：\(message)"
      }
      interviewErrorDetails = interviewErrorDetailsText(
        operation: "interview --schema",
        exitCode: exitCode,
        reason: message
      )
    }
  }

  private func runInterviewWrite(in workspaceURL: URL, schema: JumaoInterviewSchema, force: Bool) {
    lastInterviewWriteUsedForce = force
    isWritingInterviewAnswers = true
    interviewWriteMessage = nil
    interviewWriteError = nil
    interviewErrorDetails = nil
    interviewErrorDetailsCopiedMessage = nil

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
      interviewErrorDetails = nil
      if isFocusedProjectInterview {
        interviewWriteMessage = "首轮答案已保存\n下一步：继续完善项目规划"
        saveInterviewDraftImmediately()
        return
      }
      interviewWriteMessage = "项目问题已写入\n下一步：开始检查"
      if let workspaceURL {
        interviewDraftStore.delete(for: workspaceURL)
      }
      interviewDraftSaveTask?.cancel()
      interviewDraftSaveTask = nil
      interviewAnswers = [:]
      projectCheckMessage = nil
      projectCheckError = nil
      hasPassedProjectCheck = false
      interviewTaskPackMessage = nil
      interviewTaskPackError = nil
    case .failed(let exitCode, let message):
      let code = exitCode.map(String.init) ?? "无法启动"
      interviewWriteError = "写入项目问题失败（退出码 \(code)）：\(message)"
      interviewErrorDetails = interviewErrorDetailsText(
        operation: "interview --answers",
        exitCode: exitCode,
        reason: message
      )
    }
  }

  private func finishProjectCheck(_ result: JumaoStrictCheckResult) {
    isCheckingProject = false
    refreshStatus()

    switch result {
    case .succeeded:
      hasPassedProjectCheck = true
      projectCheckMessage = "检查通过\n下一步：生成 Codex 任务包"
      projectCheckError = nil
      interviewErrorDetails = nil
    case .failed(let exitCode, let message):
      hasPassedProjectCheck = false
      projectCheckMessage = "发现需要补充的内容"
      projectCheckError = "请补充项目文档中的必要内容后重新检查。"
      interviewErrorDetails = interviewErrorDetailsText(
        operation: "check --strict",
        exitCode: exitCode,
        reason: message
      )
    }
  }

  private func finishInterviewTaskPackGeneration(_ result: CodexTaskPackRunResult) {
    isGeneratingInterviewTaskPack = false

    switch result {
    case .succeeded:
      refreshStatus()
      isInterviewPresented = false
      interviewTaskPackMessage = "任务包已生成"
      interviewTaskPackError = nil
      interviewErrorDetails = nil
    case .failed(let exitCode, let message):
      interviewTaskPackError = "任务包生成失败，请确认项目内容后重试。"
      interviewErrorDetails = interviewErrorDetailsText(
        operation: "pack --target codex",
        exitCode: exitCode,
        reason: message
      )
    }
  }

  private func scheduleInterviewDraftSave() {
    interviewDraftSaveTask?.cancel()
    interviewDraftSaveTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 400_000_000)
      guard !Task.isCancelled else { return }
      self?.saveInterviewDraftImmediately()
    }
  }

  private func saveInterviewDraftImmediately() {
    interviewDraftSaveTask?.cancel()
    guard let workspaceURL, let interviewSchema else { return }

    let draft = InterviewDraft(
      schemaVersion: interviewSchema.schemaVersion,
      workspaceIdentifier: InterviewDraftStore.workspaceIdentifier(for: workspaceURL),
      currentQuestionIndex: interviewCurrentQuestionIndex,
      answers: interviewAnswers,
      skippedAnswerPaths: Array(skippedInterviewAnswerPaths),
      isInterviewComplete: isInterviewComplete,
      stageID: interviewCurrentStageID,
      isCurrentStageComplete: isCurrentInterviewStageComplete,
      updatedAt: Date()
    )

    do {
      try interviewDraftStore.save(draft, for: workspaceURL)
      interviewDraftError = nil
      if interviewSchemaError == nil, interviewWriteError == nil {
        interviewErrorDetails = nil
      }
    } catch {
      interviewDraftError = "无法保存本地问答草稿。"
      interviewErrorDetails = interviewErrorDetailsText(
        operation: "保存问答草稿",
        exitCode: nil,
        reason: "本地草稿文件写入失败。"
      )
    }
  }

  private func restoreInterviewDraft(for workspaceURL: URL) {
    switch interviewDraftStore.load(for: workspaceURL) {
    case .missing:
      restoredInterviewDraftNeedsStageInference = false
      interviewDraftError = nil
    case .loaded(let draft):
      interviewAnswers = draft.answers
      skippedInterviewAnswerPaths = Set(draft.skippedAnswerPaths)
      interviewCurrentQuestionIndex = max(draft.currentQuestionIndex, 0)
      isInterviewComplete = draft.isInterviewComplete
      interviewCurrentStageID = draft.stageID
      isCurrentInterviewStageComplete = draft.isCurrentStageComplete
      restoredInterviewDraftNeedsStageInference = draft.stageID == nil
      interviewDraftError = nil
    case .corrupted:
      restoredInterviewDraftNeedsStageInference = false
      interviewDraftError = "本地问答草稿无法读取，已忽略。"
      interviewErrorDetails = interviewErrorDetailsText(
        operation: "读取问答草稿",
        exitCode: nil,
        reason: "草稿文件格式无效或内容损坏。"
      )
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
    interviewDraftError = nil
    interviewMode = nil
    interviewInspectionContext = nil
    interviewErrorDetails = nil
    interviewErrorDetailsCopiedMessage = nil
    interviewAnswers = [:]
    skippedInterviewAnswerPaths = []
    interviewCurrentStageID = nil
    interviewCurrentQuestionIndex = 0
    isCurrentInterviewStageComplete = false
    interviewValidationMessage = nil
    isInterviewComplete = false
    isWritingInterviewAnswers = false
    interviewWriteMessage = nil
    interviewWriteError = nil
    isCheckingProject = false
    projectCheckMessage = nil
    projectCheckError = nil
    isGeneratingInterviewTaskPack = false
    interviewTaskPackMessage = nil
    interviewTaskPackError = nil
    hasPassedProjectCheck = false
    isInterviewWriteConfirmationPresented = false
    isInterviewOverwriteConfirmationPresented = false
    interviewDocumentsToOverwrite = []
    isInterviewPresented = false
  }

  private func interviewErrorDetailsText(operation: String, exitCode: Int32?, reason: String) -> String {
    let code = exitCode.map(String.init) ?? "无法启动"
    return "操作：\(operation)\n退出码：\(code)\n原因：\(reason)"
  }

  private func validateCurrentInterviewQuestion() -> Bool {
    guard let question = interviewCurrentQuestion else { return false }
    guard question.required else { return true }
    guard isMeaningfulInterviewAnswer(interviewAnswers[question.answerPath] ?? "") else {
      interviewValidationMessage = "请先填写这道必填问题。"
      return false
    }
    return true
  }

  private func finishCurrentInterviewStage() {
    isCurrentInterviewStageComplete = true
    isInterviewComplete = !hasNextInterviewStage
    interviewValidationMessage = nil
  }

  private func questionStageID(for question: JumaoInterviewQuestion) -> String {
    question.stage ?? interviewStages.first?.id ?? JumaoInterviewSchema.legacyStage.id
  }

  private func isMeaningfulInterviewAnswer(_ answer: String) -> Bool {
    let normalized = answer
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: " ", with: "")

    guard !normalized.isEmpty else { return false }
    let placeholderAnswers = ["暂不确定", "不确定", "不知道", "不清楚", "待定", "以后再说", "n/a", "na"]
    return !placeholderAnswers.contains(normalized)
  }

  private func isDirectory(_ url: URL) -> Bool {
    var directory = ObjCBool(false)
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
  }
}
