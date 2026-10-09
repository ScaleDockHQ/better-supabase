import type { CredentialRef } from "../credentials/provider.ts";
import type { BlockTransport } from "./block-transport.ts";

import { fromPgError } from "../postgres/executor.ts";
import { rawError } from "./block-transport.ts";
import {
  type DbError,
  dbError,
  type ErrorMapper,
  mapDbError,
} from "./errors.ts";
import { AsyncResult, err, ok, toDbError } from "./result.ts";
import { temporal } from "./temporal-required.ts";
import { provideTemporal } from "./temporal.ts";

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

/** The options every block creator shares. */
export interface BlockOptions extends BlockTemporalOptions {
  /** `sqlTransport(ctx.postgres)` for members, or `rpcTransport` over an API schema. */
  readonly transport: BlockTransport;
  /** The transport for service-only calls (jobs, purges). Defaults to `transport`. */
  readonly service?: BlockTransport;
  /** The module's schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  /** Error mappers that run before the built-in ones. */
  readonly mappers?: readonly ErrorMapper[];
}

/** Provides `options.temporal`, when set, for the block's time values. */
export function applyTemporal(options: BlockTemporalOptions | undefined): void {
  if (options?.temporal !== undefined) provideTemporal(options.temporal);
}

/** The block schema when the options name none. */
export const DEFAULT_BLOCK_SCHEMA = "better_supabase";

/** `mappers`, or the deprecated `errorMappers` some blocks took before 0.7. */
export function mappersOf(options: {
  readonly mappers?: readonly ErrorMapper[] | undefined;
  readonly errorMappers?: readonly ErrorMapper[] | undefined;
}): readonly ErrorMapper[] {
  return options.mappers ?? options.errorMappers ?? [];
}

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

/** `value` when it is one of `values`, otherwise `fallback`. */
export function oneOf<T extends string>(
  value: unknown,
  values: readonly T[],
  fallback: T,
): T {
  return values.find((item) => item === value) ?? fallback;
}

/** `value` when it is one of `values`; throws for anything else. */
export function enumOrThrow<T extends string>(
  value: unknown,
  values: readonly T[],
  what: string,
): T {
  const found = values.find((item) => item === value);
  if (found === undefined) {
    throw new TypeError(`unknown ${what} "${String(value)}"`);
  }
  return found;
}

/** A jsonb object column, or an empty object for anything else. */
export const recordOrEmpty = (
  value: unknown,
): Readonly<Record<string, unknown>> => (isRecord(value) ? value : {});

/** A `credential_ref` column, or `undefined` when it names no provider. */
export function credentialRefOf(value: unknown): CredentialRef | undefined {
  if (!isRecord(value) || typeof value["provider"] !== "string") {
    return undefined;
  }
  return { ...value, provider: value["provider"] };
}

/** The `not_found` error a block returns for a row the caller can't see. */
export const notFoundError = (message: string, hint?: string): DbError =>
  dbError("not_found", message, hint === undefined ? {} : { hint });

/** A `timestamptz` from jsonb or `pg`, or `undefined` for null. */
export const optionalInstant = (
  value: unknown,
): Temporal.Instant | undefined =>
  value === null || value === undefined
    ? undefined
    : value instanceof Date || typeof value === "string"
      ? toInstant(value)
      : undefined;

/** A `timestamptz` that must be there; throws when it is null or missing. */
export function requiredInstant(
  value: unknown,
  field: string,
): Temporal.Instant {
  const instant = optionalInstant(value);
  if (instant === undefined) throw new TypeError(`${field} is missing`);
  return instant;
}

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

/**
 * The request body as text, or `undefined` once it is longer than `limit`
 * bytes. A larger `Content-Length` is refused before reading; otherwise
 * reading stops at the limit, so a body without one can't fill memory.
 */
export async function readBodyCapped(
  request: Request,
  limit: number,
): Promise<string | undefined> {
  const length = Number(request.headers.get("content-length") ?? Number.NaN);
  if (Number.isFinite(length) && length > limit) return undefined;
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      // Not awaited: a branch of a cloned request settles its cancel only
      // once the other branch is cancelled too.
      void reader.cancel().catch(() => undefined);
      return undefined;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

export function seconds(value: number | string): string {
  return typeof value === "number" ? `${String(value)} seconds` : value;
}

export function workerId(): string {
  return `worker-${crypto.randomUUID().slice(0, 8)}`;
}

/**
 * Runs `fn` over `items` with at most `limit` calls in flight. After the
 * first rejection no new item starts; the ones running finish, then it
 * rethrows.
 */
export async function eachLimit<T>(
  items: readonly T[],
  limit: number,
  fn: (item: T, index: number) => Promise<void>,
): Promise<void> {
  let next = 0;
  let failure: { cause: unknown } | undefined;
  const lane = async (): Promise<void> => {
    while (failure === undefined && next < items.length) {
      const index = next++;
      try {
        await fn(items[index]!, index);
      } catch (cause) {
        failure ??= { cause };
      }
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(Math.max(1, limit), items.length) }, lane),
  );
  if (failure) throw failure.cause;
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

/**
 * Returns an injectable after checking its optional `apiVersion`. An omitted
 * version means 1; anything else throws, so an injectable built for a newer
 * contract fails at construction instead of mid-call.
 */
export function injectableOf<T extends { readonly apiVersion?: 1 }>(
  what: string,
  value: T,
): T;
export function injectableOf<T extends { readonly apiVersion?: 1 }>(
  what: string,
  value: T | undefined,
): T | undefined;
export function injectableOf<T extends { readonly apiVersion?: 1 }>(
  what: string,
  value: T | undefined,
): T | undefined {
  if (value === undefined) return undefined;
  const version: unknown = value.apiVersion;
  if (version !== undefined && version !== 1) {
    throw new TypeError(
      `${what} targets API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release built for API 1.`,
    );
  }
  return value;
}

/**
 * One page of a list. `cursor` is the previous page's `next` cursor or last
 * item, in the shape each list documents.
 */
export interface CursorPageOptions<Cursor> {
  /** The most items to return. Each list documents its default and maximum. */
  readonly limit?: number;
  readonly cursor?: Cursor;
}

/**
 * Reads `limit` and `cursor`, falling back to the deprecated `size`,
 * `before` and `after` names the lists accepted before 0.7.
 */
export function pageOf<Cursor>(
  options: {
    readonly limit?: number | undefined;
    readonly size?: number | undefined;
    readonly cursor?: Cursor | undefined;
    readonly before?: Cursor | undefined;
    readonly after?: Cursor | undefined;
  } = {},
): { readonly limit: number | undefined; readonly cursor: Cursor | undefined } {
  return {
    limit: options.limit ?? options.size,
    cursor: options.cursor ?? options.before ?? options.after,
  };
}
