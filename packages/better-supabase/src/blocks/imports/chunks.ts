import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AsyncResult } from "../../core/result.ts";
import type { ImportItem } from "./define-import.ts";
import type { Imports } from "./imports.ts";

/** One batch of stored items as `process` reports it. */
export interface ImportChunkOutcome {
  /**
   * `processed` after this call wrote the chunk, `done` when an earlier call
   * had, `skipped` when the chunk is missing or another worker holds it, and
   * `failed` when `fail` marked it (store it again to retry).
   */
  readonly status: "processed" | "done" | "skipped" | "failed";
  /** The message `fail` gave, for a failed chunk. */
  readonly message?: string;
  readonly inserted?: number;
  readonly updated?: number;
  readonly unchanged?: number;
  readonly conflicted?: number;
  readonly errors?: readonly {
    readonly key: string | null;
    readonly code: string;
    readonly message: string;
  }[];
}

export interface ImportChunkProgress {
  readonly pending: number;
  readonly claimed: number;
  readonly done: number;
  readonly failed: number;
}

export interface ImportChunks {
  /**
   * Stores one chunk of an entity's items, from chunk 0. Storing it again
   * before it is done replaces its items; `false` means it was done already.
   */
  store(input: {
    runId: string;
    entity: string;
    chunk: number;
    items: readonly ImportItem[];
  }): AsyncResult<boolean>;
  /**
   * Claims the chunk, writes it with `upsertBatch` and marks it done in one
   * transaction. A failure leaves it pending, and a chunk that is done is not
   * written twice, so a queue can retry the call.
   */
  process(input: {
    runId: string;
    entity: string;
    chunk: number;
  }): AsyncResult<ImportChunkOutcome>;
  /**
   * Marks a chunk failed with a message, so the run reports it instead of a
   * queue retrying it. Storing the chunk again makes it pending. `false` means
   * the chunk is done or missing. `final` (the queue's last attempt) also fails
   * the run with the message.
   */
  fail(input: {
    runId: string;
    entity: string;
    chunk: number;
    message: string;
    final?: boolean;
  }): AsyncResult<boolean>;
  progress(runId: string): AsyncResult<ImportChunkProgress>;
}

/** The payload `enqueue_import_chunks` puts on the `imports` queue. */
export interface ImportChunkJob {
  readonly run: string;
  readonly entity: string;
  readonly chunk: number;
}

/** The Standard Schema of `ImportChunkJob`, for the queue's schema map. */
export const importChunkSchema: StandardSchemaV1<unknown, ImportChunkJob> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) => {
      const record = typeof value === "object" && value !== null ? value : {};
      const run = "run" in record ? record.run : undefined;
      const entity = "entity" in record ? record.entity : undefined;
      const chunk = "chunk" in record ? record.chunk : undefined;

      return typeof run === "string" &&
        typeof entity === "string" &&
        typeof chunk === "number" &&
        Number.isInteger(chunk) &&
        chunk >= 0
        ? { value: { run, entity, chunk } }
        : {
            issues: [
              { message: "an import chunk job has run, entity and chunk" },
            ],
          };
    },
  },
};

/** The part of a queue `Job` the chunk handler reads. */
export interface ImportChunkAttempt {
  /** 1 on the first run. */
  readonly attempts: number;
  readonly maxAttempts: number;
}

/**
 * A queue job handler for the `imports` queue: it processes the chunk the job
 * names and throws a failure so the queue retries it. On the job's last attempt
 * it first marks the chunk failed with `final`, so the run fails instead of
 * waiting for a chunk no worker will write. A chunk that is done or held by
 * another worker is a success.
 */
export function importChunkHandler(
  imports: Pick<Imports, "chunks">,
): (
  payload: ImportChunkJob,
  job?: ImportChunkAttempt,
) => Promise<ImportChunkOutcome> {
  return async (payload, job) => {
    const target = {
      runId: payload.run,
      entity: payload.entity,
      chunk: payload.chunk,
    };

    const processing = imports.chunks.process(target);
    const processed = await processing;

    if (!processed.ok && job !== undefined && job.attempts >= job.maxAttempts) {
      await imports.chunks.fail({
        ...target,
        message: processed.error.message,
        final: true,
      });
    }

    return processing.orThrow();
  };
}

/** The part of a `Queue` the worker uses. */
export interface ImportWorkerQueue {
  work(input: {
    queue: "imports";
    handler: (payload: ImportChunkJob, job: ImportChunkAttempt) => unknown;
    concurrency?: number;
    signal?: AbortSignal;
    pollInterval?: number;
    maxPollInterval?: number;
  }): Promise<{ readonly succeeded: number; readonly failed: number }>;
}

/**
 * Polls the `imports` queue and writes each chunk it names, `concurrency` at a
 * time, until `signal` aborts. Start it where the app's other workers run.
 */
export function runImportWorker(options: {
  readonly imports: Pick<Imports, "chunks">;
  readonly queue: ImportWorkerQueue;
  readonly concurrency?: number;
  readonly signal?: AbortSignal;
  readonly pollInterval?: number;
  readonly maxPollInterval?: number;
}): Promise<{ readonly succeeded: number; readonly failed: number }> {
  const { imports, queue, ...work } = options;

  return queue.work({
    queue: "imports",
    handler: importChunkHandler(imports),
    ...work,
  });
}
