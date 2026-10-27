import type { DbErrorOf } from "./errors.ts";
import type { RequestContext } from "./plugin.ts";
import type { Result } from "./result.ts";

import { cloneValue, deepFreeze, isPlainObject } from "./clone.ts";
import { dbError } from "./errors.ts";
import { err, ok } from "./result.ts";

type JsonObject = Readonly<Record<string, unknown>>;

/** Who asks (AuthZEN Subject). Always built from the verified request context. */
export interface AuthorizationSubject {
  /**
   * `user`, `service`, `anon`, or `agent` for a delegated token with an `act`
   * chain.
   */
  readonly type: string;
  readonly id: string;
  /**
   * `role`, `email` and `impersonator` when set, and `claims`: the verified
   * access-token claims (a frozen copy, including what a token hook wrote, such
   * as `memberships`, `roles` and `act`). The client never supplies them.
   * Anonymous subjects have no properties.
   */
  readonly properties?: JsonObject;
}

/**
 * Where `resource.properties` came from: `loaded` from the database through the
 * caller's client, or `input` the caller sent, which an authorizer must not
 * trust as stored state.
 */
export type AuthorizationResourceSource = "loaded" | "input";

/**
 * The write a request makes: the stored row, when there is one, and the new
 * values.
 */
export interface AuthorizationChange {
  /** The row before the write; absent for a create. */
  readonly current?: JsonObject;
  /** The values the caller sends. Caller input, never trusted as stored state. */
  readonly next: JsonObject;
}

/** What is acted on (AuthZEN Resource): a table, a topic or an action's target. */
export interface AuthorizationResource {
  readonly type: string;
  readonly id?: string;
  /** The row, for decisions that read it (`get`, `update`, `delete`). */
  readonly properties?: JsonObject;
  /** Where `properties` came from. */
  readonly source?: AuthorizationResourceSource;
  /** The write, for `create`, `upsert` and `update`. */
  readonly change?: AuthorizationChange;
}

/** Whether a request reads or writes. */
export type AuthorizationIntent = "read" | "write";

/**
 * The kind of call that asks: a repository method, an action, a route or an MCP
 * tool.
 */
export type AuthorizationOperation =
  | "get"
  | "list"
  | "create"
  | "update"
  | "delete"
  | "action"
  | "route"
  | "tool";

/** The `intent` and `operation` a call site passes to `requestOf`. */
export interface AuthorizationPurpose {
  readonly intent?: AuthorizationIntent;
  readonly operation?: AuthorizationOperation;
}

/**
 * The typed part of `AuthorizationRequest.context`. better-supabase builds it
 * from the verified request context; every field is optional.
 */
export interface AuthorizationContext extends AuthorizationPurpose {
  readonly tenant?: string;
  /** The token's assurance level (`aal1`, `aal2`). */
  readonly aal?: string;
  /** The token's OAuth scopes, split from `scope`. */
  readonly scopes?: readonly string[];
  /** `RequestContext.requestId`: the same for every check in one request scope. */
  readonly requestId?: string;
  /** The approval id the client resumes with (`ServerOptions.approval`). */
  readonly approval?: string;
}

/**
 * One access request, in the AuthZEN Authorization API 1.0 information model
 * (`SPEC_PINS.authzen`): subject, action, resource and context. `action` is the
 * permission reference the authorizer understands.
 */
export interface AuthorizationRequest<Ref = string> {
  readonly subject: AuthorizationSubject;
  readonly action: Ref;
  readonly resource: AuthorizationResource;
  /** The tenant, assurance level, scopes, purpose and approval of the request. */
  readonly context: AuthorizationContext & JsonObject;
}

export type AuthorizationOutcome =
  | { readonly outcome: "granted"; readonly context?: JsonObject }
  | {
      readonly outcome: "denied";
      readonly reason?: string;
      readonly context?: JsonObject;
    }
  | {
      readonly outcome: "approval-required";
      readonly approval?: { readonly id: string };
      readonly context?: JsonObject;
    };

