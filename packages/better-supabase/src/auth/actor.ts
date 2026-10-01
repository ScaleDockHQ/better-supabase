/** One level of an RFC 8693 `act` chain: who acts, and who acted before it. */
export interface ActClaim {
  readonly sub: string;
  readonly act?: ActClaim;
  readonly [claim: string]: unknown;
}

/**
 * The app acting for the user: the outermost `sub` of an RFC 8693 `act`
 * chain (prior actors stay on `chain`), else the OAuth `client_id` of a
 * Supabase OAuth server token.
 */
export interface SessionActor {
  readonly id: string;
  readonly kind: "oauth-client";
  readonly chain?: ActClaim;
}

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

/**
 * Reads only `act` and `client_id`, the way PermDock's `actorOf` does. An
 * `act` that is not a chain of objects each with a non-empty `sub` is
 * `{ ok: false }`: the session must not pass as the user alone.
 */
export function actorOf(
  claims: Readonly<Record<string, unknown>>,
): ActorOutcome {
  const outer = claims["act"];
  if (outer !== undefined) {
    let level: unknown = outer;
    while (level !== undefined) {
      if (!isRecord(level)) return { ok: false, reason: "invalid-chain" };
      const sub = level["sub"];
      if (typeof sub !== "string" || sub === "")
        return { ok: false, reason: "invalid-chain" };
      level = level["act"];
    }
    if (!isRecord(outer) || typeof outer["sub"] !== "string")
      return { ok: false, reason: "invalid-chain" };
    return {
      ok: true,
      actor: { id: outer["sub"], kind: "oauth-client", chain: copyAct(outer) },
    };
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
