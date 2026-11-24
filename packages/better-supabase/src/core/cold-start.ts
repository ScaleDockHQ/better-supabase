/** The first-time steps a process records, in the order a request meets them. */
export type ColdStep = "create" | "warm" | "claims" | "query";

/**
 * One process's first-request timings, in milliseconds. `evalStart` and
 * `evalEnd` count from the start of the process (`performance.now()`), the
 * steps are durations.
 */
export interface ColdStart {
  evalStart?: number;
  evalEnd?: number;
  create?: number;
  warm?: number;
  claims?: number;
  query?: number;
}

/** The record and what reads it; only the Next.js adapter sets `onQuery`. */
export interface ColdRecord {
  readonly timings: ColdStart;
  reported: string;
  onQuery?: () => void;
}

// Every copy of the library a process loads fills one record.
const KEY = Symbol.for("better-supabase.cold-start");

/** The process's record, filled as the first request runs. */
export function coldRecord(): ColdRecord {
  // SAFETY: only this module writes KEY, always with a ColdRecord.
  const scope = globalThis as { [KEY]?: ColdRecord };

  scope[KEY] ??= { timings: {}, reported: "" };

  return scope[KEY];
}

/** Whether `step` still waits for its first run in this process. */
export function coldPending(step: ColdStep): boolean {
  return coldRecord().timings[step] === undefined;
}

/** Keeps the first duration of `step`; later runs change nothing. */
export function recordCold(step: ColdStep, ms: number): void {
  const current = coldRecord();

  if (current.timings[step] !== undefined) {
    return;
  }

  current.timings[step] = ms;

  if (step === "query") {
    current.onQuery?.();
  }
}
