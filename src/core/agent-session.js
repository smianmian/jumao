import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

export const defaultSessionTimeouts = {
  startupMs: 5 * 60 * 1000,
  stallMs: 15 * 60 * 1000,
  exitGraceMs: 60 * 1000,
  globalMs: 40 * 60 * 1000,
  termGraceMs: 10 * 1000,
  tickMs: 250
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function groupPids(pgid) {
  const result = spawnSync('ps', ['-A', '-o', 'pid=,pgid=,stat='], { encoding: 'utf8' });
  if (result.status !== 0 || !result.stdout) return [];
  return result.stdout.split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [pid, group, stat] = line.split(/\s+/);
      return { pid: Number(pid), pgid: Number(group), stat: stat || '' };
    })
    .filter((entry) => entry.pgid === pgid && !entry.stat.startsWith('Z'))
    .map((entry) => entry.pid);
}

function signalGroup(pgid, signal, record) {
  try {
    process.kill(-pgid, signal);
    record.signalsSent.push(signal);
  } catch (error) {
    if (error.code === 'ESRCH') record.noopSignals.push(signal);
    else throw error;
  }
}

export async function killProcessGroup({ pgid, termGraceMs = 10000, waitTickMs = 100 }) {
  const record = {
    pgid,
    noop: false,
    signalsSent: [],
    noopSignals: [],
    survivorsBeforeCleanup: [],
    survivors: []
  };
  // The guard: this helper only ever signals the negative pgid it was given,
  // and refuses anything that is not a regular positive group id.
  if (!Number.isInteger(pgid) || pgid <= 1) {
    record.noop = true;
    return record;
  }
  record.survivorsBeforeCleanup = groupPids(pgid);
  if (record.survivorsBeforeCleanup.length === 0) {
    record.noop = true;
    return record;
  }
  signalGroup(pgid, 'SIGTERM', record);
  const termDeadline = Date.now() + termGraceMs;
  while (Date.now() < termDeadline && groupPids(pgid).length > 0) await sleep(waitTickMs);
  let survivors = groupPids(pgid);
  if (survivors.length > 0) {
    signalGroup(pgid, 'SIGKILL', record);
    const killDeadline = Date.now() + 2000;
    while (Date.now() < killDeadline && groupPids(pgid).length > 0) await sleep(waitTickMs);
    survivors = groupPids(pgid);
  }
  record.survivors = survivors;
  return record;
}

