import SwiftUI

struct InterviewForm: View {
  @ObservedObject var appState: AppState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCatIdleAnimating = false
  @State private var isCatJumping = false

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
    .onAppear {
      isCatIdleAnimating = !reduceMotion
    }
    .onChange(of: reduceMotion) { _, shouldReduceMotion in
      isCatIdleAnimating = !shouldReduceMotion
      if shouldReduceMotion {
        isCatJumping = false
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
    VStack(alignment: .leading, spacing: 10) {
      if appState.isCheckingProject {
        Text("正在检查")
          .font(.headline)
        ProgressView()
        Button("正在检查") {}
          .buttonStyle(.borderedProminent)
          .tint(.orange)
          .disabled(true)
      } else if let message = appState.projectCheckMessage {
        Text(message)
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        if let error = appState.projectCheckError {
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
        InterviewCompanionCat(
          isIdleAnimating: isCatIdleAnimating,
          isJumping: isCatJumping,
          reduceMotion: reduceMotion
        )
      }

      TextField("请输入你的回答", text: appState.interviewAnswerBinding(for: question.answerPath), axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...3)

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
        .disabled(!appState.canGoToPreviousInterviewQuestion || isCatJumping)

        Spacer()
        Button(appState.isLastInterviewQuestion ? "完成填写" : "下一题") {
          advanceInterview()
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isCatJumping)
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

    isCatJumping = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      isCatJumping = false
      _ = appState.advanceInterviewQuestion()
    }
  }
}

private struct InterviewCompanionCat: View {
  let isIdleAnimating: Bool
  let isJumping: Bool
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
      .offset(y: jumpOffset)
      .animation(jumpAnimation, value: isJumping)
      .accessibilityHidden(true)
  }

  private var idleScale: CGFloat {
    isIdleAnimating && !reduceMotion ? 1.03 : 1
  }

  private var idleOffset: CGFloat {
    isIdleAnimating && !reduceMotion ? -2 : 0
  }

  private var jumpOffset: CGFloat {
    isJumping && !reduceMotion ? -8 : 0
  }

  private var idleAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
  }

  private var jumpAnimation: Animation? {
    reduceMotion ? nil : .interpolatingSpring(stiffness: 280, damping: 12)
  }
}
