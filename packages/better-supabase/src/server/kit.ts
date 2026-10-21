import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AuthState } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type { DbError } from "../core/errors.ts";

import { authContext } from "../auth/context.ts";
import { toSession } from "../auth/view.ts";
import {
  checkPermission,
  type AnyAuthorizer,
  type AuthorizationResource,
} from "../core/authorizer.ts";
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
export interface AuthorizeOptions<
  I,
  C,
  P,
  R extends boolean,
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
> {
  /** Refuse callers without an active tenant, so `ctx.tenant` is a string. */
  readonly requireTenant?: R;
  /** Admit only users holding one of these roles at `roleClaim`. */
  readonly roles?: readonly string[];
  /** The dotted claim path `roles` reads: one string or an array. Defaults to `app_metadata.role`. */
  readonly roleClaim?: string;
  /**
   * The permission the server's `authorizer` must grant. Without an
   * authorizer, or on any outcome but `granted`, the caller is refused;
   * `approval-required` refuses with `code: "APPROVAL_REQUIRED"`.
   */
  readonly permission?: Ref;
  /**
   * The resource `permission` is checked against, loaded after the session
   * and tenant checks, e.g. the project row with its owner and team. It
   * gets the validated input and the request's context (`db`, `session`,
   * `tenant`). Defaults to `{ type: "action" }` with the input as
   * `properties`, or `{ type: "route" }`. A thrown `DbException` refuses
   * with its error (such as `not_found`); any other throw refuses with
   * `forbidden` and `code: "RESOURCE_UNAVAILABLE"`.
   */
  readonly resource?: (
    input: I,
    ctx: X,
  ) => AuthorizationResource | Promise<AuthorizationResource>;
  /** Return `false` to refuse the caller, e.g. `(session, input) => input.ownerId === session.user.id`. */
  readonly authorize?: (
    session: AuthSession<C, P>,
    input: I,
  ) => boolean | Promise<boolean>;
}

