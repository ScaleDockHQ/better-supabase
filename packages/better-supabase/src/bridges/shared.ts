import {
  type AnyEntry,
  pipeline,
  seedContext,
  type ValidateEntries,
} from "@supabase/middleware";

/**
 * `unknown` when the entries compose, so a parameter typed
 * `Entries & Validated<Entries>` stays `Entries`. Otherwise the engine's
 * error string, and the intersection fails the call with the
 * `middleware-conflict` or `middleware-prereq` message.
 */
export type Validated<Entries extends readonly AnyEntry[]> = [
  ValidateEntries<Entries>,
] extends [true]
  ? unknown
  : ValidateEntries<Entries>;

/** The string keys of a pipeline context: every contribution, without the seed's symbols. */
function contributionsOf(ctx: object): Record<string, unknown> {
  const contributions: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(ctx)) contributions[key] = value;
  return contributions;
}

/** The per-request value a bridge seeds under `key`. */
export function handoffOf<T>(ctx: object, key: symbol): T {
  // SAFETY: every bridge seeds its own symbol with its own handoff type before the fold runs.
  return (ctx as { readonly [key: symbol]: T })[key] as T;
}

/**
 * Makes the body of `request` readable more than once, in place: the first
 * reader drains the stream into a cache and later readers are served from
 * it, so an entry and the route both see the body. For frameworks that hand
 * the route the same `Request` the middleware saw (TanStack Start,
 * SvelteKit, React Router), where `bufferRequest`'s wrapped copy can't go.
 */
export function bufferInPlace(request: Request): void {
  if (!request.body || request.bodyUsed) return;
  const readOnce = request.arrayBuffer.bind(request);
  let buffer: Promise<ArrayBuffer> | undefined;
  const arrayBuffer = (): Promise<ArrayBuffer> => (buffer ??= readOnce());
  const text = async (): Promise<string> =>
    new TextDecoder().decode(await arrayBuffer());
  const readers = {
    arrayBuffer,
    text,
    json: async (): Promise<unknown> => JSON.parse(await text()),
    bytes: async (): Promise<Uint8Array> => new Uint8Array(await arrayBuffer()),
    blob: async (): Promise<Blob> => new Blob([await arrayBuffer()]),
    formData: async (): ReturnType<Request["formData"]> =>
      new Response(await arrayBuffer(), {
        headers: request.headers,
      }).formData(),
    clone: (): Request => request,
  };
  for (const [name, value] of Object.entries(readers)) {
    Object.defineProperty(request, name, { value, configurable: true });
  }
}

/** Runs the rest of the framework's chain with the contributions and returns its response. */
export type Downstream = (
  contributions: Record<string, unknown>,
) => Promise<Response>;

/** Folds `entries` once into a function that runs them around a framework's `next`. */
export type Around = (
  request: Request,
  platform: unknown,
  downstream: Downstream,
) => Promise<Response>;

const DOWNSTREAM = Symbol("bridge.downstream");

/**
 * The shared shape of the upstream bridges: the pipeline folds once, each
 * request seeds the framework's `next` under a symbol, and the terminal
 * hands it the contributions, so response-phase entries see the
 * framework's response. `platform` is the host's env object, if any, which
 * `getEnv` reads first.
 */
export function around(entries: readonly AnyEntry[]): Around {
  const run = pipeline(entries, (_request, ctx) =>
    handoffOf<Downstream>(ctx, DOWNSTREAM)(contributionsOf(ctx)),
  );
  return (request, platform, downstream) =>
    run(request, { ...seedContext(platform), [DOWNSTREAM]: downstream });
}

/** The status and headers a framework collected for a handler that returned a plain value. */
export interface HandlerResponseInit {
  readonly status?: number | undefined;
  readonly statusText?: string | undefined;
  readonly headers?: ConstructorParameters<typeof Headers>[0] | undefined;
}

/**
 * A framework handler's value as a `Response`: responses as is, `undefined`
 * as 204, other values as JSON. `init` carries the status and headers the
 * handler set on the framework's response object.
 */
export function toResponse(
  value: unknown,
  init: HandlerResponseInit = {},
): Response {
  if (value instanceof Response) return value;
  const options = {
    ...(init.status === undefined ? {} : { status: init.status }),
    ...(init.statusText === undefined ? {} : { statusText: init.statusText }),
    ...(init.headers === undefined ? {} : { headers: init.headers }),
  };
  if (value === undefined || value === null)
    return new Response(null, { status: 204, ...options });
  if (typeof value === "string") return new Response(value, options);
  return Response.json(value, options);
}
