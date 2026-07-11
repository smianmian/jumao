import AppKit

@MainActor
protocol WorkspaceChoosing {
  func chooseWorkspace(startingAt directoryURL: URL) -> URL?
}

@MainActor
struct MacWorkspaceChooser: WorkspaceChoosing {
  func chooseWorkspace(startingAt directoryURL: URL) -> URL? {
    let panel = makePanel(startingAt: directoryURL)
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }

  func makePanel(startingAt directoryURL: URL) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.title = "选择 Jumao 项目"
    panel.message = "选择你的项目文件夹"
    panel.directoryURL = directoryURL
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    return panel
  }
}
