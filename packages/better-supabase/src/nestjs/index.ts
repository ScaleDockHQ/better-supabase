import type { AnyEntry } from "@supabase/middleware";
import type { IncomingMessage, ServerResponse } from "node:http";

import { createRequire } from "node:module";

import type { Validated } from "../bridges/shared.ts";
import type { ToNodeOptions } from "../node/index.ts";
import type { RouteGuardOptions } from "../server/refusal.ts";

import { beforeRoute } from "../bridges/before-route.ts";
import { applyWebHeaders } from "../bridges/node-headers.ts";
import { sendWebResponse, toWebRequest } from "../node/http.ts";
import {
  errorResponse,
  guardedLocals,
  routeRefusal,
} from "../server/refusal.ts";

export type { RouteGuardOptions } from "../server/refusal.ts";

/** The part of Nest's `ArgumentsHost` and `ExecutionContext` the integration reads. */
export interface ExecutionContextLike {
  switchToHttp(): {
    getRequest(): object;
    getResponse(): object;
  };
}

/** A Nest guard instance, for `@UseGuards(...)`. */
export interface CanActivateLike {
  canActivate(context: ExecutionContextLike): Promise<boolean>;
}

/** A Nest exception filter instance, for `@UseFilters(...)` or `app.useGlobalFilters(...)`. */
export interface ExceptionFilterLike {
  catch(exception: unknown, host: ExecutionContextLike): void;
}

/** Nest functional middleware: raw Node `req` and `res` under Express and Fastify. */
export type NestMiddleware = (
  req: IncomingMessage,
  res: ServerResponse,
  next: (error?: unknown) => void,
) => void;

const contexts = new WeakMap<object, Record<string, unknown>>();

/** The Node request under an Express request or a Fastify request (`request.raw`). */
function rawOf(value: object): object {
  return "raw" in value && typeof value.raw === "object" && value.raw !== null
    ? value.raw
    : value;
}

function isServerResponse(value: object): value is ServerResponse {
  return (
    "setHeader" in value &&
    typeof value.setHeader === "function" &&
    "end" in value &&
    typeof value.end === "function"
  );
}

function responseOf(host: ExecutionContextLike): ServerResponse {
  const raw = rawOf(host.switchToHttp().getResponse());
  if (!isServerResponse(raw)) {
    throw new TypeError("better-supabase: not an HTTP response");
  }
  return raw;
}

function requestOf(host: ExecutionContextLike): IncomingMessage {
  // SAFETY: Express requests are IncomingMessages and rawOf unwraps Fastify's.
  return rawOf(host.switchToHttp().getRequest()) as IncomingMessage;
}

/** The contributions `toNestMiddleware` stored for a request (Express or Fastify), if it ran. */
export function contextOf(
  request: object,
): Readonly<Record<string, unknown>> | undefined {
  return contexts.get(rawOf(request));
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

/**
 * Nest middleware that runs the entries before the route: a short circuit
 * (a 401, a CORS preflight) is the answer; otherwise the entries' cookies
 * go on the response and `@Ctx()` reads the contributions.
 *
 * ```ts title="src/app.module.ts"
 * export class AppModule implements NestModule {
 *   configure(consumer: MiddlewareConsumer) {
 *     consumer.apply(toNestMiddleware([withBetterSupabase(server)])).forRoutes('*')
 *   }
 * }
 * ```
 */
export function toNestMiddleware<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  options: ToNodeOptions = {},
): NestMiddleware {
  const run = beforeRoute(entries);
  const handle = async (
    req: IncomingMessage,
    res: ServerResponse,
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
    contexts.set(req, outcome.contributions);
    return true;
  };
  return (req, res, next) => {
    void continueWith(handle(req, res), next);
  };
}

/** The parts of `@nestjs/common` the decorator and guard use. */
interface NestCommon {
  createParamDecorator(
    factory: (data: unknown, context: ExecutionContextLike) => unknown,
  ): (data?: unknown) => ParameterDecorator;
  readonly HttpException: new (response: object, status: number) => Error;
}

function isNestCommon(value: unknown): value is NestCommon {
  return (
    typeof value === "object" &&
    value !== null &&
    "createParamDecorator" in value &&
    typeof value.createParamDecorator === "function" &&
    "HttpException" in value &&
    typeof value.HttpException === "function"
  );
}

