import type { DbError } from "../core/errors.ts";

import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";

/** One level of an RFC 8693 `act` chain: who acts, and who acted before it. */
export interface ActClaim {
  readonly sub: string;
  readonly act?: ActClaim;
  readonly [claim: string]: unknown;
}

/**
 * Who acts for the user, from the outermost level of the RFC 8693 `act` claim,
 * by its `kind`:
 *
 * - `oauth-client`: an `act` without `kind` (prior actors stay on `chain`), else
 *   the OAuth `client_id` of a Supabase OAuth server token. Only this kind is
 *   limited to the scopes the user delegated.
 * - `support`: an admin in a support session (`act.kind: "support"`, from
 *   `supportClaims`). An `act` without `kind` but with `session_id`, as 0.5.0
 *   minted it, is an invalid chain.
 * - `impersonation`: an admin acting as the user (`act.kind: "impersonation"`,
 *   from `actClaim`).
 * - `agent`: an AI agent running tools for the user (`act.kind: "agent"`, from
 *   `agentClaims`). Its writes run under the user's permissions, and a token
 *   that also carries a `scope` limits it to those scopes.
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
    }
  | {
      readonly kind: "agent";
      readonly id: string;
      /**
       * `act.tools`: the tools the run may call. Missing means every tool; `[]`
       * means none.
       */
      readonly tools?: readonly string[];
      /** `act.read_only`; an agent without it may write as the user. */
      readonly readOnly: boolean;
      /** The full `act` level, with whoever acted before the agent. */
      readonly chain: ActClaim;
    };

/** What the user delegated to the actor: the token's OAuth `scope`. */
export interface SessionDelegation {
  readonly scopes: readonly string[];
  readonly chain?: ActClaim;
}

export type ActorOutcome =
  | { readonly ok: true; readonly actor?: SessionActor }
  | { readonly ok: false; readonly reason: "invalid-chain" };

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

function isString(value: unknown): value is string {
  return typeof value === "string";
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

  if (kind === "support") {
    if (typeof sessionId !== "string" || sessionId === "") {
      return INVALID;
    }

    if (readOnly !== undefined && typeof readOnly !== "boolean") {
      return INVALID;
    }

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

  if (kind === "agent") {
    if (sessionId !== undefined) {
      return INVALID;
    }

    const tools = outer["tools"];

    if (readOnly !== undefined && typeof readOnly !== "boolean") {
      return INVALID;
    }

    if (
      tools !== undefined &&
      !(
        Array.isArray(tools) &&
        tools.every((tool) => typeof tool === "string" && tool !== "")
      )
    ) {
      return INVALID;
    }

    return {
      ok: true,
      actor: {
        kind: "agent",
        id,
        ...(Array.isArray(tools) ? { tools: tools.filter(isString) } : {}),
        readOnly: readOnly ?? false,
        chain: copyAct(outer),
      },
    };
  }

  if (kind !== undefined || sessionId !== undefined) {
    return INVALID;
  }

  return {
    ok: true,
    actor: { kind: "oauth-client", id, chain: copyAct(outer) },
  };
}

/**
 * Reads only `act` and `client_id`. An `act` that is not a chain of objects
 * each with a non-empty `sub`, a `kind` other than `support`, `impersonation`
 * or `agent`, a support level without a `session_id`, an agent level whose
 * `tools` is not a list of names, a non-boolean `read_only` on a support or
 * agent level, or a `session_id` without `kind` is `{ ok: false }`: the session
 * must not pass as the user alone.
 */
export function actorOf(
  claims: Readonly<Record<string, unknown>>,
): ActorOutcome {
  const outer = claims["act"];

  if (outer !== undefined) {
    if (!isRecord(outer)) {
      return INVALID;
    }

    const id = outer["sub"];

    if (typeof id !== "string" || id === "") {
      return INVALID;
    }

    let level: unknown = outer["act"];

    while (level !== undefined) {
      if (!isRecord(level)) {
        return INVALID;
      }

      const sub = level["sub"];

      if (typeof sub !== "string" || sub === "") {
        return INVALID;
      }

      level = level["act"];
    }

    return actorAt(outer, id);
  }

  const client = claims["client_id"];

  if (typeof client === "string" && client !== "") {
    return { ok: true, actor: { id: client, kind: "oauth-client" } };
  }

  return { ok: true };
}

/**
 * `agentClaims(claims, { agent, tools, readOnly })`: the agent that acts, and
 * what it may do.
 */
export interface AgentActOptions {
  readonly agent: string;
  /** The tools the run may call. Leave it out for every tool; `[]` allows none. */
  readonly tools?: readonly string[];
  /** Writes `read_only: true`, so `actor_may_write()` refuses the run's writes. */
  readonly readOnly?: boolean;
}

/**
 * The user's claims with the agent as the outermost `act` level. An `act`
 * already on the claims (an OAuth client, say) moves below it, so the run keeps
 * the user's delegation. Pass the result to `asUser` or `forContext` for the
 * agent's database calls.
 */
export function agentClaims<C extends Readonly<Record<string, unknown>>>(
  claims: C,
  options: AgentActOptions,
): C & { readonly act: ActClaim } {
  const prior = claims["act"];

  const act: ActClaim = {
    kind: "agent",
    sub: options.agent,
    ...(options.tools === undefined ? {} : { tools: [...options.tools] }),
    ...(options.readOnly === undefined ? {} : { read_only: options.readOnly }),
    ...(isRecord(prior) ? { act: copyAct(prior) } : {}),
  };

  return { ...claims, act };
}

/** The 401 for a session whose `act` claim `actorOf` refuses (`ACTOR_INVALID`). */
export function invalidActorError(): DbError {
  return dbError(
    "unauthorized",
    "The token's act claim is not a valid chain of actors: every level needs a sub, and kind must be support, impersonation, agent or absent",
    { code: "ACTOR_INVALID" },
  );
}

/**
 * OpenID Connect scopes that ask for identity claims or a refresh token. They
 * grant no permission, so `delegationOf` leaves them out.
 */
export const IDENTITY_SCOPES: ReadonlySet<string> = new Set([
  "openid",
  "email",
  "profile",
  "phone",
  "address",
  "offline_access",
]);

/**
 * The OAuth `scope` claim (a space-separated string or a list), without
 * `IDENTITY_SCOPES`. `undefined` when the token names no scope. A token that
 * names only identity scopes gets `{ scopes: [] }`, so an actor limited to its
 * delegation stays limited.
 */
export function delegationOf(
  claims: Readonly<Record<string, unknown>>,
): SessionDelegation | undefined {
  const scope = claims["scope"];

  const named =
    typeof scope === "string"
      ? scope.split(/\s+/u).filter(Boolean)
      : Array.isArray(scope)
        ? scope.filter(
            (item): item is string => typeof item === "string" && item !== "",
          )
        : [];

  if (named.length === 0) {
    return undefined;
  }

  return { scopes: named.filter((item) => !IDENTITY_SCOPES.has(item)) };
}
