/** A signal that also aborts after a timeout, and whether the timeout fired. */
export interface Deadline {
  readonly signal: AbortSignal | undefined;
  timedOut(): boolean;
  /** Stops the timer and detaches from the caller's signal. */
  clear(): void;
}

const NO_DEADLINE = (signal: AbortSignal | undefined): Deadline => ({
  signal,
  timedOut: () => false,
  clear: () => {},
});

/**
 * Either signal aborting aborts the result. Uses `AbortSignal.any` where the
 * runtime has it; Hermes and older runtimes get the same behaviour by hand.
 */
function anySignal(signals: readonly AbortSignal[]): {
  signal: AbortSignal;
  detach: () => void;
} {
  if (typeof AbortSignal.any === "function")
    return { signal: AbortSignal.any([...signals]), detach: () => {} };
  const controller = new AbortController();
  const abort = (): void => {
    controller.abort();
  };
  for (const signal of signals) {
    if (signal.aborted) {
      abort();
      return { signal: controller.signal, detach: () => {} };
    }
  }
  for (const signal of signals) signal.addEventListener("abort", abort);
  return {
    signal: controller.signal,
    detach: () => {
      for (const signal of signals) signal.removeEventListener("abort", abort);
    },
  };
}

/** `true` for a timeout the executors and the repository accept. */
export function isTimeout(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

/**
 * `signal` combined with a `timeoutMs` timer. Without a timeout it returns
 * the signal unchanged, so calls without one allocate nothing.
 */
export function deadline(
  signal: AbortSignal | undefined,
  timeoutMs: number | undefined,
): Deadline {
  if (timeoutMs === undefined) return NO_DEADLINE(signal);
  const timer = new AbortController();
  const handle = setTimeout(() => {
    timer.abort();
  }, timeoutMs);
  const combined = signal
    ? anySignal([signal, timer.signal])
    : { signal: timer.signal, detach: () => {} };
  return {
    signal: combined.signal,
    timedOut: () => timer.signal.aborted && !(signal?.aborted ?? false),
    clear: () => {
      clearTimeout(handle);
      combined.detach();
    },
  };
}

/** A call's `timeout` and `retry`, after validation. */
export interface RequestTuning {
  readonly timeout?: number;
  readonly retry?: boolean;
}

export const NO_TUNING: RequestTuning = Object.freeze({});

/** `invalid_request` text for a bad `timeout` or `retry`, else `undefined`. */
export function invalidTuning(tuning: {
  readonly timeout?: unknown;
  readonly retry?: unknown;
}): string | undefined {
  if (tuning.timeout !== undefined && !isTimeout(tuning.timeout))
    return `"timeout" must be a positive number of milliseconds, got ${String(tuning.timeout)}`;
  if (tuning.retry !== undefined && typeof tuning.retry !== "boolean")
    return `"retry" must be a boolean, got ${String(tuning.retry)}`;
  return undefined;
}

/** `timeout` and `retry` from a call's arguments, or why they are invalid. */
export function tuningOf(
  args: Readonly<Record<string, unknown>> | undefined,
): RequestTuning | { readonly invalid: string } {
  const timeout = args?.["timeout"];
  const retry = args?.["retry"];
  if (timeout === undefined && retry === undefined) return NO_TUNING;
  const invalid = invalidTuning({ timeout, retry });
  if (invalid) return { invalid };
  return {
    ...(isTimeout(timeout) ? { timeout } : {}),
    ...(typeof retry === "boolean" ? { retry } : {}),
  };
}
