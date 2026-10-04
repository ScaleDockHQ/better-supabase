import type {
  SupportSession,
  SupportSessionStore,
} from "../../src/auth/support.ts";

/** An in-memory `SupportSessionStore` for unit tests. */
export function memorySupportStore(
  claims: Readonly<Record<string, Readonly<Record<string, unknown>>>> = {},
): SupportSessionStore & { readonly sessions: Map<string, SupportSession> } {
  const sessions = new Map<string, SupportSession>();
  let next = 0;
  const running = (session: SupportSession) =>
    session.endedAt === undefined &&
    session.expiresAt.epochMilliseconds > Date.now();
  const endSession = (
    session: SupportSession,
    endedBy: NonNullable<SupportSession["endedBy"]>,
  ) => {
    sessions.set(session.id, {
      ...session,
      endedAt: Temporal.Now.instant(),
      endedBy,
    });
  };
  return {
    apiVersion: 1,
    name: "memory",
    sessions,
    start(input) {
      for (const session of sessions.values()) {
        if (session.adminId === input.adminId && running(session)) {
          endSession(session, "admin");
        }
      }
      next += 1;
      const startedAt = Temporal.Now.instant();
      const session: SupportSession = {
        id: `00000000-0000-4000-8000-${String(next).padStart(12, "0")}`,
        adminId: input.adminId,
        targetUserId: input.targetUserId,
        reason: input.reason,
        readOnly: input.readOnly,
        ...(input.tenant === undefined ? {} : { tenant: input.tenant }),
        startedAt,
        expiresAt: startedAt.add({ seconds: input.ttlSeconds }),
        metadata: input.metadata,
      };
      sessions.set(session.id, session);
      return Promise.resolve(session);
    },
    get(sessionId, adminId) {
      const session = sessions.get(sessionId);
      return Promise.resolve(
        session?.adminId === adminId && running(session) ? session : undefined,
      );
    },
    end(sessionId, endedBy) {
      const session = sessions.get(sessionId);
      if (!session || session.endedAt !== undefined) {
        return Promise.resolve(false);
      }
      endSession(session, endedBy);
      return Promise.resolve(true);
    },
    list(filter = {}) {
      return Promise.resolve(
        [...sessions.values()]
          .filter(
            (session) =>
              (filter.adminId === undefined ||
                session.adminId === filter.adminId) &&
              (filter.targetUserId === undefined ||
                session.targetUserId === filter.targetUserId) &&
              (filter.active === undefined ||
                filter.active === running(session)),
          )
          .slice(0, filter.limit ?? 50),
      );
    },
    claims(targetUserId) {
      return Promise.resolve(claims[targetUserId] ?? { role: "authenticated" });
    },
  };
}
