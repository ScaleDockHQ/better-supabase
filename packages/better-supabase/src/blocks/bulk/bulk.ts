import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";

/** The actions every install knows, when the block that owns each is installed. */
export type BuiltInBulkAction =
  | "tags.set"
  | "stateMachine.transition"
  | "relations.link"
  | "trash.trash"
  | "collections.add"
  | "appTables.set";

/** Arguments per built-in action; an app's own actions take any object. */
export interface BulkActionArgs {
  readonly "tags.set": {
    readonly add?: readonly string[];
    readonly remove?: readonly string[];
  };
  readonly "stateMachine.transition": {
    readonly to: string;
    readonly reason?: string;
  };
  readonly "relations.link": {
    readonly kind: string;
    readonly targetType: string;
    readonly targetId: string;
    readonly data?: Readonly<Record<string, unknown>>;
  };
  readonly "trash.trash": Readonly<Record<string, never>>;
  readonly "collections.add": { readonly collectionId: string };
  /**
   * Sets editable columns of an app table row; values are cast to the column
   * types.
   */
  readonly "appTables.set": {
    readonly values: Readonly<Record<string, unknown>>;
  };
}

type ArgsOf<A extends string> = A extends keyof BulkActionArgs
  ? BulkActionArgs[A]
  : Readonly<Record<string, unknown>>;

/**
 * The rows to act on: ids, or a function that resolves them (a list query's
 * filter tree).
 */
export type BulkRows =
  | readonly string[]
  | (() => PromiseLike<readonly string[]>);

export interface BulkInput<A extends string = string> {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly rows: BulkRows;
  readonly action: A;
  readonly args?: ArgsOf<A>;
}

export interface BulkRowResult {
  readonly id: string;
  readonly ok: boolean;
  /**
   * The failing row's hint (such as `TAG_SUBJECT_FORBIDDEN`), message and
   * SQLSTATE.
   */
  readonly error: {
    readonly code: string | undefined;
    readonly message: string;
    readonly sqlstate: string | undefined;
  } | null;
}

export interface BulkResult {
  readonly total: number;
  readonly succeeded: number;
  readonly failed: number;
  readonly results: readonly BulkRowResult[];
}

export interface BulkStarted {
  readonly id: string;
  readonly total: number;
  /** The Realtime topic the run broadcasts `progress` on. */
  readonly topic: string;
}

export type BulkStatus = "pending" | "running" | "completed" | "failed";

export interface BulkProgress {
  readonly id: string;
  /** `failed` when the user lost `bulk.run` while the run was going. */
  readonly status: BulkStatus;
  readonly position: number;
  readonly total: number;
  readonly succeeded: number;
  readonly failed: number;
  readonly done: boolean;
}

export interface BulkRun extends BulkResult {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly action: string;
  readonly status: BulkStatus;
  readonly position: number;
  readonly createdAt: string;
  readonly finishedAt: string | undefined;
}

/** What `apply` did: ran the rows now, or started a background run. */
export type BulkOutcome =
  | ({ readonly mode: "now" } & BulkResult)
  | ({ readonly mode: "background" } & BulkStarted);

export interface BulkOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Bulk>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `blocks.bulk.options.limit`, which `defineBlocks` passes from
   * `blocks.generated.ts`: more rows than this start a background run. Defaults
   * to 500.
   */
  readonly limit?: number;
}

export interface BulkDrainOptions {
  /** Rows per step. Defaults to 200, capped by the module's limit. */
  readonly size?: number;
  readonly signal?: AbortSignal;
}

export interface Bulk {
  /**
   * Runs one action on every row in one call (up to the limit), with a result
   * per row.
   */
  run<A extends string>(
    input: BulkInput<A> & { readonly atomic?: boolean },
  ): AsyncResult<BulkResult>;
  /** Starts a background run on the jobs queue `bulk`. */
  start<A extends string>(input: BulkInput<A>): AsyncResult<BulkStarted>;
  /** `run` up to the limit, `start` beyond it. */
  apply<A extends string>(input: BulkInput<A>): AsyncResult<BulkOutcome>;
  /** A run the caller started, with its per-row results; `null` for anyone else. */
  get(id: string): AsyncResult<BulkRun | null>;
  /** Service role: runs the next rows of a run as the user who started it. */
  step(id: string, size?: number): AsyncResult<BulkProgress>;
  /** Service role: steps until the run is done or `signal` aborts. */
  drain(id: string, options?: BulkDrainOptions): AsyncResult<BulkProgress>;
  /**
   * A handler for the jobs queue `bulk`: `jobs.work({ handlers: { bulk:
   * bulk.handler() } })`.
   */
  handler(
    options?: Omit<BulkDrainOptions, "signal">,
  ): (payload: unknown, job: unknown, signal: AbortSignal) => Promise<void>;
}

