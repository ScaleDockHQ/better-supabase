import type { Operation } from "../ir/types.ts";
import type { BlockEvent } from "./block-events.ts";
import type { DbError } from "./errors.ts";
import type { Logger } from "./logger.ts";
import type { MutationIntent, MutationKind, RequestContext } from "./plugin.ts";

import { cloneValue, deepFreeze } from "./clone.ts";
import { consoleLogger } from "./logger.ts";

export interface QueryEvent {
  readonly table: string;
  readonly operation: Operation["kind"];
  readonly ok: boolean;
  readonly durationMs: number;
  readonly rows: number;
  /**
   * An unbounded read returned `maxRows` rows: PostgREST's `db-max-rows`
   * probably cut it short. Add `limit` or use `page`.
   */
  readonly truncated: boolean;
}

export interface MutationNotice {
  readonly table: string;
  readonly kind: MutationKind;
  /** See `MutationEvent.intent`. */
  readonly intent?: MutationIntent;
  /** A copy of the returned rows: changing it never changes the result. */
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  /** See `MutationEvent.keys`. */
  readonly keys?: readonly Readonly<Record<string, unknown>>[];
  /** See `MutationEvent.tenant`. */
  readonly tenant?: string;
  readonly context: RequestContext;
}

/**
 * A successful RPC registered with `betterSupabase.defineRpc(name, {
 * invalidates })`.
 */
export interface RpcNotice {
  readonly name: string;
  /** App keys of the tables the function changes. */
  readonly invalidates: readonly string[];
  readonly context: RequestContext;
}

export interface ErrorEvent {
  readonly table?: string;
  readonly error: DbError;
}

/**
 * The `error` event for `error`: a frozen copy, so a handler can't change the
 * `DbError` the caller gets back (invariant 5).
 */
export function errorEvent(error: DbError, table?: string): ErrorEvent {
  // SAFETY: cloneValue keeps the shape of the plain DbError object.
  const copy = deepFreeze(cloneValue(error) as DbError);

  return table === undefined ? { error: copy } : { table, error: copy };
}

export interface AuthEvent {
  readonly source: "bearer" | "cookie" | "none";
  readonly ok: boolean;
  readonly userId?: string;
  /**
   * Why there is no user: the anon reason (`expired`, `signed_out`, ...) or the
   * invalid reason (`token`, `claims`, `actor`).
   */
  readonly reason?:
    | "none"
    | "expired"
    | "signed_out"
    | "refresh_failed"
    | "token"
    | "claims"
    | "actor";
  /** The user's `source` as the resolver set it, e.g. a custom resolver's name. */
  readonly rawSource?: string;
}

export interface RefreshEvent {
  readonly ok: boolean;
  readonly shared: boolean;
  readonly durationMs: number;
  /**
   * Why a failed refresh failed: `network` (Auth unreachable, timed out, or
   * answering 5xx or 429; the session is kept), `raced` (another request
   * rotated the token first; the cookies are kept) or `rejected` (the refresh
   * token is dead; the user is signed out).
   */
  readonly reason?: "network" | "raced" | "rejected";
  /** The Auth server's HTTP status, when it answered. */
  readonly status?: number;
  /** The Auth server's `error_code`, such as `refresh_token_not_found`. */
  readonly code?: string;
}

/**
 * A refresh that failed because the Auth server was unreachable, timed out or
 * answered 5xx or 429. `kept`: the access token was still valid, so the request
 * runs as the user; otherwise it runs as `anon` with `reason: "refresh_failed"`
 * and the cookies stay untouched.
 */
export interface AuthOutageEvent {
  readonly cause: "network" | "timeout" | "status";
  readonly status?: number;
  readonly kept: boolean;
  readonly durationMs: number;
}

export interface BetterSupabaseEvents {
  query: QueryEvent;
  mutation: MutationNotice;
  rpc: RpcNotice;
  error: ErrorEvent;
  auth: AuthEvent;
  refresh: RefreshEvent;
  /** Support sessions, organizations, invitations, notifications and webhooks. */
  block: BlockEvent;
}

export type EventName = keyof BetterSupabaseEvents;

export type EventHandler<K extends EventName> = (
  event: BetterSupabaseEvents[K],
) => void;

/** More handlers than this for one event usually means a missing unsubscribe. */
const HANDLER_WARNING = 50;

function isDevelopment(): boolean {
  return (
    typeof process !== "undefined" && process.env["NODE_ENV"] !== "production"
  );
}

/**
 * Observers only: a handler that throws is reported to the logger and never
 * changes a result.
 */
export class EventHub {
  readonly #handlers = new Map<EventName, Set<(event: never) => void>>();
  readonly #warned = new Set<EventName>();
  readonly #pending = new Set<Promise<void>>();
  readonly logger: Logger;
  /** The definition's `now` option; block events take their `time` from it. */
  readonly now: (() => Temporal.Instant) | undefined;

  constructor(logger: Logger = consoleLogger, now?: () => Temporal.Instant) {
    this.logger = logger;
    this.now = now;
  }

  on<K extends EventName>(name: K, handler: EventHandler<K>): () => void {
    let set = this.#handlers.get(name);

    if (!set) {
      set = new Set();
      this.#handlers.set(name, set);
    }

    set.add(handler);

    if (
      set.size > HANDLER_WARNING &&
      !this.#warned.has(name) &&
      isDevelopment()
    ) {
      this.#warned.add(name);
      this.logger.warn(
        `${set.size} "${name}" handlers are registered; call the function on() returns to remove one you no longer need`,
      );
    }

    return () => {
      set.delete(handler);
    };
  }

  has(name: EventName): boolean {
    return (this.#handlers.get(name)?.size ?? 0) > 0;
  }

  /**
   * Keeps async work a handler started (a sink send) until it settles, so
   * adapters can hand it to `after()` or `waitUntil`. Its outcome is ignored:
   * handlers report their own failures.
   */
  track(work: PromiseLike<unknown>): void {
    const settled: Promise<void> = Promise.resolve(work).then(
      () => undefined,
      () => undefined,
    );

    this.#pending.add(settled);
    void settled.then(() => this.#pending.delete(settled));
  }

  /** Whether tracked work is still running. */
  get pending(): boolean {
    return this.#pending.size > 0;
  }

  /** Resolves once the work tracked so far has settled. Never rejects. */
  async settled(): Promise<void> {
    await Promise.all(this.#pending);
  }

  emit<K extends EventName>(name: K, event: BetterSupabaseEvents[K]): void {
    const set = this.#handlers.get(name);

    if (!set) {
      return;
    }

    for (const handler of set) {
      try {
        // SAFETY: on() files each handler under its event name, so this set
        // holds handlers for K.
        (handler as EventHandler<K>)(event);
      } catch (cause) {
        this.logger.error(`"${name}" handler threw`, { cause });
      }
    }
  }
}
