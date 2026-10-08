import { withCors, type WithCorsConfig } from "@supabase/middleware/cors";

import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server.ts";

import { type EdgeHandler, toEdge } from "../bridges/edge.ts";
import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { flushEvents, unexpectedResponse } from "../server/adapter.ts";
import { withBetterSupabase } from "../server/composite.ts";
import {
  defineResource,
  type ResourceHandler,
  type ResourceRouteOptions,
} from "../server/resource.ts";
import {
  defaultExpose,
  type MiddlewareOptions,
  respond,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";
export { toEdge } from "../bridges/edge.ts";
export type { EdgeExecutionContext, EdgeHandler } from "../bridges/edge.ts";
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
  /**
   * Keeps the invocation alive for event sink sends a handler started, e.g.
   * `EdgeRuntime.waitUntil` on Supabase. On Workers the `ctx` the runtime
   * passes to `fetch` is used when this is unset.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

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

/** `CorsOptions` as `withCors` from `@supabase/middleware/cors` takes them. */
export function corsConfig(cors: CorsOptions): WithCorsConfig {
  return {
    origin:
      cors.origin === undefined || typeof cors.origin === "string"
        ? (cors.origin ?? "*")
        : [...cors.origin],
    allowedHeaders: [...(cors.headers ?? SUPABASE_CORS_HEADERS)],
    methods: [
      ...(cors.methods ?? ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]),
    ],
    ...(cors.maxAge === undefined ? {} : { maxAge: cors.maxAge }),
  };
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
  const withCorsConfig = cors ? corsConfig(cors) : undefined;

  const serve = (
    run: (request: Request, ctx: ServerContext<M, F, E, C, P>) => unknown,
    handlerOptions: MiddlewareOptions,
    /** Answers before auth resolves, e.g. a 404 for an unknown route. */
    early?: (request: Request) => Response | undefined,
  ): EdgeHandler => {
    const authorized = toEdge(
      [withBetterSupabase(server, { ...handlerOptions, expose })],
      async (request, ctx) => {
        const instance = new URL(request.url).pathname;
        try {
          return await respond(() => run(request, ctx.bs), {
            instance,
            expose,
          });
        } catch (cause) {
          return unexpectedResponse(cause, { instance, expose });
        }
      },
    );
    const routed: EdgeHandler = (request, env, executionContext) =>
      Promise.resolve(
        early?.(request) ?? authorized(request, env, executionContext),
      );
    const answer: EdgeHandler = withCorsConfig
      ? toEdge(
          [withCors(withCorsConfig)],
          (request, _ctx, executionContext, env) =>
            routed(request, env, executionContext),
        )
      : routed;
    return async (request, env, executionContext) => {
      const response = await answer(request, env, executionContext);
      flushEvents(
        server,
        options.waitUntil ?? executionContext?.waitUntil.bind(executionContext),
      );
      return response;
    };
  };

  return extendServer<BetterEdge<M, F, E, C, P>>(server, {
    handler(fn, handlerOptions = {}) {
      return serve(fn, handlerOptions);
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
      // Matched from the URL on each call: the bridge buffers a request with a
      // body into a new Request, so the early check and the handler see
      // different objects.
      const match = (request: Request): Route | Response => {
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
        try {
          const key =
            id === undefined || id === "" ? undefined : decodeURIComponent(id);
          return { handler, id: key, instance: pathname };
        } catch {
          return problemResponse(
            dbError("invalid_input", `Malformed id in ${pathname}`),
            { instance: pathname },
          );
        }
      };
      return serve(
        (request, ctx) => {
          const route = match(request);
          if (route instanceof Response) return route;
          return route.handler.handle(request, ctx.db, route.id, {
            instance: route.instance,
            expose,
          });
        },
        resourcesOptions,
        (request) => {
          const route = match(request);
          return route instanceof Response ? route : undefined;
        },
      );
    },
  });
}