const count = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

const STATUSES: readonly BulkStatus[] = [
  "pending",
  "running",
  "completed",
  "failed",
];

const statusOf = (value: unknown): BulkStatus =>
  STATUSES.find((status) => status === value) ?? "pending";

function rowResultOf(value: unknown): BulkRowResult {
  const row = recordOf(value, "bulk row");
  const error = row["error"];

  return {
    id: textOf(row["id"]),
    ok: row["ok"] === true,
    error: isRecord(error)
      ? {
          code: optionalText(error["code"]),
          message: textOf(error["message"]),
          sqlstate: optionalText(error["sqlstate"]),
        }
      : null,
  };
}

function resultOf(value: unknown): BulkResult {
  const row = recordOf(value, "bulk result");
  const results = row["results"];

  return {
    total: count(row["total"]),
    succeeded: count(row["succeeded"]),
    failed: count(row["failed"]),
    results: Array.isArray(results) ? results.map(rowResultOf) : [],
  };
}

function progressOf(value: unknown): BulkProgress {
  const row = recordOf(value, "bulk progress");

  return {
    id: textOf(row["id"]),
    status: statusOf(row["status"]),
    position: count(row["position"]),
    total: count(row["total"]),
    succeeded: count(row["succeeded"]),
    failed: count(row["failed"]),
    done: row["done"] === true,
  };
}

function startedOf(value: unknown): BulkStarted {
  const row = recordOf(value, "bulk run");

  return {
    id: textOf(row["id"]),
    total: count(row["total"]),
    topic: textOf(row["topic"]),
  };
}

function runOf(value: unknown): BulkRun | null {
  if (!isRecord(value)) {
    return null;
  }

  return {
    ...resultOf(value),
    id: textOf(value["id"]),
    organizationId: textOf(value["organizationId"]),
    subjectType: textOf(value["subjectType"]),
    action: textOf(value["action"]),
    status: statusOf(value["status"]),
    position: count(value["position"]),
    createdAt: textOf(value["createdAt"]),
    finishedAt: optionalText(value["finishedAt"]),
  };
}

async function rowsOf(rows: BulkRows): Promise<readonly string[]> {
  return typeof rows === "function" ? rows() : rows;
}

export function createBulk(options: BulkOptions): Bulk {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const limit = options.limit ?? 500;

  const args = (
    input: BulkInput,
    ids: readonly string[],
  ): Record<string, unknown> => ({
    tenant: input.organizationId,
    subject_type: input.subjectType,
    ids,
    action: input.action,
    args: input.args ?? {},
  });

  const runIds = (input: BulkInput, ids: readonly string[], atomic: boolean) =>
    call("bulk_apply", { ...args(input, ids), atomic }, resultOf);

  const startIds = (input: BulkInput, ids: readonly string[]) =>
    call("start_bulk", args(input, ids), startedOf);

  const step = (id: string, size?: number) =>
    call("bulk_step", { run_id: id, size: size ?? null }, progressOf);

  const drain = (id: string, drainOptions: BulkDrainOptions = {}) =>
    AsyncResult.from(async () => {
      for (;;) {
        drainOptions.signal?.throwIfAborted();
        const result = await step(id, drainOptions.size);

        if (!result.ok || result.data.done) {
          return result;
        }
      }
    });

  const client: Bulk = {
    run: (input) =>
      AsyncResult.from(async () =>
        runIds(input, await rowsOf(input.rows), input.atomic ?? false),
      ),
    start: (input) =>
      AsyncResult.from(async () => startIds(input, await rowsOf(input.rows))),
    apply: (input) =>
      AsyncResult.from(async (): Promise<Result<BulkOutcome>> => {
        const ids = await rowsOf(input.rows);

        if (ids.length <= limit) {
          const result = await runIds(input, ids, false);

          return result.ok
            ? ok({ mode: "now" as const, ...result.data })
            : result;
        }

        const started = await startIds(input, ids);

        return started.ok
          ? ok({ mode: "background" as const, ...started.data })
          : started;
      }),
    get: (id) => call("bulk_run", { run_id: id }, runOf),
    step,
    drain,
    handler:
      (handlerOptions = {}) =>
      async (payload, _job, signal) => {
        const run = isRecord(payload) ? payload["run"] : undefined;

        if (typeof run !== "string") {
          throw new TypeError("a bulk job needs { run: <id> }");
        }

        await drain(run, { ...handlerOptions, signal }).orThrow();
      },
  };

  return withBlockHooks(client, options.hooks, {
    block: "bulk",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
