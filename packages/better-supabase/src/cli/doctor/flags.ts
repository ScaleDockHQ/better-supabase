import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { expiredFlagsQuery, moduleLayout } from "../../sql/index.ts";

/** Flags past their `expires_at` extra column that aren't archived. */
async function expiredFlags(context: DoctorContext): Promise<FindingInput[]> {
  const db = context.database;

  if (!db || "skipped" in db) {
    return [];
  }

  let query: string | undefined;

  try {
    query = expiredFlagsQuery(
      moduleLayout(context.config),
      context.config.blockNames,
    );
  } catch {
    return [];
  }

  if (!query) {
    return [];
  }

  let rows: { key: string; expires_at: string; owner: string | null }[];

  try {
    rows = await db.query(query);
  } catch {
    return [];
  }

  return rows.map((row) => ({
    message: `Flag "${row.key}" expired on ${row.expires_at}${row.owner ? ` (owner: ${row.owner})` : ""}. Remove its checks from the code, then archive it with \`flags.save("${row.key}", { archived: true })\`, or move \`expires_at\` when it stays.`,
    target: `flags:${row.key}`,
  }));
}

export const FLAG_RULES: readonly Rule[] = [
  {
    code: "BS336",
    severity: "warning",
    title: "Flag past its expiry",
    description:
      "The flags table has an `expires_at` column (`blocks.flags.options.extraColumns`), and a flag on the live database that isn't archived has an `expires_at` in the past. A release flag that outlives its rollout keeps a dead branch in the code. The finding names the `owner` column when the table has one.",
    check: expiredFlags,
  },
];
