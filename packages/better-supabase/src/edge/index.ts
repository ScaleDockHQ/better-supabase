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
  type GuardOptions,
  respond,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions } from "../server/respond.ts";
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

export interface HandlerOptions extends GuardOptions {
  /** Refresh an expired cookie session and send the new cookies. */
  readonly refresh?: boolean;
}

export type EdgeHandler = (request: Request) => Promise<Response>;

export type ResourceMap<M extends AnyModels> = {
  readonly [T in TableKey<M>]?: ResourceRouteOptions<M, T> | true;
};

export interface ResourcesOptions extends HandlerOptions {
  /** Path before the resources, e.g. `/api` (Supabase: `/<function-name>`). */
  readonly basePath?: string;
}

export interface BetterEdge<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
> extends BetterServer<M, F, E> {
  /**
   * A fetch handler (`Deno.serve`, Workers `fetch`) running as the caller.
   * `Result`s become JSON or Problem Details; `undefined` becomes 204.
   */
  handler(
    fn: (request: Request, ctx: ServerContext<M, F, E>) => unknown,
    options?: HandlerOptions,
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

function corsHeaders(
  request: Request,
  cors: CorsOptions,
): Record<string, string> | undefined {
  const origin = request.headers.get("origin");
  const allowed = cors.origin ?? "*";
  let value: string | undefined;
  if (allowed === "*") value = "*";
  else if (
    origin &&
    (typeof allowed === "string" ? [allowed] : allowed).includes(origin)
  )
    value = origin;
  if (!value) return undefined;
  return {
    "access-control-allow-origin": value,
    "access-control-allow-headers": (
      cors.headers ?? SUPABASE_CORS_HEADERS
    ).join(", "),
    "access-control-allow-methods": (
      cors.methods ?? ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
    ).join(", "),
    ...(cors.maxAge === undefined
      ? {}
      : { "access-control-max-age": String(cors.maxAge) }),
    ...(value === "*" ? {} : { vary: "origin" }),
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
export function createEdge<M extends AnyModels, D, F extends AnyFunctions, E>(
  sb: BetterSupabase<M, D, F, E>,
  options: EdgeOptions = {},
): BetterEdge<M, F, E> {
  const server = createServer(sb, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const cors: CorsOptions | undefined =
    options.cors === true
      ? {}
      : options.cors === false
        ? undefined
        : options.cors;

  const serve = (
    run: (request: Request, ctx: ServerContext<M, F, E>) => Promise<Response>,
    handlerOptions: HandlerOptions,
  ): EdgeHandler => {
    return async (request) => {
      const extra = cors ? corsHeaders(request, cors) : undefined;
      if (cors && request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: extra ?? {} });
      }
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

  return extendServer<BetterEdge<M, F, E>>(server, {
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
            sb,
            table as TableKey<M>,
            resource === true
              ? {}
              : (resource as ResourceRouteOptions<M, TableKey<M>>),
          ),
        );
      }
      return serve(async (request, ctx) => {
        const { pathname } = new URL(request.url);
        const instance = pathname;
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
            {
              instance,
            },
          );
        }
        return handler.handle(
          request,
          ctx.db,
          id === undefined || id === "" ? undefined : decodeURIComponent(id),
          { instance, expose },
        );
      }, resourcesOptions);
    },
  });
}
