import type { BlockTransport } from "../../core/block-transport.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { run } from "../shared.ts";

export interface LeaseOptions {
  /** How long the lease holds without an `extend`. Defaults to 60 seconds. */
  readonly seconds?: number;
  readonly scope?: string;
  /** The schema the functions live in, over a transport. Defaults to `better_supabase`. */
  readonly schema?: string;
}

/** The held lease, passed to the `withLease` callback. */
export interface Lease {
  readonly holder: string;
  /** Moves the expiry; `false` once the lease was lost to another holder. */
  extend(seconds?: number): AsyncResult<boolean>;
}

export type LeaseOutcome<T> =
  | { readonly acquired: true; readonly value: T }
  | { readonly acquired: false };

interface LeaseCalls {
  acquire(key: string, ttl: number, scope: string): Promise<string | null>;
  extend(
    key: string,
    holder: string,
    ttl: number,
    scope: string,
  ): Promise<boolean>;
  release(key: string, holder: string, scope: string): Promise<void>;
}

function sqlCalls(sql: SqlClient): LeaseCalls {
  return {
    async acquire(key, ttl, scope) {
      const [row] = await sql.queryRaw<{ holder: string | null }>(
        "select better_supabase.acquire_lease($1, $2, $3) as holder",
        [key, ttl, scope],
      );
      return row?.holder ?? null;
    },
    async extend(key, holder, ttl, scope) {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.extend_lease($1, $2, $3, $4) as done",
        [key, holder, ttl, scope],
      );
      return row?.done === true;
    },
    async release(key, holder, scope) {
      await sql.queryRaw("select better_supabase.release_lease($1, $2, $3)", [
        key,
        holder,
        scope,
      ]);
    },
  };
}

function transportCalls(transport: BlockTransport, schema: string): LeaseCalls {
  return {
    async acquire(key, ttl, scope) {
      const holder = await transport.call(schema, "acquire_lease", {
        key,
        seconds: ttl,
        scope,
      });
      return typeof holder === "string" ? holder : null;
    },
    extend: async (key, holder, ttl, scope) =>
      (await transport.call(schema, "extend_lease", {
        key,
        holder,
        seconds: ttl,
        scope,
      })) === true,
    async release(key, holder, scope) {
      await transport.call(schema, "release_lease", { key, holder, scope });
    },
  };
}

/**
 * Runs `fn` while holding the lease on `key`, one holder at a time, and
 * releases it afterwards, also when `fn` throws. `{ acquired: false }` while
 * another holder has it. A lease that expires mid-run is taken by the next
 * caller; call `lease.extend()` for long work. Takes a service SQL
 * connection, or a service-role `rpcTransport` over the wrappers
 * `blocks.idempotency.api` writes.
 */
export function withLease<T>(
  source: SqlClient | BlockTransport,
  key: string,
  fn: (lease: Lease) => Promise<T> | T,
  options: LeaseOptions = {},
): AsyncResult<LeaseOutcome<T>> {
  const scope = options.scope ?? "";
  const ttl = options.seconds ?? 60;
  const calls =
    "call" in source
      ? transportCalls(source, options.schema ?? DEFAULT_BLOCK_SCHEMA)
      : sqlCalls(source);
  return run(async (): Promise<LeaseOutcome<T>> => {
    const holder = await calls.acquire(key, ttl, scope);
    if (!holder) return { acquired: false };
    const lease: Lease = {
      holder,
      extend: (next = ttl) => run(() => calls.extend(key, holder, next, scope)),
    };
    try {
      return { acquired: true, value: await fn(lease) };
    } finally {
      await calls.release(key, holder, scope);
    }
  });
}
