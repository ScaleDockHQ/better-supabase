import type { AsyncResult } from "../../core/result.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { run } from "../shared.ts";

export interface LeaseOptions {
  /** How long the lease holds without an `extend`. Defaults to 60 seconds. */
  readonly seconds?: number;
  readonly scope?: string;
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

/**
 * Runs `fn` while holding the lease on `key`, one holder at a time, and
 * releases it afterwards, also when `fn` throws. `{ acquired: false }` while
 * another holder has it. A lease that expires mid-run is taken by the next
 * caller; call `lease.extend()` for long work.
 */
export function withLease<T>(
  sql: SqlClient,
  key: string,
  fn: (lease: Lease) => Promise<T> | T,
  options: LeaseOptions = {},
): AsyncResult<LeaseOutcome<T>> {
  const scope = options.scope ?? "";
  const ttl = options.seconds ?? 60;
  return run(async (): Promise<LeaseOutcome<T>> => {
    const [row] = await sql.queryRaw<{ holder: string | null }>(
      "select better_supabase.acquire_lease($1, $2, $3) as holder",
      [key, ttl, scope],
    );
    const holder = row?.holder;
    if (!holder) return { acquired: false };
    const lease: Lease = {
      holder,
      extend: (next = ttl) =>
        run(async () => {
          const [extended] = await sql.queryRaw<{ done: boolean }>(
            "select better_supabase.extend_lease($1, $2, $3, $4) as done",
            [key, holder, next, scope],
          );
          return extended?.done === true;
        }),
    };
    try {
      return { acquired: true, value: await fn(lease) };
    } finally {
      await sql.queryRaw("select better_supabase.release_lease($1, $2, $3)", [
        key,
        holder,
        scope,
      ]);
    }
  });
}

// ---------------------------------------------------------------------------
// Webhook inbox (SQL module `webhook-inbox`)
