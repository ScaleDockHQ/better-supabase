import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { BetterServer } from "../server/server.ts";
import type { StorageImageOptions } from "../storage/image-url.ts";

import { around } from "../bridges/shared.ts";
import { flushEvents } from "../server/adapter.ts";
import {
  type FrameworkLocals,
  type FrameworkOptions,
  frameworkEntry,
  localsOf,
} from "../server/framework.ts";
import {
  type ActionParsed,
  type ActionResult,
  type AuthorizedContext,
  type BlockActionOptions,
  type BlockRequireOptions,
  requireCaller,
  runAction,
  type Unwrapped,
} from "../server/kit.ts";
import { refusalResponse } from "../server/refusal.ts";
import { defaultExpose } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import { storageImageUrl } from "../storage/image-url.ts";

export type { RefusalRedirects } from "../server/refusal.ts";
export type { ActionResult } from "../server/kit.ts";

/** The part of Astro's `APIContext` (middleware, pages, endpoints, actions) the integration uses. */
export interface AstroContextLike {
  readonly request: Request;
  readonly locals: object;
}

export interface AstroOptions extends FrameworkOptions {
  /** The host's env object for `getEnv`; defaults to `locals.runtime.env` (Cloudflare). */
  readonly platformEnv?: (context: AstroContextLike) => unknown;
}

export interface BetterAstro<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /**
   * Astro middleware: verifies the caller, refreshes the session cookie on
   * navigations and form posts, and puts `db`, `bs`, `auth`, `tenant` and
   * `session` on `locals`. Response-phase entries see the page's response.
   *
   * ```ts title="src/middleware.ts"
   * export const onRequest = bs.onRequest
   * ```
   */
  readonly onRequest: (
    context: AstroContextLike,
    next: () => Promise<Response>,
  ) => Promise<Response>;
  /** The request's `locals`, typed. */
  locals(context: AstroContextLike): FrameworkLocals<M, F, E, C, P>;
  /**
   * The refusal for a caller `options` refuses (a redirect to `signIn` or
   * `mfa`, else Problem Details), or `undefined`. Return it from a page's
   * frontmatter or an endpoint.
   *
   * ```astro
   * ---
   * const refused = await bs.guard(Astro, { roles: ['admin'] })
   * if (refused) return refused
   * ---
   * ```
   */
  guard(
    context: AstroContextLike,
    options?: BlockRequireOptions<C, P>,
  ): Promise<Response | undefined>;
  /**
   * The caller, or a thrown refusal `Response`, for endpoints that return
   * whatever is thrown.
   */
  require<R extends boolean = false>(
    context: AstroContextLike,
    options?: BlockRequireOptions<C, P, R>,
  ): Promise<FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>>;
  /**
   * The `handler` of `defineAction`, returning an `ActionResult`:
   *
   * ```ts title="src/actions/index.ts"
   * export const server = {
   *   addNote: defineAction({ accept: 'form', handler: bs.action({ input: NoteInput }, (input, { db }) => db.notes.create(input)) }),
   * }
   * ```
   */
  action<S extends StandardSchemaV1 | undefined, T, R extends boolean = false>(
    options: BlockActionOptions<S, C, P, R>,
    fn: (
      input: ActionParsed<S>,
      ctx: FrameworkLocals<M, F, E, C, P> & AuthorizedContext<C, P, R>,
    ) => T,
  ): (
    input: unknown,
    context: AstroContextLike,
  ) => Promise<ActionResult<Unwrapped<Awaited<T>>>>;
}

function runtimeEnv(locals: object): unknown {
  const runtime: unknown = "runtime" in locals ? locals.runtime : undefined;
  return typeof runtime === "object" && runtime !== null && "env" in runtime
    ? runtime.env
    : undefined;
}

/** Astro integration: middleware, page guards and Actions. */
export function createAstro<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: AstroOptions = {},
): BetterAstro<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const run = around([frameworkEntry(server, options, expose)]);
  type Locals = FrameworkLocals<M, F, E, C, P>;

  const scopeOf = (context: AstroContextLike): Locals => {
    if (!("bs" in context.locals)) {
      throw new TypeError(
        "better-supabase: no context; export bs.onRequest from src/middleware.ts",
      );
    }
    // SAFETY: onRequest put localsOf(contributions) on locals.
    return context.locals as Locals;
  };

  const refusalOf = async (
    context: AstroContextLike,
    requireOptions: BlockRequireOptions<C, P>,
  ) => {
    const scope = scopeOf(context);
    const caller = await requireCaller(
      scope.bs.auth,
      requireOptions,
      scope.tenant,
    );
    return { scope, caller };
  };

  return extendServer<BetterAstro<M, F, E, C, P>>(server, {
    onRequest: async (context, next) => {
      const env = options.platformEnv
        ? options.platformEnv(context)
        : runtimeEnv(context.locals);
      try {
        return await run(context.request, env, (contributions) => {
          Object.assign(context.locals, localsOf<M, F, E, C, P>(contributions));
          return next();
        });
      } finally {
        flushEvents(server, options.waitUntil);
      }
    },

    locals: scopeOf,

    guard: async (context, requireOptions = {}) => {
      const { caller } = await refusalOf(context, requireOptions);
      return "kind" in caller
        ? refusalResponse(caller, context.request, options, expose)
        : undefined;
    },

    require: async (context, requireOptions = {}) => {
      const { scope, caller } = await refusalOf(context, requireOptions);
      if ("kind" in caller) {
        // oxlint-disable-next-line typescript/only-throw-error -- endpoints that rethrow send the Response as the answer.
        throw refusalResponse(caller, context.request, options, expose);
      }
      // SAFETY: requireTenant refused a missing tenant.
      return { ...scope, ...caller } as never;
    },

    action(actionOptions, fn) {
      return async (input, context) => {
        const scope = scopeOf(context);
        const result = await runAction(
          scope.bs.auth,
          actionOptions,
          input,
          scope.tenant,
          // SAFETY: parsed is the validated input, or the raw input when the
          // action has no schema; requireTenant refused a missing tenant.
          (parsed, caller) =>
            fn(parsed as never, { ...scope, ...caller } as never),
        );
        // SAFETY: the settled data is what fn returned, unwrapped.
        return result as never;
      };
    },
  });
}

/** What Astro passes to an image service's `getURL`. */
export interface AstroImageTransform {
  readonly src: string | { readonly src: string };
  readonly width?: number | undefined;
  readonly height?: number | undefined;
  readonly quality?: number | "low" | "mid" | "high" | "max" | undefined;
}

/** An Astro external image service, typed structurally. */
export interface AstroImageService {
  getURL(options: AstroImageTransform): string;
}

const QUALITY_PRESETS = { low: 40, mid: 60, high: 80, max: 100 } as const;

/**
 * An external image service that renders public Storage objects through
 * Supabase image transformations; other sources pass through.
 *
 * ```ts title="src/image-service.ts"
 * export default createImageService({ url: import.meta.env.PUBLIC_SUPABASE_URL })
 * ```
 */
export function createImageService(
  options: StorageImageOptions,
): AstroImageService {
  const imageUrl = storageImageUrl(options);
  return {
    getURL(transform) {
      const src =
        typeof transform.src === "string" ? transform.src : transform.src.src;
      if (transform.width === undefined) return src;
      const quality =
        typeof transform.quality === "string"
          ? QUALITY_PRESETS[transform.quality]
          : transform.quality;
      return (
        imageUrl(src, {
          width: transform.width,
          height: transform.height,
          quality,
        }) ?? src
      );
    },
  };
}
