import type { AuthSession } from "./view.ts";

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
  if (session.kind !== "user") return;
  const { impersonator } = session;
  const sessionId = impersonator?.sessionId;
  if (!impersonator || !sessionId) return;
  return {
    sessionId,
    adminId: impersonator.id,
    targetUserId: session.user.id,
    ...(impersonator.reason ? { reason: impersonator.reason } : {}),
    readOnly: impersonator.readOnly ?? true,
    expiresAt: session.expiresAt,
  };
}
