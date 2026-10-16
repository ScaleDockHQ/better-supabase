import type { BlockOf } from "../define-block.ts";
import type { PushEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { pushEvents } from "./events.ts";
import { pushSqlOptions } from "./options.ts";
import { createPush } from "./push.ts";

/** The `push` block's manifest (ADR 0029). */
export const pushBlock: BlockOf<"push", typeof createPush, PushEvents> =
  defineBlock({
    name: "push",
    sql: ["push"],
    options: { push: pushSqlOptions },
    events: pushEvents,
    create: createPush,
    category: "collaboration",
  });
