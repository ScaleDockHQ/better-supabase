import type { AuthSession } from "./view.ts";

/**
 * The `digest` of every `SupportUnavailableError`. Next.js keeps an error's own
 * digest, so an `error.tsx` boundary can match it.
 */
export const SUPPORT_UNAVAILABLE_DIGEST = "SUPPORT_SESSION_UNAVAILABLE";

/** The shape of a support session id: a UUID, as every store must return. */
export const SUPPORT_SESSION_ID: RegExp =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** A running support session as the target's view shows it, for a banner. */
export interface SupportView {
  readonly sessionId: string;
  /** The admin viewing the app. */
  readonly adminId: string;
  readonly targetUserId: string;
  readonly reason?: string;
  readonly readOnly: boolean;
  /** Seconds since epoch. */
  readonly expiresAt: number | null;
}

/** The support session behind `session`, or `undefined` outside one. */
export function supportOf(session: AuthSession): SupportView | undefined {
  if (session.kind !== "user") {
    return;
  }

  const { impersonator } = session;
  const sessionId = impersonator?.sessionId;

  if (!impersonator || !sessionId) {
    return;
  }

  return {
    sessionId,
    adminId: impersonator.id,
    targetUserId: session.user.id,
    ...(impersonator.reason ? { reason: impersonator.reason } : {}),
    readOnly: impersonator.readOnly ?? true,
    expiresAt: session.expiresAt,
  };
}
