import type { Rule } from "./rules.ts";

import { catalogOf, qualified, tableObject } from "./shared.ts";

/** The comment `topic.trigger(..., { payload: "row" })` puts on its function. */
const ROW_PAYLOAD_MARKER = "better-supabase: payload row";

const BROADCAST_ROW =
  /realtime\.broadcast_changes\s*\([^;]*\b(?:new|old)\b|'old_record'/i;

/** Whether a trigger function body sends `new` or `old` whole. */
function sendsWholeRow(source: string): boolean {
  return BROADCAST_ROW.test(source.replaceAll(/--[^\n]*/g, ""));
}

/** Realtime checks that read the trigger functions in the snapshot. */
export const REALTIME_RULES: readonly Rule[] = [
  {
    code: "BS337",
    severity: "warning",
    title: "Broadcast trigger sends whole rows",
    description:
      'A trigger function sends the whole row to Realtime with `realtime.broadcast_changes(..., new, old)` or `old_record` and `record`, and has no `payload: "row"` marker. Subscribers then see every column, including ones their column grants hide.',
    check: (context) =>
      catalogOf(context).tables.flatMap((table) =>
        table.triggers
          .filter(
            (trigger) =>
              trigger.source !== undefined &&
              trigger.comment !== ROW_PAYLOAD_MARKER &&
              sendsWholeRow(trigger.source),
          )
          .map((trigger) => ({
            message: `${trigger.name} on ${qualified(table)} calls ${trigger.function}(), which broadcasts whole rows. Regenerate it with \`topic.trigger()\`, whose default payload sends the primary key and the topic values, or pass \`payload: "row"\` to keep whole rows on purpose.`,
            target: `${qualified(table)}.${trigger.name}`,
            object: tableObject(table),
          })),
      ),
  },
];
