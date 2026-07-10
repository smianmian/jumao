import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published private(set) var workspaceURL: URL?
  @Published private(set) var status: WorkspaceStatus = .unselected

  private let statusReader = StatusReader()
  private let workspaceBookmarkStore: WorkspaceBookmarkStore
  private lazy var statusWatcher = StatusFileWatcher { [weak self] in
    Task { @MainActor [weak self] in
      self?.refreshStatus()
    }
  }

  init(workspaceBookmarkStore: WorkspaceBookmarkStore = WorkspaceBookmarkStore()) {
    self.workspaceBookmarkStore = workspaceBookmarkStore
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
    }
  }

  func refreshStatus() {
    guard let workspaceURL else {
      status = .unselected
      return
    }

    status = statusReader.read(workspaceURL: workspaceURL)
  }

  func shutdown() {
    statusWatcher.stop()
    workspaceBookmarkStore.stopAccessingWorkspace()
  }

  private func activateWorkspace(_ workspaceURL: URL) {
    statusWatcher.stop()
    self.workspaceURL = workspaceURL
    refreshStatus()
    statusWatcher.start(watching: workspaceURL)
  }
}
