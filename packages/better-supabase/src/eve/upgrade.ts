import type { EveOpenSession, EveSessionStore } from "./store.ts";

export interface OpenSessionsOptions {
  /** The store from `world.eveSessions`. */
  readonly store: Pick<EveSessionStore, "open">;
  /**
   * The eve version of the deployment you are moving to. Sessions that run it
   * are left out, so the list is what the upgrade has to deal with.
   */
  readonly notVersion?: string;
  readonly tenantId?: string;
  /** 1 to 1000, default 100. */
  readonly limit?: number;
}

/**
 * The open sessions started on another eve version than `notVersion`, oldest
 * first. A session keeps the version it started on, so this is the list to
 * drain, or to end with `endStrandedSessions`, before a version that cannot
 * resume them goes live.
 */
export function openSessions(
  options: OpenSessionsOptions,
): Promise<readonly EveOpenSession[]> {
  const { store, ...rest } = options;

  return store.open(rest);
}

export interface EndStrandedSessionsOptions extends OpenSessionsOptions {
  readonly store: Pick<EveSessionStore, "open" | "mark">;
  /**
   * Cancels the run of each session in eve (for example with
   * `world.runs.cancel`), so no worker resumes it. Without it the sessions are
   * only marked.
   */
  readonly cancelRun?: (session: EveOpenSession) => Promise<void>;
  /** Lists nothing and changes nothing; resolves with the sessions it would end. */
  readonly dryRun?: boolean;
}

export interface EndStrandedSessionsResult {
  readonly sessions: readonly EveOpenSession[];
  /** The sessions marked `stranded`; empty on a dry run. */
  readonly ended: number;
}

/**
 * Marks the open sessions of an older eve version `stranded`, so the sync
 * writes their last state and they stay readable, then cancels their runs when
 * `cancelRun` is set. Run it from the deploy that moves traffic to the new
 * version.
 */
export async function endStrandedSessions(
  options: EndStrandedSessionsOptions,
): Promise<EndStrandedSessionsResult> {
  const sessions = await openSessions(options);

  if (options.dryRun === true) {
    return { sessions, ended: 0 };
  }

  let ended = 0;

  for (const session of sessions) {
    await options.cancelRun?.(session);

    if (await options.store.mark(session.sessionId, "stranded")) {
      ended += 1;
    }
  }

  return { sessions, ended };
}
