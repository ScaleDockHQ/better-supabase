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
    recipes: ["sessions-list"],
  });