/**
 * A runtime authorization decision point (API v1). Authorization libraries ship
 * an adapter that implements it; better-supabase builds every request and fails
 * closed on anything but `granted`.
 */
export interface Authorizer<
  Ref = string,
  V extends AuthzVersionCache = AuthzVersionCache,
> {
  readonly apiVersion: 1;
  readonly name: string;
  /** The stable key of a permission reference, for specs, SQL and messages. */
  key(ref: Ref): string;
  /**
   * The default permission for a table operation; lets `permissions: true`
   * work.
   */
  forOperation?(table: string, operation: string): Ref | undefined;
  evaluate(
    request: AuthorizationRequest<Ref>,
    runtime?: AuthorizerRuntime<V>,
  ): AuthorizationOutcome | Promise<AuthorizationOutcome>;
  /**
   * The batch form (AuthZEN Access Evaluations); results keep the request
   * order.
   */
  evaluations?(
    requests: readonly AuthorizationRequest<Ref>[],
    runtime?: AuthorizerRuntime<V>,
  ): Promise<readonly AuthorizationOutcome[]>;
}

/**
 * A process-wide cache of authorization versions per user, owned by the
 * authorization library and typed structurally here. Create it once at module
 * scope and pass it to `createServer({ versions })`; never per request or per
 * cache scope.
 */
export interface AuthzVersionCache {
  /** Forgets a user's version, so the next decision reads it again. */
  evict(userId: string): void | PromiseLike<void>;
}

/**
 * Work shared within one request scope: the caller creates it and passes it in,
 * so nothing request-specific lives in module state. Each `use cache` scope
 * gets its own; sharing across scopes goes through `AuthzVersionCache`.
 */
export interface RequestMemo {
  /** `load()`'s promise, run once per key for this memo. */
  once<T>(key: string, load: () => Promise<T>): Promise<T>;
}

/**
 * Runs `evaluate`, passing the runtime only when there is one, so authorizers
 * written before it see the call they always did.
 */
async function evaluateWith<Ref>(
  authorizer: Authorizer<Ref>,
  request: AuthorizationRequest<Ref>,
  runtime: AuthorizerRuntime | undefined,
): Promise<AuthorizationOutcome> {
  return runtime
    ? authorizer.evaluate(request, runtime)
    : authorizer.evaluate(request);
}

/** Whether `value` is a `RequestMemo`. */
export function isRequestMemo(value: unknown): value is RequestMemo {
  return (
    typeof value === "object" &&
    value !== null &&
    "once" in value &&
    typeof value.once === "function"
  );
}

/** A new memo for one request scope. */
export function requestMemo(): RequestMemo {
  const entries = new Map<string, Promise<unknown>>();

  return {
    once<T>(key: string, load: () => Promise<T>): Promise<T> {
      const known = entries.get(key);

      if (known) {
        // SAFETY: a key is only ever stored with the promise its load returned.
        return known as Promise<T>;
      }

      const promise = load();
      entries.set(key, promise);
      promise.catch(() => {
        entries.delete(key);
      });

      return promise;
    },
  };
}

/**
 * What better-supabase hands an authorizer next to each request. Optional, so
 * authorizers written for API v1 keep working.
 */
export interface AuthorizerRuntime<
  V extends AuthzVersionCache = AuthzVersionCache,
> {
  /**
   * `ServerOptions.versions`, when the server has one, typed as the library's
   * own cache.
   */
  readonly versions?: V;
  /** The scope's memo, for reads several checks in one scope share. */
  readonly memo?: RequestMemo;
}

/**
 * `authorizer` with `runtime` merged under the runtime of every call, so a
 * server's `versions` reaches each decision.
 */
export function bindAuthorizer<
  A extends AnyAuthorizer<V> | undefined,
  V extends AuthzVersionCache = AuthzVersionCache,
