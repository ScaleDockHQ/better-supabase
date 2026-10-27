/** The outcome of claiming a start idempotency key. */
export interface RunKeyClaim {
  /** `true` when this caller may start the run for the key. */
  readonly claimed: boolean;
  /**
   * The run an earlier start created for the key; `undefined` when `claimed`,
   * or while that start is still running.
   */
  readonly runId: string | undefined;
}

/**
 * Start idempotency keys, held in `workflow.workflow_run_keys`. The Supabase
 * World implements them; `startFor` uses them when the World has them, so two
 * concurrent starts with one key start one run.
 */
export interface WorkflowRunKeys {
  claim(key: string): Promise<RunKeyClaim>;
  set(key: string, runId: string): Promise<void>;
  release(key: string): Promise<void>;
}

/** A status `purgeRuns` may delete. */
export type WorkflowTerminalStatus = "completed" | "failed" | "cancelled";

export interface PurgeRunsOptions {
  /** A Postgres interval such as `30 days`. Defaults to `30 days`. */
  readonly olderThan?: string;
  /** Defaults to every terminal status. */
  readonly statuses?: readonly WorkflowTerminalStatus[];
  /** Runs per statement; `purgeRuns` repeats until none are left. Defaults to 500. */
  readonly batch?: number;
}

export interface OpenHooksOptions {
  /** Only the runs started in this tenant (the `bsb.tenant` attribute). */
  readonly tenantId?: string;
  /** Only the runs of this workflow name. */
  readonly workflowName?: string;
  /** 1 to 500, default 50. */
  readonly limit?: number;
}

/** A hook a pending or running run waits on. */
export interface OpenWorkflowHook {
  readonly hookId: string;
  readonly runId: string;
  readonly workflowName: string;
  readonly tenantId: string | undefined;
  readonly actorId: string | undefined;
  /** The hook's metadata when it is JSON, such as `hookMetadata(context)`. */
  readonly metadata: unknown;
  readonly createdAt: Temporal.Instant;
}

/** The maintenance methods of the Supabase World. */
export interface WorkflowMaintenance {
  readonly runKeys: WorkflowRunKeys;
  /** Deletes ended runs and their rows; resolves with how many runs it deleted. */
  purgeRuns(options?: PurgeRunsOptions): Promise<number>;
  /** The hooks of pending and running runs, newest first. */
  openHooks(options?: OpenHooksOptions): Promise<readonly OpenWorkflowHook[]>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function hasRunKeys(
  world: unknown,
): world is { readonly runKeys: WorkflowRunKeys } {
  if (!isRecord(world) || !isRecord(world["runKeys"])) {
    return false;
  }

  const keys = world["runKeys"];

  return (
    typeof keys["claim"] === "function" &&
    typeof keys["set"] === "function" &&
    typeof keys["release"] === "function"
  );
}

/** The World's run keys, when it has them. */
export function runKeysOf(world: unknown): WorkflowRunKeys | undefined {
  return hasRunKeys(world) ? world.runKeys : undefined;
}
