import type { GuardOptions } from "../server/respond.ts";

export interface NextResourcesOptions extends GuardOptions {
  /** The catch-all route's path, e.g. `/api` for `app/api/[...path]/route.ts`. */
  readonly basePath?: string;
  /**
   * Refresh an expired session cookie and send the new cookies. Off by
   * default because the proxy refreshes everything it matches.
   */
  readonly refresh?: boolean;
}

/** A route handler of the resources' catch-all route. */
export type NextResourceHandler = (request: Request) => Promise<Response>;

/**
 * The exports of `app/api/[...path]/route.ts`:
 * `export const { GET, POST, PATCH, PUT, DELETE } = bs.resources({ ... })`.
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
