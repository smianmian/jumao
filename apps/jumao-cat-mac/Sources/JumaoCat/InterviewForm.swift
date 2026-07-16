import AppKit
import SwiftUI

struct InterviewForm: View {
  @ObservedObject var appState: AppState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCatIdleAnimating = false
  @State private var isCatTilting = false
  @State private var catTiltDirection: Double = 1
  @State private var isCatNodding = false
  @State private var isCatJumping = false
  @State private var catCelebrationPhase = 0
  @State private var lastCatNodAt = Date.distantPast
  @State private var isEditingUnderstanding = false
  @State private var expandedAgentGroups = Set<String>()

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text(stageHeaderTitle)
          .font(.title3.weight(.semibold))
        Spacer()
        Button("暂时隐藏") {
          appState.hideInterview()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        if appState.interviewSchema != nil {
          Text("共 \(appState.interviewCurrentStageQuestionCount) 题")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }

      if let summary = appState.interviewInspectionSummary {
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      }

      if let draftError = appState.interviewDraftError {
        compactError(draftError)
      }

      if let session = appState.agentPlanningSession {
        agentPlanningCard(session)
      } else if appState.isLoadingInterviewSchema {
        loadingCard
      } else if let schemaError = appState.interviewSchemaError {
        errorCard(title: "无法打开项目问答", message: schemaError)
      } else if appState.shouldOfferInterviewDraftRecovery {
        draftRecoveryCard
      } else if let planningResult = appState.focusedPlanningResult {
        focusedPlanningResultCard(planningResult)
      } else if appState.isCurrentInterviewStageComplete {
        if appState.hasNextInterviewStage {
          stageCompletionCard
        } else if appState.isFocusedProjectInterview {
          focusedUnderstandingCard
        } else {
          completionCard
        }
      } else if let question = appState.interviewCurrentQuestion {
        questionCard(question)
      }
    }
    .padding(20)
    .frame(width: 420, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .task(id: reduceMotion) {
      guard !reduceMotion else {
        stopCatAnimation()
        return
      }

      isCatIdleAnimating = true
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 3_600_000_000)
        guard !Task.isCancelled else { return }
        catTiltDirection *= -1
        isCatTilting = true
        try? await Task.sleep(nanoseconds: 620_000_000)
        guard !Task.isCancelled else { return }
        isCatTilting = false
      }
    }
    .alert("确认写入项目", isPresented: $appState.isInterviewWriteConfirmationPresented) {
      Button("取消", role: .cancel) {}
      Button("确认并写入项目") {
        appState.confirmInterviewWrite()
      }
    } message: {
      Text("将生成项目资料和开发任务包，不修改项目源代码。")
    }
    .alert("将覆盖已有项目文档", isPresented: $appState.isInterviewOverwriteConfirmationPresented) {
      Button("取消", role: .cancel) {}
      Button("确认覆盖", role: .destructive) {
        appState.confirmInterviewOverwrite()
      }
    } message: {
      Text(appState.interviewOverwriteMessage)
    }
  }

  private var stageHeaderTitle: String {
    if let session = appState.agentPlanningSession {
      switch session.phase {
      case .running: return "橘猫正在帮你整理"
      case .completed: return "橘猫已经整理好了"
      case .interrupted: return "上次整理没有完成"
      case .failed: return "整理时遇到问题"
      case .cancelled: return "整理已取消"
      }
    }
    guard let stage = appState.currentInterviewStage else { return appState.interviewWindowTitle }
    return "第 \(stage.order) 阶段：\(stage.title)"
  }

  @ViewBuilder
  private func agentPlanningCard(_ session: JumaoAgentPlanningSession) -> some View {
    switch session.phase {
    case .running:
      agentPlanningProgressCard(session)
    case .completed:
      agentPlanningResultCard(session)
    case .interrupted, .failed, .cancelled:
      agentPlanningErrorCard(session)
    }
  }

  private func agentPlanningProgressCard(_ session: JumaoAgentPlanningSession) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        VStack(alignment: .leading, spacing: 3) {
          Text("橘猫正在帮你整理")
            .font(.headline)
          Text("它会检查项目、整理边界，并准备一份可以交给 Codex 的开发计划。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Text("\(session.totalAgents) 个角色正在检查 · \(session.groups.count) 个小组")
        .font(.caption.weight(.semibold))
      agentPlanningGroups(session.groups)
      Button("取消整理", role: .destructive) {
        appState.cancelAgentPlanning()
      }
      .buttonStyle(.bordered)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func agentPlanningResultCard(_ session: JumaoAgentPlanningSession) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("橘猫已经整理好了")
        .font(.headline)
      if let understanding = session.understanding {
        Text(understanding)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      } else if let request = session.request {
        Text(request)
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      }
      if session.reused {
        Text("已使用现有规划结果")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 14) {
        planningMetric("参与检查", session.totalAgents)
        planningMetric("实际参与", session.counts.completed)
        planningMetric("无关", session.counts.skipped)
        planningMetric("需处理", session.counts.blocked)
        if session.counts.failed > 0 {
          planningMetric("失败", session.counts.failed)
        }
      }
      if let runId = session.runId {
        Text("运行编号：\(runId)")
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Button("交给 Codex") {
        appState.copyAgentPlanningCodexInstruction()
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)

      HStack {
        Button("查看开发计划") { appState.openAgentDevelopmentPlan() }
        Button(appState.showsAgentPlanningGroups ? "收起 8 个小组" : "查看 8 个小组") {
          appState.toggleAgentPlanningGroups()
        }
      }
      .buttonStyle(.bordered)

      HStack {
        Button("在 Finder 中查看资料") { appState.openWorkspaceInFinder() }
        Button("重新整理") { appState.rerunAgentPlanning() }
      }
      .buttonStyle(.bordered)

      if appState.showsAgentPlanningGroups {
        agentPlanningGroups(session.groups)
      }
      if let feedback = appState.agentPlanningCopyFeedback {
        Text(feedback)
          .font(.caption)
          .foregroundStyle(.green)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func agentPlanningErrorCard(_ session: JumaoAgentPlanningSession) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(session.errorMessage ?? "上次整理没有完成")
        .font(.headline)
      Text("可以重新整理，或先查看项目中已经留下的资料。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack {
        Button("重新整理") { appState.retryAgentPlanning() }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
        Button("复制详细错误") { appState.copyAgentPlanningErrorDetails() }
          .buttonStyle(.bordered)
          .disabled(session.errorDetails == nil)
      }
      HStack {
        Button("在 Finder 中查看资料") { appState.openWorkspaceInFinder() }
        Button("关闭") { appState.hideInterview() }
      }
      .buttonStyle(.bordered)
      if let message = appState.agentPlanningErrorCopiedMessage {
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
      if !session.groups.isEmpty {
        agentPlanningGroups(session.groups)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func planningMetric(_ title: String, _ value: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(String(value)).font(.headline.monospacedDigit())
      Text(title).font(.caption2).foregroundStyle(.secondary)
    }
  }

  private func agentPlanningGroups(_ groups: [JumaoAgentGroupProgress]) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        ForEach(groups) { group in
          DisclosureGroup(
            isExpanded: Binding(
              get: { expandedAgentGroups.contains(group.id) },
              set: { expanded in
                if expanded { expandedAgentGroups.insert(group.id) }
                else { expandedAgentGroups.remove(group.id) }
              }
            )
          ) {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(group.agents) { agent in
                VStack(alignment: .leading, spacing: 2) {
                  HStack {
                    Text(agent.name).font(.caption.weight(.medium))
                    Spacer()
                    Text(agentStatusLabel(agent.status)).font(.caption2).foregroundStyle(.secondary)
                  }
                  if let detail = agent.skippedReason ?? agent.summary, !detail.isEmpty {
                    Text(detail)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
            }
            .padding(.top, 6)
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(group.name).font(.caption.weight(.semibold))
                Spacer()
                Text(agentStatusLabel(group.status)).font(.caption2).foregroundStyle(.secondary)
              }
              Text("共 \(group.totalAgents) · 完成 \(group.counts.completed) · 跳过 \(group.counts.skipped) · 阻塞 \(group.counts.blocked) · 失败 \(group.counts.failed)")
                .font(.caption2)
                .foregroundStyle(.secondary)
              if let summary = group.summary, !summary.isEmpty {
                Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
              }
            }
          }
          .padding(10)
          .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
      }
    }
    .frame(maxHeight: 300)
  }

  private func agentStatusLabel(_ status: JumaoAgentProgressStatus) -> String {
    switch status {
    case .waiting: "等待"
    case .working: "正在检查"
    case .completed: "已完成"
    case .skipped: "已跳过"
    case .blocked: "被阻塞"
    case .failed: "失败"
    }
  }

  private var loadingCard: some View {
    HStack(spacing: 12) {
      ProgressView()
        .controlSize(.small)
      VStack(alignment: .leading, spacing: 3) {
        Text("正在准备问题")
          .font(.headline)
        Text("正在读取 Jumao interview schema。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var draftRecoveryCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("发现这个项目上次没有填完")
        .font(.headline)
      Text("你可以继续上次填写，或者清除旧草稿后从第一题重新开始。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("继续填写") {
          appState.continueInterviewDraftRecovery()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)

        Button("重新开始") {
          appState.restartInterviewDraftRecovery()
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func errorCard(title: String, message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.red)
        .fixedSize(horizontal: false, vertical: true)
      interviewErrorActions
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func compactError(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
      interviewErrorActions
    }
  }

  private var interviewErrorActions: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Button("重试") {
          appState.retryInterviewOperation()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!appState.canRetryInterviewOperation)

        Button("复制详细错误") {
          appState.copyInterviewErrorDetails()
        }
        .buttonStyle(.bordered)
        .disabled(appState.interviewErrorDetails == nil)
      }

      if let message = appState.interviewErrorDetailsCopiedMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button("打开项目文件夹") {
        appState.openWorkspaceInFinder()
      }
      .buttonStyle(.bordered)
    }
  }

  private func focusedPlanningResultCard(_ result: FocusedPlanningResult) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        Text(result.mode == .newProject ? "规划完成" : "本次改动资料已准备")
          .font(.headline)
        Text("项目：\(result.projectName)")
          .font(.subheadline.weight(.medium))
        if result.mode == .newProject {
          Text("你想做的：\(result.idea)")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
          Text("你希望它能做的事：\(result.firstVersion ?? "待确认")")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
          Text(platformUsageDescription(result.platform))
            .font(.subheadline)
        } else {
          Text("本次想改的：\(result.idea)")
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        }

        Text("已生成的资料")
          .font(.subheadline.weight(.semibold))
          .padding(.top, 2)
        if result.files.isEmpty {
          Text("正在确认生成文件；可先在 Finder 中检查项目资料。")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(result.files, id: \.self) { file in
            Label(file, systemImage: "doc.text")
              .font(.caption)
              .lineLimit(1)
          }
        }

        Text("未回答的信息都已标为“待确认”，不会自动假设登录、支付或云服务。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button("打开任务包") {
          appState.openFocusedPlanningTaskPack()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)

        Button("复制给 Codex") {
          appState.copyFocusedPlanningCodexInstruction()
        }
        .buttonStyle(.bordered)

        Button("在 Finder 中查看全部资料") {
          appState.openWorkspaceInFinder()
        }
        .buttonStyle(.bordered)

        if let feedback = appState.focusedPlanningCopyFeedback {
          Text(feedback)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let error = appState.focusedPlanningOpenError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Spacer(minLength: 0)
      companionCat()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var stageCompletionCard: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        if appState.currentInterviewStage?.id == "idea" {
          Text("第一阶段完成")
            .font(.headline)
          Text("你已经把第一版要做什么说清楚了。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          Text("第二阶段完成")
            .font(.headline)
          Text("页面、操作和常见情况已经补充好了。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        HStack {
          Button("暂时结束") {
            appState.hideInterview()
          }
          .buttonStyle(.bordered)

          Button(appState.currentInterviewStage?.id == "idea" ? "继续完善第一版" : "继续准备给别人使用") {
            appState.continueToNextInterviewStage()
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
        }
      }

      Spacer(minLength: 0)
      companionCat()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var completionCard: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        if !appState.pendingInterviewQuestions.isEmpty {
          Text("还有 \(appState.pendingInterviewQuestions.count) 题需要补充")
            .font(.headline)
          Text("点下面的题目回去补答，补齐后才能写入项目。")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          ForEach(appState.pendingInterviewQuestions, id: \.answerPath) { question in
            Button("第 \(question.order) 题：\(question.title)") {
              appState.jumpToInterviewQuestion(question)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        } else if appState.isCheckingProject {
          Text("正在检查")
            .font(.headline)
          ProgressView()
          Button("正在检查") {}
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(true)
        } else if appState.isGeneratingInterviewTaskPack {
          Text("正在生成任务包")
            .font(.headline)
          ProgressView()
          Button("正在生成任务包") {}
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(true)
        } else if let error = appState.interviewTaskPackError {
          Text("生成任务包失败")
            .font(.headline)
          Text(error)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Button("重新生成") {
            appState.generateInterviewTaskPack()
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          copyErrorDetailsButton
        } else if let message = appState.projectCheckMessage {
          Text(message)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          if appState.hasPassedProjectCheck {
            Button("生成 Codex 任务包") {
              appState.generateInterviewTaskPack()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!appState.canGenerateInterviewTaskPack)
          } else if let error = appState.projectCheckError {
            Text(error)
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Button("重新检查") {
              appState.startProjectCheck()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            copyErrorDetailsButton
          }
        } else if let message = appState.interviewWriteMessage {
          Text(message)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          if appState.isFocusedProjectInterview {
            Button("完成") {
              appState.hideInterview()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
          } else {
            Button("开始检查") {
              appState.startProjectCheck()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!appState.canStartProjectCheck)
          }
        } else {
          Text("已完成 \(appState.interviewQuestions.count) 个问题")
            .font(.headline)
          Text("下一步：确认并写入项目")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Button(appState.isWritingInterviewAnswers ? "正在写入项目" : "确认并写入项目") {
            appState.requestInterviewWrite()
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .disabled(!appState.canWriteCompletedInterview)
        }

        if let error = appState.interviewWriteError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
          interviewErrorActions
        }
      }

      Spacer(minLength: 0)
      companionCat(isWaiting: appState.isCheckingProject || appState.isGeneratingInterviewTaskPack)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var focusedUnderstandingCard: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 12) {
        if appState.isFocusedNewProjectInterview {
          newProjectUnderstanding
        } else {
          existingProjectUnderstanding
        }
      }

      Spacer(minLength: 0)
      companionCat()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var newProjectUnderstanding: some View {
    let features = (appState.interviewAnswers["newProject.features"] ?? appState.interviewAnswers["newProject.firstVersion"] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if isEditingUnderstanding {
      Text("直接改成你的意思")
        .font(.headline)
      Text("你想做的是")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      nativeTextEditor(
        placeholder: "说说你想做什么",
        answerPath: "newProject.idea"
      )
      Text("你希望它能做哪些事")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      nativeTextEditor(
        placeholder: "想到什么就写什么",
        answerPath: "newProject.features"
      )
      Text("你想先在哪儿用它")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      platformButtons
      Button("改好了") {
        isEditingUnderstanding = false
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)
    } else {
      Text("Jumao 是这样理解的")
        .font(.headline)
      Text("我理解你想做的是：\(appState.interviewAnswers["newProject.idea"] ?? "待确认")")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      Text("你希望它能做的事：\(features)")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      Text(platformUsageDescription(appState.interviewAnswers["newProject.platform"]))
        .font(.subheadline)
      HStack {
        Button("对，就是这个意思") {
          appState.confirmFocusedInterviewUnderstanding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(appState.isWritingInterviewAnswers)

        Button("改一下") {
          isEditingUnderstanding = true
        }
        .buttonStyle(.bordered)
      }
    }

    if appState.isWritingInterviewAnswers {
      ProgressView("正在整理项目资料")
        .controlSize(.small)
    }
    if let error = appState.interviewWriteError {
      Text(error)
        .font(.caption)
        .foregroundStyle(.red)
      interviewErrorActions
    }
  }

  @ViewBuilder
  private var existingProjectUnderstanding: some View {
    if isEditingUnderstanding {
      Text("直接改成你的意思")
        .font(.headline)
      nativeTextEditor(
        placeholder: "描述这次想增加、调整或修复的地方",
        answerPath: "existingProject.requestedChange"
      )
      Button("改好了") {
        isEditingUnderstanding = false
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)
    } else {
      Text("Jumao 是这样理解的")
        .font(.headline)
      Text("这次你想让它：\(appState.interviewAnswers["existingProject.requestedChange"] ?? "待确认")")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      Text("Jumao 会结合当前扫描结果整理影响区域、保护项、测试和发布检查，不再把这些专业判断变成问卷。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("对，就是这个意思") {
          appState.confirmFocusedInterviewUnderstanding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(appState.isWritingInterviewAnswers)

        Button("改一下") {
          isEditingUnderstanding = true
        }
        .buttonStyle(.bordered)
      }
    }

    if appState.isWritingInterviewAnswers {
      ProgressView("正在整理本次改动")
        .controlSize(.small)
    }
    if let error = appState.interviewWriteError {
      Text(error)
        .font(.caption)
        .foregroundStyle(.red)
      interviewErrorActions
    }
  }

  private func platformUsageDescription(_ platform: String?) -> String {
    NewProjectPlatformWording.usageDescription(for: platform)
  }

  private var platformButtons: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(["iPhone", "Mac", "网页", "还没想好"], id: \.self) { option in
        Button {
          appState.updateInterviewAnswer(option, for: "newProject.platform")
        } label: {
          HStack {
            Image(systemName: appState.interviewAnswers["newProject.platform"] == option ? "largecircle.fill.circle" : "circle")
            Text(option)
            Spacer()
          }
        }
        .buttonStyle(.bordered)
        .tint(.orange)
      }
    }
  }

  private func questionCard(_ question: JumaoInterviewQuestion) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text("第 \(appState.interviewCurrentQuestionNumber) 题 / 共 \(appState.interviewCurrentStageQuestionCount) 题")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
          Text(question.title)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          Text(question.description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if let guidance = question.guidance, !guidance.isEmpty {
            Text("你可以这样想：")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(guidance)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let example = question.example, !example.isEmpty {
            Text("示例：")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(example)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer(minLength: 0)
        companionCat()
      }

      if question.inputType == "choice" {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(question.options ?? [], id: \.self) { option in
            Button {
              appState.updateInterviewAnswer(option, for: question.answerPath)
              _ = appState.advanceInterviewQuestion()
            } label: {
              HStack {
                Image(systemName: appState.interviewAnswers[question.answerPath] == option ? "largecircle.fill.circle" : "circle")
                Text(option)
                Spacer()
              }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
          }

          if question.answerPath == "newProject.platform",
             let message = appState.interviewPlatformMigrationMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      } else {
        nativeTextEditor(
          placeholder: question.placeholder ?? "请输入你的回答",
          answerPath: question.answerPath
        )
      }

      if let hint = appState.interviewInputHint {
        Text(hint)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let message = appState.interviewValidationMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Button("上一题") {
          appState.goToPreviousInterviewQuestion()
        }
        .buttonStyle(.bordered)
        .disabled(!appState.canGoToPreviousInterviewQuestion || isCatActionAnimating)

        if question.inputType != "choice" {
          Spacer()
          Button(appState.isLastInterviewQuestion ? (appState.hasNextInterviewStage ? "完成本阶段" : "完成填写") : "下一题") {
            advanceInterview()
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .disabled(isCatActionAnimating)
        }
      }
    }
    .padding(16)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.orange.opacity(0.28), lineWidth: 1)
    }
  }

  private func nativeTextEditor(placeholder: String, answerPath: String) -> some View {
    ZStack(alignment: .topLeading) {
      NativeInterviewTextView(
        text: appState.interviewAnswerBinding(for: answerPath),
        onTextChange: nodForTyping
      )
        .padding(1)
        .frame(minHeight: 84)

      if (appState.interviewAnswers[answerPath] ?? "").isEmpty {
        Text(placeholder)
          .font(.body)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 10)
          .padding(.vertical, 13)
          .allowsHitTesting(false)
      }
    }
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
    }
  }

  private var copyErrorDetailsButton: some View {
    VStack(alignment: .leading, spacing: 5) {
      Button("复制详细错误") {
        appState.copyInterviewErrorDetails()
      }
      .buttonStyle(.bordered)
      .disabled(appState.interviewErrorDetails == nil)

      if let message = appState.interviewErrorDetailsCopiedMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func advanceInterview() {
    guard appState.interviewCurrentQuestion?.required != true
      || !(appState.interviewAnswers[appState.interviewCurrentQuestion?.answerPath ?? ""] ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty else {
      _ = appState.advanceInterviewQuestion()
      return
    }

    if reduceMotion {
      _ = appState.advanceInterviewQuestion()
      return
    }

    if appState.isLastInterviewQuestion && !appState.hasNextInterviewStage {
      celebrateInterviewCompletion()
      return
    }

    isCatJumping = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      _ = appState.advanceInterviewQuestion()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        isCatJumping = false
      }
    }
  }

  private var isCatActionAnimating: Bool {
    isCatJumping || catCelebrationPhase != 0
  }

  private func companionCat(isWaiting: Bool = false) -> some View {
    InterviewCompanionCat(
      isIdleAnimating: isCatIdleAnimating,
      isTilting: isCatTilting,
      tiltDirection: catTiltDirection,
      isNodding: isCatNodding,
      isJumping: isCatJumping,
      celebrationPhase: catCelebrationPhase,
      isWaiting: isWaiting,
      reduceMotion: reduceMotion
    )
  }

  private func nodForTyping() {
    guard !reduceMotion,
          !isCatActionAnimating,
          Date().timeIntervalSince(lastCatNodAt) > 1.2 else { return }

    lastCatNodAt = Date()
    isCatNodding = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
      isCatNodding = false
    }
  }

  private func celebrateInterviewCompletion() {
    catCelebrationPhase = 1
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      catCelebrationPhase = 0
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
      catCelebrationPhase = 2
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
      _ = appState.advanceInterviewQuestion()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) {
      catCelebrationPhase = 0
    }
  }

  private func stopCatAnimation() {
    isCatIdleAnimating = false
    isCatTilting = false
    isCatNodding = false
    isCatJumping = false
    catCelebrationPhase = 0
  }
}

enum InterviewTextSynchronization {
  static func shouldApplyModelValue(isFirstResponder: Bool, hasMarkedText: Bool) -> Bool {
    !(isFirstResponder && hasMarkedText)
  }
}

enum NewProjectPlatformWording {
  static func usageDescription(for platform: String?) -> String {
    switch platform {
    case "iPhone": "先在 iPhone 上使用"
    case "Mac": "先在 Mac 上使用"
    case "网页": "先通过网页使用"
    default: "使用方式暂未确定"
    }
  }
}

private struct NativeInterviewTextView: NSViewRepresentable {
  @Binding var text: String
  let onTextChange: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onTextChange: onTextChange)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false

    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.string = text
    textView.font = .preferredFont(forTextStyle: .body)
    textView.textColor = .textColor
    textView.backgroundColor = .textBackgroundColor
    textView.drawsBackground = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    scrollView.documentView = textView

    DispatchQueue.main.async { [weak scrollView, weak textView] in
      guard let window = scrollView?.window,
            window.isKeyWindow,
            let textView,
            !(window.firstResponder is NSTextView) else { return }
      window.makeFirstResponder(textView)
    }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.update(text: $text, onTextChange: onTextChange)
    guard let textView = scrollView.documentView as? NSTextView,
          textView.string != text else { return }
    let isFirstResponder = textView.window?.firstResponder === textView
    guard InterviewTextSynchronization.shouldApplyModelValue(
      isFirstResponder: isFirstResponder,
      hasMarkedText: textView.hasMarkedText()
    ) else { return }

    let selection = textView.selectedRange()
    context.coordinator.isApplyingModelValue = true
    textView.string = text
    textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
    context.coordinator.isApplyingModelValue = false
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var isApplyingModelValue = false
    private var text: Binding<String>
    private var onTextChange: () -> Void

    init(text: Binding<String>, onTextChange: @escaping () -> Void) {
      self.text = text
      self.onTextChange = onTextChange
    }

    func update(text: Binding<String>, onTextChange: @escaping () -> Void) {
      self.text = text
      self.onTextChange = onTextChange
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingModelValue,
            let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
      onTextChange()
    }
  }
}

private struct InterviewCompanionCat: View {
  let isIdleAnimating: Bool
  let isTilting: Bool
  let tiltDirection: Double
  let isNodding: Bool
  let isJumping: Bool
  let celebrationPhase: Int
  let isWaiting: Bool
  let reduceMotion: Bool

  var body: some View {
    Image("JumaoCatColor")
      .resizable()
      .interpolation(.none)
      .scaledToFit()
      .frame(width: 40, height: 40)
      .scaleEffect(idleScale)
      .animation(idleAnimation, value: isIdleAnimating)
      .offset(y: idleOffset)
      .animation(idleAnimation, value: isIdleAnimating)
      .rotationEffect(.degrees(tiltAngle), anchor: .bottom)
      .animation(tiltAnimation, value: isTilting)
      .rotationEffect(.degrees(nodAngle), anchor: .top)
      .animation(nodAnimation, value: isNodding)
      .offset(y: actionOffset)
      .animation(actionAnimation, value: isJumping)
      .animation(actionAnimation, value: celebrationPhase)
      .accessibilityHidden(true)
  }

  private var idleScale: CGFloat {
    isIdleAnimating && !reduceMotion && !isWaiting ? 1.03 : 1
  }

  private var idleOffset: CGFloat {
    guard isIdleAnimating, !reduceMotion else { return 0 }
    return isWaiting ? -1 : -2.5
  }

  private var tiltAngle: Double {
    isTilting && !reduceMotion && !isWaiting ? tiltDirection * 2 : 0
  }

  private var nodAngle: Double {
    isNodding && !reduceMotion ? 5 : 0
  }

  private var actionOffset: CGFloat {
    guard !reduceMotion else { return 0 }
    if isJumping { return -8 }
    switch celebrationPhase {
    case 1: return -8
    case 2: return -6
    default: return 0
    }
  }

  private var idleAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: isWaiting ? 2.4 : 1.8).repeatForever(autoreverses: true)
  }

  private var tiltAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.28)
  }

  private var nodAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.12)
  }

  private var actionAnimation: Animation? {
    reduceMotion ? nil : .interpolatingSpring(stiffness: 280, damping: 12)
  }
}
