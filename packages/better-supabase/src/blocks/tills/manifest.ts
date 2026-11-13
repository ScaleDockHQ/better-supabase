import type { BlockOf } from "../define-block.ts";
import type { TillsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { tillsEvents } from "./events.ts";
import { tillSessionListSurface } from "./lists.ts";
import { tillInputSchema } from "./schemas.ts";
import { createTills } from "./tills.ts";

/** The `tills` block's manifest (ADR 0029). */
export const tillsBlock: BlockOf<"tills", typeof createTills, TillsEvents> =
  defineBlock({
    name: "tills",
    sql: ["tills"],
    events: tillsEvents,
    schemas: { till: { input: tillInputSchema } },
    create: createTills,
    recipes: [],
    category: "commerce",
    entities: {
      till: { mutability: "editable", emits: { create: true, update: true } },
      till_session: {
        ...tillSessionListSurface,
        mutability: "state-machine",
        emits: { create: false },
      },
      till_movement: { mutability: "append-only", emits: { create: true } },
      till_count: { mutability: "read-only" },
      till_deposit: { mutability: "state-machine", emits: { create: true } },
    },
    concerns: ["lifecycle", "search"],
    description:
      "Till sessions with an opening float, cash in and out, end-of-day counts that book their difference in accounting, and cash deposits that reconcile to bank transactions.",
  });
