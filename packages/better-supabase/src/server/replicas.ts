import { parseCookieHeader, serializeCookieHeader } from "@supabase/ssr";

import type { CookieWrite } from "../auth/session.ts";
import type { Executor } from "../core/executor.ts";

/** Cookie holding the epoch ms until which reads stay on the primary. */
export const PRIMARY_COOKIE = "bs-primary-until";

/** Default time reads stay on the primary after a write. */
export const DEFAULT_PIN_MS = 5000;

/** Where a request context sends its reads. */
export interface ReplicaState {
  /** Reads go to the primary: this context wrote, or a recent request did. */
  readonly pinned: boolean;
  /** This context wrote through its repositories (or called `pin()`). */
  readonly wrote: boolean;
  /** Sends later reads to the primary, e.g. after a write through `$client` or `ctx.sql`. */
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

/** `bs-primary-until` from a `cookie` header or parsed cookies, or 0. */
export function pinnedUntil(
  cookies: string | null | readonly { name: string; value: string }[],
): number {
  if (!cookies) return 0;
  const records =
    typeof cookies === "string" ? parseCookieHeader(cookies) : cookies;
  const value = records.find((cookie) => cookie.name === PRIMARY_COOKIE)?.value;
  const until = Number(value);
  return value !== undefined && Number.isFinite(until) ? until : 0;
}

/** Options of the `bs-primary-until` cookie. */
function primaryCookieOptions(pinMs: number): {
  readonly path: "/";
  readonly maxAge: number;
  readonly httpOnly: true;
  readonly sameSite: "lax";
} {
  return {
    path: "/",
    maxAge: Math.max(1, Math.ceil(pinMs / 1000)),
    httpOnly: true,
    sameSite: "lax",
  };
}

/** The `bs-primary-until` cookie write after a write, for cookie-jar APIs. */
export function primaryCookieWrite(
  replica: ReplicaState | undefined,
  pinMs: number,
  now: number = Date.now(),
): CookieWrite | undefined {
  if (!replica?.wrote) return undefined;
  return {
    name: PRIMARY_COOKIE,
    value: String(now + pinMs),
    options: primaryCookieOptions(pinMs),
  };
}

/** A `Set-Cookie` value keeping the next requests on the primary for `pinMs`. */
export function primaryCookie(pinMs: number, now: number = Date.now()): string {
  return serializeCookieHeader(
    PRIMARY_COOKIE,
    String(now + pinMs),
    primaryCookieOptions(pinMs),
  );
}

/**
 * `response` with the `bs-primary-until` cookie when the request wrote, so the
 * caller's next requests read their own writes. A response with immutable
 * headers is copied.
 */
export function withPrimaryPin(
  response: Response,
  replica: ReplicaState | undefined,
  pinMs: number,
): Response {
  if (!replica?.wrote) return response;
  const cookie = primaryCookie(pinMs);
  try {
    response.headers.append("set-cookie", cookie);
    return response;
  } catch {
    const copy = new Response(response.body, response);
    copy.headers.append("set-cookie", cookie);
    return copy;
  }
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
    ...(primary.functionSources && replica.functionSources
      ? { functionSources: true }
      : {}),
    async execute(op, context) {
      if (op.kind === "select" && !state.pinned)
        return replica.execute(op, context);
      const result = await primary.execute(op, context);
      if (op.kind !== "select" && result.ok) state.pin();
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
