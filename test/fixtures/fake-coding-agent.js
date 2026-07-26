#!/usr/bin/env node
// Synthetic one-shot Coding Agent that speaks the codex exec --json dialect.
// FAKE_AGENT_SCENARIO selects a lifecycle behavior; timings come from env so
// tests can keep every scenario fast.

import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const scenario = process.env.FAKE_AGENT_SCENARIO || 'complete_and_exit';
const workDir = process.env.FAKE_AGENT_WORKDIR || process.cwd();
const toolMs = Number(process.env.FAKE_AGENT_TOOL_MS || 120);
const receiptOverride = process.env.FAKE_AGENT_RECEIPT || null;

const emit = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const stayAlive = () => setInterval(() => {}, 1000);

const receipt = receiptOverride || JSON.stringify({
  jumaoCompletion: {
    status: 'completed',
    goalsCompleted: ['goal:demo'],
    goalsBlocked: [],
    validation: [{ command: 'npm test', exitCode: 0 }],
    productionEffects: false,
    remainingWork: []
  }
});

const finalMessage = `好的，爹！工作完成。\n\`\`\`json\n${receipt}\n\`\`\`\n再见。`;

function threadStart() {
  emit({ type: 'thread.started', thread_id: 'fake-thread-1' });
  emit({ type: 'turn.started' });
}

function toolItem(id, command, exitCode) {
  emit({ type: 'item.started', item: { id, type: 'command_execution', command, aggregated_output: '', exit_code: null, status: 'in_progress' } });
  emit({ type: 'item.completed', item: { id, type: 'command_execution', command, aggregated_output: 'ok\n', exit_code: exitCode, status: 'completed' } });
}

function finish(message = finalMessage) {
  emit({ type: 'item.completed', item: { id: 'item_final', type: 'agent_message', text: message } });
  emit({ type: 'turn.completed', usage: { input_tokens: 10, cached_input_tokens: 0, output_tokens: 5 } });
}

async function main() {
  if (scenario === 'claude_complete_and_exit') {
    // Claude Code 的 stream-json 方言：system.init → assistant(tool_use) → user(tool_result) → result。
    emit({ type: 'system', subtype: 'init', session_id: 'fake-claude-session', model: 'claude-sonnet-4-6' });
    emit({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', id: 'tool_1', name: 'Bash', input: { command: 'echo ok' } }] } });
    emit({ type: 'user', message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'tool_1', content: 'ok' }] } });
    emit({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: '完成了。' }] } });
    emit({ type: 'result', subtype: 'success', result: finalMessage, usage: { input_tokens: 12, output_tokens: 6 } });
    return;
  }
  if (scenario === 'never_start') {
    // The process and event stream come up, but the model never begins work.
    threadStart();
    stayAlive();
    return;
  }
  if (scenario === 'environment_error') {
    process.stderr.write('ERROR stream error: unauthorized\n');
    process.exit(1);
  }
  if (scenario === 'wait_stdin_then_complete') {
    // Blocks until stdin reaches EOF, exactly like codex exec with piped stdin.
    // A runner that closes stdin at spawn unblocks this immediately.
    await new Promise((resolve) => {
      process.stdin.resume();
      process.stdin.on('end', resolve);
      process.stdin.on('error', resolve);
    });
  }
  threadStart();
  if (scenario === 'tool_hang') {
    emit({ type: 'item.started', item: { id: 'item_1', type: 'command_execution', command: 'sleep forever', aggregated_output: '', exit_code: null, status: 'in_progress' } });
    stayAlive();
    return;
  }
  if (scenario === 'tool_hang_with_child') {
    const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000);'], { stdio: 'ignore' });
    fs.writeFileSync(path.join(workDir, 'fake-agent-child.pid'), String(child.pid));
    emit({ type: 'item.started', item: { id: 'item_1', type: 'command_execution', command: 'long child', aggregated_output: '', exit_code: null, status: 'in_progress' } });
    stayAlive();
    return;
  }
  if (scenario === 'event_drip_forever') {
    let index = 0;
    setInterval(() => {
      index += 1;
      toolItem(`item_${index}`, `echo drip-${index}`, 0);
    }, 150);
    return;
  }
  if (scenario === 'slow_tool_completes') {
    emit({ type: 'item.started', item: { id: 'item_1', type: 'command_execution', command: 'npm test (slow)', aggregated_output: '', exit_code: null, status: 'in_progress' } });
    await sleep(toolMs);
    emit({ type: 'item.completed', item: { id: 'item_1', type: 'command_execution', command: 'npm test (slow)', aggregated_output: 'ok\n', exit_code: 0, status: 'completed' } });
    finish();
    return;
  }
  if (scenario === 'work_no_receipt') {
    fs.writeFileSync(path.join(workDir, 'modified-by-agent.txt'), 'changed\n');
    toolItem('item_1', 'apply change', 0);
    finish('工作完成了，但我忘了写回执。');
    return;
  }
  if (scenario === 'malformed_receipt') {
    toolItem('item_1', 'apply change', 0);
    finish('这是回执：{"jumaoCompletion": {"status": "completed", ');
    return;
  }
  if (scenario === 'receipt_then_hang') {
    toolItem('item_1', 'apply change', 0);
    finish();
    stayAlive();
    return;
  }
  if (scenario === 'leak_child') {
    const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000);'], { stdio: 'ignore' });
    child.unref();
    fs.writeFileSync(path.join(workDir, 'fake-agent-child.pid'), String(child.pid));
    toolItem('item_1', 'apply change', 0);
    finish();
    return;
  }
  // complete_and_exit (default), including after wait_stdin_then_complete.
  toolItem('item_1', 'apply change', 0);
  finish();
}

main();
