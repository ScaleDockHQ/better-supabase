import type { Authorizer } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type {
  ResourceHandler,
  ResourceRouteOptions,
} from "./resource-types.ts";

import { dbError } from "../core/errors.ts";
import { problemResponse } from "../core/problem.ts";
import { actionFits } from "./resource-http.ts";
import { defineResource } from "./resource.ts";

/** Resources by table name; `true` serves a table with the defaults. */
export type ResourceMap<M extends AnyModels, Ref = string, DbT = unknown> = {
  readonly [T in TableKey<M>]?: ResourceRouteOptions<M, T, Ref, DbT> | true;
};

/** A request matched to a resource: the handler and the path below it. */
export interface ResourceRoute<Ref = string> {
  readonly handler: ResourceHandler<Ref>;
  readonly segments: readonly string[];
  readonly instance: string;
}

export interface ResourceRouter<Ref = string> {
  readonly handlers: readonly ResourceHandler<Ref>[];
  /**
   * The resource a request is for, or the 404 (or 400 for a malformed path)
   * to send before auth resolves. Matched from the URL, so it can run twice
   * for one request.
   */
  match(request: Request): ResourceRoute<Ref> | Response;
}

function split(path: string): readonly string[] {
  return path.split("/").filter((segment) => segment !== "");
}

/** Whether a resource serves this path below it, with some method. */
function serves(
  handler: ResourceHandler<unknown>,
  segments: readonly string[],
): boolean {
  if (segments.length === 0) {
    return true;
  }

  if (handler.plan.actions.some((action) => actionFits(action, segments))) {
    return true;
  }

  return segments.length === 1 && handler.keyParam !== undefined;
}

/**
 * Matches the still encoded path segments below one resource: the decoded
 * segments, or the 404 for a path it doesn't serve (400 for a malformed
 * segment). `instance` is the request path for the problem response.
 */
export function matchResource<Ref>(
  handler: ResourceHandler<Ref>,
  raw: readonly string[],
  instance: string,
): ResourceRoute<Ref> | Response {
  let segments: readonly string[];

  try {
    segments = raw.map((segment) => decodeURIComponent(segment));
  } catch {
    return problemResponse(
      dbError("invalid_input", `Malformed id in ${instance}`),
      { instance },
    );
  }

  if (!serves(handler, segments)) {
    return problemResponse(dbError("not_found", `No route for ${instance}`), {
      instance,
    });
  }

  return { handler, segments, instance };
}

/**
 * Routes `basePath` plus each resource's path (`/<table>` unless `path` is
 * set) to its handler. Shared by the edge and Next.js resource routers.
 */
export function resourceRouter<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  Ref = string,
  DbT = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  map: ResourceMap<M, NoInfer<Ref>, DbT>,
  options: {
    readonly basePath?: string;
    readonly authorizer?: Authorizer<Ref>;
  } = {},
): ResourceRouter<Ref> {
  const base = split(options.basePath ?? "");

  const routes: {
    readonly prefix: readonly string[];
    readonly handler: ResourceHandler<Ref>;
  }[] = [];

  for (const [table, resource] of Object.entries(map)) {
    if (!resource) {
      continue;
    }

    // SAFETY: the map is keyed by table names of M, and a value that is not
    // true is that table's options object.
    const routeOptions = (
      resource === true ? {} : resource
    ) as ResourceRouteOptions<M, TableKey<M>, Ref, DbT>;

    const handler = defineResource<M, D, F, E, TableKey<M>, Ref, DbT>(
      betterSupabase,
      // SAFETY: Object.entries widens the keys of a map keyed by TableKey<M>.
      table as TableKey<M>,
      routeOptions,
      options.authorizer,
    );

    routes.push({
      prefix: split(handler.plan.description.path ?? `/${table}`),
      handler,
    });
  }

  // The longest prefix wins, so `/billing/invoices` beats `/billing`.
  routes.sort((a, b) => b.prefix.length - a.prefix.length);

  return {
    handlers: routes.map((route) => route.handler),
    match(request) {
      const { pathname } = new URL(request.url);

      const notFound = (): Response =>
        problemResponse(dbError("not_found", `No route for ${pathname}`), {
          instance: pathname,
        });

      const raw = split(pathname);

      if (!base.every((segment, index) => raw[index] === segment)) {
        return notFound();
      }

      const rest = raw.slice(base.length);

      const route = routes.find(
        ({ prefix }) =>
          prefix.length <= rest.length &&
          prefix.every((segment, index) => rest[index] === segment),
      );

      if (!route) {
        return notFound();
      }

      return matchResource(
        route.handler,
        rest.slice(route.prefix.length),
        pathname,
      );
    },
  };
}