>(authorizer: A, runtime: AuthorizerRuntime<V>): A {
  if (!authorizer || runtime.versions === undefined) {
    return authorizer;
  }

  const inner: AnyAuthorizer = authorizer;

  const merged = (call?: AuthorizerRuntime): AuthorizerRuntime => ({
    ...runtime,
    ...call,
  });

  const evaluations = inner.evaluations?.bind(inner);
  const forOperation = inner.forOperation?.bind(inner);

  // Methods are bound, not spread, so class-based authorizers keep them.
  const bound: AnyAuthorizer = {
    apiVersion: inner.apiVersion,
    name: inner.name,
    key: (ref) => inner.key(ref),
    ...(forOperation ? { forOperation } : {}),
    evaluate: (request, call) => inner.evaluate(request, merged(call)),
    ...(evaluations
      ? { evaluations: (requests, call) => evaluations(requests, merged(call)) }
      : {}),
  };

  // SAFETY: bound has every member of `authorizer`, with the same signatures.
  return bound as A;
}

/** An authorizer with any permission reference, for a version cache `V`. */
export type AnyAuthorizer<V extends AuthzVersionCache = AuthzVersionCache> =
  // oxlint-disable-next-line typescript/no-explicit-any -- Ref is invariant (key() takes it), so `unknown` would reject typed authorizers
  Authorizer<any, V>;

/** The permission reference type of an authorizer, `string` without one. */
export type PermissionRef<A> = A extends Authorizer<infer R> ? R : string;

/**
 * Identity helper that fixes `apiVersion` and infers `Ref`, and `V` from a
 * typed `runtime` parameter.
 */
export function defineAuthorizer<
  Ref = string,
  V extends AuthzVersionCache = AuthzVersionCache,
>(
  authorizer: Omit<Authorizer<Ref, V>, "apiVersion"> & {
    readonly apiVersion?: 1;
  },
): Authorizer<Ref, V> {
  return { ...authorizer, apiVersion: 1 };
}

const ANONYMOUS: AuthorizationSubject = { type: "anon", id: "anonymous" };

function scopesOf(claims: JsonObject | undefined): readonly string[] {
  const scope = claims?.["scope"];

  return typeof scope === "string" ? scope.split(" ").filter(Boolean) : [];
}

/** A frozen copy of the verified claims, so an authorizer cannot change them. */
function claimsProperty(claims: unknown): { readonly claims?: JsonObject } {
  if (!isPlainObject(claims)) {
    return {};
  }

  // SAFETY: cloneValue keeps the shape of a plain claims object.
  return { claims: deepFreeze(cloneValue(claims) as JsonObject) };
}

/** The subject and context of a request, from the verified context only. */
export function requestOf(
  context: RequestContext | undefined,
  purpose: AuthorizationPurpose = {},
): {
  readonly subject: AuthorizationSubject;
  readonly context: AuthorizationContext & JsonObject;
} {
  const actor = context?.actor;
  const claims = context?.claims;
  const act = claims?.["act"];

  const subject: AuthorizationSubject = actor
    ? {
        type:
          typeof act === "object" && act !== null && actor.kind === "user"
            ? "agent"
            : actor.kind,
        id: actor.id,
        properties: {
          ...(actor.role === undefined ? {} : { role: actor.role }),
          ...(actor.email === undefined ? {} : { email: actor.email }),
          ...(actor.impersonator === undefined
            ? {}
            : { impersonator: actor.impersonator }),
          ...claimsProperty(claims),
        },
      }
    : ANONYMOUS;

  const aal = claims?.["aal"];

  return {
    subject,
    context: {
      ...(context?.tenant === undefined ? {} : { tenant: context.tenant }),
      ...(typeof aal === "string" ? { aal } : {}),
      scopes: scopesOf(claims),
      ...(purpose.intent === undefined ? {} : { intent: purpose.intent }),
      ...(purpose.operation === undefined
        ? {}
        : { operation: purpose.operation }),
      ...(typeof context?.requestId === "string"
        ? { requestId: context.requestId }
        : {}),
      ...(typeof context?.approval === "string"
        ? { approval: context.approval }
        : {}),
    },
  };
}

function isOutcome(value: unknown): value is AuthorizationOutcome {
  if (typeof value !== "object" || value === null || !("outcome" in value)) {
    return false;
  }

  const { outcome } = value;

  return (
    outcome === "granted" ||
    outcome === "denied" ||
    outcome === "approval-required"
  );
}

