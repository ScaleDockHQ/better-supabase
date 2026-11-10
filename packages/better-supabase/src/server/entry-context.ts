import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { AuthzVersionCache } from "../core/authorizer.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  BetterServer,
  ContextOptions,
  ServerContext,
} from "./server-types.ts";

import { cronRoute } from "../core/cron-route.ts";

/** The key name of the service caller `entryContext` and `cronHandler` use. */
export const CRON_KEY_NAME = "cron";

/**
 * Where a context comes from. Each kind names what the entry point already has,
 * so a route, a proxy, a queue consumer and a cron job all build their context
 * the same way.
 */
export type ContextEntry<C = unknown, P = unknown> =
  | {
      /** A request: verifies its token or cookie. */
      readonly kind: "request";
      readonly request: Request;
      readonly options?: ContextOptions;
    }
  | {
      /** A resolution from `bsb.resolve(request)`, verified once. */
      readonly kind: "resolution";
      readonly resolution: AuthResolution<C, P>;
      readonly request: Request;
      readonly options?: Omit<ContextOptions, "refresh">;
    }
  | {
      /** An auth state resolved elsewhere: the proxy or a queue message. */
      readonly kind: "auth";
      readonly auth: AuthState<C, P>;
      readonly options?: ContextOptions;
    }
  | {
      /** A trusted scheduler: the service role, as the key named `keyName`. */
      readonly kind: "cron";
      readonly keyName?: string;
      readonly options?: ContextOptions;
    };

/**
 * The context for any entry point: `request` runs `bsb.context`, `resolution`
 * runs `bsb.contextFromResolution`, `auth` runs `bsb.contextFor`, and `cron`
 * runs `bsb.contextFor` as the service role. The result is the same
 * `ServerContext` everywhere.
 */
export async function entryContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  V extends AuthzVersionCache,
>(
  bsb: BetterServer<M, F, E, C, P, B, V>,
  entry: ContextEntry<C, P>,
): Promise<ServerContext<M, F, E, C, P, B>> {
  switch (entry.kind) {
    case "request": {
      return bsb.context(entry.request, entry.options);
    }

    case "resolution": {
      return bsb.contextFromResolution(
        entry.resolution,
        entry.request,
        entry.options,
      );
    }

    case "auth": {
      return bsb.contextFor(entry.auth, entry.options);
    }

    case "cron": {
      return bsb.contextFor(
        { kind: "secret", keyName: entry.keyName ?? CRON_KEY_NAME },
        entry.options,
      );
    }

    default: {
      const unreachable: never = entry;

      throw new TypeError(
        `Unknown context entry: ${JSON.stringify(unreachable)}`,
      );
    }
  }
}

export interface CronHandlerOptions {
  /** Names the route in its errors, such as `"digest"`. */
  readonly name: string;
  /** The bearer token the scheduler sends, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** The key name the context's service caller carries. Defaults to `"cron"`. */
  readonly keyName?: string;
}

/**
 * A `GET` or `POST` route for a scheduler such as Vercel Cron. It answers 405
 * to other methods and 401 without the bearer secret, then runs `run` with a
 * service-role context. A `Response` it returns is sent as is, anything else as
 * JSON (`{ ok: true }` for nothing). It throws at creation when `secret` is
 * missing.
 */
export function cronHandler<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
  B,
  V extends AuthzVersionCache,
>(
  bsb: BetterServer<M, F, E, C, P, B, V>,
  options: CronHandlerOptions,
  run: (ctx: ServerContext<M, F, E, C, P, B>, request: Request) => unknown,
): (request: Request) => Promise<Response> {
  return cronRoute(
    { name: options.name, secret: options.secret },
    async (request) => {
      const ctx = await entryContext(bsb, {
        kind: "cron",
        ...(options.keyName === undefined ? {} : { keyName: options.keyName }),
      });

      const result = await run(ctx, request);

      return result instanceof Response
        ? result
        : Response.json(result ?? { ok: true });
    },
  );
}
