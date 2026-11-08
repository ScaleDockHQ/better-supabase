import type { DbError } from "../core/errors.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterServer, ServerKeys } from "./server-types.ts";

import { problemResponse } from "../core/problem.ts";
import { flushEvents } from "./adapter.ts";
import { defaultExpose } from "./respond.ts";
import { extendServer } from "./server.ts";

export interface AdapterBaseOptions {
  /**
   * Include error messages in problem responses. Defaults to `NODE_ENV ===
   * 'development'`.
   */
  readonly exposeErrors?: boolean;
  /** Where pending event sink sends go; adapters may find one on the platform. */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

export interface AdapterBase {
  /** Whether problem responses carry the error message. */
  readonly expose: boolean;
  /**
   * Hands pending event sink sends to `waitUntil`, the option's or the one the
   * adapter found on the platform; call it in a `finally`.
   */
  flush(platformWaitUntil?: (promise: Promise<unknown>) => void): void;
  /** The Problem Details response for a refused caller. */
  refuse(error: DbError, request: Request): Response;
  /** The adapter's server: the core server plus the adapter's own methods. */
  extend<R extends object>(extra: Omit<R, ServerKeys>): R;
}

/**
 * What every framework adapter shares: the `exposeErrors` default, event
 * flushing, the refusal response and server extension. An adapter holds only
 * its framework glue on top.
 */
export function adapterBase(
  server: Pick<BetterServer<AnyModels, AnyFunctions, unknown>, "events">,
  options: AdapterBaseOptions = {},
): AdapterBase {
  const expose = options.exposeErrors ?? defaultExpose();

  return {
    expose,
    flush: (platformWaitUntil) => {
      flushEvents(server, options.waitUntil ?? platformWaitUntil);
    },
    refuse: (error, request) =>
      problemResponse(error, {
        instance: new URL(request.url).pathname,
        expose,
      }),
    extend: (extra) => extendServer(server, extra),
  };
}
