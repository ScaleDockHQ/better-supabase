/** One level of an RFC 8693 `act` chain: who acts, and who acted before it. */
export interface ActClaim {
  readonly sub: string;
  readonly act?: ActClaim;
  readonly [claim: string]: unknown;
}

/**
 * Who acts for the user, from the outermost level of the RFC 8693 `act`
 * claim, by its `kind`:
 *
 * - `oauth-client`: an `act` without `kind` (prior actors stay on `chain`),
 *   else the OAuth `client_id` of a Supabase OAuth server token. Only this
 *   kind is limited to the scopes the user delegated.
 * - `support`: an admin in a support session (`act.kind: "support"`, from
 *   `supportClaims`). An `act` without `kind` but with `session_id`, as
 *   0.5.0 minted it, counts as one until 0.6.
 * - `impersonation`: an admin acting as the user (`act.kind:
 *   "impersonation"`, from `actClaim`).
 */
export type SessionActor =
  | {
      readonly kind: "oauth-client";
      readonly id: string;
      readonly chain?: ActClaim;
    }
  | {
      readonly kind: "support";
      readonly id: string;
      readonly sessionId: string;
      /** `act.read_only`; a support token without it is read-only. */
      readonly readOnly: boolean;
      readonly reason?: string;
    }
  | {
      readonly kind: "impersonation";
      readonly id: string;
      readonly reason?: string;
    };

/** What the user delegated to the actor: the token's OAuth `scope`. */
export interface SessionDelegation {
  readonly scopes: readonly string[];
  readonly chain?: ActClaim;
}

export type ActorOutcome =
  | { readonly ok: true; readonly actor?: SessionActor }
  | { readonly ok: false; readonly reason: "invalid-chain" };

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function copyAct(level: Readonly<Record<string, unknown>>): ActClaim {
  const entries = Object.entries(level).map(
    ([key, value]): [string, unknown] => [
      key,
      key === "act" && isRecord(value) ? copyAct(value) : value,
    ],
  );
  // SAFETY: actorOf checked that this level and every nested `act` is an object with a non-empty string `sub`.
  return Object.fromEntries(entries) as ActClaim;
}

const INVALID: ActorOutcome = { ok: false, reason: "invalid-chain" };

function actorAt(
  outer: Readonly<Record<string, unknown>>,
  id: string,
): ActorOutcome {
  const kind = outer["kind"];
  const sessionId = outer["session_id"];
  const readOnly = outer["read_only"];
  const reason = outer["reason"];
  if (kind === "support" || (kind === undefined && sessionId !== undefined)) {
    if (typeof sessionId !== "string" || sessionId === "") return INVALID;
    if (readOnly !== undefined && typeof readOnly !== "boolean") return INVALID;
    return {
      ok: true,
      actor: {
        kind: "support",
        id,
        sessionId,
        readOnly: readOnly ?? true,
        ...(typeof reason === "string" ? { reason } : {}),
      },
    };
  }
  if (kind === "impersonation") {
    return {
      ok: true,
      actor: {
        kind: "impersonation",
        id,
        ...(typeof reason === "string" ? { reason } : {}),
      },
    };
  }
  if (kind !== undefined) return INVALID;
  return {
    ok: true,
    actor: { kind: "oauth-client", id, chain: copyAct(outer) },
  };
}

/**
 * Reads only `act` and `client_id`. An
 * `act` that is not a chain of objects each with a non-empty `sub`, a
 * `kind` other than `support` or `impersonation`, or a support level without
 * a `session_id` is `{ ok: false }`: the session must not pass as the user
 * alone.
 */
export function actorOf(
  claims: Readonly<Record<string, unknown>>,
): ActorOutcome {
  const outer = claims["act"];
  if (outer !== undefined) {
    if (!isRecord(outer)) return INVALID;
    const id = outer["sub"];
    if (typeof id !== "string" || id === "") return INVALID;
    let level: unknown = outer["act"];
    while (level !== undefined) {
      if (!isRecord(level)) return INVALID;
      const sub = level["sub"];
      if (typeof sub !== "string" || sub === "") return INVALID;
      level = level["act"];
    }
    return actorAt(outer, id);
  }
  const client = claims["client_id"];
  if (typeof client === "string" && client !== "")
    return { ok: true, actor: { id: client, kind: "oauth-client" } };
  return { ok: true };
}

/** The OAuth `scope` claim (a space-separated string or a list); `undefined` when empty. */
export function delegationOf(
  claims: Readonly<Record<string, unknown>>,
): SessionDelegation | undefined {
  const scope = claims["scope"];
  const scopes =
    typeof scope === "string"
      ? scope.split(/\s+/u).filter(Boolean)
      : Array.isArray(scope)
        ? scope.filter((item): item is string => typeof item === "string")
        : [];
  return scopes.length > 0 ? { scopes } : undefined;
}
