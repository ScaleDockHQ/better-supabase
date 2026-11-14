import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, fail } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** One module table an erasure reaches. */
interface EraseEntry {
  /** `schema.table`, unquoted, for the result keys. */
  readonly name: string;
  readonly table: string;
  readonly mode: "delete" | "anonymize" | "keep";
  readonly retention: string;
  readonly tenant: string;
  readonly type: string;
  readonly id: string;
  /** Quoted columns an `anonymize` blanks. */
  readonly personal: readonly string[];
}

/** The hold kind an entry uses when it declares no retention class. */
export const ERASE_DEFAULT_KIND = "personal_data";

/**
 * The tables an erasure reaches (ADR 0903): every installed module table whose
 * `lifecycle.erase` names a mode, has a tenant column and the `subjectType` and
 * `subjectId` columns. A column the module does not create is left out.
 */
function eraseEntries(ctx: BlockSqlContext): readonly EraseEntry[] {
  const list: EraseEntry[] = [];

  for (const module of ctx.installedModules) {
    const of = ctx.of(module);

    for (const [logical, spec] of Object.entries(of.names.tables)) {
      const erase = spec.lifecycle?.erase;
      const tenant = spec.lifecycle?.tenant;

      if (
        erase === undefined ||
        tenant === undefined ||
        !of.hasTable(logical) ||
        !of.has(logical, tenant) ||
        !of.has(logical, "subjectType") ||
        !of.has(logical, "subjectId")
      ) {
        continue;
      }

      const { schema, name } = of.tableName(logical);

      list.push({
        name: `${schema}.${name}`,
        table: of.table(logical),
        mode: erase.mode,
        retention: erase.retention ?? ERASE_DEFAULT_KIND,
        tenant: of.col(logical, tenant),
        type: of.col(logical, "subjectType"),
        id: of.col(logical, "subjectId"),
        personal:
          erase.mode === "anonymize"
            ? (erase.personal ?? [])
                .filter(
                  (column) =>
                    Object.hasOwn(spec.columns, column) &&
                    of.has(logical, column),
                )
                .map((column) => of.col(logical, column))
            : [],
      });
    }
  }

  return list;
}

function eraseAllowed(ctx: BlockSqlContext, tenant: string): string {
  const permission = ctx.permission(
    "export",
    moduleOperations("data-lifecycle").export,
  );

  return `${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)}`;
}

/**
 * `erase_data_subject(request_id)`: runs a verified, open erasure request over
 * the `lifecycle.erase` tables of the installed modules and returns what was
 * removed, blanked, kept and held, each by table. A table under an active legal
 * hold on its retention kind is left untouched and reported under `held`; a
 * hold on every kind holds them all. It never deletes a table that declares
 * `anonymize` or `keep`, and it reaches only the request's own tenant. The
 * request stays open: `fulfil_data_subject_request` closes it.
 */
export function eraseSql(ctx: BlockSqlContext): string {
  const entries = eraseEntries(ctx);
  const t = ctx.table("requests");
  const c = (logical: string): string => ctx.col("requests", logical);
  const fn = (name: string): string => ctx.fn(name);

  const steps = entries.map((entry) => {
    const where = `x.${entry.tenant}::text = v_row.${c("tenant")}::text and x.${entry.type} = v_row.${c("subjectType")} and x.${entry.id} = v_row.${c("subjectId")}`;
    const key = sqlString(entry.name);

    const hold = `${fn("is_held")}(${sqlString(entry.retention)}, v_row.${c("tenant")}::text)`;

    const act =
      entry.mode === "delete"
        ? `with gone as (delete from ${entry.table} x where ${where} returning 1) select count(*) into v_count from gone;
      v_removed := v_removed || jsonb_build_object(${key}, v_count);`
        : entry.mode === "anonymize" && entry.personal.length > 0
          ? `with blank as (update ${entry.table} x set ${entry.personal.map((column) => `${column} = null`).join(", ")} where ${where} returning 1) select count(*) into v_count from blank;
      v_blanked := v_blanked || jsonb_build_object(${key}, v_count);`
          : `select count(*) into v_count from ${entry.table} x where ${where};
      v_kept := v_kept || jsonb_build_object(${key}, v_count);`;

    return `
  if ${hold} then
    select count(*) into v_count from ${entry.table} x where ${where};
    v_held := v_held || jsonb_build_object(${key}, v_count);
  else
    ${act}
  end if;`;
  });

  return `
-- Erases the data of the request's person across the modules' tables that
-- declare a lifecycle erase mode (ADR 0903). delete removes the rows, anonymize
-- sets the personal columns to null and keeps the row, keep leaves it. A table
-- under an active legal hold is untouched and listed under held. The request
-- must be a verified, open erasure; fulfil_data_subject_request closes it.
create or replace function ${fn("erase_data_subject")}(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
  v_count bigint;
  v_removed jsonb := '{}'::jsonb;
  v_blanked jsonb := '{}'::jsonb;
  v_kept jsonb := '{}'::jsonb;
  v_held jsonb := '{}'::jsonb;
begin
  select * into v_row from ${t} x where x.${c("id")} = erase_data_subject.request_id for update;
  if v_row.${c("id")} is null then
    ${fail("DSAR_NOT_FOUND", "request not found", "P0002")}
  end if;
  if not (${eraseAllowed(ctx, `v_row.${c("tenant")}`)}) then
    ${fail("DSAR_FORBIDDEN", "You may not handle data subject requests here")}
  end if;
  if v_row.${c("kind")} <> 'erasure' then
    ${fail("DSAR_INVALID", "only an erasure request is executed", "22023")}
  end if;
  if v_row.${c("closedAt")} is not null then
    ${fail("DSAR_CLOSED", "the request is already fulfilled or refused", "55000")}
  end if;
  if v_row.${c("verifiedAt")} is null then
    ${fail("DSAR_UNVERIFIED", "verify the requester's identity first", "55000")}
  end if;
  if v_row.${c("subjectType")} is null then
    ${fail("DSAR_INVALID", "an erasure request names the record to erase", "22023")}
  end if;
${steps.join("\n")}
  return jsonb_build_object('removed', v_removed, 'blanked', v_blanked, 'kept', v_kept, 'held', v_held);
end;
$$;

revoke execute on function ${fn("erase_data_subject")}(uuid) from public, anon;
grant execute on function ${fn("erase_data_subject")}(uuid) to authenticated, service_role;
`;
}
