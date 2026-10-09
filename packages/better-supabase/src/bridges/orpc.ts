import {
  type AnyEntry,
  bufferRequest,
  type Contributions,
  pipeline,
  seedContext,
} from "@supabase/middleware";

import type { Validated } from "./shared.ts";

/** The part of an oRPC fetch handler (`RPCHandler`, `OpenAPIHandler`) a bridge calls. */
export interface OrpcHandlerLike<Context> {
  handle(
    request: Request,
    options: {
      readonly prefix?: `/${string}`;
      readonly context: Context;
    },
  ): Promise<{
    readonly matched: boolean;
    readonly response?: Response | undefined;
  }>;
}

export interface ToOrpcOptions {
  /** Path prefix the router is mounted under, e.g. `/rpc`. */
  readonly prefix?: `/${string}`;
}

/**
 * Runs an entry array around an oRPC fetch handler. The procedures' initial
 * context is `{ request }` plus every contributed key, and the response
 * passes back through the entries, so refreshed cookies and response-phase
 * headers reach it. A request no procedure matched answers 404.
 *
 * ```ts
 * const os = implement(contract).$context<{ request: Request; db: Db }>()
 * export default { fetch: toOrpc([withBetterSupabase(server)], new RPCHandler(router), { prefix: '/rpc' }) }
 * ```
 */
export function toOrpc<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  handler: OrpcHandlerLike<
    { readonly request: Request } & Contributions<Entries>
  >,
  options: ToOrpcOptions = {},
): (request: Request, env?: unknown) => Promise<Response> {
  // SAFETY: widening to the constraint; the parameter type already validated the entries.
  const run = pipeline(entries as readonly AnyEntry[], async (request, ctx) => {
    const { response } = await handler.handle(request, {
      ...(options.prefix ? { prefix: options.prefix } : {}),
      // SAFETY: the pipeline accumulated exactly the entries' contributions onto ctx.
      context: { ...(ctx as Contributions<Entries>), request },
    });
    return response ?? new Response("Not found", { status: 404 });
  });
  return (request, env) =>
    run(request.body ? bufferRequest(request) : request, seedContext(env));
}
