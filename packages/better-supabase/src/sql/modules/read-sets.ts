import type { SqlModule } from "../module-types.ts";

export const READ_SETS: SqlModule = {
  name: "read-sets",
  title: "Read sets",
  description:
    "One `stable` function per `defineReadSet` in `readSets`, so `db.$many(readSet, params)` is a single GET.",
  requires: [],
  target: "schema",
  sql: `-- Functions for the read sets in \`readSets\` (better-supabase.config.ts); \`gen\` and \`sql sync\` rewrite them.
-- They are security invoker: RLS decides what each caller reads, as for any other query.`,
  extras: (_ctx, layout) => {
    const sets = layout.readSets ?? [];
    if (sets.length === 0) return "";
    return `\n-- config.readSets\n${sets.map((set) => `-- ${set.name}\n${set.sql}`).join("\n\n")}\n`;
  },
};