/** The `forbidden` error for an outcome other than `granted`, or `undefined`. */
function outcomeError(
  outcome: unknown,
  permission: string,
): DbErrorOf<"forbidden"> | undefined {
  if (!isOutcome(outcome)) {
    return dbError(
      "forbidden",
      `The authorizer gave no decision for ${permission}`,
      { code: "PERMISSION_DENIED", permission },
    );
  }

  switch (outcome.outcome) {
    case "granted": {
      return undefined;
    }

    case "denied": {
      return dbError(
        "forbidden",
        outcome.reason ?? `Permission ${permission} is required`,
        { code: "PERMISSION_DENIED", permission },
      );
    }

    case "approval-required": {
      return dbError("forbidden", `${permission} needs an approval`, {
        code: "APPROVAL_REQUIRED",
        permission,
        ...(outcome.approval ? { approval: { id: outcome.approval.id } } : {}),
      });
    }

    default: {
      const exhaustive: never = outcome;

      return exhaustive;
    }
  }
}

export interface CheckOptions<Ref> extends AuthorizationPurpose {
  readonly authorizer: Authorizer<Ref> | undefined;
  readonly permission: Ref;
  readonly resource: AuthorizationResource;
  readonly context: RequestContext | undefined;
  readonly runtime?: AuthorizerRuntime;
}

function purposeOf(options: AuthorizationPurpose): AuthorizationPurpose {
  return {
    ...(options.intent === undefined ? {} : { intent: options.intent }),
    ...(options.operation === undefined
      ? {}
      : { operation: options.operation }),
  };
}

/**
 * Checks one permission and fails closed: a missing authorizer, a throw or an
 * unknown outcome all deny. Never throws (invariant 4).
 */
export async function checkPermission<Ref>(
  options: CheckOptions<Ref>,
): Promise<Result<void>> {
  const { authorizer, permission } = options;

  if (!authorizer) {
    return err(
      dbError(
        "forbidden",
        "A permission is declared, but no authorizer is set",
        { code: "PERMISSION_DENIED" },
      ),
    );
  }

  let key: string;

  try {
    key = authorizer.key(permission);
  } catch {
    return err(
      dbError("forbidden", "Unknown permission", { code: "PERMISSION_DENIED" }),
    );
  }

  const { subject, context } = requestOf(options.context, purposeOf(options));

  try {
    const outcome = await evaluateWith(
      authorizer,
      { subject, action: permission, resource: options.resource, context },
      options.runtime,
    );

    const error = outcomeError(outcome, key);

    return error ? err(error) : ok(undefined);
  } catch {
    return err(
      dbError("forbidden", `The authorizer failed for ${key}`, {
        code: "PERMISSION_DENIED",
        permission: key,
      }),
    );
  }
}

/**
 * Checks one permission per resource, with `evaluations` when the authorizer
 * has it. Returns whether each one is granted, in order; any failure denies.
 */
export async function checkEach<Ref>(
  authorizer: Authorizer<Ref> | undefined,
  permission: Ref,
  resources: readonly AuthorizationResource[],
  context: RequestContext | undefined,
  runtime?: AuthorizerRuntime,
  purpose: AuthorizationPurpose = {},
): Promise<readonly boolean[]> {
  if (!authorizer || resources.length === 0) {
    return resources.map(() => false);
  }

  const { subject, context: requestContext } = requestOf(
    context,
    purposeOf(purpose),
  );

  const requests = resources.map((resource) => ({
    subject,
    action: permission,
    resource,
    context: requestContext,
  }));

  try {
    const outcomes = authorizer.evaluations
      ? await (runtime
          ? authorizer.evaluations(requests, runtime)
          : authorizer.evaluations(requests))
      : await Promise.all(
          requests.map((request) => evaluateWith(authorizer, request, runtime)),
        );

    return requests.map(
      (_, index) =>
        isOutcome(outcomes[index]) && outcomes[index].outcome === "granted",
    );
  } catch {
    return resources.map(() => false);
  }
}
