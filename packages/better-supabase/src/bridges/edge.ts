import {
  type AnyEntry,
  bufferRequest,
  type Contributions,
  pipeline,
  seedContext,
} from "@supabase/middleware";

import type { Validated } from "./shared.ts";

/** The platform context Workers pass as the third `fetch` argument. */
export interface EdgeExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
}

/** `Deno.serve` passes `(request, info)`, Workers `fetch` passes `(request, env, ctx)`. */
export type EdgeHandler = (
  request: Request,
  env?: unknown,
  executionContext?: EdgeExecutionContext,
) => Promise<Response>;

/**
 * Runs an entry array around `handler` as a fetch handler for Supabase Edge
 * Functions, Deno, Bun and Workers. The host's second argument seeds the
 * context, so on Workers `getEnv` inside the entries reads the bindings.
 *
 * ```ts
 * Deno.serve(toEdge([withBetterSupabase(server)], async (req, ctx) =>
 *   Response.json(await ctx.db.notes.findMany().orThrow())))
 * ```
 */
export function toEdge<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  handler: (
    request: Request,
    ctx: Contributions<Entries>,
    executionContext: EdgeExecutionContext | undefined,
  ) => Response | Promise<Response>,
): EdgeHandler {
  const EXECUTION = Symbol("toEdge.execution");
  // SAFETY: widening to the constraint; the parameter type already validated the entries.
  const run = pipeline(entries as readonly AnyEntry[], (request, ctx) =>
    Promise.resolve(
      handler(
        request,
        // SAFETY: the pipeline accumulated exactly the entries' contributions onto ctx.
        ctx as Contributions<Entries>,
        // SAFETY: the bridge seeds this symbol with the host's execution context.
        (ctx as { readonly [EXECUTION]?: EdgeExecutionContext })[EXECUTION],
      ),
    ),
  );
  return (request, env, executionContext) =>
    run(request.body ? bufferRequest(request) : request, {
      ...seedContext(env),
      [EXECUTION]: executionContext,
    });
}
