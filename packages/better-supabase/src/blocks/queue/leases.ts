import type { BlockTransport } from "../../core/block-transport.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import {
  budget,
  DEFAULT_BLOCK_SCHEMA,
  leaseHeartbeat,
  run,
  sleep,
  toInstant,
} from "../../core/block-helpers.ts";
import { transportRows } from "./backends.ts";

/** Where `createLeases` stores leases: a service SQL connection or transport. */
export type LeasesSource = SqlClient | BlockTransport;

export interface LeasesOptions {
  /**
   * The schema the functions live in, over a transport. Defaults to
   * `better_supabase`.
   */
  readonly schema?: string;
  /** The scope a call uses without its own. Defaults to the empty scope. */
  readonly scope?: string;
}

export interface LeaseClaimInput {
  readonly scope?: string;
  readonly key: string;
  /**
   * How long `claim` waits while another holder has the lease, in ms. It
   * retries with backoff and stops at this bound, so pass what is left of a
   * drain's `budgetMs`. Defaults to 0: one attempt.
   */
  readonly timeoutMs?: number;
  /** Seconds the lease holds without an `extend`. Defaults to 60. */
  readonly leaseSeconds?: number;
}

/** The held lease. */
export interface HeldLease {
  readonly scope: string;
  readonly key: string;
  readonly holder: string;
  readonly expiresAt: Temporal.Instant;
  /** Moves the expiry; `false` once the lease ran out or was taken over. */
  extend(leaseSeconds?: number): AsyncResult<boolean>;
  /**
   * Marks the work done: later claims answer `completed` for `keepSeconds`
   * (default one day). `false` when another holder took the lease over.
   */
  complete(keepSeconds?: number): AsyncResult<boolean>;
  /** Gives the lease up so the next claim succeeds at once. */
  release(): AsyncResult<boolean>;
}

/**
 * `claimed` holds the lease. `busy` means another holder still had it when the
 * wait ended, and `retryAfterMs` is when that holder's lease runs out.
 * `completed` means a holder finished the work, so the caller skips it.
 */
export type LeaseClaim =
  | { readonly status: "claimed"; readonly lease: HeldLease }
  | { readonly status: "busy"; readonly retryAfterMs: number }
  | { readonly status: "completed"; readonly until: Temporal.Instant };

export interface WithLeaseOptions extends LeaseClaimInput {
  /**
   * Mark the lease completed when `fn` returns, for this many seconds (`true`
   * keeps it for a day). Without it the lease is released.
   */
  readonly completeFor?: number | true;
  /** Extend the lease while `fn` runs. Defaults to true. */
  readonly heartbeat?: boolean;
}

export type WithLeaseResult<T> =
  | { readonly status: "claimed"; readonly value: T }
  | { readonly status: "busy"; readonly retryAfterMs: number }
  | { readonly status: "completed"; readonly until: Temporal.Instant };

export interface Leases {
  /**
   * Claims the lease on `(scope, key)`, waiting up to `timeoutMs` while another
   * holder has it. A lease that ran out is taken over.
   */
  claim(input: LeaseClaimInput): AsyncResult<LeaseClaim>;
  /**
   * Runs `fn` while holding the lease, extends it in the background, and
   * releases it afterwards, also when `fn` throws (the thrown error comes back
   * as the error of the result).
   */
  withLease<T>(
    input: WithLeaseOptions,
    fn: (lease: HeldLease) => Promise<T> | T,
  ): AsyncResult<WithLeaseResult<T>>;
}

interface ClaimRow {
  readonly lease_state: string;
  readonly lease_holder: string | null;
  readonly lease_expires_at: Date | string | null;
  readonly retry_after_ms: number | string | null;
}

interface LeaseCalls {
  claim(
    scope: string,
    key: string,
    seconds: number,
  ): Promise<readonly ClaimRow[]>;
  extend(
    scope: string,
    key: string,
    holder: string,
    seconds: number,
  ): Promise<boolean>;
  complete(
    scope: string,
    key: string,
    holder: string,
    keep: number,
  ): Promise<boolean>;
  release(scope: string, key: string, holder: string): Promise<boolean>;
}

const DAY_SECONDS = 86_400;
const FIRST_BACKOFF_MS = 50;
const MAX_BACKOFF_MS = 1000;

function sqlCalls(sql: SqlClient): LeaseCalls {
  const flag = async (text: string, values: unknown[]): Promise<boolean> => {
    const [row] = await sql.queryRaw<{ done: boolean }>(text, values);

    return row?.done === true;
  };

  return {
    claim: (scope, key, seconds) =>
      sql.queryRaw<ClaimRow>(
        "select * from better_supabase.claim_lease($1, $2, $3)",
        [scope, key, seconds],
      ),
    extend: (scope, key, holder, seconds) =>
      flag(
        "select better_supabase.extend_lease_claim($1, $2, $3::uuid, $4) as done",
        [scope, key, holder, seconds],
      ),
    complete: (scope, key, holder, keep) =>
      flag(
        "select better_supabase.complete_lease($1, $2, $3::uuid, $4) as done",
        [scope, key, holder, keep],
      ),
    release: (scope, key, holder) =>
      flag(
        "select better_supabase.release_lease_claim($1, $2, $3::uuid) as done",
        [scope, key, holder],
      ),
  };
}