const NEST_COMMON = "@nestjs/common";
let nest: NestCommon | undefined;

/**
 * `@nestjs/common` is an optional peer, loaded on first use with a
 * variable specifier so apps on other frameworks never resolve it. It is
 * required synchronously because decorators run while the class is defined.
 */
function nestCommon(): NestCommon {
  if (nest) return nest;
  let loaded: unknown;
  try {
    loaded = createRequire(import.meta.url)(NEST_COMMON);
  } catch (cause) {
    throw new Error(
      "better-supabase/nestjs needs @nestjs/common. Install it with `pnpm add @nestjs/common`.",
      { cause },
    );
  }
  if (!isNestCommon(loaded)) {
    throw new Error(
      "better-supabase/nestjs: @nestjs/common has no createParamDecorator",
    );
  }
  nest = loaded;
  return nest;
}

let ctxDecorator: ((data?: unknown) => ParameterDecorator) | undefined;

/**
 * A parameter decorator for the request's contributions, or one of them:
 * `@Ctx() ctx` or `@Ctx('db') db`.
 *
 * ```ts
 * @Get('notes')
 * list(@Ctx('db') db: Db) { return db.notes.findMany().orThrow() }
 * ```
 */
export function Ctx(key?: string): ParameterDecorator {
  ctxDecorator ??= nestCommon().createParamDecorator((data, context) => {
    const contributions = contextOf(context.switchToHttp().getRequest());
    if (contributions === undefined) {
      throw new Error(
        "better-supabase: no request context; apply toNestMiddleware(...) for this route",
      );
    }
    return typeof data === "string" ? contributions[data] : contributions;
  });
  return ctxDecorator(key);
}

/**
 * A guard instance that refuses callers outside `options`: Problem Details,
 * or a 303 to `signIn` or `mfa`, thrown as Nest's `HttpException`.
 *
 * ```ts
 * @UseGuards(guard({ roles: ['admin'] }))
 * ```
 */
export function guard(options: RouteGuardOptions = {}): CanActivateLike {
  return {
    canActivate: async (context) => {
      const req = requestOf(context);
      const contributions = contexts.get(req);
      if (contributions === undefined) {
        throw new Error(
          "better-supabase: no request context; apply toNestMiddleware(...) before the guard",
        );
      }
      const refused = await routeRefusal(
        guardedLocals(contributions),
        toWebRequest(req, { body: false }),
        options,
      );
      if (!refused) return true;
      const location = refused.headers.get("location");
      if (location !== null)
        responseOf(context).setHeader("location", location);
      const body: unknown = refused.body ? await refused.json() : {};
      const { HttpException } = nestCommon();
      throw new HttpException(
        typeof body === "object" && body !== null ? body : {},
        refused.status,
      );
    },
  };
}

/**
 * An exception filter that answers thrown `DbException`s (from
 * `.orThrow()`) with Problem Details. Register it with `@Catch()` scope in
 * mind: other exceptions are answered the way Nest's base filter does.
 */
export function problemFilter(
  options: { readonly expose?: boolean } = {},
): ExceptionFilterLike {
  return {
    catch(exception, host) {
      const req = requestOf(host);
      const res = responseOf(host);
      const response =
        errorResponse(exception, toWebRequest(req, { body: false }), options) ??
        nestErrorResponse(exception);
      if (res.headersSent) return;
      void sendWebResponse(res, response);
    },
  };
}

/** The part of Nest's `HttpException` the filter reads. */
interface HttpExceptionLike {
  getStatus(): unknown;
  getResponse(): unknown;
}

function isHttpException(value: unknown): value is HttpExceptionLike {
  return (
    typeof value === "object" &&
    value !== null &&
    "getStatus" in value &&
    typeof value.getStatus === "function" &&
    "getResponse" in value &&
    typeof value.getResponse === "function"
  );
}

function nestErrorResponse(exception: unknown): Response {
  if (isHttpException(exception)) {
    const status: unknown = exception.getStatus();
    const body: unknown = exception.getResponse();
    return Response.json(
      typeof body === "string" ? { statusCode: status, message: body } : body,
      { status: typeof status === "number" ? status : 500 },
    );
  }
  return Response.json(
    { statusCode: 500, message: "Internal server error" },
    { status: 500 },
  );
}
