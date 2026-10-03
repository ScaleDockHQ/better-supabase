import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server.ts";

import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import {
  defineResource,
  type ResourceHandler,
  type ResourceRouteOptions,
} from "../server/resource.ts";
import {
  defaultExpose,
  guard,
  type MiddlewareOptions,
  respond,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";
export type { ResourceRouteOptions } from "../server/resource.ts";

export interface CorsOptions {
  /** Allowed origins, or `*`. Defaults to `*`. */
  readonly origin?: string | readonly string[];
  /** Defaults to the headers supabase-js sends. */
  readonly headers?: readonly string[];
  readonly methods?: readonly string[];
  readonly maxAge?: number;
}

export interface EdgeOptions extends ServerOptions {
  /** Answer preflights and add CORS headers. `true` uses Supabase's defaults. */
  readonly cors?: boolean | CorsOptions;
  /** Include error details in problem responses. Defaults to `NODE_ENV === 'development'`. */
  readonly exposeErrors?: boolean;
}

export type EdgeHandler = (request: Request) => Promise<Response>;

export type ResourceMap<M extends AnyModels> = {
  readonly [T in TableKey<M>]?: ResourceRouteOptions<M, T> | true;
};

export interface ResourcesOptions extends MiddlewareOptions {
  /** Path before the resources, e.g. `/api` (Supabase: `/<function-name>`). */
  readonly basePath?: string;
}

export interface BetterEdge<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * A fetch handler (`Deno.serve`, Workers `fetch`) running as the caller.
   * `Result`s become JSON or Problem Details; `undefined` becomes 204.
   */
  handler(
    fn: (request: Request, ctx: ServerContext<M, F, E, C, P>) => unknown,
    options?: MiddlewareOptions,
  ): EdgeHandler;
  /** REST resources matching `createOpenApi`, e.g. `Deno.serve(bs.resources({ customers: true }))`. */
  resources(map: ResourceMap<M>, options?: ResourcesOptions): EdgeHandler;
}

export const SUPABASE_CORS_HEADERS: readonly string[] = [
  "authorization",
  "x-client-info",
  "apikey",
  "content-type",
];

/** The CORS headers for a request's origin; the fixed ones are joined once. */
function corsFor(
  cors: CorsOptions,
): (request: Request) => Record<string, string> | undefined {
  const allowed = cors.origin ?? "*";
  const origins = new Set(typeof allowed === "string" ? [allowed] : allowed);
  const fixed: Record<string, string> = {
    "access-control-allow-headers": (
      cors.headers ?? SUPABASE_CORS_HEADERS
    ).join(", "),
    "access-control-allow-methods": (
      cors.methods ?? ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
    ).join(", "),
    ...(cors.maxAge === undefined
      ? {}
      : { "access-control-max-age": String(cors.maxAge) }),
  };
  const any = { "access-control-allow-origin": "*", ...fixed };
  return (request) => {
    if (allowed === "*") return any;
    const origin = request.headers.get("origin");
    if (!origin || !origins.has(origin)) return;
    return { "access-control-allow-origin": origin, ...fixed, vary: "origin" };
  };
}

function withHeaders(
  response: Response,
  headers: Record<string, string>,
): Response {
  let target = response;
  try {
    for (const [name, value] of Object.entries(headers))
      target.headers.set(name, value);
  } catch {
    target = new Response(response.body, response);
    for (const [name, value] of Object.entries(headers))
      target.headers.set(name, value);
  }
  return target;
}

/** Fetch-handler integration for Supabase Edge Functions, Deno, Bun and Workers. */
export function createEdge<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: EdgeOptions = {},
): BetterEdge<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const cors: CorsOptions | undefined =
    options.cors === true
      ? {}
      : options.cors === false
        ? undefined
        : options.cors;
  const corsHeaders = cors ? corsFor(cors) : undefined;

  const serve = (
    run: (
      request: Request,
      ctx: ServerContext<M, F, E, C, P>,
    ) => Promise<Response>,
    handlerOptions: MiddlewareOptions,
    /** Answers before auth resolves, e.g. a 404 for an unknown route. */
    early?: (request: Request) => Response | undefined,
  ): EdgeHandler => {
    return async (request) => {
      const extra = corsHeaders?.(request);
      if (cors && request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: extra ?? {} });
      }
      const answered = early?.(request);
      if (answered) return extra ? withHeaders(answered, extra) : answered;
      const ctx = await server.context(request, {
        refresh: handlerOptions.refresh ?? false,
      });
      const instance = new URL(request.url).pathname;
      const denied = guard(
        ctx.auth,
        handlerOptions.allow,
        handlerOptions.aal,
        handlerOptions.scopes,
      );
      let response: Response;
      try {
        response = denied
          ? problemResponse(denied, { instance, expose })
          : await run(request, ctx);
      } catch (cause) {
        response = problemResponse(
          dbError(
            "unexpected",
            expose && cause instanceof Error
              ? cause.message
              : "Internal server error",
          ),
          { instance, expose },
        );
      }
      response = ctx.resolution.apply(response);
      return extra ? withHeaders(response, extra) : response;
    };
  };

  return extendServer<BetterEdge<M, F, E, C, P>>(server, {
    handler(fn, handlerOptions = {}) {
      return serve(
        (request, ctx) =>
          respond(() => fn(request, ctx), {
            instance: new URL(request.url).pathname,
            expose,
          }),
        handlerOptions,
      );
    },

    resources(map, resourcesOptions = {}) {
      const base = (resourcesOptions.basePath ?? "").replace(/\/$/, "");
      const handlers = new Map<string, ResourceHandler>();
      for (const [table, resource] of Object.entries(map)) {
        if (!resource) continue;
        // SAFETY: the resources option is keyed by table names of M, and a
        // value that is not true is its options object.
        handlers.set(
          table,
          defineResource(
            betterSupabase,
            table as TableKey<M>,
            resource === true
              ? {}
              : (resource as ResourceRouteOptions<M, TableKey<M>>),
          ),
        );
      }
      interface Route {
        readonly handler: ResourceHandler;
        readonly id: string | undefined;
        readonly instance: string;
      }
      const routes = new WeakMap<Request, Route>();
      const notFound = (request: Request): Response | undefined => {
        const { pathname } = new URL(request.url);
        const rest = pathname.startsWith(`${base}/`)
          ? pathname.slice(base.length + 1)
          : undefined;
        const [table, id, extra] = rest?.split("/") ?? [];
        const handler = table ? handlers.get(table) : undefined;
        if (
          !handler ||
          extra !== undefined ||
          (id !== undefined && !handler.keyParam)
        ) {
          return problemResponse(
            dbError("not_found", `No route for ${pathname}`),
            { instance: pathname },
          );
        }
        let key: string | undefined;
        try {
          key =
            id === undefined || id === "" ? undefined : decodeURIComponent(id);
        } catch {
          return problemResponse(
            dbError("invalid_request", `Malformed id in ${pathname}`),
            { instance: pathname },
          );
        }
        routes.set(request, { handler, id: key, instance: pathname });
        return undefined;
      };
      return serve(
        (request, ctx) => {
          // SAFETY: serve() only runs this after notFound() matched the request.
          const { handler, id, instance } = routes.get(request)!;
          return handler.handle(request, ctx.db, id, { instance, expose });
        },
        resourcesOptions,
        notFound,
      );
    },
  });
}
