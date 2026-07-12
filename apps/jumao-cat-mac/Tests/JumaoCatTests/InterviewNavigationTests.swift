import XCTest
@testable import JumaoCat

@MainActor
final class InterviewNavigationTests: XCTestCase {
  func testNavigatesAllTwentyTwoQuestions() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 22, required: false))

    for number in 1...22 {
      XCTAssertEqual(appState.interviewCurrentQuestionNumber, number)
      if number < 22 {
        XCTAssertTrue(appState.advanceInterviewQuestion())
      }
    }

    XCTAssertTrue(appState.isLastInterviewQuestion)
  }

  func testPreviousAndNextKeepAnswersAfterReopeningInterview() {
    let appState = AppState()
    let schema = makeSchema(questionCount: 3, required: false)
    appState.beginInterview(with: schema)
    appState.updateInterviewAnswer("第一题答案", for: "question1")

    XCTAssertTrue(appState.advanceInterviewQuestion())
    appState.updateInterviewAnswer("第二题答案", for: "question2")
    appState.goToPreviousInterviewQuestion()

    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 1)
    XCTAssertEqual(appState.interviewAnswers["question1"], "第一题答案")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertEqual(appState.interviewAnswers["question2"], "第二题答案")

    appState.isInterviewPresented = false
    appState.beginInterview(with: schema)
    XCTAssertEqual(appState.interviewAnswers["question1"], "第一题答案")
    XCTAssertEqual(appState.interviewAnswers["question2"], "第二题答案")
  }

  func testRequiredQuestionBlocksNextQuestionUntilFilled() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 2, required: true))

    XCTAssertFalse(appState.advanceInterviewQuestion())
    XCTAssertEqual(appState.interviewValidationMessage, "请先填写这道必填问题。")
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 1)

    appState.updateInterviewAnswer("已填写", for: "question1")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 2)
  }

  func testListQuestionShowsCommaSeparatedHint() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 1, required: false, firstInputType: "list"))

    XCTAssertEqual(appState.interviewInputHint, "请使用逗号分隔多个项目。")
  }

  func testLastQuestionCompletesInterviewWithoutWritingFiles() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 1, required: true))
    appState.updateInterviewAnswer("已填写", for: "question1")

    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertTrue(appState.isInterviewComplete)
    XCTAssertEqual(appState.interviewQuestions.count, 1)
  }

  private func makeSchema(
    questionCount: Int,
    required: Bool,
    firstInputType: String = "text"
  ) -> JumaoInterviewSchema {
    JumaoInterviewSchema(
      schemaVersion: 1,
      questions: (1...questionCount).map { order in
        JumaoInterviewQuestion(
          id: "question\(order)",
          answerPath: "question\(order)",
          title: "问题 \(order)",
          description: "问题说明 \(order)",
          inputType: order == 1 ? firstInputType : "text",
          required: required,
          order: order
        )
      }
    )
  }
}
