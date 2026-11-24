import type { ColdStart, ColdStep } from "../core/cold-start.ts";

import { coldPending, coldRecord, recordCold } from "../core/cold-start.ts";

const STEPS: readonly ColdStep[] = ["create", "warm", "claims", "query"];

/** Runs `work` and records its duration when it is the first `step`. */
export async function timeFirst<T>(
  step: ColdStep,
  work: () => Promise<T>,
): Promise<T> {
  if (!coldPending(step)) {
    return work();
  }

  const started = performance.now();

  try {
    return await work();
  } finally {
    recordCold(step, performance.now() - started);
  }
}

function rounded(ms: number): string {
  return String(Math.round(ms * 10) / 10);
}

/**
 * `eval:…,ready:…,create:…,warm:…,claims:…,query:…`, leaving out what hasn't
 * run. `eval` is the time `better-supabase/next` took to evaluate, `ready` the
 * process time at which it finished.
 */
export function formatColdStart(timings: ColdStart): string {
  const parts: string[] = [];

  if (timings.evalStart !== undefined && timings.evalEnd !== undefined) {
    parts.push(`eval:${rounded(timings.evalEnd - timings.evalStart)}`);
  }

  if (timings.evalEnd !== undefined) {
    parts.push(`ready:${rounded(timings.evalEnd)}`);
  }

  for (const step of STEPS) {
    const ms = timings[step];

    if (ms !== undefined) {
      parts.push(`${step}:${rounded(ms)}`);
    }
  }

  return parts.join(",");
}

/**
 * The formatted record when it gained a step since the last call, so each new
 * timing is reported once per process.
 */
export function takeColdStart(): string | undefined {
  const current = coldRecord();
  const formatted = formatColdStart(current.timings);

  if (formatted === "" || formatted === current.reported) {
    return undefined;
  }

  current.reported = formatted;

  return formatted;
}

/**
 * Logs the record through `log` once the process's first query returns. The
 * latest call wins, so a second `createNext` logs no second line.
 */
export function logColdStart(log: (line: string) => void): void {
  const current = coldRecord();

  current.onQuery = () => {
    log(`bsb.cold ${formatColdStart(current.timings)}`);
  };
}
