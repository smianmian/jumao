import assert from 'node:assert/strict';
import test from 'node:test';
import { agentGroups } from '../src/core/agent-registry.js';
import { interviewSchema } from '../src/core/interview.js';
import { routeInterview } from '../src/core/interview-router.js';

const entryQuestionIds = [
  'firstVersionGoal',
  'primaryUser',
  'userCanDo',
  'wontDo'
];

const baselineGroupIds = [
  'direction_entity',
  'product_design',
  'tech_development'
];

const answerPaths = [
  'primaryUser',
  'firstVersionGoal',
  'userCanDo',
  'successEvidence',
  'cannotCollect',
  'humanConfirmActions',
  'mustDo',
  'wontDo',
  'aiMustNotAdd',
  'mainScreen.name',
  'mainScreen.userGoal',
  'mainScreen.loading',
  'mainScreen.empty',
  'mainScreen.error',
  'mainScreen.success',
  'mainScreen.permissionDenied',
  'dataSafety.collects',
  'dataSafety.doesNotCollect',
  'dataSafety.thirdParties',
  'dataSafety.deletion',
  'dataSafety.retention'
];

function route(overrides = {}) {
  return routeInterview({
    entryAnswers: {},
    routingSelections: [],
    phase: 'start',
    ...overrides
  });
}

test('interview schema defines exactly four fixed entry questions', () => {
  assert.deepEqual(interviewSchema.entryQuestionIds, entryQuestionIds);
  assert.equal(new Set(interviewSchema.entryQuestionIds).size, 4);

  const entryQuestions = interviewSchema.questions.filter((question) => question.askMode === 'entry');
  assert.equal(entryQuestions.length, 4);
  assert.deepEqual(
    new Set(entryQuestions.map((question) => question.id)),
    new Set(entryQuestionIds)
  );
  assert.ok(entryQuestions.every((question) => question.phase === 'start'));
});

test('router always activates the three baseline agent groups', () => {
  const result = route({ phase: 'build' });

  assert.deepEqual(result.activeGroups, baselineGroupIds);
  assert.ok(baselineGroupIds.every((groupId) => !result.deferredGroups.includes(groupId)));
});

test('each routing option activates only its mapped agent group', () => {
  const options = interviewSchema.routing.question.options.filter((option) => !option.exclusive);

  for (const option of options) {
    const result = route({ routingSelections: [option.id], phase: 'build' });
    assert.deepEqual(
      new Set(result.activeGroups),
      new Set([...baselineGroupIds, option.groupId]),
      option.id
    );
  }
});

test('the none option does not activate conditional groups', () => {
  const result = route({
    routingSelections: ['none', 'payments_subscriptions_refunds'],
    phase: 'release'
  });

  assert.deepEqual(result.activeGroups, baselineGroupIds);
  assert.deepEqual(result.questionQueue, []);
});

test('router never guesses groups from natural-language entry answers', () => {
  const result = route({
    entryAnswers: {
      firstVersionGoal: '做一个需要登录、订阅、健康数据并上架 App Store 的产品',
      primaryUser: '付费用户',
      userCanDo: '登录后保存健康记录',
      wontDo: ['暂不处理退款']
    },
    phase: 'release'
  });

  assert.deepEqual(result.activeGroups, baselineGroupIds);
  assert.deepEqual(result.questionQueue, []);
});

test('start phase returns only the four entry questions in fixed order', () => {
  const result = route({
    routingSelections: interviewSchema.routing.question.options.map((option) => option.id),
    phase: 'start'
  });

  assert.deepEqual(result.questionQueue.map((question) => question.id), entryQuestionIds);
  assert.ok(result.questionQueue.every((question) => question.askMode === 'entry'));
});

test('build phase never returns release questions', () => {
  const result = route({
    routingSelections: interviewSchema.routing.question.options
      .filter((option) => !option.exclusive)
      .map((option) => option.id),
    phase: 'build'
  });

  assert.ok(result.questionQueue.length > 0);
  assert.ok(result.questionQueue.every((question) => question.phase === 'build'));
  assert.ok(result.questionQueue.every((question) => question.askMode === 'conditional'));
});

test('release phase returns questions only for explicitly active groups', () => {
  const result = route({
    routingSelections: ['payments_subscriptions_refunds', 'platform_distribution'],
    phase: 'release'
  });

  assert.deepEqual(
    result.questionQueue.map((question) => question.answerPath),
    ['humanConfirmActions', 'mainScreen.permissionDenied']
  );
  assert.ok(result.questionQueue.every((question) => result.activeGroups.includes(question.ownerGroupId)));
});

test('question queues never contain duplicate questions', () => {
  for (const phase of ['start', 'build', 'release']) {
    const result = route({
      routingSelections: interviewSchema.routing.question.options
        .filter((option) => !option.exclusive)
        .map((option) => option.id),
      phase
    });
    const paths = result.questionQueue.map((question) => question.answerPath);
    assert.equal(new Set(paths).size, paths.length, phase);
  }
});

test('all interview questions belong to registered agent groups', () => {
  const groupIds = new Set(agentGroups.map((group) => group.id));

  for (const question of interviewSchema.questions) {
    assert.ok(groupIds.has(question.ownerGroupId), question.answerPath);
    assert.ok(['start', 'build', 'release'].includes(question.phase), question.answerPath);
    assert.ok(['entry', 'conditional'].includes(question.askMode), question.answerPath);
    assert.equal(typeof question.requiredWhenActive, 'boolean', question.answerPath);
  }
});

test('schema version 2 preserves all 21 answer paths', () => {
  assert.equal(interviewSchema.schemaVersion, 2);
  assert.equal(interviewSchema.questions.length, 21);
  assert.deepEqual(interviewSchema.questions.map((question) => question.answerPath), answerPaths);
});
