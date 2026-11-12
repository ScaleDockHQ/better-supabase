import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { sessionsSqlOptions } from "./options.ts";
import { createSessions } from "./sessions.ts";

/** The `sessions` block's manifest (ADR 0029). */
export const sessionsBlock: BlockOf<"sessions", typeof createSessions> =
  defineBlock({
    name: "sessions",
    sql: ["sessions"],
    options: { sessions: sessionsSqlOptions },
    create: createSessions,
    category: "identity",
    entities: { session: { mutability: "read-only" } },
    description:
      "session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.",
    recipes: ["sessions-list"],
  });
