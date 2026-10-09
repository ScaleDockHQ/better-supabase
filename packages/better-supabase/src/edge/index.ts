import { withCors, type WithCorsConfig } from "@supabase/middleware/cors";

import type { AuthSession } from "../auth/view.ts";
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
import { err } from "../core/result.ts";
import { flushEvents, unexpectedResponse } from "../server/adapter.ts";
import { withBetterSupabase } from "../server/composite.ts";
import { EVERY_CALLER } from "../server/framework.ts";
import { type KitRequireOptions, requireCaller } from "../server/kit.ts";
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
import { createServer, extendServer, withExtra } from "../server/server.ts";
import { compileRoutes, matchRoute, type RouteMatch } from "./routes.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";
export { toEdge } from "../bridges/edge.ts";
export type { EdgeExecutionContext, EdgeHandler } from "../bridges/edge.ts";
export type { ResourceRouteOptions } from "../server/resource.ts";
export type { KitRequireOptions } from "../server/kit.ts";

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

type ParamNames<K extends string> =
  K extends `${string}:${infer Name}/${infer Rest}`
    ? Name | ParamNames<Rest>
    : K extends `${string}:${infer Name}`
      ? Name
      : never;

/**
 * The params a route key declares: one per `:name` segment, and `*` for a
 * final wildcard. `RouteParams<"GET /orgs/:org/files/*">` is
 * `{ org: string; "*": string }`.
 */
export type RouteParams<K extends string> = {
  readonly [
    N in ParamNames<K> | (K extends `${string}/*` ? "*" : never)
  ]: string;
};

/** A route handler: the request, the caller's context and the path params. */
export type EdgeRouteHandler<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Params = Readonly<Record<string, string>>,
> = (
  request: Request,
  ctx: ServerContext<M, F, E, C, P> & {
    readonly params: Params;
    readonly session: AuthSession<C, P>;
    readonly tenant: string | undefined;
  },
) => unknown;

/** A route with its own guard: `allow`, `aal`, `scopes`, `requireTenant`, `authorize`. */
export interface EdgeRoute<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Params = Readonly<Record<string, string>>,
> extends KitRequireOptions<C, P> {
  readonly handler: EdgeRouteHandler<M, F, E, C, P, Params>;
}

/**
 * Routes by `"METHOD /path"` (or `"/path"` for every method). `:name`
 * segments are params, a final `*` matches the rest of the path.
 */
export type EdgeRoutes<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> = Readonly<
  Record<string, EdgeRouteHandler<M, F, E, C, P> | EdgeRoute<M, F, E, C, P>>
>;

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
  /**
   * A router: each route runs as the caller, behind the shared guard in
   * `options` and its own. An unknown path answers 404 and a known path
   * with another method 405, both before auth resolves. `ctx.params` is
   * typed from the key: `"GET /customers/:id"` gets `params.id`.
   *
   * ```ts
   * Deno.serve(bs.routes({
   *   'GET /customers': (req, ctx) => ctx.db.customers.findMany(),
   *   'GET /customers/:id': (req, ctx) => ctx.db.customers.find(ctx.params.id),
   *   'POST /invites': { requireTenant: true, handler: (req, ctx) => invite(req, ctx) },
   * }, { basePath: '/api' }))
   * ```
   */
  routes<K extends string>(
    routes: {
      readonly [Key in K]:
        | EdgeRouteHandler<M, F, E, C, P, RouteParams<Key>>
        | EdgeRoute<M, F, E, C, P, RouteParams<Key>>;
    },
    options?: ResourcesOptions,
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
    run: (
      request: Request,
      ctx: ServerContext<M, F, E, C, P>,
      tenant: string | undefined,
    ) => unknown,
    handlerOptions: MiddlewareOptions,
    /** Answers before auth resolves, e.g. a 404 for an unknown route. */
    early?: (request: Request) => Response | undefined,
  ): EdgeHandler => {
    const authorized = toEdge(
      [withBetterSupabase(server, { ...handlerOptions, expose })],
      async (request, ctx) => {
        const instance = new URL(request.url).pathname;
        try {
          return await respond(() => run(request, ctx.bs, ctx.tenant), {
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

    routes(routes, routesOptions = {}) {
      const base = (routesOptions.basePath ?? "").replace(/\/$/, "");
      const compiled = compileRoutes<M, F, E, C, P>(routes);
      const { allow, aal, scopes, ...middlewareOptions } = routesOptions;
      const shared = {
        ...(allow === undefined ? {} : { allow }),
        ...(aal === undefined ? {} : { aal }),
        ...(scopes === undefined ? {} : { scopes }),
      };
      const find = (request: Request): RouteMatch<M, F, E, C, P> | Response => {
        const { pathname } = new URL(request.url);
        const path =
          base === ""
            ? pathname
            : pathname === base || pathname.startsWith(`${base}/`)
              ? pathname.slice(base.length) || "/"
              : undefined;
        const found =
          path === undefined
            ? undefined
            : matchRoute(compiled, request.method, path);
        if (found === undefined || found === "none") {
          return problemResponse(
            dbError("not_found", `No route for ${pathname}`),
            {
              instance: pathname,
            },
          );
        }
        if (!("route" in found)) {
          return Response.json(
            {
              type: "about:blank",
              title: "Method Not Allowed",
              status: 405,
              detail: `${request.method} is not allowed on ${pathname}`,
              instance: pathname,
            },
            {
              status: 405,
              headers: {
                allow: found.join(", "),
                "content-type": "application/problem+json",
              },
            },
          );
        }
        return found;
      };
      return serve(
        async (request, ctx, tenant) => {
          const found = find(request);
          if (found instanceof Response) return found;
          const { route, params } = found;
          const caller = await requireCaller(
            ctx.auth,
            { ...shared, ...route.options },
            tenant,
          );
          if ("kind" in caller) return err(caller);
          return route.handler(
            request,
            withExtra(ctx, {
              // SAFETY: matchRoute sets every `:name` segment of the route's
              // key, and `*` for a final wildcard: the params its handler names.
              params: params as never,
              session: caller.session,
              tenant,
            }),
          );
        },
        { ...middlewareOptions, allow: EVERY_CALLER },
        (request) => {
          const found = find(request);
          return found instanceof Response ? found : undefined;
        },
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
