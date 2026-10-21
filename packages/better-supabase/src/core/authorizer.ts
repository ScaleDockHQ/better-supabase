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

/** What is acted on (AuthZEN Resource): a table, a topic or an action's target. */
export interface AuthorizationResource {
  readonly type: string;
  readonly id?: string;
  /** The row, for decisions that read it (`get`, `update`, `delete`). */
  readonly properties?: JsonObject;
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
  /** The tenant, assurance level and scopes of the request. */
  readonly context: JsonObject;
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
export interface Authorizer<Ref = string> {
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
  ): AuthorizationOutcome | Promise<AuthorizationOutcome>;
  /**
   * The batch form (AuthZEN Access Evaluations); results keep the request
   * order.
   */
  evaluations?(
    requests: readonly AuthorizationRequest<Ref>[],
  ): Promise<readonly AuthorizationOutcome[]>;
}

// oxlint-disable-next-line typescript/no-explicit-any -- Ref is invariant (key() takes it), so `unknown` would reject typed authorizers
export type AnyAuthorizer = Authorizer<any>;

/** The permission reference type of an authorizer, `string` without one. */
export type PermissionRef<A> = A extends Authorizer<infer R> ? R : string;

/** Identity helper that fixes `apiVersion` and infers `Ref`. */
export function defineAuthorizer<Ref = string>(
  authorizer: Omit<Authorizer<Ref>, "apiVersion"> & { readonly apiVersion?: 1 },
): Authorizer<Ref> {
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
export function requestOf(context: RequestContext | undefined): {
  readonly subject: AuthorizationSubject;
  readonly context: JsonObject;
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

export interface CheckOptions<Ref> {
  readonly authorizer: Authorizer<Ref> | undefined;
  readonly permission: Ref;
  readonly resource: AuthorizationResource;
  readonly context: RequestContext | undefined;
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

  const { subject, context } = requestOf(options.context);

  try {
    const outcome = await authorizer.evaluate({
      subject,
      action: permission,
      resource: options.resource,
      context,
    });

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
): Promise<readonly boolean[]> {
  if (!authorizer || resources.length === 0) {
    return resources.map(() => false);
  }

  const { subject, context: requestContext } = requestOf(context);

  const requests = resources.map((resource) => ({
    subject,
    action: permission,
    resource,
    context: requestContext,
  }));

  try {
    const outcomes = authorizer.evaluations
      ? await authorizer.evaluations(requests)
      : await Promise.all(
          requests.map((request) =>
            Promise.resolve(authorizer.evaluate(request)),
          ),
        );

    return requests.map(
      (_, index) =>
        isOutcome(outcomes[index]) && outcomes[index].outcome === "granted",
    );
  } catch {
    return resources.map(() => false);
  }
}
