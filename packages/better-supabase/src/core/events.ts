import type { Operation } from '../ir/types.ts';
import type { DbError } from './errors.ts';
import type { MutationKind, RequestContext } from './plugin.ts';

import { consoleLogger, type Logger } from './logger.ts';

export interface QueryEvent {
  readonly table: string;
  readonly operation: Operation['kind'];
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
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  readonly context: RequestContext;
}

/** A successful RPC registered with `sb.defineRpc(name, { invalidates })`. */
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
  readonly source: 'bearer' | 'cookie' | 'none';
  readonly ok: boolean;
  readonly userId?: string;
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

/**
 * Observers only: a handler that throws is reported to the logger and never
 * changes a result.
 */
export class EventHub {
  readonly #handlers = new Map<EventName, Set<(event: never) => void>>();
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
    return () => {
      set.delete(handler);
    };
  }

  has(name: EventName): boolean {
    return (this.#handlers.get(name)?.size ?? 0) > 0;
  }

  emit<K extends EventName>(name: K, event: BetterSupabaseEvents[K]): void {
    const set = this.#handlers.get(name);
    if (!set) return;
    for (const handler of set) {
      try {
        (handler as EventHandler<K>)(event);
      } catch (cause) {
        this.logger.error(`"${name}" handler threw`, { cause });
      }
    }
  }
}
