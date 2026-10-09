import type { AnyEntry, Contributions } from "@supabase/middleware";
import type { IncomingMessage, ServerResponse } from "node:http";

import type { Validated } from "../bridges/shared.ts";
import type { RouteGuardOptions } from "../server/refusal.ts";

import { beforeRoute } from "../bridges/before-route.ts";
import { applyWebHeaders } from "../bridges/node-headers.ts";
import { around, toResponse } from "../bridges/shared.ts";
import {
  errorResponse,
  guardedLocals,
  routeRefusal,
} from "../server/refusal.ts";
import {
  sendWebResponse,
  toWebRequest,
  type WebRequestOptions,
} from "./http.ts";

export { applyWebHeaders, toWebHeaders } from "../bridges/node-headers.ts";
export type { NodeHeaderTarget } from "../bridges/node-headers.ts";
export { sendWebResponse, toWebRequest } from "./http.ts";
export type { WebRequestOptions } from "./http.ts";
export type { RouteGuardOptions } from "../server/refusal.ts";

export interface ToNodeOptions<Req = IncomingMessage> extends Omit<
  WebRequestOptions,
  "body"
> {
  /** The host's env object for `getEnv`; defaults to `process.env` through `getEnv`. */
  readonly env?: (req: Req) => unknown;
}

/**
 * A `node:http` request listener running the entries around `handler`.
 * Response-phase entries see the handler's response, so refreshed cookies
 * and `withDbStats` totals reach the client.
 *
 * ```ts
 * createServer(toNodeHandler([withBetterSupabase(server)], (request, { db }) => db.notes.findMany()))
 * ```
 */
export function toNodeHandler<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  handler: (request: Request, contributions: Contributions<Entries>) => unknown,
  options: ToNodeOptions = {},
): (req: IncomingMessage, res: ServerResponse) => Promise<void> {
  const run = around(entries);
  return async (req, res) => {
    const request = toWebRequest(req, options);
    const response = await run(
      request,
      options.env?.(req),
      async (contributions) =>
        // SAFETY: around() hands over exactly the entries' contributions.
        toResponse(
          await handler(request, contributions as Contributions<Entries>),
        ),
    );
    await sendWebResponse(res, response);
  };
}

/** Calls `next()` when `step` resolves true and `next(error)` when it rejects. */
async function continueWith(
  step: Promise<boolean>,
  next: (error?: unknown) => void,
): Promise<void> {
  let proceed: boolean;
  try {
    proceed = await step;
  } catch (error) {
    next(error);
    return;
  }
  if (proceed) next();
}

/** The part of an Express response the middleware writes. */
export interface ExpressResponse extends ServerResponse {
  /** Express's per-request locals; the contributions land here. */
  locals: Record<string, unknown>;
}

/** Express (or Connect) middleware, typed structurally. */
export type ExpressMiddleware = (
  req: IncomingMessage,
  res: ExpressResponse,
  next: (error?: unknown) => void,
) => void;

/** An Express error handler, typed structurally. */
export type ExpressErrorHandler = (
  error: unknown,
  req: IncomingMessage,
  res: ExpressResponse,
  next: (error?: unknown) => void,
) => void;

/**
 * Express middleware that puts every contribution on `res.locals`
 * (`res.locals.db`, `res.locals.bs`). Mount it before the routes.
 *
 * ```ts
 * app.use(toExpress([withBetterSupabase(server)]))
 * app.get('/notes', async (req, res) => res.json(await res.locals.db.notes.findMany().orThrow()))
 * ```
 */
export function toExpress<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  options: ToNodeOptions = {},
): ExpressMiddleware {
  const run = beforeRoute(entries);
  const handle = async (
    req: IncomingMessage,
    res: ExpressResponse,
  ): Promise<boolean> => {
    const outcome = await run(
      toWebRequest(req, { ...options, body: false }),
      options.env?.(req),
    );
    if (!outcome.reached) {
      await sendWebResponse(res, outcome.response);
      return false;
    }
    applyWebHeaders(res, outcome.headers);
    Object.assign(res.locals, outcome.contributions);
    return true;
  };
  return (req, res, next) => {
    void continueWith(handle(req, res), next);
  };
}

/**
 * Express route middleware that refuses callers outside `options`:
 * Problem Details, or a redirect to `signIn` or `mfa`. Runs after `toExpress`.
 *
 * ```ts
 * app.get('/admin', guard({ roles: ['admin'] }), handler)
 * ```
 */
export function guard(options: RouteGuardOptions = {}): ExpressMiddleware {
  const handle = async (
    req: IncomingMessage,
    res: ExpressResponse,
  ): Promise<boolean> => {
    const refused = await routeRefusal(
      guardedLocals(res.locals),
      toWebRequest(req, { body: false }),
      options,
    );
    if (!refused) return true;
    await sendWebResponse(res, refused);
    return false;
  };
  return (req, res, next) => {
    void continueWith(handle(req, res), next);
  };
}

/**
 * An Express error handler that answers thrown `DbException`s (from
 * `.orThrow()`) with Problem Details and passes every other error on.
 * Register it after the routes.
 */
export function problemErrorHandler(
  options: { readonly expose?: boolean } = {},
): ExpressErrorHandler {
  return (error, req, res, next) => {
    const response = errorResponse(
      error,
      toWebRequest(req, { body: false }),
      options,
    );
    if (!response || res.headersSent) {
      next(error);
      return;
    }
    void continueWith(
      sendWebResponse(res, response).then(() => false),
      next,
    );
  };
}

