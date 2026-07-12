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
        Text("回答项目问题")
          .font(.title3.weight(.semibold))
        Spacer()
        Text("共 \(appState.interviewQuestions.count) 题")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }

      if appState.isInterviewComplete {
        completionCard
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

  private var completionCard: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        if appState.isCheckingProject {
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
          }
        } else if let message = appState.interviewWriteMessage {
          Text(message)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          Button("开始检查") {
            appState.startProjectCheck()
          }
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .disabled(!appState.canStartProjectCheck)
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
          .disabled(appState.isWritingInterviewAnswers)
        }

        if let error = appState.interviewWriteError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
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
          Text("第 \(appState.interviewCurrentQuestionNumber) 题 / 共 \(appState.interviewQuestions.count) 题")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
          Text(question.title)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
          Text(question.description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
        companionCat()
      }

      TextField("请输入你的回答", text: appState.interviewAnswerBinding(for: question.answerPath), axis: .vertical)
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
        Button(appState.isLastInterviewQuestion ? "完成填写" : "下一题") {
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

    if appState.isLastInterviewQuestion {
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
