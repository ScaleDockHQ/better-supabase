import type { StorageApi } from "../storage/storage-api.ts";
import type { BucketRegistry } from "./db-buckets.ts";
import type { ErrorMapper } from "./errors.ts";
import type { Executor } from "./executor.ts";
import type { Logger } from "./logger.ts";
import type { ThrowMapper } from "./result.ts";
import type { StandardSchemaV1 } from "./standard.ts";
import type { StatsRecorder } from "./stats.ts";

export interface SupabaseOptions {
  /** Set by `betterSupabase.buckets()`; read by `db.$buckets`. */
  readonly buckets?: BucketRegistry;
  /**
   * Clock used by plugins (timestamps, soft delete) and for the `time` of
   * block events on `betterSupabase.events`. Pass it to `createJobs` too.
   */
  readonly now?: () => Temporal.Instant;
  /**
   * The `Temporal` namespace, for runtimes without a global one (Hermes,
   * Node 24) when patching `globalThis` is not an option:
   * `import { Temporal } from 'temporal-polyfill'`. Defaults to `globalThis.Temporal`.
   */
  readonly temporal?: typeof Temporal;
  /** Extra error mappers, run before plugin mappers. */
  readonly errors?: readonly ErrorMapper[];
  /** Receives errors from event handlers, hooks and cache adapters. Defaults to `console`. */
  readonly logger?: Logger;
  /**
   * Debug records on `logger` for every query, database error, session
   * refresh and auth resolution: table, operation, outcome, timing and row
   * count, never tokens, row values, filters or error messages. Off by
   * default; with it off, no handler runs.
   */
  readonly diagnostics?: boolean;
  /** RPCs that change tables, keyed by function name. Prefer `betterSupabase.defineRpc()`. */
  readonly rpc?: Readonly<Record<string, RpcDefinition>>;
  /** Builds the error `.orThrow()` throws. Prefer `betterSupabase.mapError()`. */
  readonly throwAs?: ThrowMapper;
  /** Validates verified JWT claims on the server. Prefer `betterSupabase.claims()`, which also types them. */
  readonly claims?: StandardSchemaV1;
  /** Parses `user_metadata` into `session.profile`. Prefer `betterSupabase.userMetadata()`, which also types it. */
  readonly userMetadata?: StandardSchemaV1;
  /**
   * PostgREST's `db-max-rows`: the most rows one read returns. An unbounded
   * `findMany` that returns this many sets `truncated` on the `query` event
   * and logs a warning once per table. Defaults to 1000, the hosted default.
   */
  readonly maxRows?: number;
  /**
   * The longest query string one PostgREST read sends, like supabase-js
   * `db.urlLengthLimit`. Longer reads are split along their longest `in`
   * list. Defaults to 6000 characters, or the client's `db.urlLengthLimit`
   * when that is lower.
   */
  readonly urlLengthLimit?: number;
  /**
   * The PostgREST version the app talks to, as in `postgrestVersion` in
   * the better-supabase config. `maxAffected` needs 13 or later, and fails
   * with `invalid_request` before any request on an older version.
   * Defaults to `"13"`.
   */
  readonly postgrestVersion?: string;
}

export interface ConnectOptions {
  /** Also records this connection's calls into a request-wide recorder. */
  readonly stats?: StatsRecorder;
  /**
   * Runs operations instead of the client's own executor, while `$client`
   * stays the client (e.g. routing reads to a replica).
   */
  readonly executor?: Executor;
  /**
   * Fails each repository call and `$rpc` after this many milliseconds with
   * a `timeout` error. A call's own `timeout` replaces it.
   */
  readonly timeout?: number;
  /**
   * postgrest-js retries of idempotent requests for this connection; a
   * call's own `retry` replaces it. Defaults to the client's setting.
   */
  readonly retry?: boolean;
  /**
   * Storage that runs as the same caller, as `db.$storage`. Defaults to
   * the client's `storage`; pass it when connecting an `Executor`, such as
   * direct Postgres as a user.
   */
  readonly storage?: StorageApi;
}

export interface RpcDefinition {
  /** App keys of the tables the function writes; their cached reads are invalidated on success. */
  readonly invalidates: readonly string[];
}
