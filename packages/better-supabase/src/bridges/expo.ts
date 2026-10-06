import {
  type AnyEntry,
  bufferRequest,
  type Contributions,
  pipeline,
  seedContext,
} from "@supabase/middleware";

import { handoffOf, type Validated } from "./shared.ts";

/** Route parameters from the file name (`[id]`, `[...slug]`). */
export type ExpoParams = Record<string, string | string[]>;

const PARAMS = Symbol("toExpo.params");

/**
 * Runs an entry array around an Expo Router API route handler
 * (`export const GET = toExpo([...], handler)`). Short-circuit responses
 * (a 401 from the guard, a CORS preflight) answer before the handler runs,
 * and the handler's response passes back through the entries.
 */
export function toExpo<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  handler: (
    request: Request,
    ctx: Contributions<Entries>,
    params: ExpoParams,
  ) => Response | Promise<Response>,
): (request: Request, params?: ExpoParams) => Promise<Response> {
  // SAFETY: widening to the constraint; the parameter type already validated the entries.
  const run = pipeline(entries as readonly AnyEntry[], (request, ctx) =>
    Promise.resolve(
      handler(
        request,
        // SAFETY: the pipeline accumulated exactly the entries' contributions onto ctx.
        ctx as Contributions<Entries>,
        handoffOf<ExpoParams>(ctx, PARAMS),
      ),
    ),
  );
  return (request, params = {}) =>
    run(request.body ? bufferRequest(request) : request, {
      ...seedContext(),
      [PARAMS]: params,
    });
}
