import XCTest
@testable import JumaoCat

@MainActor
final class InterviewNavigationTests: XCTestCase {
  func testNavigatesAllTwentyOneQuestions() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 21, required: false))

    for number in 1...21 {
      XCTAssertEqual(appState.interviewCurrentQuestionNumber, number)
      if number < 21 {
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

  func testTemporarilyHidingInterviewKeepsAnswersAndQuestionPosition() {
    let appState = AppState()
    let schema = makeSchema(questionCount: 3, required: false)
    appState.beginInterview(with: schema)
    appState.updateInterviewAnswer("第一题答案", for: "question1")
    XCTAssertTrue(appState.advanceInterviewQuestion())

    appState.hideInterview()
    XCTAssertFalse(appState.isInterviewPresented)

    appState.beginInterview(with: schema)
    XCTAssertTrue(appState.isInterviewPresented)
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 2)
    XCTAssertEqual(appState.interviewAnswers["question1"], "第一题答案")
  }

  func testLastQuestionCompletesInterviewWithoutWritingFiles() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 1, required: true))
    appState.updateInterviewAnswer("已填写", for: "question1")

    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertTrue(appState.isInterviewComplete)
    XCTAssertEqual(appState.interviewQuestions.count, 1)
  }

  func testSkippedQuestionIsMarkedAndCanBeCompletedLater() {
    let appState = AppState()
    let schema = makeSchema(questionCount: 2, required: true)
    appState.beginInterview(with: schema)

    appState.skipCurrentInterviewQuestion()

    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 2)
    XCTAssertTrue(appState.isInterviewQuestionMarkedForCompletion(schema.questions[0]))
    XCTAssertEqual(appState.pendingInterviewQuestions.map(\.answerPath), ["question1", "question2"])

    appState.updateInterviewAnswer("第二题答案", for: "question2")
    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertTrue(appState.isInterviewComplete)
    XCTAssertEqual(appState.pendingInterviewQuestions.map(\.answerPath), ["question1"])
    XCTAssertFalse(appState.canWriteCompletedInterview)

    appState.jumpToInterviewQuestion(schema.questions[0])
    XCTAssertEqual(appState.interviewCurrentQuestionNumber, 1)
    XCTAssertFalse(appState.isInterviewComplete)
    appState.updateInterviewAnswer("第一题答案", for: "question1")
    XCTAssertFalse(appState.isInterviewQuestionMarkedForCompletion(schema.questions[0]))
    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertTrue(appState.advanceInterviewQuestion())
    XCTAssertTrue(appState.pendingInterviewQuestions.isEmpty)
    XCTAssertTrue(appState.canWriteCompletedInterview)
  }

  func testPlaceholderAnswerDoesNotCountAsCompletedAnswer() {
    let appState = AppState()
    appState.beginInterview(with: makeSchema(questionCount: 1, required: true))
    appState.updateInterviewAnswer("暂不确定", for: "question1")

    XCTAssertFalse(appState.advanceInterviewQuestion())
    XCTAssertEqual(appState.interviewValidationMessage, "请先填写这道必填问题。")
  }

  func testStagesKeepFiveTenAndSevenQuestionsInOrder() {
    let appState = AppState()
    appState.beginInterview(with: makeThreeStageSchema())

    XCTAssertEqual(appState.interviewStages.map(\.id), ["idea", "prototype", "release"])
    XCTAssertEqual(appState.interviewStages.map { stage in
      appState.interviewQuestions.filter { $0.stage == stage.id }.count
    }, [5, 10, 6])
    XCTAssertEqual(appState.currentInterviewStage?.id, "idea")
    XCTAssertEqual(appState.interviewCurrentStageQuestionCount, 5)
  }

  func testFirstStageCanTemporarilyEndAndContinueToSecondStage() {
    let appState = AppState()
    appState.beginInterview(with: makeThreeStageSchema())

    completeCurrentStage(in: appState)

    XCTAssertTrue(appState.isCurrentInterviewStageComplete)
    XCTAssertFalse(appState.isInterviewComplete)
    XCTAssertFalse(appState.canWriteCompletedInterview)
    appState.hideInterview()
    XCTAssertFalse(appState.isInterviewPresented)

    appState.beginInterview(with: makeThreeStageSchema())
    XCTAssertEqual(appState.currentInterviewStage?.id, "idea")
    XCTAssertTrue(appState.isCurrentInterviewStageComplete)

    appState.continueToNextInterviewStage()
    XCTAssertEqual(appState.currentInterviewStage?.id, "prototype")
    XCTAssertEqual(appState.interviewCurrentStageQuestionCount, 10)
    XCTAssertFalse(appState.isCurrentInterviewStageComplete)
  }

  func testPendingQuestionsOnlyCountWithinCurrentStage() {
    let appState = AppState()
    appState.beginInterview(with: makeThreeStageSchema())
    completeCurrentStage(in: appState)
    appState.continueToNextInterviewStage()

    appState.skipCurrentInterviewQuestion()
    completeCurrentStage(in: appState)

    XCTAssertEqual(appState.currentInterviewStage?.id, "prototype")
    XCTAssertEqual(appState.pendingCurrentStageInterviewQuestions.map(\.answerPath), ["question6"])
  }

  func testPreviousQuestionCrossesStageBoundaryAndKeepsAnswers() {
    let appState = AppState()
    let schema = makeThreeStageSchema()
    appState.beginInterview(with: schema)
    appState.updateInterviewAnswer("第二阶段答案", for: "question6")

    appState.jumpToInterviewQuestion(schema.questions[15])
    appState.goToPreviousInterviewQuestion()
    XCTAssertEqual(appState.currentInterviewStage?.id, "prototype")
    XCTAssertEqual(appState.interviewCurrentQuestion?.answerPath, "question15")

    appState.jumpToInterviewQuestion(schema.questions[5])
    appState.goToPreviousInterviewQuestion()
    XCTAssertEqual(appState.currentInterviewStage?.id, "idea")
    XCTAssertEqual(appState.interviewCurrentQuestion?.answerPath, "question5")
    XCTAssertEqual(appState.interviewAnswers["question6"], "第二阶段答案")
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

  private func makeThreeStageSchema() -> JumaoInterviewSchema {
    let stages = [
      JumaoInterviewStage(id: "idea", title: "想法", description: "说明", order: 1),
      JumaoInterviewStage(id: "prototype", title: "第一版", description: "说明", order: 2),
      JumaoInterviewStage(id: "release", title: "给别人使用", description: "说明", order: 3)
    ]
    let questions = (1...21).map { order in
      let stage = order <= 5 ? "idea" : (order <= 15 ? "prototype" : "release")
      return JumaoInterviewQuestion(
        id: "question\(order)",
        answerPath: "question\(order)",
        title: "问题 \(order)",
        description: "说明",
        stage: stage,
        inputType: "text",
        required: true,
        order: order
      )
    }
    return JumaoInterviewSchema(schemaVersion: 1, stages: stages, questions: questions)
  }

  private func completeCurrentStage(in appState: AppState) {
    while !appState.isCurrentInterviewStageComplete {
      guard let question = appState.interviewCurrentQuestion else {
        return XCTFail("当前阶段应有题目")
      }
      appState.updateInterviewAnswer("已填写 \(question.id)", for: question.answerPath)
      XCTAssertTrue(appState.advanceInterviewQuestion())
    }
  }

}
