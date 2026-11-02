import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockOptions } from "../shared.ts";
import type { SessionsOverview } from "./overview.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  nullableText,
  optionalInstant,
  recordsOf,
  textOf,
} from "../shared.ts";
import { decodeSessionsOverview } from "./overview.ts";

export interface SessionsOptions extends BlockOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Sessions>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** One of the caller's unexpired sessions, as `list_my_sessions` returns it. */
export interface UserSession {
  readonly id: string;
  readonly createdAt: Temporal.Instant | undefined;
  readonly lastActiveAt: Temporal.Instant | undefined;
  readonly userAgent: string | null;
  readonly ip: string | null;
  readonly aal: string | null;
  /** The session behind the token that made the call. */
  readonly current: boolean;
}

export interface Sessions {
  /** The caller's unexpired sessions, most recently active first. */
  listMine(): AsyncResult<readonly UserSession[]>;
  /**
   * The caller's security page in one `sessions_overview` call: the sessions,
   * how many there are and the id of the current one.
   */
  overview(): AsyncResult<SessionsOverview>;
  /**
   * Ends one of the caller's sessions. Its refresh tokens stop working at once;
   * an access token it holds lasts until it expires, unless a policy calls
   * `session_active()`. `false` when the caller has no such session.
   */
  end(input: { sessionId: string }): AsyncResult<boolean>;
  /**
   * Ends every session of the caller except the current one; returns the ids it
   * ended. It calls `end` for each, so `end` hooks see every session.
   */
  endOthers(): AsyncResult<readonly string[]>;
}

function sessionOf(row: Readonly<Record<string, unknown>>): UserSession {
  return {
    id: textOf(row["id"]),
    createdAt: optionalInstant(row["createdAt"]),
    lastActiveAt: optionalInstant(row["lastActiveAt"]),
    userAgent: nullableText(row["userAgent"]),
    ip: nullableText(row["ip"]),
    aal: nullableText(row["aal"]),
    current: row["current"] === true,
  };
}

/**
 * The `sessions` SQL module as typed calls: the caller's own sessions, listed
 * and ended through `list_my_sessions` and `end_my_session`.
 */
export function createSessions(options: SessionsOptions): Sessions {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: Sessions = {
    listMine: () =>
      call("list_my_sessions", {}, (value) =>
        recordsOf(value, "list_my_sessions").map(sessionOf),
      ),
    overview: () => call("sessions_overview", {}, decodeSessionsOverview),
    end: ({ sessionId }) =>
      call("end_my_session", { session: sessionId }, (value) => value === true),
    endOthers: () =>
      AsyncResult.from(async () => {
        const sessions = await hooked.listMine();

        if (!sessions.ok) {
          return sessions;
        }

        const ended: string[] = [];

        for (const session of sessions.data) {
          if (session.current) {
            continue;
          }

          const result = await hooked.end({ sessionId: session.id });

          if (!result.ok) {
            return result;
          }

          if (result.data) {
            ended.push(session.id);
          }
        }

        return ok(ended);
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Sessions = withBlockHooks(client, options.hooks, {
    block: "sessions",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