export function runAgentSession({ command, args = [], cwd, env, evidenceDir, timeouts = {} }) {
  const limits = { ...defaultSessionTimeouts, ...timeouts };
  fs.mkdirSync(evidenceDir, { recursive: true });
  const files = {
    events: path.join(evidenceDir, 'events.jsonl'),
    stderr: path.join(evidenceDir, 'stderr.log'),
    timeline: path.join(evidenceDir, 'timeline.json')
  };
  const session = {
    command: [command, ...args].join(' '),
    spawnError: null,
    threadId: null,
    usage: null,
    finalMessage: null,
    milestones: {
      processSpawned: null,
      threadStarted: null,
      modelResponseStarted: null,
      firstToolStarted: null,
      firstToolCompleted: null,
      effectiveWorkStarted: null,
      turnCompleted: null,
      exited: null,
      cleanupCompleted: null
    },
    exit: { code: null, signal: null, natural: false, at: null },
    forced: { reason: null, signalsSent: [], survivorsBeforeCleanup: [], survivorsAfterCleanup: [] },
    residualAfterNaturalExit: [],
    residualCleanup: null,
    timersFired: [],
    eventCount: 0,
    parseErrorCount: 0,
    files
  };

  return new Promise((resolve) => {
    const eventsStream = fs.createWriteStream(files.events);
    const stderrStream = fs.createWriteStream(files.stderr);
    const startedAt = Date.now();
    let lastActivityAt = startedAt;
    let stdoutBuffer = '';
    let childExited = false;
    let cleaning = false;
    let finished = false;
    let ticker = null;

    const finalize = async () => {
      if (finished) return;
      finished = true;
      if (ticker) clearInterval(ticker);
      await Promise.all([
        new Promise((done) => eventsStream.end(done)),
        new Promise((done) => stderrStream.end(done))
      ]);
      fs.writeFileSync(files.timeline, `${JSON.stringify({
        command: session.command,
        startedAt,
        limits,
        milestones: session.milestones,
        timersFired: session.timersFired,
        exit: session.exit,
        forced: session.forced,
        residualAfterNaturalExit: session.residualAfterNaturalExit,
        residualCleanup: session.residualCleanup,
        eventCount: session.eventCount,
        parseErrorCount: session.parseErrorCount,
        spawnError: session.spawnError ? String(session.spawnError.message || session.spawnError) : null
      }, null, 2)}\n`, 'utf8');
      resolve(session);
    };

    let child;
    try {
      child = spawn(command, args, {
        cwd,
        env,
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe']
      });
    } catch (error) {
      session.spawnError = error;
      finalize();
      return;
    }

    const pgid = child.pid;

    child.on('error', (error) => {
      session.spawnError = error;
      if (!childExited) {
        childExited = true;
        finalize();
      }
    });

    // 同一解析器同时理解两种一次性 Agent 的 JSONL 方言：
    // codex exec --json（thread.started / item.* / turn.completed）
    // claude -p --output-format stream-json（system.init / assistant / user / result）
    const observeEvent = (line) => {
      session.eventCount += 1;
      lastActivityAt = Date.now();
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        session.parseErrorCount += 1;
        return;
      }
      const now = Date.now();
      const item = event.item || {};
      if (event.type === 'thread.started') {
        session.milestones.threadStarted ??= now;
        session.threadId = event.thread_id || session.threadId;
        return;
      }
      if (event.type === 'turn.completed') {
        session.milestones.turnCompleted ??= now;
        session.usage = event.usage || session.usage;
        return;
      }
      if (event.type && event.type.startsWith('item.')) {
        session.milestones.modelResponseStarted ??= now;
        const isMessage = item.type === 'agent_message' || item.type === 'reasoning';
        if (!isMessage) {
          session.milestones.firstToolStarted ??= now;
          session.milestones.effectiveWorkStarted ??= now;
          if (event.type === 'item.completed') session.milestones.firstToolCompleted ??= now;
        }
        if (event.type === 'item.completed' && item.type === 'agent_message' && typeof item.text === 'string') {
          session.finalMessage = item.text;
        }
        return;
      }
      if (event.type === 'system' && event.subtype === 'init') {
        session.milestones.threadStarted ??= now;
        session.threadId = event.session_id || session.threadId;
        return;
      }
      if (event.type === 'assistant') {
        session.milestones.modelResponseStarted ??= now;
        const blocks = Array.isArray(event.message?.content) ? event.message.content : [];
        if (blocks.some((block) => block?.type === 'tool_use')) {
          session.milestones.firstToolStarted ??= now;
          session.milestones.effectiveWorkStarted ??= now;
        }
        const text = blocks.filter((block) => block?.type === 'text' && typeof block.text === 'string')
          .map((block) => block.text).join('\n');
        if (text) session.finalMessage = text;
        return;
      }
      if (event.type === 'user') {
        const blocks = Array.isArray(event.message?.content) ? event.message.content : [];
        if (blocks.some((block) => block?.type === 'tool_result')) {
          session.milestones.firstToolCompleted ??= now;
        }
        return;
      }
      if (event.type === 'result') {
        session.milestones.turnCompleted ??= now;
        session.usage = event.usage || session.usage;
        if (typeof event.result === 'string' && event.result) session.finalMessage = event.result;
      }
    };

    child.stdout.on('data', (chunk) => {
      eventsStream.write(chunk);
      stdoutBuffer += chunk.toString('utf8');
      let newline = stdoutBuffer.indexOf('\n');
      while (newline !== -1) {
        const line = stdoutBuffer.slice(0, newline).trim();
        stdoutBuffer = stdoutBuffer.slice(newline + 1);
        if (line) observeEvent(line);
        newline = stdoutBuffer.indexOf('\n');
      }
    });

    child.stderr.on('data', (chunk) => {
      stderrStream.write(chunk);
    });

    const forceCleanup = async (reason) => {
      if (cleaning || childExited) return;
      cleaning = true;
      session.forced.reason = reason;
      session.timersFired.push(reason);
      const record = await killProcessGroup({ pgid, termGraceMs: limits.termGraceMs });
      session.forced.signalsSent = record.signalsSent;
      session.forced.survivorsBeforeCleanup = record.survivorsBeforeCleanup;
      session.forced.survivorsAfterCleanup = record.survivors;
      session.milestones.cleanupCompleted = Date.now();
    };

    ticker = setInterval(() => {
      if (finished || childExited || cleaning) return;
      const now = Date.now();
      const { turnCompleted, threadStarted, modelResponseStarted } = session.milestones;
      if (turnCompleted && now - turnCompleted > limits.exitGraceMs) {
        forceCleanup('exit_grace');
        return;
      }
      if ((!threadStarted || !modelResponseStarted) && now - startedAt > limits.startupMs) {
        forceCleanup('startup_timeout');
        return;
      }
      if (now - lastActivityAt > limits.stallMs) {
        forceCleanup('stall');
        return;
      }
      if (now - startedAt > limits.globalMs) {
        forceCleanup('global_timeout');
      }
    }, limits.tickMs);

    child.on('exit', async (code, signal) => {
      childExited = true;
      const now = Date.now();
      session.exit = { code, signal: signal || null, natural: !session.forced.reason, at: now };
      session.milestones.exited = now;
      if (session.exit.natural) {
        const residual = groupPids(pgid).filter((pid) => pid !== child.pid);
        if (residual.length > 0) {
          session.residualAfterNaturalExit = residual;
          session.residualCleanup = await killProcessGroup({ pgid, termGraceMs: limits.termGraceMs });
          session.milestones.cleanupCompleted = Date.now();
        }
      } else {
        // Give the group scan one settle pass so the record reflects reality.
        session.forced.survivorsAfterCleanup = groupPids(pgid);
      }
      finalize();
    });

    session.milestones.processSpawned = Date.now();
  });
}
