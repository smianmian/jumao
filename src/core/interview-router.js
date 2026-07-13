import { agentGroups } from './agent-registry.js';
import { interviewSchema } from './interview.js';

const phases = new Set(['start', 'build', 'release']);

export function routeInterview(input = {}, schema = interviewSchema) {
  const entryAnswers = input.entryAnswers ?? {};
  const routingSelections = input.routingSelections ?? [];
  const phase = input.phase ?? 'start';

  if (typeof entryAnswers !== 'object' || entryAnswers === null || Array.isArray(entryAnswers)) {
    throw new TypeError('entryAnswers must be an object');
  }
  if (!Array.isArray(routingSelections)) {
    throw new TypeError('routingSelections must be an array');
  }
  if (!phases.has(phase)) {
    throw new RangeError(`Unknown interview phase: ${phase}`);
  }

  const validGroupIds = new Set(agentGroups.map((group) => group.id));
  const routingOptions = schema.routing?.question?.options ?? [];
  const selectedIds = new Set(routingSelections);
  const noneSelected = routingOptions.some(
    (option) => option.exclusive === true && selectedIds.has(option.id)
  );
  const selectedGroupIds = noneSelected
    ? []
    : routingOptions
        .filter((option) => selectedIds.has(option.id))
        .map((option) => option.groupId)
        .filter(Boolean);
  const activeGroups = unique([
    ...(schema.routing?.alwaysActiveGroupIds ?? []),
    ...selectedGroupIds
  ]).filter((groupId) => validGroupIds.has(groupId));
  const activeGroupIds = new Set(activeGroups);
  const deferredGroups = agentGroups
    .map((group) => group.id)
    .filter((groupId) => !activeGroupIds.has(groupId));

  const questionQueue = phase === 'start'
    ? uniqueQuestions(
        (schema.entryQuestionIds ?? [])
          .map((questionId) => schema.questions.find((question) => question.id === questionId))
          .filter(Boolean)
      )
    : uniqueQuestions(
        schema.questions
          .filter((question) => (
            question.phase === phase
            && question.askMode === 'conditional'
            && activeGroupIds.has(question.ownerGroupId)
          ))
          .sort((left, right) => left.order - right.order)
      );

  return {
    activeGroups,
    deferredGroups,
    questionQueue
  };
}

function unique(values) {
  return [...new Set(values)];
}

function uniqueQuestions(questions) {
  const seenAnswerPaths = new Set();
  return questions.filter((question) => {
    if (seenAnswerPaths.has(question.answerPath)) return false;
    seenAnswerPaths.add(question.answerPath);
    return true;
  });
}