function transportCalls(transport: BlockTransport, schema: string): LeaseCalls {
  return {
    claim: async (scope, key, seconds) =>
      transportRows<ClaimRow>(
        "claim_lease",
        await transport.call(schema, "claim_lease", {
          scope,
          key,
          lease_seconds: seconds,
        }),
      ),
    extend: async (scope, key, holder, seconds) =>
      (await transport.call(schema, "extend_lease_claim", {
        scope,
        key,
        holder,
        lease_seconds: seconds,
      })) === true,
    complete: async (scope, key, holder, keep) =>
      (await transport.call(schema, "complete_lease", {
        scope,
        key,
        holder,
        keep_seconds: keep,
      })) === true,
    release: async (scope, key, holder) =>
      (await transport.call(schema, "release_lease_claim", {
        scope,
        key,
        holder,
      })) === true,
  };
}

function checkKey(key: string): void {
  if (key === "") {
    throw new TypeError("better-supabase: a lease needs a key");
  }
}

/**
 * Leases on any `(scope, key)` in the `queue` block's `job_leases` table: one
 * holder at a time, a bounded wait with backoff, and a `completed` answer once
 * the work is done. Takes a service SQL connection or a service-role transport
 * (`rpcTransport` over the wrappers `blocks.queue.api` writes).
 */
export function createLeases(
  source: LeasesSource,
  options: LeasesOptions = {},
): Leases {
  const calls =
    "call" in source
      ? transportCalls(source, options.schema ?? DEFAULT_BLOCK_SCHEMA)
      : sqlCalls(source);

  const defaultScope = options.scope ?? "";

  const holdOf = (
    scope: string,
    key: string,
    holder: string,
    expiresAt: Temporal.Instant,
    seconds: number,
  ): HeldLease => ({
    scope,
    key,
    holder,
    expiresAt,
    extend: (next = seconds) =>
      run(() => calls.extend(scope, key, holder, next)),
    complete: (keep = DAY_SECONDS) =>
      run(() => calls.complete(scope, key, holder, keep)),
    release: () => run(() => calls.release(scope, key, holder)),
  });

  async function claimOnce(
    input: LeaseClaimInput,
    scope: string,
    seconds: number,
  ): Promise<LeaseClaim> {
    const [row] = await calls.claim(scope, input.key, seconds);
    const retryAfterMs = Number(row?.retry_after_ms ?? 0);

    if (row?.lease_state === "claimed" && row.lease_holder) {
      return {
        status: "claimed",
        lease: holdOf(
          scope,
          input.key,
          row.lease_holder,
          toInstant(row.lease_expires_at ?? new Date()),
          seconds,
        ),
      };
    }

    if (row?.lease_state === "completed" && row.lease_expires_at) {
      return { status: "completed", until: toInstant(row.lease_expires_at) };
    }

    return { status: "busy", retryAfterMs };
  }

  async function claim(input: LeaseClaimInput): Promise<LeaseClaim> {
    checkKey(input.key);

    const scope = input.scope ?? defaultScope;
    const seconds = input.leaseSeconds ?? 60;
    const wait = budget(input.timeoutMs ?? 0);
    let backoff = FIRST_BACKOFF_MS;

    for (;;) {
      const claimed = await claimOnce(input, scope, seconds);

      if (claimed.status !== "busy") {
        return claimed;
      }

      const left = wait.remaining();

      if (left <= 0) {
        return claimed;
      }

      // Wake when the holder's lease ends if that is sooner than the backoff.
      const hint =
        claimed.retryAfterMs > 0
          ? claimed.retryAfterMs
          : Number.POSITIVE_INFINITY;

      await sleep(Math.max(1, Math.min(backoff, hint, left)));
      backoff = Math.min(backoff * 2, MAX_BACKOFF_MS);
    }
  }

  async function withLease<T>(
    input: WithLeaseOptions,
    fn: (lease: HeldLease) => Promise<T> | T,
  ): Promise<WithLeaseResult<T>> {
    const claimed = await claim(input);

    if (claimed.status !== "claimed") {
      return claimed;
    }

    const { lease } = claimed;
    const seconds = input.leaseSeconds ?? 60;

    const stop =
      input.heartbeat === false
        ? () => undefined
        : leaseHeartbeat(seconds, () => {
            // A failed extend surfaces when the lease is completed or lost.
            void lease.extend(seconds);
          });

    let value: T;

    try {
      value = await fn(lease);
    } catch (cause) {
      stop();
      // Released first, so the next claim does not wait for the lease to run
      // out. A failed release never hides the error.
      await lease.release();
      throw cause;
    }

    stop();

    if (input.completeFor === undefined) {
      await lease.release();
    } else {
      await lease.complete(
        input.completeFor === true ? DAY_SECONDS : input.completeFor,
      );
    }

    return { status: "claimed", value };
  }

  return {
    claim: (input) => run(() => claim(input)),
    withLease: (input, fn) => run(() => withLease(input, fn)),
  };
}