/** What a `resource` loader gets besides the input, when the adapter has no context of its own. */
export interface ResourceLoaderContext<C = unknown, P = unknown> {
  readonly session: AuthSession<C, P>;
  readonly tenant: string | undefined;
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
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
>
  extends GuardOptions, AuthorizeOptions<ActionParsed<S>, C, P, R, Ref, X> {
  /** Validates the input (plain object or `FormData`) with any Standard Schema. */
  readonly input?: S;
}

/** The guard and authorize checks of a loader, page or route. */
export interface BlockRequireOptions<
  C = unknown,
  P = unknown,
  R extends boolean = boolean,
  Ref = unknown,
  X = ResourceLoaderContext<C, P>,
>
  extends GuardOptions, AuthorizeOptions<undefined, C, P, R, Ref, X> {}

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

/** What a `permission` on an action or route is checked against. */
function callerResource(input: unknown): AuthorizationResource {
  if (input === undefined || input instanceof Request) {
    return { type: "route" };
  }

  if (
    typeof input !== "object" ||
    input === null ||
    Array.isArray(input) ||
    input instanceof FormData
  ) {
    return { type: "action" };
  }

  // SAFETY: a plain object input is JSON-like data, which properties hold.
  return {
    type: "action",
    properties: input as Readonly<Record<string, unknown>>,
  };
}

/** Runs a `resource` loader; any failure refuses, so a missing row never reads as granted. */
async function loadResource(
  load: () => unknown,
): Promise<AuthorizationResource | DbError> {
  const unavailable = dbError(
    "forbidden",
    "The resource this needs could not be loaded",
    { code: "RESOURCE_UNAVAILABLE" },
  );

  let settled: Awaited<ReturnType<typeof settle>>;

  try {
    settled = await settle(load);
  } catch {
    return unavailable;
  }

  if (!settled.ok) {
    return settled.error;
  }

  const { data } = settled;

  if (
    typeof data !== "object" ||
    data === null ||
    !("type" in data) ||
    typeof data.type !== "string"
  ) {
    return unavailable;
  }

  // SAFETY: the loader is typed to return an AuthorizationResource, and the
  // check above confirms the one field every resource has.
  return data as AuthorizationResource;
}

/**
 * `requireTenant`, `roles`, `permission` and `authorize`, in that order: the
 * session and tenant, or why the caller is refused.
 */
export async function authorizeCaller<I, C, P, X = ResourceLoaderContext<C, P>>(
  auth: AuthState<C, P>,
  checks: AuthorizeOptions<I, C, P, boolean, unknown, X>,
  input: I,
  tenant: string | undefined,
  authorizer?: AnyAuthorizer,
  scope?: object,
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

  if (checks.permission !== undefined) {
    const resource = checks.resource
      ? await loadResource(() =>
          // SAFETY: X is the adapter's context, which `scope` is, plus
          // the session and tenant added here.
          checks.resource?.(input, { ...scope, session, tenant } as X),
        )
      : callerResource(input);

    if ("kind" in resource) {
      return resource;
    }

    const permitted = await checkPermission({
      authorizer,
      permission: checks.permission,
      resource,
      context: {
        ...authContext(auth),
        ...(tenant === undefined ? {} : { tenant }),
      },
    });

    if (!permitted.ok) {
      return permitted.error;
    }
  }

  if (checks.authorize && !(await checks.authorize(session, input))) {
    return dbError("forbidden", "You are not allowed to do this", {
      code: "NOT_AUTHORIZED",
    });
  }

  return { session, tenant };
}

/** `guard`, then `authorizeCaller`: the caller, or the refusal. */
export async function requireCaller<C, P, X = ResourceLoaderContext<C, P>>(
  auth: AuthState<C, P>,
  options: BlockRequireOptions<C, P, boolean, unknown, X>,
  tenant: string | undefined,
  authorizer?: AnyAuthorizer,
  scope?: object,
): Promise<
  | { readonly session: AuthSession<C, P>; readonly tenant: string | undefined }
  | DbError
> {
  const denied = guard(auth, options.allow, options.aal, options.scopes);

  return (
    denied ??
    authorizeCaller(auth, options, undefined, tenant, authorizer, scope)
  );
}

/**
 * Runs an action body with the guard, input validation and authorize checks
 * every adapter shares, and settles it into an `ActionResult`: `Result`s
 * unwrap, thrown `DbException`s become errors, other throws propagate (so
 * framework redirects keep working).
 */
export async function runAction<C, P, X = ResourceLoaderContext<C, P>>(
  auth: AuthState<C, P>,
  options: BlockActionOptions<
    StandardSchemaV1 | undefined,
    C,
    P,
    boolean,
    unknown,
    X
  >,
  input: unknown,
  tenant: string | undefined,
  body: (
    parsed: unknown,
    caller: {
      readonly session: AuthSession<C, P>;
      readonly tenant: string | undefined;
    },
  ) => unknown,
  authorizer?: AnyAuthorizer,
  scope?: object,
): Promise<ActionResult<unknown>> {
  const denied = guard(auth, options.allow, options.aal, options.scopes);

  if (denied) {
    return actionError(denied);
  }

  let parsed: unknown =
    input instanceof FormData ? formDataObject(input) : input;

  if (options.input) {
    const checked = await validate(options.input, parsed, "input");

    if (!checked.ok) {
      return actionError(checked.error);
    }

    parsed = checked.data;
  }

  const caller = await authorizeCaller(
    auth,
    options,
    parsed,
    tenant,
    authorizer,
    scope,
  );

  if ("kind" in caller) {
    return actionError(caller);
  }

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

  if (single !== undefined) {
    return [single];
  }

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
  if (auth.kind !== "user") {
    return false;
  }

  const held = rolesAt(auth.claims, path);

  return roles.some((role) => held.includes(role));
}
