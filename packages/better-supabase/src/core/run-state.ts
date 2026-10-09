/**
 * Where a run is, in the words every block that records runs shares: ai-chat
 * runs, ai-tasks runs and workflow runs. Each block uses the subset it needs.
 */
export type RunState =
  | "queued"
  | "running"
  | "waiting"
  | "cancel_requested"
  | "completed"
  | "failed"
  | "cancelled";

/** The states a run ends in. */
export type FinalRunState = Extract<
  RunState,
  "completed" | "failed" | "cancelled"
>;

/** The states a run ends in, in the order blocks list them. */
export const FINAL_RUN_STATES: readonly FinalRunState[] = [
  "completed",
  "failed",
  "cancelled",
];

/**
 * The run states ai-chat and ai-tasks used before 0.7: `done`, `error` and
 * `stopped` for chat runs, `succeeded` for task runs. Inputs still accept
 * them, deprecated since 0.7 and removed in 0.8; reads never return them.
 */
export type LegacyRunState = "done" | "error" | "stopped" | "succeeded";

/** The shared name of each pre-0.7 run state. */
export const LEGACY_RUN_STATES: Readonly<Record<LegacyRunState, RunState>> = {
  done: "completed",
  error: "failed",
  stopped: "cancelled",
  succeeded: "completed",
};

function isLegacy(value: string): value is LegacyRunState {
  return Object.hasOwn(LEGACY_RUN_STATES, value);
}

/** The shared name of a run state the caller passed, mapping a pre-0.7 one. */
export function sharedRunState<S extends RunState>(
  state: S | LegacyRunState,
): S | RunState {
  return isLegacy(state) ? LEGACY_RUN_STATES[state] : state;
}

/**
 * Reads a stored or passed run state: a pre-0.7 name maps to its shared one,
 * and a value outside `states` reads as `fallback`.
 */
export function runStateOf<S extends RunState>(
  value: unknown,
  states: readonly S[],
  fallback: S,
): S {
  if (typeof value !== "string") return fallback;
  const state = isLegacy(value) ? LEGACY_RUN_STATES[value] : value;
  return states.find((member) => member === state) ?? fallback;
}
