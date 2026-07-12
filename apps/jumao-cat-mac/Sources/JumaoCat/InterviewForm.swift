import SwiftUI

struct InterviewForm: View {
  let schema: JumaoInterviewSchema
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var answer = ""
  @State private var currentQuestionIndex = 0
  @State private var isCatIdleAnimating = false
  @State private var isCatJumping = false

  private var questions: [JumaoInterviewQuestion] {
    schema.questions.sorted { $0.order < $1.order }
  }

  private var currentQuestion: JumaoInterviewQuestion? {
    guard questions.indices.contains(currentQuestionIndex) else { return nil }
    return questions[currentQuestionIndex]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("回答项目问题")
          .font(.title3.weight(.semibold))
        Spacer()
        Text("共 \(questions.count) 题")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }

      if let question = currentQuestion {
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
  }

  private func questionCard(_ question: JumaoInterviewQuestion) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Text("第 \(currentQuestionIndex + 1) 题 / 共 \(questions.count) 题")
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

      TextField("请输入你的回答", text: $answer, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...3)

      HStack {
        Spacer()
        Button("下一题") {
          moveToNextQuestion()
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

  private func moveToNextQuestion() {
    guard currentQuestionIndex < questions.count - 1 else { return }

    if reduceMotion {
      advanceQuestion()
      return
    }

    isCatJumping = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      isCatJumping = false
      advanceQuestion()
    }
  }

  private func advanceQuestion() {
    currentQuestionIndex += 1
    answer = ""
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
