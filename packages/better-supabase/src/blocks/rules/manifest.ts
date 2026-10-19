import type { BlockOf } from "../define-block.ts";
import type { RulesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { rulesEvents } from "./events.ts";
import { rulesSqlOptions } from "./options.ts";
import { createRules } from "./rules.ts";

/** The `rules` block's manifest (ADR 0029). */
export const rulesBlock: BlockOf<"rules", typeof createRules, RulesEvents> =
  defineBlock({
    name: "rules",
    sql: ["rules"],
    options: {
      rules: rulesSqlOptions,
    },
    events: rulesEvents,
    create: createRules,
    category: "automation",
  });
