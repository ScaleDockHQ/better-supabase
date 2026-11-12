import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `realtime-tables` block's manifest (ADR 0029). */
export const realtimeTablesBlock: Block<"realtime-tables"> = defineBlock({
  name: "realtime-tables",
  sql: ["realtime-tables"],
  category: "database",
  entities: { realtime_table: { mutability: "read-only" } },
  description:
    "Broadcasts a change signal (no row data) once per statement on bsb:t:<schema>.<table>[:<tenant>], or bsb:t:<schema>.<table>:u:<user> for realtime.users tables, for live queries.",
});
