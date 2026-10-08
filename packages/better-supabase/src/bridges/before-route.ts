import type { AnyEntry } from "@supabase/middleware";

import { around } from "./shared.ts";

/** What the entries decided before the framework's route. */
export type BeforeRoute =
  | {
      readonly reached: true;
      /** Everything the entries contributed (`db`, `bs`, ...). */
      readonly contributions: Record<string, unknown>;
      /** The headers and cookies the entries set, for the framework's response. */
      readonly headers: Headers;
    }
  | {
      readonly reached: false;
      /** The entries' short circuit: a 401, a CORS preflight, a redirect. */
      readonly response: Response;
    };

/**
 * Runs the entries ahead of a framework that owns the route and the
 * response (Express, Fastify, Koa, Nitro 2, SolidStart, NestJS). A short
 * circuit is the answer; otherwise the framework copies the headers and
 * hands the contributions to the route. Response-phase entries see an
 * empty response, so `withDbStats` and `withServerTiming` report nothing here.
 */
export function beforeRoute(
  entries: readonly AnyEntry[],
): (request: Request, env: unknown) => Promise<BeforeRoute> {
  const run = around(entries);
  return async (request, env) => {
    let contributions: Record<string, unknown> | undefined;
    const marker = new Response(null);
    const response = await run(request, env, (handed) => {
      contributions = handed;
      return Promise.resolve(marker);
    });
    return contributions === undefined
      ? { reached: false, response }
      : { reached: true, contributions, headers: response.headers };
  };
}