/** The part of a Fastify request the hook reads and writes. */
export interface FastifyRequestLike {
  readonly raw: IncomingMessage;
  /** The contributions land here: `request.locals.db`. */
  locals?: Record<string, unknown>;
}

/** The part of a Fastify reply the hook writes. */
export interface FastifyReplyLike {
  readonly raw: ServerResponse;
  readonly sent: boolean;
  code(status: number): FastifyReplyLike;
  header(name: string, value: string | readonly string[]): FastifyReplyLike;
  getHeader(name: string): number | string | string[] | undefined;
  send(payload?: unknown): FastifyReplyLike;
}

/** A Fastify `onRequest` or `preHandler` hook, typed structurally. */
export type FastifyHook = (
  request: FastifyRequestLike,
  reply: FastifyReplyLike,
) => Promise<void>;

function replyHeaders(reply: FastifyReplyLike): {
  getHeader(name: string): number | string | string[] | undefined;
  setHeader(name: string, value: number | string | readonly string[]): void;
} {
  return {
    getHeader: (name) => reply.getHeader(name),
    setHeader: (name, value) => {
      reply.header(name, typeof value === "number" ? String(value) : value);
    },
  };
}

async function sendReply(
  reply: FastifyReplyLike,
  response: Response,
): Promise<void> {
  applyWebHeaders(replyHeaders(reply), response.headers);
  reply.code(response.status);
  const body = response.body
    ? new Uint8Array(await response.arrayBuffer())
    : undefined;
  reply.send(body);
}

/**
 * A Fastify `onRequest` hook that puts every contribution on
 * `request.locals`. Declare `locals` with `app.decorateRequest('locals', null)`.
 *
 * ```ts
 * app.decorateRequest('locals', null)
 * app.addHook('onRequest', toFastify([withBetterSupabase(server)]))
 * app.get('/notes', (request) => request.locals.db.notes.findMany().orThrow())
 * ```
 */
export function toFastify<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  options: ToNodeOptions<FastifyRequestLike> = {},
): FastifyHook {
  const run = beforeRoute(entries);
  return async (request, reply) => {
    const web = toWebRequest(request.raw, { ...options, body: false });
    const outcome = await run(web, options.env?.(request));
    if (!outcome.reached) {
      await sendReply(reply, outcome.response);
      return;
    }
    applyWebHeaders(replyHeaders(reply), outcome.headers);
    request.locals = { ...request.locals, ...outcome.contributions };
  };
}

/**
 * A Fastify `preHandler` hook that refuses callers outside `options`. Runs
 * after `toFastify`.
 */
export function fastifyGuard(options: RouteGuardOptions = {}): FastifyHook {
  return async (request, reply) => {
    const refused = await routeRefusal(
      guardedLocals(request.locals ?? {}),
      toWebRequest(request.raw, { body: false }),
      options,
    );
    if (refused) await sendReply(reply, refused);
  };
}

/** The part of a Koa context the middleware reads and writes. */
export interface KoaContextLike {
  readonly req: IncomingMessage;
  readonly res: ServerResponse;
  /** Koa's per-request state; the contributions land here. */
  state: Record<string, unknown>;
  status: number;
  body: unknown;
  set(name: string, value: string | readonly string[]): void;
  get response(): { get(name: string): string | string[] | undefined };
}

/** Koa middleware, typed structurally. */
export type KoaMiddleware = (
  ctx: KoaContextLike,
  next: () => Promise<unknown>,
) => Promise<void>;

function koaHeaders(ctx: KoaContextLike): {
  getHeader(name: string): string | string[] | undefined;
  setHeader(name: string, value: number | string | readonly string[]): void;
} {
  return {
    getHeader: (name) => {
      const value = ctx.response.get(name);
      return value === "" ? undefined : value;
    },
    setHeader: (name, value) => {
      ctx.set(name, typeof value === "number" ? String(value) : value);
    },
  };
}

async function sendKoa(ctx: KoaContextLike, response: Response): Promise<void> {
  applyWebHeaders(koaHeaders(ctx), response.headers);
  ctx.status = response.status;
  ctx.body = response.body ? Buffer.from(await response.arrayBuffer()) : null;
}

/**
 * Koa middleware that puts every contribution on `ctx.state`, then awaits
 * the rest of the chain. Thrown `DbException`s become Problem Details.
 *
 * ```ts
 * app.use(toKoa([withBetterSupabase(server)]))
 * app.use(async (ctx) => { ctx.body = await ctx.state.db.notes.findMany().orThrow() })
 * ```
 */
export function toKoa<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  options: ToNodeOptions<KoaContextLike> & { readonly expose?: boolean } = {},
): KoaMiddleware {
  const run = beforeRoute(entries);
  return async (ctx, next) => {
    const web = toWebRequest(ctx.req, { ...options, body: false });
    const outcome = await run(web, options.env?.(ctx));
    if (!outcome.reached) {
      await sendKoa(ctx, outcome.response);
      return;
    }
    applyWebHeaders(koaHeaders(ctx), outcome.headers);
    Object.assign(ctx.state, outcome.contributions);
    try {
      await next();
    } catch (error) {
      const response = errorResponse(error, web, options);
      if (!response) throw error;
      await sendKoa(ctx, response);
    }
  };
}

/** Koa middleware that refuses callers outside `options`. Runs after `toKoa`. */
export function koaGuard(options: RouteGuardOptions = {}): KoaMiddleware {
  return async (ctx, next) => {
    const refused = await routeRefusal(
      guardedLocals(ctx.state),
      toWebRequest(ctx.req, { body: false }),
      options,
    );
    if (refused) {
      await sendKoa(ctx, refused);
      return;
    }
    await next();
  };
}
