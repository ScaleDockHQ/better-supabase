import type { Actor, RequestContext } from "../core/plugin.ts";

import { actorOf } from "./actor.ts";

/** The admin acting as the user, from the RFC 8693 `act` claim. */
export interface Impersonator {
  /** `act.kind`: a support session or an impersonated session. */
  readonly kind: "support" | "impersonation";
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
  readonly kind: "impersonation";
  readonly sub: string;
  readonly reason: string;
} {
  return { kind: "impersonation", sub: options.actor, reason: options.reason };
}

/**
 * The admin in `claims.act`: a support session or an impersonated session
 * (`actorOf` reads the same level, so the two always agree). `undefined`
 * for a normal session, an OAuth client or agent chain, and an invalid `act`.
 */
export function impersonatorOf(
  claims: Readonly<Record<string, unknown>>,
): Impersonator | undefined {
  const outcome = actorOf(claims);
  const actor = outcome.ok ? outcome.actor : undefined;
  if (actor === undefined) return undefined;
  switch (actor.kind) {
    case "oauth-client":
      return undefined;
    case "support":
    case "impersonation":
      return { ...actor };
    default: {
      const unreachable: never = actor;
      return unreachable;
    }
  }
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
