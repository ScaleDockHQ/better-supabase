import type { BlockTransport } from "../core/block-transport.ts";

import { rawError } from "../core/block-transport.ts";
import { type DbError, type ErrorMapper, mapDbError } from "../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";
import { provideTemporal } from "../core/temporal.ts";
import { fromPgError } from "../postgres/executor.ts";

/** The `temporal` option every block creator takes. */
export interface BlockTemporalOptions {
  /**
   * The Temporal namespace for runtimes without a global one, such as
   * `import { Temporal } from "temporal-polyfill"`. Blocks use it instead of
   * `globalThis.Temporal`, which stays untouched; like
   * `defineSupabase(schema, { temporal })`, it applies to the whole process.
   */
  readonly temporal?: typeof Temporal;
}

/** Provides `options.temporal`, when set, for the block's time values. */
export function applyTemporal(options: BlockTemporalOptions | undefined): void {
  if (options?.temporal !== undefined) provideTemporal(options.temporal);
}

/** The block schema when the options name none. */
export const DEFAULT_BLOCK_SCHEMA = "better_supabase";

/** Calls one block function and maps a rejection to a `DbError`. */
export type BlockCall = <T>(
  fn: string,
  args: Readonly<Record<string, unknown>>,
  then: (value: unknown) => T | Promise<T>,
) => AsyncResult<T>;

/** A `BlockCall` over `transport`, in `schema`, with the app's error mappers first. */
export function blockCall(
  transport: BlockTransport,
  schema: string = DEFAULT_BLOCK_SCHEMA,
  mappers: readonly ErrorMapper[] = [],
): BlockCall {
  return (fn, args, then) =>
    AsyncResult.from(async () => {
      let value: unknown;
      try {
        value = await transport.call(schema, fn, args);
      } catch (cause) {
        const raw = rawError(cause);
        return err(raw ? mapDbError(raw, mappers) : toDbError(cause));
      }
      return ok(await then(value));
    });
}

export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export const textOf = (value: unknown): string =>
  typeof value === "string" ? value : String(value);

export const optionalText = (value: unknown): string | undefined =>
  value === null || value === undefined ? undefined : textOf(value);

/** A function result that must be an object. */
export function recordOf(value: unknown, fn: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new TypeError(`${fn} returned ${JSON.stringify(value)}`);
  }
  return value;
}

/** A function result that must be an array of objects. */
export function recordsOf(
  value: unknown,
  fn: string,
): Record<string, unknown>[] {
  if (value === null || value === undefined) return [];
  if (!Array.isArray(value) || !value.every(isRecord)) {
    throw new TypeError(`${fn} returned ${JSON.stringify(value)}`);
  }
  return value;
}

export const stringsOf = (value: unknown): readonly string[] =>
  Array.isArray(value) ? value.map(textOf) : [];

/** A `timestamptz` from jsonb or `pg`, or `undefined` for null. */
export const optionalInstant = (
  value: unknown,
): Temporal.Instant | undefined =>
  value === null || value === undefined
    ? undefined
    : value instanceof Date || typeof value === "string"
      ? toInstant(value)
      : undefined;

/** An optional `timestamptz` as text for a function argument. */
export const instantArg = (
  value: Temporal.Instant | undefined | null,
): string | null | undefined =>
  value === undefined ? undefined : value === null ? null : value.toString();

/** SHA-256 of `value` as lowercase hex, with WebCrypto. */
export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/** `bytes` random bytes as base64url, for secrets and codes. */
export function randomToken(bytes = 24): string {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  let binary = "";
  for (const byte of data) binary += String.fromCodePoint(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

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
