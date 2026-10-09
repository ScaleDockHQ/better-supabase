import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { DbError } from "../core/errors.ts";

import { toSession } from "../auth/view.ts";
import { claimAt } from "../core/claims.ts";
import { dbError } from "../core/errors.ts";
import { validate } from "../core/standard.ts";
import { guard, type GuardOptions, settle } from "./respond.ts";

/** What a server action returns: plain data, safe across any serialization boundary. */
export type ActionResult<T> =
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

/**
 * Checks after `allow`, `aal` and `scopes`. A caller who fails one gets
 * `forbidden`: an `ActionResult` error, a 403, or the framework's refusal.
 */
export interface AuthorizeOptions<I, C, P, R extends boolean> {
  /** Refuse callers without an active tenant, so `ctx.tenant` is a string. */
  readonly requireTenant?: R;
  /** Admit only users holding one of these roles at `roleClaim`. */
  readonly roles?: readonly string[];
  /** The dotted claim path `roles` reads: one string or an array. Defaults to `app_metadata.role`. */
  readonly roleClaim?: string;
  /** Return `false` to refuse the caller, e.g. `(session, input) => input.ownerId === session.user.id`. */
  readonly authorize?: (
    session: AuthSession<C, P>,
    input: I,
  ) => boolean | Promise<boolean>;
}

/** What `requireTenant` and `authorize` add to the context. */
export interface AuthorizedContext<C, P, R extends boolean> {
  readonly session: AuthSession<C, P>;
  /**
   * The active tenant: the action's `tenant`, then the server's `tenant`
   * option, then the tenant claim (`tenantOf(session)`).
   */
  readonly tenant: R extends true ? string : string | undefined;
}

export type ActionInput<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferInput<S> | FormData
  : unknown;
export type ActionParsed<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : unknown;

// Distributes over a `Result` union: the `Err` member adds nothing, so an
// action that returns `err(...)` on one path keeps the data type of the others.
export type Unwrapped<T> = T extends {
  readonly ok: true;
  readonly data: infer D;
}
  ? D
  : T extends { readonly ok: false }
    ? never
    : T;

/** Guard, authorize and validate options of a framework-neutral action. */
export interface BlockActionOptions<
  S extends StandardSchemaV1 | undefined,
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
>
  extends GuardOptions, AuthorizeOptions<ActionParsed<S>, C, P, R> {
  /** Validates the input (plain object or `FormData`) with any Standard Schema. */
  readonly input?: S;
}

/** The guard and authorize checks of a loader, page or route. */
export interface BlockRequireOptions<
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
>
  extends GuardOptions, AuthorizeOptions<undefined, C, P, R> {}

/** `FormData` as a plain object; repeated keys become arrays. */
export function formDataObject(form: FormData): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of new Set(form.keys())) {
    const values = form.getAll(key);
    out[key] = values.length > 1 ? values : values[0];
  }
  return out;
}

/** A failed `ActionResult`. */
function actionError(error: DbError): ActionResult<never> {
  return { ok: false, data: null, error };
}

/** `requireTenant` and `authorize`: the session and tenant, or why the caller is refused. */
export async function authorizeCaller<I, C, P>(
  auth: AuthState<C, P>,
  checks: AuthorizeOptions<I, C, P, boolean>,
  input: I,
  tenant: string | undefined,
): Promise<
  | {
      readonly session: AuthSession<C, P>;
      readonly tenant: string | undefined;
    }
  | DbError
> {
  const session = toSession(auth);
  if (checks.requireTenant && tenant === undefined) {
    return dbError("forbidden", "Choose an organization first", {
      code: "NO_TENANT",
    });
  }
  if (checks.roles && !hasRole(auth, checks.roles, checks.roleClaim)) {
    return dbError("forbidden", "You do not have the role this needs", {
      code: "MISSING_ROLE",
    });
  }
  if (checks.authorize && !(await checks.authorize(session, input))) {
    return dbError("forbidden", "You are not allowed to do this", {
      code: "NOT_AUTHORIZED",
    });
  }
  return { session, tenant };
}

/** `guard`, then `authorizeCaller`: the caller, or the refusal. */
export async function requireCaller<C, P>(
  auth: AuthState<C, P>,
  options: BlockRequireOptions<C, P>,
  tenant: string | undefined,
): Promise<
  | { readonly session: AuthSession<C, P>; readonly tenant: string | undefined }
  | DbError
> {
  const denied = guard(auth, options.allow, options.aal, options.scopes);
  return denied ?? authorizeCaller(auth, options, undefined, tenant);
}

/**
 * Runs an action body with the guard, input validation and authorize checks
 * every adapter shares, and settles it into an `ActionResult`: `Result`s
 * unwrap, thrown `DbException`s become errors, other throws propagate (so
 * framework redirects keep working).
 */
export async function runAction<C, P>(
  auth: AuthState<C, P>,
  options: BlockActionOptions<StandardSchemaV1 | undefined, C, P>,
  input: unknown,
  tenant: string | undefined,
  body: (
    parsed: unknown,
    caller: {
      readonly session: AuthSession<C, P>;
      readonly tenant: string | undefined;
    },
  ) => unknown,
): Promise<ActionResult<unknown>> {
  const denied = guard(auth, options.allow, options.aal, options.scopes);
  if (denied) return actionError(denied);
  let parsed: unknown =
    input instanceof FormData ? formDataObject(input) : input;
  if (options.input) {
    const checked = await validate(options.input, parsed, "input");
    if (!checked.ok) return actionError(checked.error);
    parsed = checked.data;
  }
  const caller = await authorizeCaller(auth, options, parsed, tenant);
  if ("kind" in caller) return actionError(caller);
  const settled = await settle(() => body(parsed, caller));
  return settled.ok
    ? { ok: true, data: settled.data, error: null }
    : actionError(settled.error);
}

/** The strings at a dotted claim path: one string, or every string in an array. */
export function rolesAt(
  claims: Readonly<Record<string, unknown>> | undefined,
  path: string,
): readonly string[] {
  const single = claimAt(claims, path);
  if (single !== undefined) return [single];
  let value: unknown = claims;
  for (const segment of path.split(".")) {
    // SAFETY: the condition narrows value to a non-null object, and claims are JSON objects.
    value =
      typeof value === "object" && value !== null
        ? (value as Record<string, unknown>)[segment]
        : undefined;
  }
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

/** Whether a signed-in caller holds one of `roles` at the claim `path`. */
export function hasRole(
  auth: AuthState,
  roles: readonly string[],
  path = "app_metadata.role",
): boolean {
  if (auth.kind !== "user") return false;
  const held = rolesAt(auth.claims, path);
  return roles.some((role) => held.includes(role));
}
