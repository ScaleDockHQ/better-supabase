import type { BlockSqlContext } from "../context.ts";

import {
  currentEventTypes,
  EVENT_TYPE_RENAMES,
  EVENT_TYPE_SPLITS,
  PROGRAM_EVENT_MOVES,
} from "../../core/renames.ts";
import { sqlString } from "../../core/template.ts";

/**
 * Each old type or pattern as a block stores it (after the app's entity
 * renames) and the types a subscriber to it needs now, which a renamed entity
 * names after the app's noun (`ticket.created`, from `work_item.created`).
 */
function typeMoves(
  ctx: BlockSqlContext,
): readonly { readonly old: string; readonly next: readonly string[] }[] {
  const naming = ctx.blockNaming();
  const events = ctx.blockEventNaming();

  return [
    ...new Set([
      ...Object.keys(EVENT_TYPE_RENAMES),
      ...Object.keys(EVENT_TYPE_SPLITS),
      ...Object.keys(PROGRAM_EVENT_MOVES),
    ]),
  ]
    .toSorted()
    .flatMap((type) => {
      const old = naming.rename(type);

      const next = currentEventTypes(type)
        .map((each) => events.rename(each))
        .filter((each) => each !== old);

      return next.length === 0 ? [] : [{ old, next }];
    });
}

/** The one-to-one renames of concrete types, as stored rows hold them. */
function typeRenames(
  ctx: BlockSqlContext,
): readonly { readonly old: string; readonly next: string }[] {
  const naming = ctx.blockNaming();
  const events = ctx.blockEventNaming();

  return [
    ...Object.entries(EVENT_TYPE_RENAMES),
    ...Object.entries(PROGRAM_EVENT_MOVES).map(
      ([old, moved]) => [old, moved.type] as const,
    ),
  ]
    .filter(([old]) => !old.endsWith(".*"))
    .toSorted(([a], [b]) => a.localeCompare(b))
    .map(([old, next]) => ({
      old: naming.rename(old),
      next: events.rename(next),
    }))
    .filter(({ old, next }) => old !== next);
}

/**
 * Renames the 0.47 event types (ADR 0130) stored in `column` of `table`, one to
 * one. Split types such as `agent.saved` stay: a stored row can't tell whether
 * it was a create or an update.
 */
export function storedTypeRenames(
  ctx: BlockSqlContext,
  table: string,
  column: string,
): string {
  const renames = typeRenames(ctx);

  if (renames.length === 0) {
    return "";
  }

  const values = renames
    .map(({ old, next }) => `  (${sqlString(old)}, ${sqlString(next)})`)
    .join(",\n");

  return `update ${table} t set ${column} = m.next_type
from (values
${values}
) as m(old_type, next_type)
where t.${column} = m.old_type;`;
}

/**
 * Adds, to each `text[]` list of type patterns in `column` of `table`, the 0.47
 * types (ADR 0130) its old entries stand for. The old entries stay, so a relay
 * with `legacyEventTypes` still matches them.
 */
export function typeListRenames(
  ctx: BlockSqlContext,
  table: string,
  column: string,
): string {
  const moves = typeMoves(ctx);

  if (moves.length === 0) {
    return "";
  }

  const values = moves
    .map(
      ({ old, next }) =>
        `  (${sqlString(old)}, array[${next.map(sqlString).join(", ")}]::text[])`,
    )
    .join(",\n");

  return `with m(old_type, next_types) as (values
${values}
)
update ${table} t set ${column} = array(
  select distinct x from unnest(t.${column} || array(
    select n from unnest(t.${column}) o join m on m.old_type = o
    cross join unnest(m.next_types) n
  )) x order by x
)
where t.${column} && array(select old_type from m);`;
}

/** A data step's statements under one comment, or nothing when none apply. */
export function eventTypeData(statements: readonly string[]): string {
  const sql = statements.filter((each) => each !== "");

  return sql.length === 0
    ? ""
    : `-- Event types renamed by the 0.47 naming convention (ADR 0130).
${sql.join("\n\n")}`;
}

/** One-to-one renames of the stored types in each `[table, column]`. */
export const storedTypesData = (
  ctx: BlockSqlContext,
  columns: readonly (readonly [string, string])[],
): string =>
  eventTypeData(
    columns.map(([table, column]) =>
      storedTypeRenames(ctx, ctx.table(table), ctx.col(table, column)),
    ),
  );
