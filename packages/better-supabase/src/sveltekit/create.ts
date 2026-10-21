import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SvelteKitHandle } from "../bridges/sveltekit.ts";
import type { AnyAuthorizer, PermissionRef } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  FrameworkLocals,
  LocalsResource,
  FrameworkOptions,
} from "../server/framework.ts";
import type {
  ActionParsed,
  ActionResult,
  AuthorizedContext,
  BlockActionOptions,
  BlockRequireOptions,
  Unwrapped,
} from "../server/kit.ts";
import type { BetterServer } from "../server/server-types.ts";

import { around, bufferInPlace } from "../bridges/shared.ts";
import { dbErrorOf, DbException } from "../core/errors.ts";
import { toProblem } from "../core/problem.ts";
import { withFlush } from "../server/adapter.ts";
import {
  actionInput,
  frameworkEntry,
  localsOf,
  platformWaitUntil,
} from "../server/framework.ts";
import { requireCaller, runAction } from "../server/kit.ts";
import { refusalTarget } from "../server/refusal.ts";
import { defaultExpose } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";

/** SvelteKit's `fail()` result, typed structurally. */
export interface SvelteKitFailure<T> {
  readonly status: number;
  readonly data: T;
}

/**
 * `error`, `redirect` and `fail` from `@sveltejs/kit`. Pass them so refused
 * callers get SvelteKit's own errors and redirects, and failed form actions a
 * `fail()` with the status.
 */
export interface SvelteKitHelpers {
  error(status: number, message: string): never;
  redirect(status: 303, location: string): never;
  fail(
    status: number,
    data: Record<string, unknown>,
  ): SvelteKitFailure<unknown>;
}

export interface SvelteKitOptions extends FrameworkOptions {
  /** `{ error, redirect, fail }` from `@sveltejs/kit`. */
  readonly kit?: SvelteKitHelpers;
}

/** The part of a SvelteKit `RequestEvent` the guards read. */
export interface SvelteKitRequestEvent<Locals extends object = object> {
  readonly request: Request;
  readonly locals: Locals;
}

/** A load's `depends`, typed structurally. */
export interface SvelteKitDepends {
  depends(...deps: `${string}:${string}`[]): void;
}

/** What `handleError` returns: SvelteKit's `App.Error` with a code. */
export interface SvelteKitAppError {
  readonly message: string;
  readonly code?: string;
}

export interface BetterSvelteKit<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
  /**
   * The keys on `event.locals`, for `App.Locals`. Type only: `undefined` at
   * runtime.
   */
  readonly Locals: FrameworkLocals<M, F, E, C, P, B>;
  /**
   * The `handle` hook: verifies the caller, refreshes the session cookie on
   * navigations and form posts, and puts `db`, `bs`, `auth`, `tenant` and the
   * serializable `session` on `event.locals`.
   */
  readonly handle: SvelteKitHandle<Partial<FrameworkLocals<M, F, E, C, P, B>>>;
  /**
   * The caller in a `load` or endpoint, or a refusal: a redirect to `signIn` or
   * `mfa` when configured, else SvelteKit's `error()`.
   *
   * ```ts
   * export const load = async (event) => {
   *   const { db, tenant } = await bs.require(event, {
   *     requireTenant: true,
   *   });
   *   return { customers: await db.customers.findMany().orThrow() };
   * };
   * ```
   */
  require<R extends boolean = false>(
    event: SvelteKitRequestEvent,
    options?: BlockRequireOptions<
      C,
      P,
      R,
      Ref,
      LocalsResource<M, F, E, C, P, B>
    >,
  ): Promise<FrameworkLocals<M, F, E, C, P, B> & AuthorizedContext<C, P, R>>;
  /**
   * A form action returning an `ActionResult`: validates the form with `input`,
   * runs the guard and `authorize`, and on failure answers with `fail(status,
   * result)` when `kit` is set, so `form.error` is a `DbError`.
   */
  action<S extends StandardSchemaV1 | undefined, T, R extends boolean = false>(
    options: BlockActionOptions<
      S,
      C,
      P,
      R,
      Ref,
      LocalsResource<M, F, E, C, P, B>
    >,
    fn: (
      input: ActionParsed<S>,
      ctx: FrameworkLocals<M, F, E, C, P, B> & AuthorizedContext<C, P, R>,
      event: SvelteKitRequestEvent,
    ) => T,
  ): (
    event: SvelteKitRequestEvent,
  ) => Promise<
    ActionResult<Unwrapped<Awaited<T>>> | SvelteKitFailure<ActionResult<never>>
  >;
  /**
   * `handleError` for `hooks.server.ts`: `DbError`s keep their message and kind
   * as `code`; other errors become a generic message unless `exposeErrors` is
   * on.
   */
  handleError(input: { readonly error: unknown }): SvelteKitAppError;
  /**
   * Registers `bs:<table>` dependencies, so `invalidate(tagFor(table))` reruns
   * the load.
   */
  depends(load: SvelteKitDepends, ...tables: readonly string[]): void;
}

