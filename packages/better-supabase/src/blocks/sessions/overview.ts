import type { SessionsOverviewRaw } from "../../sql/modules/sessions-reads.ts";

import { decodeRead } from "../../core/read-type.ts";
import { SESSIONS_OVERVIEW_RESULT } from "../../sql/modules/sessions-reads.ts";
import { optionalInstant } from "../shared.ts";

/** One of the caller's sessions, as `sessions.overview` returns it. */
export interface SessionsOverviewEntry {
  readonly id: string;
  readonly createdAt: Temporal.Instant | undefined;
  readonly lastActiveAt: Temporal.Instant | undefined;
  readonly userAgent: string | null;
  readonly ip: string | null;
  readonly aal: string | null;
  /** The session behind the token that made the call. */
  readonly current: boolean;
}

/** What `sessions.overview` returns. */
export interface SessionsOverview {
  readonly count: number;
  /** The id of the current session, or `null` for a token without one. */
  readonly currentId: string | null;
  /** Most recently active first. */
  readonly sessions: readonly SessionsOverviewEntry[];
}

export function decodeSessionsOverview(value: unknown): SessionsOverview {
  const raw = decodeRead<SessionsOverviewRaw>(
    SESSIONS_OVERVIEW_RESULT,
    value,
    "sessions_overview",
  );

  return {
    count: raw.count,
    currentId: raw.currentId,
    sessions: raw.sessions.map((session) => ({
      ...session,
      createdAt: optionalInstant(session.createdAt),
      lastActiveAt: optionalInstant(session.lastActiveAt),
    })),
  };
}
