import type { StandardSchemaV1 } from '@standard-schema/spec';

import { cacheTag, revalidateTag, updateTag } from 'next/cache.js';
import { headers } from 'next/headers.js';
import { type NextRequest, NextResponse } from 'next/server.js';
import { cache } from 'react';

import type { AuthState } from '../auth/resolve.ts';
import type { AuthSession } from '../auth/view.ts';
import type { CacheAdapter } from '../core/cache.ts';
import type { BetterSupabase } from '../core/define.ts';
import type { DbError } from '../core/errors.ts';
import type { QuerySpec } from '../core/spec.ts';
import type { AnyFunctions, AnyModels } from '../schema/types.ts';

import { serializeCookie } from '../auth/session.ts';
import { toSession } from '../auth/view.ts';
import { problemResponse } from '../core/problem.ts';
import { validate } from '../core/standard.ts';
import {
  defaultExpose,
  guard,
  type GuardOptions,
  respond,
  settle,
} from '../server/respond.ts';
import {
  type BetterServer,
  createServer,
  extendServer,
  type ServerContext,
  type ServerOptions,
} from '../server/server.ts';

export interface NextOptions extends ServerOptions {
  /** Invalidate `tagFor(table)` cache tags after mutations. Defaults to true. */
  readonly cacheTags?: boolean;
  /** Include internal error messages in Problem Details. Defaults to development only. */
  readonly exposeErrors?: boolean;
}

export type { AuthKind, GuardOptions } from '../server/respond.ts';
export type { AuthSession } from '../auth/view.ts';
export { toSession } from '../auth/view.ts';

export interface ProxyOptions {
  /** Answer before rendering, e.g. redirect signed-out users. Refreshed cookies are kept. */
  readonly protect?: (
    auth: AuthState,
    request: NextRequest,
  ) => Response | undefined | Promise<Response | undefined>;
}

export type ActionResult<T> =
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

export interface ActionOptions<
  S extends StandardSchemaV1 | undefined,
> extends GuardOptions {
  /** Validates the input (plain object or `FormData`) with any Standard Schema. */
  readonly input?: S;
}

type ActionInput<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferInput<S> | FormData
  : unknown;
type ActionParsed<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : unknown;
type Unwrapped<T> = T extends
  | { readonly ok: true; readonly data: infer D }
  | { readonly ok: false }
  ? D
  : T;

export interface BetterNext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
> extends BetterServer<M, F, E> {
  /** `proxy.ts`: refreshes sessions for page loads and server actions. */
  proxy(request: NextRequest, options?: ProxyOptions): Promise<Response>;
  /** Server Components and actions: the caller's context, memoized per request. */
  server(): Promise<ServerContext<M, F, E>>;
  /**
   * The verified caller as serializable data (no token, no clients), memoized
   * per request. Wrap it in a `'use cache: private'` function with Cache
   * Components and pass the promise to `<SessionProvider>`.
   */
  session(): Promise<AuthSession>;
  /** Route handler with auth, Result unwrapping and Problem Details errors. */
  route<P = Record<string, string | string[]>>(
    handler: (
      request: NextRequest,
      ctx: ServerContext<M, F, E> & { readonly params: P },
    ) => unknown,
    options?: GuardOptions,
  ): (
    request: NextRequest,
    segment: { readonly params: Promise<P> },
  ) => Promise<Response>;
  /** Server action returning a serializable `ActionResult`. */
  action<S extends StandardSchemaV1 | undefined, T>(
    options: ActionOptions<S>,
    fn: (input: ActionParsed<S>, ctx: ServerContext<M, F, E>) => Promise<T> | T,
  ): (input: ActionInput<S>) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
  /** Tags the current `"use cache"` scope with a table (and row) tag. */
  cacheTag(table: Extract<keyof M, string>, id?: string | number): void;
  /**
   * Tags the current `"use cache"` scope with every table `spec` reads (and
   * the row of a `findById`), so any mutation that changes one revalidates it.
   */
  cacheTags(spec: QuerySpec<Extract<keyof M, string>>): void;
}

/** `bs:<table>` or `bs:<table>:<id>`. Mutations invalidate both. */
export function tagFor(table: string, id?: string | number): string {
  return id === undefined ? `bs:${table}` : `bs:${table}:${String(id)}`;
}

function invalidate(tag: string): void {
  try {
    updateTag(tag);
  } catch {
    try {
      revalidateTag(tag, 'max');
    } catch {
      // Outside a Next.js request (jobs, scripts): nothing to invalidate.
    }
  }
}

/**
 * Invalidates `bs:<table>` for every table in the target and
 * `bs:<table>:<id>` for the changed rows. `createNext` attaches it unless
 * `cacheTags: false`.
 */
