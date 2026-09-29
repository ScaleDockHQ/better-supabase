import type { Executor } from '../core/executor.ts';

/** Cookie holding the epoch ms until which reads stay on the primary. */
export const PRIMARY_COOKIE = 'bs-primary-until';

/** Default time reads stay on the primary after a write. */
export const DEFAULT_PIN_MS = 5000;

/** Where a request context sends its reads. */
export interface ReplicaState {
  /** Reads go to the primary: this context wrote, or a recent request did. */
  readonly pinned: boolean;
  /** This context wrote through its repositories (or called `pin()`). */
  readonly wrote: boolean;
  /** Sends later reads to the primary, e.g. after a write through `$client` or `$sql`. */
  pin(): void;
}

export function replicaState(
  pinnedUntil: number = 0,
  now: number = Date.now(),
): ReplicaState {
  let wrote = false;
  const inherited = pinnedUntil > now;
  return {
    get pinned() {
      return wrote || inherited;
    },
    get wrote() {
      return wrote;
    },
    pin() {
      wrote = true;
    },
  };
}

/** `bs-primary-until` from a `cookie` header, or 0. */
export function pinnedUntil(cookieHeader: string | null): number {
  if (!cookieHeader) return 0;
  for (const part of cookieHeader.split(';')) {
    const [name, value] = part.trim().split('=', 2);
    if (name === PRIMARY_COOKIE) {
      const until = Number(value);
      return Number.isFinite(until) ? until : 0;
    }
  }
  return 0;
}

/** A `Set-Cookie` value keeping the next requests on the primary for `pinMs`. */
export function primaryCookie(pinMs: number, now: number = Date.now()): string {
  const seconds = Math.max(1, Math.ceil(pinMs / 1000));
  return `${PRIMARY_COOKIE}=${String(now + pinMs)}; Path=/; Max-Age=${String(seconds)}; HttpOnly; SameSite=Lax`;
}

/**
 * Reads go to `replica` until the context is pinned; writes, and every read
 * after a successful write, go to `primary`.
 */
export function routedExecutor(
  primary: Executor,
  replica: Executor,
  state: ReplicaState,
): Executor {
  const batch = primary.batch?.bind(primary);
  const replicaBatch = replica.batch?.bind(replica);
  return {
    name: primary.name,
    async execute(op, context) {
      if (op.kind === 'select' && !state.pinned)
        return replica.execute(op, context);
      const result = await primary.execute(op, context);
      if (op.kind !== 'select' && result.ok) state.pin();
      return result;
    },
    ...(primary.rpc
      ? {
          async rpc(name, args, context) {
            if (context.get && !state.pinned && replica.rpc)
              return replica.rpc(name, args, context);
            const result = await primary.rpc!(name, args, context);
            if (!context.get && result.ok) state.pin();
            return result;
          },
        }
      : {}),
    ...(batch
      ? {
          batch: (ops, context) =>
            !state.pinned && replicaBatch
              ? replicaBatch(ops, context)
              : batch(ops, context),
        }
      : {}),
  } satisfies Executor;
}
