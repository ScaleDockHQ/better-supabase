import type { AnyEntry, Contributions } from "@supabase/middleware";

import { around, bufferInPlace, type Validated } from "./shared.ts";

/** The `response` of a request middleware's `next()` result; server function results have none. */
function responseOf(result: object): Response | undefined {
  return "response" in result && result.response instanceof Response
    ? result.response
    : undefined;
}

/** The arguments TanStack Start passes to a `.server()` callback. */
export interface TanStackStartServerArgs<Context, Result> {
  readonly request: Request;
  readonly next: (options: { readonly context: Context }) => Promise<Result>;
}

export interface ToTanStackStartOptions {
  /** The host's env object for `getEnv`, read per request. */
  readonly env?: (request: Request) => unknown;
}

/**
 * Runs an entry array as the `.server()` callback of a TanStack Start
 * middleware. Every contributed key lands on `context`. On request
 * middleware the response passes back through the entries, so refreshed
 * session cookies reach it; on server function middleware the context still
 * flows, and a short circuit (a 401 from the guard) is thrown as a
 * `Response`, which TanStack Start sends.
 *
 * ```ts title="src/start.ts"
 * const supabase = createMiddleware().server(toTanStackStart([withBetterSupabase(server)]))
 * export const startInstance = createStart(() => ({ requestMiddleware: [supabase] }))
 * ```
 */
export function toTanStackStart<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  options: ToTanStackStartOptions = {},
): <Result extends object>(
  args: TanStackStartServerArgs<Contributions<Entries>, Result>,
) => Promise<Result> {
  const run = around(entries);
  return async <Result extends object>({
    request,
    next,
  }: TanStackStartServerArgs<
    Contributions<Entries>,
    Result
  >): Promise<Result> => {
    bufferInPlace(request);
    const downstream: { result?: Result } = {};
    const env = options.env?.(request);
    const response = await run(request, env, async (contributions) => {
      const result = await next({
        // SAFETY: around() hands over exactly the entries' contributions.
        context: contributions as Contributions<Entries>,
      });
      downstream.result = result;
      return responseOf(result) ?? new Response(null, { status: 204 });
    });
    const { result } = downstream;
    if (result === undefined) {
      // oxlint-disable-next-line typescript/only-throw-error -- TanStack Start sends a thrown Response as the answer, which is how middleware short-circuits.
      throw response;
    }
    if (responseOf(result) === undefined) return result;
    return { ...result, response };
  };
}
