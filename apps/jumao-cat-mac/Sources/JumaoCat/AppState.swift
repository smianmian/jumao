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

  private let statusReader = StatusReader()
  private let workspaceBookmarkStore: WorkspaceBookmarkStore
  private let workspaceOpener: any WorkspaceOpening
  private let agentReportOpener: any AgentReportOpening
  private let taskPackCopier: any TaskPackCopying
  private var taskPackCopyFeedbackToken = UUID()
  private lazy var statusWatcher = StatusFileWatcher { [weak self] in
    Task { @MainActor [weak self] in
      self?.refreshStatus()
    }
  }

  init(
    workspaceBookmarkStore: WorkspaceBookmarkStore = WorkspaceBookmarkStore(),
    workspaceOpener: any WorkspaceOpening = FinderWorkspaceOpener(),
    agentReportOpener: any AgentReportOpening = FinderAgentReportOpener(),
    taskPackCopier: any TaskPackCopying = CodexTaskPackCopier()
  ) {
    self.workspaceBookmarkStore = workspaceBookmarkStore
    self.workspaceOpener = workspaceOpener
    self.agentReportOpener = agentReportOpener
    self.taskPackCopier = taskPackCopier
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

  func loadSavedWorkspace() {
    guard let workspaceURL = workspaceBookmarkStore.restore() else {
      self.workspaceURL = nil
      status = .unselected
      workspaceOpenError = nil
      agentReportOpenError = nil
      clearTaskPackCopyFeedback()
      return
    }

    activateWorkspace(workspaceURL)
  }

  func chooseWorkspace() {
    let panel = NSOpenPanel()
    panel.title = "选择 Jumao 项目"
    panel.message = "选择包含 .jumao/status.json 的项目目录。"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else {
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

  func shutdown() {
    statusWatcher.stop()
    workspaceBookmarkStore.stopAccessingWorkspace()
  }

  private func activateWorkspace(_ workspaceURL: URL) {
    statusWatcher.stop()
    self.workspaceURL = workspaceURL
    workspaceOpenError = nil
    agentReportOpenError = nil
    clearTaskPackCopyFeedback()
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
}
