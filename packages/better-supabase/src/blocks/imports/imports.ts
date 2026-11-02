import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { ImportBatchReply, ImportItem } from "./define-import.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  blockCall,
  nullableInstant,
  nullableText,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ImportsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the methods (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Imports>>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

export type ImportRunStatus =
  | "pending"
  | "running"
  | "completed"
  | "failed"
  | "canceled";

/** What a run did to one entity. */
export interface ImportEntityCounts {
  readonly inserted: number;
  readonly updated: number;
  readonly unchanged: number;
  readonly conflicted: number;
  /** Records of a full run the source no longer sends. */
  readonly missing: number;
}

export interface ImportRunError {
  readonly entity: string;
  readonly key: string | null;
  /** A hint code, such as `IMPORT_ITEM_INVALID` or `IMPORT_TARGET_UNKNOWN`. */
  readonly code: string;
  readonly message: string;
}

/** Lets a scope reuse another scope's records for some entities. */
export interface ImportScopeAlias {
  readonly scope: string;
  readonly of: string;
  readonly entities: readonly string[];
}

export interface ImportRun {
  readonly id: string;
  readonly organizationId: string;
  readonly source: string;
  readonly status: ImportRunStatus;
  readonly mapping: Readonly<Record<string, string>>;
  readonly counts: Readonly<Record<string, ImportEntityCounts>>;
  readonly errors: readonly ImportRunError[];
  readonly dryRun: boolean;
  readonly full: boolean;
  readonly inputChecksum: string | null;
  readonly correlationId: string | null;
  readonly scopeAliases: readonly ImportScopeAlias[];
  readonly createdBy: string | null;
  readonly createdAt: Temporal.Instant;
  readonly startedAt: Temporal.Instant | null;
  readonly finishedAt: Temporal.Instant | null;
}

export interface StartImportRunOptions {
  /** CSV header to field, for runs that come from a file. */
  readonly mapping?: Readonly<Record<string, string>>;
  /** Run every write, then roll it back and report only the counts. */
  readonly dryRun?: boolean;
  /** The run sends the source's whole data; `finish` marks what it left out. */
  readonly full?: boolean;
  /** Identifies the input, so a caller can tell a repeated file. */
  readonly inputChecksum?: string;
  readonly correlationId?: string;
  readonly scopeAliases?: readonly ImportScopeAlias[];
}

export interface ListImportRunsOptions {
  readonly source?: string;
  readonly status?: ImportRunStatus;
  /** At most 200; defaults to 50. */
  readonly limit?: number;
}

/** One key of `resolve`: the key, or the key within a scope. */
export type ImportKey =
  | string
  | { readonly key: string; readonly scope?: string; readonly role?: string };

export interface ResolvedImportKey {
  readonly key: string;
  readonly scope: string;
  readonly role: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

export interface UpsertBatchResult extends ImportBatchReply {
  /** True when the run is a dry run: nothing was written. */
  readonly dryRun: boolean;
}

/** One entity's items for `run`, in the order runs must write them. */
export interface ImportRunEntity {
  readonly entity: string;
  readonly items: Iterable<ImportItem> | AsyncIterable<ImportItem>;
}

export interface RunImportsOptions extends StartImportRunOptions {
  /** Items per `upsertBatch` call. Default 200. */
  readonly batchSize?: number | undefined;
  /** Called after each batch with the entity's running totals. */
  readonly onBatch?:
    | ((progress: {
        readonly entity: string;
        readonly items: number;
        readonly errors: number;
      }) => void)
    | undefined;
}

/** What `run` answers: the finished run's counts and what the batches reported. */
export interface ImportRunResult {
  readonly id: string;
  readonly dryRun: boolean;
  readonly counts: Readonly<Record<string, ImportEntityCounts>>;
  /** Rejected items, by entity, with the batch's hint code. */
  readonly errors: readonly ImportRunError[];
  readonly warnings: readonly {
    readonly entity: string;
    readonly key: string | null;
    readonly code: string;
    readonly message: string;
  }[];
}

export interface Imports {
  /**
   * Runs a whole import in one call, for the service role: `runs.start`,
   * `markRunning`, one `upsertBatch` per `batchSize` items of each entity in
   * the order given, then `finish`. Item errors do not stop the run; they come
   * back in `errors`. When a call fails (the run could not start, a batch
   * threw), the run is cancelled and the error returned.
   */
  run(
    input: {
      organizationId: string;
      source: string;
      entities: readonly ImportRunEntity[];
    } & RunImportsOptions,
  ): AsyncResult<ImportRunResult>;
  /** Starts a run and returns its id. Prefer `runs.start`. */
  start(input: {
    organizationId: string;
    source: string;
    mapping?: Readonly<Record<string, string>> | undefined;
  }): AsyncResult<{ readonly id: string }>;
  readonly runs: {
    /**
     * Starts a pending run. Fails with `IMPORT_RUN_ACTIVE` while another is
     * open.
     */
    start(
      input: { organizationId: string; source: string } & StartImportRunOptions,
    ): AsyncResult<{ readonly id: string }>;
    get(id: string): AsyncResult<ImportRun>;
    list(
      input: { organizationId: string } & ListImportRunsOptions,
    ): AsyncResult<readonly ImportRun[]>;
    /** Cancels a pending or running run; `false` when it already ended. */
    cancel(id: string): AsyncResult<boolean>;
  };
  /** Marks a pending run running (service role). */
  markRunning(id: string): AsyncResult<boolean>;
  /**
   * Writes one batch of an entity through its `importTarget` (service role).
   * Each item inserts, is unchanged, updates, or is `conflicted`.
   */
  upsertBatch(input: {
    runId: string;
    entity: string;
    items: readonly ImportItem[];
  }): AsyncResult<UpsertBatchResult>;
  /**
   * Looks up the subjects keys imported to; a key never imported is left out
   * (service role).
   */
  resolve(input: {
    runId: string;
    entity: string;
    keys: readonly ImportKey[];
  }): AsyncResult<readonly ResolvedImportKey[]>;
  /**
   * Ends a running run, marks missing records on a full run and emits the
   * import events (service role).
   */
  finish(
    runId: string,
  ): AsyncResult<Readonly<Record<string, ImportEntityCounts>>>;
}

const toCount = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const entityCounts = (value: unknown): ImportEntityCounts => {
  const row = recordOrEmpty(value);

  return {
    inserted: toCount(row["inserted"]),
    updated: toCount(row["updated"]),
    unchanged: toCount(row["unchanged"]),
    conflicted: toCount(row["conflicted"]),
    missing: toCount(row["missing"]),
  };
};

const countsOf = (value: unknown): Record<string, ImportEntityCounts> =>
  Object.fromEntries(
    Object.entries(recordOrEmpty(value)).map(([entity, counts]) => [
      entity,
      entityCounts(counts),
    ]),
  );

const STATUSES: readonly ImportRunStatus[] = [
  "pending",
  "running",
  "completed",
  "failed",
  "canceled",
];

function runOf(value: unknown, fn: string): ImportRun {
  const row = recordOf(value, fn);
  const status = textOf(row["status"]);
  const found = STATUSES.find((item) => item === status);

  if (found === undefined) {
    throw new TypeError(`${fn} returned the status "${status}"`);
  }

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    source: textOf(row["source"]),
    status: found,
    mapping: Object.fromEntries(
      Object.entries(recordOrEmpty(row["mapping"])).map(([key, item]) => [
        key,
        textOf(item),
      ]),
    ),
    counts: countsOf(row["counts"]),
    errors: recordsOf(row["errors"], fn).map((error) => ({
      entity: textOf(error["entity"]),
      key: nullableText(error["key"]),
      code: textOf(error["code"]),
      message: textOf(error["message"]),
    })),
    dryRun: row["dryRun"] === true,
    full: row["full"] === true,
    inputChecksum: nullableText(row["inputChecksum"]),
    correlationId: nullableText(row["correlationId"]),
    scopeAliases: recordsOf(row["scopeAliases"], fn).map((alias) => ({
      scope: textOf(alias["scope"]),
      of: textOf(alias["of"]),
      entities: Array.isArray(alias["entities"])
        ? alias["entities"].map(textOf)
        : [],
    })),
    createdBy: nullableText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    startedAt: nullableInstant(row["startedAt"]),
    finishedAt: nullableInstant(row["finishedAt"]),
  };
}

const itemArg = (item: ImportItem): Record<string, unknown> => ({
  key: item.key,
  scope: item.scope ?? "",
  data: item.data,
  refs: item.refs ?? {},
});

const keyArg = (key: ImportKey): Record<string, unknown> =>
  typeof key === "string"
    ? { key }
    : {
        key: key.key,
        ...(key.scope === undefined ? {} : { scope: key.scope }),
        ...(key.role === undefined ? {} : { role: key.role }),
      };

const startArg = (start: StartImportRunOptions): Record<string, unknown> => ({
  ...(start.mapping ? { mapping: start.mapping } : {}),
  ...(start.dryRun === undefined ? {} : { dryRun: start.dryRun }),
  ...(start.full === undefined ? {} : { full: start.full }),
  ...(start.inputChecksum === undefined
    ? {}
    : { inputChecksum: start.inputChecksum }),
  ...(start.correlationId === undefined
    ? {}
    : { correlationId: start.correlationId }),
  ...(start.scopeAliases === undefined
    ? {}
    : { scopeAliases: start.scopeAliases }),
});

export function createImports(options: ImportsOptions): Imports {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const idOf = (value: unknown, fn: string): { readonly id: string } => ({
    id: textOf(recordOf(value, fn)["id"]),
  });

  const client: Imports = {
    run: ({ organizationId, source, entities, batchSize, onBatch, ...start }) =>
      AsyncResult.from(async () => {
        const size = Math.max(1, batchSize ?? 200);

        const started = await hooked.runs.start({
          organizationId,
          source,
          ...start,
        });

        if (!started.ok) {
          return started;
        }

        const { id } = started.data;
        const errors: ImportRunError[] = [];
        const warnings: ImportRunResult["warnings"][number][] = [];

        const stop = async <T>(failure: T): Promise<T> => {
          await hooked.runs.cancel(id);

          return failure;
        };

        const running = await hooked.markRunning(id);

        if (!running.ok) {
          return stop(running);
        }

        for (const { entity, items } of entities) {
          let batch: ImportItem[] = [];
          let sent = 0;
          let rejected = 0;

          const flush = async () => {
            const reply = await hooked.upsertBatch({
              runId: id,
              entity,
              items: batch,
            });

            if (!reply.ok) {
              return reply;
            }

            sent += batch.length;
            rejected += reply.data.errors.length;
            batch = [];

            for (const error of reply.data.errors) {
              errors.push({ entity, ...error });
            }

            for (const warning of reply.data.warnings ?? []) {
              warnings.push({ entity, ...warning });
            }

            onBatch?.({ entity, items: sent, errors: rejected });

            return reply;
          };

          for await (const item of items) {
            batch.push(item);

            if (batch.length >= size) {
              const flushed = await flush();

              if (!flushed.ok) {
                return stop(flushed);
              }
            }
          }

          if (batch.length > 0) {
            const flushed = await flush();

            if (!flushed.ok) {
              return stop(flushed);
            }
          }
        }

        const finished = await hooked.finish(id);

        if (!finished.ok) {
          return stop(finished);
        }

        return ok({
          id,
          dryRun: start.dryRun === true,
          counts: finished.data,
          errors,
          warnings,
        });
      }),
    start: ({ organizationId, source, mapping }) =>
      call(
        "start_import",
        { tenant: organizationId, source, mapping: mapping ?? {} },
        (value) => idOf(value, "start_import"),
      ),
    runs: {
      start: ({ organizationId, source, ...startOptions }) =>
        call(
          "start_import_run",
          { tenant: organizationId, source, options: startArg(startOptions) },
          (value) => idOf(value, "start_import_run"),
        ),
      get: (id) =>
        call("get_import_run", { id }, (value) =>
          runOf(value, "get_import_run"),
        ),
      list: ({ organizationId, ...listOptions }) =>
        call(
          "list_import_runs",
          {
            tenant: organizationId,
            source: listOptions.source ?? null,
            status: listOptions.status ?? null,
            row_limit: listOptions.limit ?? 50,
          },
          (value) =>
            (Array.isArray(value) ? value : []).map((row) =>
              runOf(row, "list_import_runs"),
            ),
        ),
      cancel: (id) =>
        call("cancel_import_run", { id }, (value) => value === true),
    },
    markRunning: (id) =>
      call("mark_import_running", { id }, (value) => value === true),
    upsertBatch: ({ runId, entity, items }) =>
      call(
        "import_upsert_batch",
        { run: runId, entity, items: items.map(itemArg) },
        (value) => {
          const row = recordOf(value, "import_upsert_batch");

          return {
            inserted: toCount(row["inserted"]),
            updated: toCount(row["updated"]),
            unchanged: toCount(row["unchanged"]),
            conflicted: toCount(row["conflicted"]),
            errors: recordsOf(row["errors"], "import_upsert_batch").map(
              (error) => ({
                key: nullableText(error["key"]),
                code: textOf(error["code"]),
                message: textOf(error["message"]),
              }),
            ),
            warnings: recordsOf(
              row["warnings"] ?? [],
              "import_upsert_batch",
            ).map((warning) => ({
              key: nullableText(warning["key"]),
              code: textOf(warning["code"]),
              message: textOf(warning["message"]),
            })),
            dryRun: row["dryRun"] === true,
          };
        },
      ),
    resolve: ({ runId, entity, keys }) =>
      call(
        "import_resolve",
        { run: runId, entity, keys: keys.map(keyArg) },
        (value) =>
          recordsOf(value, "import_resolve").map((row): ResolvedImportKey => ({
            key: textOf(row["key"]),
            scope: optionalText(row["scope"]) ?? "",
            role: optionalText(row["role"]) ?? "primary",
            subjectType: textOf(row["subjectType"]),
            subjectId: textOf(row["subjectId"]),
          })),
      ),
    finish: (runId) =>
      call("finish_import_run", { run: runId }, (value) => countsOf(value)),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Imports = withBlockHooks(client, options.hooks, {
    block: "imports",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
