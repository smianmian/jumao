import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published private(set) var workspaceURL: URL?
  @Published private(set) var status: WorkspaceStatus = .unselected
  @Published private(set) var workspaceOpenError: String?

  private let statusReader = StatusReader()
  private let workspaceBookmarkStore: WorkspaceBookmarkStore
  private let workspaceOpener: any WorkspaceOpening
  private lazy var statusWatcher = StatusFileWatcher { [weak self] in
    Task { @MainActor [weak self] in
      self?.refreshStatus()
    }
  }

  init(
    workspaceBookmarkStore: WorkspaceBookmarkStore = WorkspaceBookmarkStore(),
    workspaceOpener: any WorkspaceOpening = FinderWorkspaceOpener()
  ) {
    self.workspaceBookmarkStore = workspaceBookmarkStore
    self.workspaceOpener = workspaceOpener
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

  func loadSavedWorkspace() {
    guard let workspaceURL = workspaceBookmarkStore.restore() else {
      self.workspaceURL = nil
      status = .unselected
      workspaceOpenError = nil
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

    switch workspaceOpener.open(workspaceURL: workspaceURL) {
    case .opened:
      workspaceOpenError = nil
    case .missingDirectory:
      workspaceOpenError = "项目目录不存在，无法在 Finder 中打开。"
    case .failed:
      workspaceOpenError = "无法在 Finder 中打开项目目录。"
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
    refreshStatus()
    statusWatcher.start(watching: workspaceURL)
  }
}
