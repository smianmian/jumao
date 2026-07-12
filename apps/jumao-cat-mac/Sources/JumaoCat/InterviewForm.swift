import SwiftUI

struct InterviewForm: View {
  let schema: JumaoInterviewSchema
  @State private var answer = ""

  private var firstQuestion: JumaoInterviewQuestion? {
    schema.questions.sorted { $0.order < $1.order }.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("回答项目问题")
        .font(.title2.weight(.semibold))

      Text("共 \(schema.questions.count) 题")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      if let question = firstQuestion {
        Text("第 1 题 / 共 \(schema.questions.count) 题")
          .font(.headline)
        Text(question.title)
          .font(.title3.weight(.semibold))
        Text(question.description)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        TextField("请输入你的回答", text: $answer, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(3, reservesSpace: true)

        Button("下一题") {}
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 460, alignment: .leading)
  }
}
