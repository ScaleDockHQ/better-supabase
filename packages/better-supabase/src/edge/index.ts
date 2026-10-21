import { withCors } from "@supabase/middleware/cors";

import type { AuthSession } from "../auth/view.ts";
import type { AnyAuthorizer, PermissionRef } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server-types.ts";

import { type EdgeHandler, toEdge } from "../bridges/edge.ts";
import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { err } from "../core/result.ts";
import { withFlush, unexpectedResponse } from "../server/adapter.ts";
import { withBetterSupabase } from "../server/composite.ts";
import {
  type CorsOptions,
  corsConfig,
  SUPABASE_CORS_HEADERS,
} from "../server/cors.ts";
import { withExtra } from "../server/extra.ts";
import { EVERY_CALLER } from "../server/framework.ts";
import {
  type BlockRequireOptions,
  requireCaller,
  type ResourceLoaderContext,
} from "../server/kit.ts";
import { type ResourceMap, resourceRouter } from "../server/resources.ts";
import {
  defaultExpose,
  type MiddlewareOptions,
  respond,
} from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import { compileRoutes, matchRoute, type RouteMatch } from "./routes.ts";

export type { GuardOptions, MiddlewareOptions } from "../server/respond.ts";

export { toEdge } from "../bridges/edge.ts";

export type { EdgeExecutionContext, EdgeHandler } from "../bridges/edge.ts";

export type {
  ActionArgs,
  ResourceAction,
  ResourceContext,
  ResourceHooks,
  ResourceRouteOptions,
} from "../server/resource-types.ts";

export { defineAction } from "../server/resource-execute.ts";

export type { ResourceMap } from "../server/resources.ts";

export type { BlockRequireOptions } from "../server/kit.ts";

export { defineFunction } from "./function.ts";

export type {
  ContractOf,
  FunctionContract,
  FunctionDefinition,
  TypedFunction,
} from "./function.ts";

export interface EdgeOptions extends ServerOptions {
  /** Answer preflights and add CORS headers. `true` uses Supabase's defaults. */
  readonly cors?: boolean | CorsOptions;
  /**
   * Include error details in problem responses. Defaults to `NODE_ENV ===
   * 'development'`.
   */
  readonly exposeErrors?: boolean;
  /**
   * Keeps the invocation alive for event sink sends a handler started, e.g.
   * `EdgeRuntime.waitUntil` on Supabase. On Workers the `ctx` the runtime
   * passes to `fetch` is used when this is unset.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

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
 * The params a route key declares: one per `:name` segment, and `*` for a final
 * wildcard. `RouteParams<"GET /orgs/:org/files/*">` is `{ org: string; "*":
 * string }`.
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
  B = unknown,
> = (
  request: Request,
  ctx: ServerContext<M, F, E, C, P, B> & {
    readonly params: Params;
    readonly session: AuthSession<C, P>;
    readonly tenant: string | undefined;
  },
) => unknown;

/**
 * A route with its own guard: `allow`, `aal`, `scopes`, `requireTenant`,
 * `authorize`.
 */
export interface EdgeRoute<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Params = Readonly<Record<string, string>>,
  B = unknown,
> extends BlockRequireOptions<
  C,
  P,
  boolean,
  unknown,
  ServerContext<M, F, E, C, P, B> & ResourceLoaderContext<C, P>
> {
  readonly handler: EdgeRouteHandler<M, F, E, C, P, Params, B>;
}

/**
 * Routes by `"METHOD /path"` (or `"/path"` for every method). `:name` segments
 * are params, a final `*` matches the rest of the path.
 */
export type EdgeRoutes<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> = Readonly<
  Record<
    string,
    | EdgeRouteHandler<M, F, E, C, P, Readonly<Record<string, string>>, B>
    | EdgeRoute<M, F, E, C, P, Readonly<Record<string, string>>, B>
  >
>;

export interface BetterEdge<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
  /**
   * A fetch handler (`Deno.serve`, Workers `fetch`) running as the caller.
   * `Result`s become JSON or Problem Details; `undefined` becomes 204.
   */
  handler(
    fn: (request: Request, ctx: ServerContext<M, F, E, C, P, B>) => unknown,
    options?: MiddlewareOptions,
  ): EdgeHandler;
  /**
   * A router: each route runs as the caller, behind the shared guard in
   * `options` and its own. An unknown path answers 404 and a known path with
   * another method 405, both before auth resolves. `ctx.params` is typed from
   * the key: `"GET /customers/:id"` gets `params.id`.
   *
   * ```ts
   * Deno.serve(
   *   bs.routes(
   *     {
   *       "GET /customers": (req, ctx) => ctx.db.customers.findMany(),
   *       "GET /customers/:id": (req, ctx) =>
   *         ctx.db.customers.find(ctx.params.id),
   *       "POST /invites": {
   *         requireTenant: true,
   *         handler: (req, ctx) => invite(req, ctx),
   *       },
   *     },
   *     { basePath: "/api" },
   *   ),
   * );
   * ```
   */
  routes<K extends string>(
    routes: {
      readonly [Key in K]:
        | EdgeRouteHandler<M, F, E, C, P, RouteParams<Key>, B>
        | EdgeRoute<M, F, E, C, P, RouteParams<Key>, B>;
    },
    options?: ResourcesOptions,
  ): EdgeHandler;
  /**
   * REST resources matching the API model, e.g. `Deno.serve(bs.resources({
   * customers: true }))`: collection, item and action paths. An unknown path
   * answers 404 before auth resolves.
   */
  resources(
    map: ResourceMap<M, Ref, ServerContext<M, F, E, C, P, B>["db"]>,
    options?: ResourcesOptions,
  ): EdgeHandler;
}

