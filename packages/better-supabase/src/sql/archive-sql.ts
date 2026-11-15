import type { BlockSqlContext } from "./context.ts";

import { filterAny, filterSet } from "./list-template.ts";
import { userGrant } from "./shared.ts";

/** What `archiveRestoreFunctions` needs from the module that owns the entity. */
export interface ArchiveSpec {
  /** The entity singular: `maintenance_plan` gives `archive_maintenance_plan`. */
  readonly entity: string;
  /** The name of the function's argument, which is also the lookup's. */
  readonly arg: string;
  /** The SQL type of `v_row`, such as the quoted table name. */
  readonly rowType: string;
  /** The quoted `id`, `archivedAt` and optional `updatedAt` columns. */
  readonly id: string;
  readonly archivedAt: string;
  readonly updatedAt?: string;
  readonly table: string;
  /**
   * Loads `v_row` for update and refuses a missing row or a caller without
   * permission. `fn` is the function name, for qualifying the argument.
   */
  readonly load: (fn: string) => string;
  /** An extra refusal before an archive (the row is still in use). */
  readonly beforeArchive?: string;
  /** An extra refusal before a restore (the row would clash with another). */
  readonly beforeRestore?: string;
  /** The JSON of `v_row` the function returns. */
  readonly json: string;
  /** The `ctx.record` statement for an event type, over `v_row`. */
  readonly record: (type: string) => string;
  /** The text of the function's comment, past tense is not needed. */
  readonly archiveNote: string;
  readonly restoreNote: string;
  /** `declare` lines beyond `v_row`. */
  readonly declare?: string;
  readonly returns?: "jsonb";
}

/**
 * `archive_<entity>` and `restore_<entity>`: each sets or clears `archived_at`,
 * records `<entity>.archived` or `<entity>.restored` once and does nothing when
 * the row is already in that state (ADR 0839, ADR 1041).
 */
export function archiveRestoreFunctions(
  ctx: BlockSqlContext,
  spec: ArchiveSpec,
): string {
  return (["archive", "restore"] as const)
    .map((verb) => {
      const name = ctx.fn(`${verb}_${spec.entity}`);
      const past = verb === "archive" ? "archived" : "restored";

      return `
-- ${verb === "archive" ? spec.archiveNote : spec.restoreNote}
create or replace function ${name}(${spec.arg} uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${spec.rowType};${spec.declare ?? ""}
begin
  ${spec.load(`${verb}_${spec.entity}`)}
  if v_row.${spec.archivedAt} ${verb === "archive" ? "is not null" : "is null"} then
    return ${spec.json};
  end if;${verb === "archive" ? (spec.beforeArchive ?? "") : (spec.beforeRestore ?? "")}
  update ${spec.table} x set
    ${spec.archivedAt} = ${verb === "archive" ? "now()" : "null"}${spec.updatedAt ? `,\n    ${spec.updatedAt} = now()` : ""}
  where x.${spec.id} = v_row.${spec.id}
  returning * into v_row;
  ${spec.record(`${spec.entity}.${past}`)}
  return ${spec.json};
end;
$$;
${userGrant(`${name}(uuid)`)}
`;
    })
    .join("");
}

/** The two contract entries of `archiveRestoreFunctions`. */
export const archiveRestoreContract = (
  entity: string,
): readonly { name: string; args: string[]; returns: string }[] => [
  { name: `archive_${entity}`, args: ["uuid"], returns: "jsonb" },
  { name: `restore_${entity}`, args: ["uuid"], returns: "jsonb" },
];

/**
 * The list predicate that hides archived rows, and with the `archived` filter
 * lists them (`true` lists the archived ones only).
 */
export const archivedListFilter = (alias: string, column: string): string =>
  `(case when ${filterSet("archived")} then ${filterAny("archived", `(${alias}.${column} is not null)::text`)} else ${alias}.${column} is null end)`;
