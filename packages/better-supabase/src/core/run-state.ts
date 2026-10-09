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

/** Reads a stored run state; a value outside `states` reads as `fallback`. */
export function runStateOf<S extends RunState>(
  value: unknown,
  states: readonly S[],
  fallback: S,
): S {
  return states.find((member) => member === value) ?? fallback;
}
