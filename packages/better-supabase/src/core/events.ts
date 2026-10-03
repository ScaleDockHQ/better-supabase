import type { Operation } from "../ir/types.ts";
import type { DbError } from "./errors.ts";
import type { MutationIntent, MutationKind, RequestContext } from "./plugin.ts";

import { consoleLogger, type Logger } from "./logger.ts";

export interface QueryEvent {
  readonly table: string;
  readonly operation: Operation["kind"];
  readonly ok: boolean;
  readonly durationMs: number;
  readonly rows: number;
  /**
   * An unbounded read returned `maxRows` rows: PostgREST's `db-max-rows`
   * probably cut it short. Add `limit` or use `paginate`.
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

/** A successful RPC registered with `betterSupabase.defineRpc(name, { invalidates })`. */
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

export interface AuthEvent {
  readonly source: "bearer" | "cookie" | "none";
  readonly ok: boolean;
  readonly userId?: string;
  /**
   * Why there is no user: the anon reason (`expired`, `signed_out`, ...) or
   * the invalid reason (`token`, `claims`, `actor`).
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
}

export interface BetterSupabaseEvents {
  query: QueryEvent;
  mutation: MutationNotice;
  rpc: RpcNotice;
  error: ErrorEvent;
  auth: AuthEvent;
  refresh: RefreshEvent;
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

  constructor(logger: Logger = consoleLogger) {
    this.logger = logger;
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
    if (!set) return;
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
