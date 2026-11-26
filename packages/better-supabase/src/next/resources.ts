import type { Authorizer } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { HandleOptions } from "../server/adapter.ts";
import type { ResourceMap } from "../server/resources.ts";
import type { GuardOptions } from "../server/respond.ts";

import { resourceRouter } from "../server/resources.ts";

/** The key `createNext` stores the pieces `createResources` needs under. */
export const RESOURCES_HOST: unique symbol = Symbol.for(
  "better-supabase.next.resources-host",
);

/**
 * What `createNext` hands `createResources`: the instance and one guarded
 * serve.
 */
export interface ResourcesHost<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  Ref,
  Db,
> {
  readonly instance: BetterSupabase<M, D, F, E>;
  readonly authorizer: Authorizer<Ref> | undefined;
  /** Whether problem responses carry error messages. */
  readonly expose: boolean;
  /** Runs `run` as the caller behind the guard, with Problem Details errors. */
  serve(
    request: Request,
    run: (db: Db) => Promise<Response>,
    options: HandleOptions & GuardOptions,
  ): Promise<Response>;
}

export interface NextResourcesOptions extends GuardOptions {
  /** The catch-all route's path, e.g. `/api` for `app/api/[...path]/route.ts`. */
  readonly basePath?: string;
  /**
   * Refresh an expired session cookie and send the new cookies. Off by default
   * because the proxy refreshes everything it matches.
   */
  readonly refresh?: boolean;
}

/** A route handler of the resources' catch-all route. */
export type NextResourceHandler = (request: Request) => Promise<Response>;

/**
 * The exports of `app/api/[...path]/route.ts`: `export const { GET, POST,
 * PATCH, PUT, DELETE } = createResources(bsb)({ ... })`.
 */
export interface NextResourceRoutes {
  readonly GET: NextResourceHandler;
  readonly POST: NextResourceHandler;
  readonly PATCH: NextResourceHandler;
  readonly PUT: NextResourceHandler;
  readonly DELETE: NextResourceHandler;
}

/** One handler for every method; the resource router picks the operation. */
export function resourceRoutes(serve: NextResourceHandler): NextResourceRoutes {
  return { GET: serve, POST: serve, PATCH: serve, PUT: serve, DELETE: serve };
}

/**
 * REST resources for a catch-all route, matching the API model: collections,
 * items and actions, as the caller (RLS), behind the guard in `options`, with
 * Problem Details errors. An unknown path answers 404 before auth resolves. It
 * lives on its own subpath so an app that serves no resources does not ship the
 * router (ADR 1258).
 *
 * ```ts
 * // app/api/[...path]/route.ts
 * export const { GET, POST, PATCH, PUT, DELETE } = createResources(bsb)(
 *   { customers: true },
 *   { basePath: "/api" },
 * );
 * ```
 */
export function createResources<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  Ref,
  Db extends object,
>(bsb: {
  readonly [RESOURCES_HOST]: ResourcesHost<M, D, F, E, Ref, Db>;
}): (
  map: ResourceMap<M, Ref, Db>,
  options?: NextResourcesOptions,
) => NextResourceRoutes {
  const host = bsb[RESOURCES_HOST];

  return (map, options = {}) => {
    const { basePath, ...guardOptions } = options;

    const router = resourceRouter(host.instance, map, {
      ...(basePath === undefined ? {} : { basePath }),
      ...(host.authorizer === undefined ? {} : { authorizer: host.authorizer }),
    });

    return resourceRoutes(async (request) => {
      const route = router.match(request);

      if (route instanceof Response) {
        return route;
      }

      return host.serve(
        request,
        (db) =>
          route.handler.serve(request, db, route.segments, {
            instance: route.instance,
            expose: host.expose,
          }),
        { ...guardOptions, instance: route.instance },
      );
    });
  };
}

/** The resource map a `bsb` accepts, for `satisfies ResourceMapOf<typeof bsb>`. */
export type ResourceMapOf<N> = N extends {
  readonly [RESOURCES_HOST]: ResourcesHost<
    infer M,
    infer _D,
    infer _F,
    infer _E,
    infer Ref,
    infer Db
  >;
}
  ? ResourceMap<M, Ref, Db>
  : never;
