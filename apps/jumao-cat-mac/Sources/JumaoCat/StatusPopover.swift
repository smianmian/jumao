import SwiftUI

struct StatusPopover: View {
  @ObservedObject var appState: AppState

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Image(nsImage: JumaoMenuBarIcon.makeImage(for: appState.status.catState))
            .resizable()
            .frame(width: 28, height: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text(appState.projectName)
              .font(.headline)
              .lineLimit(1)
            Text("Jumao Cat")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("选择项目") {
            appState.chooseWorkspace()
          }
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
          Text("橘猫状态：\(appState.status.catState)")
            .font(.subheadline.weight(.semibold))
          Text(appState.status.label)
            .font(.headline)
          Text(appState.status.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 3) {
          Text("项目目录")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(appState.workspacePath)
            .font(.caption)
            .textSelection(.enabled)
            .lineLimit(2)
        }

        if let snapshot = appState.status.snapshot {
          statusDetails(snapshot)
        }

        if let error = appState.workspaceOpenError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let error = appState.agentReportOpenError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 10) {
          Button("打开治理报告") {
            appState.openAgentReport()
          }
          .disabled(!appState.canOpenAgentReport)

          Button("打开项目目录") {
            appState.openWorkspaceInFinder()
          }
          .disabled(appState.workspaceURL == nil)

          Spacer()
          Button("刷新") {
            appState.refreshStatus()
          }
          .disabled(appState.workspaceURL == nil)
        }
      }
      .padding(16)
    }
    .frame(width: 360, height: 500)
  }

  private func statusDetails(_ snapshot: StatusSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      if let date = appState.statusFileModificationDate {
        detail("最后更新", date.formatted(date: .abbreviated, time: .shortened))
      }

      VStack(alignment: .leading, spacing: 6) {
        sectionTitle("Agent Board")
        HStack(spacing: 12) {
          metric("已触发", snapshot.status.agentBoard.triggeredAgentCount)
          metric("活跃分组", snapshot.status.agentBoard.activeGroupCount)
          metric("阻塞分组", snapshot.status.agentBoard.blockedGroupCount)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        sectionTitle("关键阻塞")
        if snapshot.status.blockers.isEmpty {
          Text("当前没有关键阻塞")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(snapshot.status.blockers.prefix(3)) { blocker in
            VStack(alignment: .leading, spacing: 2) {
              Text(blocker.title)
                .font(.caption.weight(.semibold))
              Text(blocker.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }

          if snapshot.status.blockers.count > 3 {
            Text("还有 \(snapshot.status.blockers.count - 3) 条关键阻塞")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if !snapshot.status.nextSafeTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        detail("下一步", snapshot.status.nextSafeTask)
      }
    }
  }

  private func sectionTitle(_ value: String) -> some View {
    Text(value)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  private func metric(_ title: String, _ value: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text("\(value)")
        .font(.subheadline.weight(.semibold))
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      sectionTitle(title)
      Text(value)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
