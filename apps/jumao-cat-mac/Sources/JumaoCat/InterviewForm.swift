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

      if appState.isLoadingInterviewSchema {
        loadingCard
      } else if let schemaError = appState.interviewSchemaError {
        errorCard(title: "无法打开项目问答", message: schemaError)
      } else if appState.isCurrentInterviewStageComplete {
        if appState.hasNextInterviewStage {
          stageCompletionCard
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
      Text("将生成或更新 4 份项目文档，不修改项目源代码。")
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
    guard let stage = appState.currentInterviewStage else { return appState.interviewWindowTitle }
    return "第 \(stage.order) 阶段：\(stage.title)"
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
    }
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

  private func questionCard(_ question: JumaoInterviewQuestion) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text("第 \(appState.interviewCurrentQuestionNumber) 题 / 共 \(appState.interviewCurrentStageQuestionCount) 题")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
          if appState.isInterviewQuestionMarkedForCompletion(question) {
            Text("待补充")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.orange)
          }
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

      TextField(
        question.placeholder ?? "请输入你的回答",
        text: appState.interviewAnswerBinding(for: question.answerPath),
        axis: .vertical
      )
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...3)
        .onChange(of: appState.interviewAnswers[question.answerPath] ?? "") { _, _ in
          nodForTyping()
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

        Spacer()
        Button("先跳过") {
          appState.skipCurrentInterviewQuestion()
        }
        .buttonStyle(.bordered)
        .disabled(isCatActionAnimating)

        Button(appState.isLastInterviewQuestion ? (appState.hasNextInterviewStage ? "完成本阶段" : "完成填写") : "下一题") {
          advanceInterview()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isCatActionAnimating)
      }
    }
    .padding(16)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.orange.opacity(0.28), lineWidth: 1)
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
