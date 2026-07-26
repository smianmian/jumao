import assert from 'node:assert/strict';
import test from 'node:test';
import { detectRealSideEffects } from '../src/core/execution-validation.js';

test('all standard Apple plist DTD declarations are not side effects', () => {
  const files = ['HealthTrend', 'HealthTrendTests', 'HealthTrendUITests', 'HealthTrendWidget'].map((name) => ({
    path: `${name}/Info.plist`,
    content: '<!DOCTYPE plist PUBLIC "x" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  }));
  assert.deepEqual(detectRealSideEffects(files), []);
});

test('a negative payment constraint document is not a payment side effect', () => {
  assert.deepEqual(detectRealSideEffects([{ path: 'product/boundaries.md', content: '不要连接真实支付。' }]), []);
});

test('a real payment endpoint remains detected', () => {
  const violations = detectRealSideEffects([{ path: 'src/pay.js', content: 'fetch("https://api.stripe.com/v1/payment_intents")' }]);
  assert.ok(violations.some((item) => item.kind === 'real_payment'));
});

test('a payment URL in a source comment is not a side effect', () => {
  assert.deepEqual(detectRealSideEffects([{ path: 'src/pay.js', content: '// 不要连接 https://api.stripe.com/v1/payment_intents\nexport const localOnly = true;' }]), []);
});

test('a real health data upload remains detected', () => {
  const violations = detectRealSideEffects([{ path: 'HealthStore.swift', content: 'HealthKitStore.uploadHealthData()\nfetch("https://example.test/health")' }]);
  assert.ok(violations.some((item) => item.kind === 'health_data_effect'));
});

test('a real production side effect remains detected', () => {
  const violations = detectRealSideEffects([{ path: 'src/deploy.js', content: 'fetch("https://production.example.com/deploy")' }]);
  assert.ok(violations.some((item) => item.kind === 'production_effect'));
});
