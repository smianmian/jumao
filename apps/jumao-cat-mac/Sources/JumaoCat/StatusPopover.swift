import SwiftUI

struct StatusPopover: View {
  @ObservedObject var appState: AppState
  private let actionColumns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      Divider()

      if appState.workspaceURL == nil {
        unselectedWorkspace
      } else {
        selectedWorkspace
      }
    }
    .padding(16)
    .frame(width: 380, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: JumaoMenuBarIcon.makeColorImage())
        .resizable()
        .interpolation(.none)
        .scaledToFit()
        .frame(width: 36, height: 36)
        .accessibilityLabel("Jumao Cat")

      VStack(alignment: .leading, spacing: 2) {
        Text(appState.workspaceURL == nil ? "Jumao Cat" : appState.projectName)
          .font(.headline)
          .lineLimit(1)
        Text(appState.workspaceURL == nil ? "本地项目状态" : "Jumao Cat")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
      Button(appState.workspaceURL == nil ? "选择项目" : "更换项目") {
        appState.chooseWorkspace()
      }
    }
  }

  private var unselectedWorkspace: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("橘猫状态")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(appState.status.label)
        .font(.headline)
      Text(appState.status.message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text("请选择一个 Jumao 项目目录。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var selectedWorkspace: some View {
    VStack(alignment: .leading, spacing: 14) {
      if appState.agentPlanningSession != nil {
        Button(appState.isAgentPlanning ? "查看整理进度" : "查看上次规划结果") {
          appState.showAgentPlanning()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
      }
      if appState.shouldShowProjectInspection {
        projectInspection
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text("橘猫状态")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(appState.status.label)
            .font(.headline)
          Text(appState.status.message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let readiness = appState.status.projectReadiness {
          projectReadiness(readiness)
        }

        if let team = appState.status.agentTeamOverview {
          agentTeam(team)
          agentGroups(team.groups)
        }

        VStack(alignment: .leading, spacing: 3) {
          sectionTitle("项目目录")
          Text(appState.workspacePath)
            .font(.caption)
            .textSelection(.enabled)
            .lineLimit(2)
        }

        if let snapshot = appState.status.snapshot {
          statusDetails(snapshot)
        }

        feedback
        Divider()
        actions
      }
    }
  }

  @ViewBuilder
  private var projectInspection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("项目扫描")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      if appState.isInspectingProject {
        ProgressView("正在检查这个文件夹…")
          .controlSize(.small)
      } else if let inspection = appState.projectInspection {
        inspectionDetails(inspection)

        if let capabilityMessage = appState.projectInspectionCapabilityMessage {
          Text(capabilityMessage)
            .font(.caption)
            .foregroundStyle(inspection.capabilityFit.level == "limited" ? .orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if appState.needsProjectInterviewModeSelection {
          Text("这个文件夹准备用来做什么？")
            .font(.subheadline.weight(.semibold))
          HStack {
            Button("这是一个新项目") {
              appState.chooseProjectInterviewMode(.newProject)
            }
            Button("梳理当前项目") {
              appState.chooseProjectInterviewMode(.existingProject)
            }
          }
          .buttonStyle(.bordered)
        } else if let title = appState.projectInspectionPrimaryActionTitle,
                  let description = appState.projectInspectionPrimaryActionDescription {
          if let modeTitle = appState.projectInspectionModeTitle {
            HStack(spacing: 6) {
              Text("已识别为\(modeTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
              Menu("不是这个类型？切换") {
                Button("识别为新项目") {
                  appState.chooseProjectInterviewMode(.newProject)
                }
                Button("识别为已有项目") {
                  appState.chooseProjectInterviewMode(.existingProject)
                }
              }
              .font(.caption)
            }
          }
          Button(title) {
            appState.startProjectInterview()
          }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canContinueFromProjectInspection)
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } else if let error = appState.projectInspectionError {
        Text(error)
          .font(.subheadline)
          .foregroundStyle(.red)
        Button("重新扫描") {
          appState.rescanProject()
        }
        .buttonStyle(.bordered)
      } else {
        ProgressView("正在检查这个文件夹…")
          .controlSize(.small)
      }
    }
  }

  private func inspectionDetails(_ inspection: JumaoProjectInspection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      detail("项目名称", inspection.project.name.isEmpty ? "未提供" : inspection.project.name)
      detail("项目类型", appState.projectInspectionKindTitle ?? "未提供")
      detail("已识别平台", inspection.project.platforms.isEmpty ? "未识别" : inspection.project.platforms.joined(separator: "、"))
      detail("已识别语言", inspection.project.languages.isEmpty ? "未识别" : inspection.project.languages.joined(separator: "、"))
      detail("构建方式", inspection.project.buildSystems.isEmpty ? "未识别" : inspection.project.buildSystems.joined(separator: "、"))
      detail("源代码", inspection.project.hasSourceCode ? "有" : "没有")
      detail("测试", inspection.project.hasTests ? "有" : "没有")
    }
  }

  private func projectReadiness(_ readiness: ProjectReadiness) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        sectionTitle("项目准备度")
        Spacer()
        Text("\(readiness.percentage)%")
          .font(.caption.weight(.semibold))
          .monospacedDigit()
      }

      ProgressView(value: Double(readiness.percentage), total: 100)
        .progressViewStyle(.linear)
        .tint(.orange)

      HStack(spacing: 4) {
        Text("当前阶段：")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(readiness.stage)
          .font(.caption.weight(.semibold))
      }

      if let rawState = readiness.rawState {
        Text("原始状态码：\(rawState)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func agentTeam(_ team: AgentTeamOverview) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Agent 团队")
      HStack(spacing: 18) {
        agentMetric("已召集", team.triggeredAgentCount)
        agentMetric("活跃分组", team.activeGroupCount, showsActivity: team.showsCheckingActivity)
        agentMetric("阻塞分组", team.blockedGroupCount)
      }
    }
  }

  private func agentGroups(_ groups: [JumaoCatStatus.AgentGroup]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Agent 分组")

      if groups.isEmpty {
        Text("暂无分组详情")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(groups.prefix(8)) { group in
              agentGroupRow(group)
            }
          }
        }
        .frame(maxHeight: 176)
      }
    }
  }

  private func agentGroupRow(_ group: JumaoCatStatus.AgentGroup) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(group.name)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 8)
        Text(group.stateLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(group.state == "blocked" ? .red : .secondary)
      }

      Text("已触发 \(group.triggeredAgentCount) 个 Agent")
        .font(.caption2)
        .foregroundStyle(.secondary)

      if group.state == "blocked", !group.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(group.message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var feedback: some View {
    if let error = appState.workspaceOpenError {
      feedbackText(error, color: .red)
    }
    if let error = appState.agentReportOpenError {
      feedbackText(error, color: .red)
    }
    if let message = appState.taskPackCopyFeedback {
      feedbackText(message, color: appState.taskPackCopySucceeded ? .green : .red)
    }
    if appState.isRegeneratingTaskPack {
      feedbackText("正在生成", color: .secondary)
    }
    if let error = appState.taskPackGenerationError {
      feedbackText(error, color: .red)
    }
    if let message = appState.interviewTaskPackMessage {
      feedbackText(message, color: .green)
    }
    if let error = appState.terminalOpenError {
      feedbackText(error, color: .red)
    }
    if let error = appState.projectInitializationError {
      feedbackText(error, color: .red)
    }
    if let error = appState.interviewSchemaError {
      feedbackText(error, color: .red)
    }
    if let error = appState.interviewDraftError {
      feedbackText(error, color: .red)
    }
  }

  private var actions: some View {
    LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
      actionButton(
        appState.isRegeneratingTaskPack ? "正在生成" : "重新生成任务包",
        systemImage: "arrow.clockwise",
        enabled: appState.canRegenerateTaskPack,
        action: appState.regenerateCodexTaskPack
      )
      actionButton(
        "复制 Codex 任务包",
        systemImage: "doc.on.doc",
        enabled: appState.canCopyLatestTaskPack,
        action: appState.copyLatestTaskPack
      )
      actionButton(
        "打开治理报告",
        systemImage: "doc.text",
        enabled: appState.canOpenAgentReport,
        action: appState.openAgentReport
      )
      actionButton(
        "打开终端",
        systemImage: "terminal",
        enabled: appState.canOpenTerminal,
        action: appState.openWorkspaceInTerminal
      )
      actionButton(
        "打开项目目录",
        systemImage: "folder",
        enabled: appState.workspaceURL != nil,
        action: appState.openWorkspaceInFinder
      )
      actionButton(
        "刷新",
        systemImage: "arrow.clockwise.circle",
        enabled: appState.workspaceURL != nil,
        action: appState.refreshStatus
      )
    }
    .buttonStyle(.bordered)
  }

  private func actionButton(
    _ title: String,
    systemImage: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .disabled(!enabled)
  }

  private func feedbackText(_ value: String, color: Color) -> some View {
    Text(value)
      .font(.caption)
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func statusDetails(_ snapshot: StatusSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let date = appState.statusFileModificationDate {
        detail("最后更新", date.formatted(date: .abbreviated, time: .shortened))
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

  private func agentMetric(
    _ title: String,
    _ value: Int,
    showsActivity: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        Text("\(value)")
          .font(.subheadline.weight(.semibold))
        if showsActivity {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
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