export function nextCache(): CacheAdapter {
  return {
    name: 'next',
    invalidate: (target) => {
      for (const table of target.tables) invalidate(tagFor(table));
      for (const id of target.ids) invalidate(tagFor(target.table, id));
    },
  };
}

function formDataObject(form: FormData): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of new Set(form.keys())) {
    const values = form.getAll(key);
    out[key] = values.length > 1 ? values : values[0];
  }
  return out;
}

/** Page loads, client navigations and server actions; never prefetches or assets. */
export function shouldRefresh(request: Request): boolean {
  const h = request.headers;
  if (request.method !== 'GET' && request.method !== 'HEAD')
    return h.has('next-action');
  if (
    h.has('next-router-prefetch') ||
    h.get('purpose') === 'prefetch' ||
    h.get('sec-purpose')?.includes('prefetch')
  ) {
    return false;
  }
  if (h.get('rsc') === '1') return true;
  const dest = h.get('sec-fetch-dest');
  if (dest) return dest === 'document';
  return h.get('accept')?.includes('text/html') ?? false;
}

/**
 * The Next.js adapter: proxy, Server Components, route handlers, server
 * actions and cache tags, on top of `createServer`.
 *
 * ```ts
 * export const next = createNext(sb);
 * ```
 */
export function createNext<M extends AnyModels, D, F extends AnyFunctions, E>(
  sb: BetterSupabase<M, D, F, E>,
  options: NextOptions = {},
): BetterNext<M, F, E> {
  const base = createServer(sb, options);
  const expose = options.exposeErrors ?? defaultExpose();

  if (options.cacheTags !== false) sb.cache(nextCache());

  const incomingRequest = async (): Promise<Request> =>
    new Request('http://next.local/', {
      headers: new Headers(await headers()),
    });

  const server = cache(async (): Promise<ServerContext<M, F, E>> =>
    base.context(await incomingRequest()),
  );

  const session = cache(async (): Promise<AuthSession> => {
    const resolution = await base.resolve(await incomingRequest(), {
      refresh: false,
    });
    return toSession(resolution.auth);
  });

  return extendServer<BetterNext<M, F, E>>(base, {
    server,
    session,

    async proxy(request, proxyOptions = {}) {
      const resolution = await base.resolve(request, {
        refresh: shouldRefresh(request),
      });
      const custom = await proxyOptions.protect?.(resolution.auth, request);
      if (custom) return resolution.apply(custom);
      if (resolution.cookies.length === 0) return NextResponse.next();

      const forwarded = new Headers(request.headers);
      forwarded.set(
        'cookie',
        resolution.requestCookies
          .map((cookie) => `${cookie.name}=${encodeURIComponent(cookie.value)}`)
          .join('; '),
      );
      const response = NextResponse.next({ request: { headers: forwarded } });
      for (const write of resolution.cookies)
        response.headers.append('set-cookie', serializeCookie(write));
      for (const [name, value] of Object.entries(resolution.headers))
        response.headers.set(name, value);
      return response;
    },

    route(handler, guardOptions = {}) {
      return async (request, segment) => {
        const ctx = await base.context(request);
        const denied = guard(ctx.auth, guardOptions.allow);
        const instance = request.nextUrl.pathname;
        if (denied) return problemResponse(denied, { instance, expose });
        const params = await segment.params;
        return respond(() => handler(request, { ...ctx, params }), {
          instance,
          expose,
        });
      };
    },

    action(actionOptions, fn) {
      type Out = ActionResult<Unwrapped<Awaited<ReturnType<typeof fn>>>>;
      return async (input) => {
        const ctx = await server();
        const denied = guard(ctx.auth, actionOptions.allow);
        if (denied) return { ok: false, data: null, error: denied } as Out;
        let parsed: unknown =
          input instanceof FormData ? formDataObject(input) : input;
        if (actionOptions.input) {
          const checked = await validate(actionOptions.input, parsed, 'input');
          if (!checked.ok)
            return { ok: false, data: null, error: checked.error } as Out;
          parsed = checked.data;
        }
        const settled = await settle(() => fn(parsed as never, ctx));
        return (
          settled.ok
            ? { ok: true, data: settled.data, error: null }
            : { ok: false, data: null, error: settled.error }
        ) as Out;
      };
    },

    cacheTag(table, id) {
      cacheTag(tagFor(table), ...(id === undefined ? [] : [tagFor(table, id)]));
    },

    cacheTags(spec) {
      const [id] = spec.args;
      const row =
        spec.method === 'findById' &&
        (typeof id === 'string' || typeof id === 'number')
          ? [tagFor(spec.table, id)]
          : [];
      cacheTag(...sb.tablesOf(spec).map((table) => tagFor(table)), ...row);
    },
  });
}
