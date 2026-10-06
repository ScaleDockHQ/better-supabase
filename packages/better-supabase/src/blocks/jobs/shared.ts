import { type DbError, mapDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { fromPgError } from "../../postgres/executor.ts";

export function asDbError(cause: unknown): DbError {
  const raw = fromPgError(cause);
  return raw ? mapDbError(raw) : toDbError(cause);
}

export function run<T>(fn: () => Promise<T>): AsyncResult<T> {
  return AsyncResult.from(async () => {
    try {
      return ok(await fn());
    } catch (cause) {
      return err(asDbError(cause));
    }
  });
}

export function seconds(value: number | string): string {
  return typeof value === "number" ? `${String(value)} seconds` : value;
}

export function workerId(): string {
  return `worker-${crypto.randomUUID().slice(0, 8)}`;
}

export const sleep = (ms: number, signal?: AbortSignal): Promise<void> =>
  new Promise((resolve) => {
    if (signal?.aborted) {
      resolve();
      return;
    }
    const timer = setTimeout(done, ms);
    function done(): void {
      clearTimeout(timer);
      signal?.removeEventListener("abort", done);
      resolve();
    }
    signal?.addEventListener("abort", done, { once: true });
  });

/** pgmq and the inbox return `timestamptz` as text over RPC and as `Date` from `pg`. */
export const toInstant = (value: Date | string): Temporal.Instant =>
  value instanceof Date
    ? temporal().Instant.fromEpochMilliseconds(value.getTime())
    : temporal().Instant.from(value);

export function errorText(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "message" in error) {
    return String(error.message);
  }
  return String(error);
}
