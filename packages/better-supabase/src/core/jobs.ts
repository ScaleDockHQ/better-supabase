import type { DbError } from "./errors.ts";

import { dbError } from "./errors.ts";
import { AsyncResult, err, ok } from "./result.ts";

/** What a long call returns instead of its result (ADR 0852). */
export interface JobRef {
  /** `<kind>:<id>`; pass it to `jobs.get`. */
  readonly jobId: string;
}

export type JobStatus = "pending" | "running" | "completed" | "failed";

/** The one shape `jobs.get(jobId)` returns for every kind of long call. */
export interface JobResult<Result = unknown> {
  readonly jobId: string;
  readonly kind: string;
  readonly status: JobStatus;
  /** Units finished and the total, when the job counts them. */
  readonly progress: { readonly done: number; readonly total: number } | null;
  /** What the job produced, once it completed. */
  readonly result: Result | null;
  /** The plain error of a failed job. */
  readonly error: DbError | null;
  readonly done: boolean;
}

/** A job kind: the block call that starts jobs and reads one back by its id. */
export interface JobSource {
  /**
   * Reads a job by the id after the kind; `null` for an unknown id or one the
   * caller did not start.
   */
  readonly get: (id: string) => AsyncResult<JobResult | null>;
}

export interface Jobs {
  readonly get: (jobId: string) => AsyncResult<JobResult | null>;
}

/** `{ jobId: "<kind>:<id>" }` for a job of `kind`. */
export function jobRef(kind: string, id: string): JobRef {
  return { jobId: `${kind}:${id}` };
}

/** Splits a `jobId` into its kind and id; `undefined` when it has no kind. */
export function parseJobId(
  jobId: string,
): { readonly kind: string; readonly id: string } | undefined {
  const at = jobId.indexOf(":");

  return at <= 0 || at === jobId.length - 1
    ? undefined
    : { kind: jobId.slice(0, at), id: jobId.slice(at + 1) };
}

/** The `JobResult` fields every source computes from its own status. */
export function jobResultOf<Result>(
  kind: string,
  id: string,
  state: {
    readonly status: JobStatus;
    readonly progress?: { readonly done: number; readonly total: number };
    readonly result?: Result;
    readonly error?: DbError;
  },
): JobResult<Result> {
  return {
    jobId: jobRef(kind, id).jobId,
    kind,
    status: state.status,
    progress: state.progress ?? null,
    result: state.result ?? null,
    error: state.error ?? null,
    done: state.status === "completed" || state.status === "failed",
  };
}

/**
 * The common `jobs.get(jobId)`: reads the kind off the id and asks that source.
 * An id with no known kind is `invalid_input`, an id the source does not know
 * `not_found`.
 */
export function createJobs(sources: Readonly<Record<string, JobSource>>): Jobs {
  return {
    get: (jobId) =>
      AsyncResult.from(async () => {
        const parsed = parseJobId(jobId);

        const source =
          parsed === undefined
            ? undefined
            : Object.hasOwn(sources, parsed.kind)
              ? sources[parsed.kind]
              : undefined;

        if (parsed === undefined || source === undefined) {
          return err(
            dbError("invalid_input", `Unknown job id "${jobId}"`, {
              hint: "JOB_KIND_UNKNOWN",
            }),
          );
        }

        const found = await source.get(parsed.id);

        if (!found.ok) {
          return found;
        }

        return found.data === null
          ? err(dbError("not_found", `No job "${jobId}"`))
          : ok(found.data);
      }),
  };
}