/** Fetch-handler integration for Supabase Edge Functions, Deno, Bun and Workers. */
export function createEdge<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  A extends AnyAuthorizer | undefined = undefined,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: EdgeOptions & { readonly authorizer?: A } = {},
): BetterEdge<M, F, E, C, P, PermissionRef<A>, B> {
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
      ctx: ServerContext<M, F, E, C, P, B>,
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

    return async (request, env, executionContext) =>
      withFlush(
        server,
        options.waitUntil ?? executionContext?.waitUntil.bind(executionContext),
        () => answer(request, env, executionContext),
      );
  };

  return extendServer<BetterEdge<M, F, E, C, P, PermissionRef<A>, B>>(server, {
    handler(fn, handlerOptions = {}) {
      return serve(fn, handlerOptions);
    },

    routes(routes, routesOptions = {}) {
      const base = (routesOptions.basePath ?? "").replace(/\/$/, "");
      const compiled = compileRoutes<M, F, E, C, P, B>(routes);
      const { allow, aal, scopes, ...middlewareOptions } = routesOptions;

      const shared = {
        ...(allow === undefined ? {} : { allow }),
        ...(aal === undefined ? {} : { aal }),
        ...(scopes === undefined ? {} : { scopes }),
      };

      const find = (
        request: Request,
      ): RouteMatch<M, F, E, C, P, B> | Response => {
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
            { instance: pathname },
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

          if (found instanceof Response) {
            return found;
          }

          const { route, params } = found;

          const caller = await requireCaller(
            ctx.auth,
            { ...shared, ...route.options },
            tenant,
            options.authorizer,
            ctx,
          );

          if ("kind" in caller) {
            return err(caller);
          }

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
      const { basePath, ...middlewareOptions } = resourcesOptions;

      const router = resourceRouter(betterSupabase, map, {
        ...(basePath === undefined ? {} : { basePath }),
        ...(options.authorizer === undefined
          ? {}
          : { authorizer: options.authorizer }),
      });

      return serve(
        (request, ctx) => {
          // Matched again here: the bridge buffers a request with a body into
          // a new Request, so the early check and the handler see different
          // objects.
          const route = router.match(request);

          if (route instanceof Response) {
            return route;
          }

          return route.handler.serve(request, ctx.db, route.segments, {
            instance: route.instance,
            expose,
          });
        },
        middlewareOptions,
        (request) => {
          const route = router.match(request);

          return route instanceof Response ? route : undefined;
        },
      );
    },
  });
}

export { type CorsOptions, corsConfig, SUPABASE_CORS_HEADERS };
