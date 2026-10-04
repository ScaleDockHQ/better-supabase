import type { Actor, RequestContext } from "../core/plugin.ts";

/** The admin acting as the user, from the RFC 8693 `act` claim. */
export interface Impersonator {
  readonly id: string;
  readonly reason?: string;
  /** The support session, when the admin started one (`act.session_id`). */
  readonly sessionId?: string;
  /** Whether the support session blocks writes (`act.read_only`). */
  readonly readOnly?: boolean;
}

/** `actingAs(userId, claims, { actor, reason })`: who acts, and why (recorded by the audit module). */
export interface ImpersonationOptions {
  readonly actor: string;
  readonly reason: string;
}

/** The `act` claim for an impersonated session. */
export function actClaim(options: ImpersonationOptions): {
  readonly sub: string;
  readonly reason: string;
} {
  return { sub: options.actor, reason: options.reason };
}

/** The impersonator in `claims.act`, or `undefined` for a normal session. */
export function impersonatorOf(
  claims: Readonly<Record<string, unknown>>,
): Impersonator | undefined {
  const act = claims["act"];
  if (typeof act !== "object" || act === null) return undefined;
  // SAFETY: the check above narrows act to a non-null object; each field is checked below.
  const { sub, reason, session_id, read_only } = act as Record<string, unknown>;
  if (typeof sub !== "string" || sub === "") return undefined;
  return {
    id: sub,
    ...(typeof reason === "string" ? { reason } : {}),
    ...(typeof session_id === "string" ? { sessionId: session_id } : {}),
    ...(typeof read_only === "boolean" ? { readOnly: read_only } : {}),
  };
}

/**
 * The repository context of a signed-in user: the actor, with the
 * impersonator from `act`, and the claims. Every adapter builds it here, so
 * plugins see the same actor on the server, in middleware and in the browser.
 */
export function userContext(
  user: {
    readonly id: string;
    readonly role?: string | undefined;
    readonly email?: string | undefined;
  },
  claims: Readonly<Record<string, unknown>>,
): RequestContext {
  const impersonator = impersonatorOf(claims);
  const actor: Actor = {
    id: user.id,
    kind: "user",
    ...(user.role ? { role: user.role } : {}),
    ...(user.email ? { email: user.email } : {}),
    ...(impersonator ? { impersonator: impersonator.id } : {}),
  };
  return { actor, claims };
}