/** SvelteKit integration: a `handle` hook, guarded loads and form actions. */
export function createSvelteKit<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  A extends AnyAuthorizer | undefined = undefined,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: SvelteKitOptions & { readonly authorizer?: A } = {},
): BetterSvelteKit<M, F, E, C, P, PermissionRef<A>, B> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();
  const run = around([frameworkEntry(server, options, expose)]);

  type Locals = FrameworkLocals<M, F, E, C, P, B>;

  const localsFrom = (event: SvelteKitRequestEvent): Locals => {
    const locals: Partial<Locals> = event.locals;

    if (!locals.bs) {
      throw new TypeError(
        "better-supabase: no context on event.locals; export handle = bs.handle from hooks.server.ts",
      );
    }

    // SAFETY: handle wrote every key of Locals when it wrote bs.
    return locals as Locals;
  };

  const refuse = (error: DbError, request: Request): never => {
    const target = refusalTarget(error, request, options);

    if (options.kit) {
      if (target) {
        options.kit.redirect(303, target.pathname + target.search);
      }

      options.kit.error(
        error.status,
        toProblem(error, { expose }).detail ?? error.message,
      );
    }

    throw new DbException(error);
  };

  const handle: BetterSvelteKit<M, F, E, C, P, B>["handle"] = ({
    event,
    resolve,
  }) => {
    bufferInPlace(event.request);
    const platform: unknown = event.platform;
    const env = event.platform?.env;

    return run(event.request, env, async (contributions) => {
      Object.assign(event.locals, localsOf<M, F, E, C, P, B>(contributions));

      return withFlush(
        server,
        options.waitUntil ?? platformWaitUntil(platform),
        () => resolve(event),
      );
    });
  };

  return extendServer<BetterSvelteKit<M, F, E, C, P, PermissionRef<A>, B>>(
    server,
    {
      // SAFETY: `Locals` only carries a type, like Drizzle's `$inferSelect`; reading
      // it at runtime is documented as `undefined`.
      // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- a type-only marker has no runtime value to narrow.
      Locals: undefined as unknown as Locals,
      handle,

      require: async (event, requireOptions = {}) => {
        const locals = localsFrom(event);

        const caller = await requireCaller(
          locals.bs.auth,
          requireOptions,
          locals.tenant,
          options.authorizer,
          locals,
        );

        if ("kind" in caller) {
          return refuse(caller, event.request);
        }

        // SAFETY: requireTenant refused a missing tenant.
        return { ...locals, ...caller } as never;
      },

      action(actionOptions, fn) {
        return async (event) => {
          const locals = localsFrom(event);
          const input = await actionInput(event.request);

          const result = await runAction(
            locals.bs.auth,
            actionOptions,
            input,
            locals.tenant,
            // SAFETY: parsed is the validated input, or the raw input when the
            // action has no schema; requireTenant refused a missing tenant.
            (parsed, caller) =>
              fn(parsed as never, { ...locals, ...caller } as never, event),
            options.authorizer,
            locals,
          );

          if (!result.ok && options.kit) {
            // SAFETY: fail() wraps the failed ActionResult, the declared failure branch.
            return options.kit.fail(result.error.status, result) as never;
          }

          // SAFETY: the settled data is what fn returned, unwrapped.
          return result as never;
        };
      },

      handleError({ error }) {
        const found = dbErrorOf(error);

        if (found) {
          const problem = toProblem(found, { expose });

          return { message: problem.detail ?? problem.title, code: found.kind };
        }

        return {
          message:
            expose && error instanceof Error ? error.message : "Internal Error",
        };
      },

      depends(load, ...tables) {
        // The same tag as tagFor(table), spelled out for the `bs:${string}` type.
        for (const table of tables) {
          load.depends(`bs:${table}`);
        }
      },
    },
  );
}
