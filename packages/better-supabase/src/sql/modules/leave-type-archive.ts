import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, userGrant } from "../shared.ts";

interface TypeArchiveDeps {
  readonly ctx: BlockSqlContext;
  readonly fail: (code: string, message: string, errcode: string) => string;
  readonly forbidden: (message: string) => string;
  readonly manage: string;
  readonly typeJson: (row: string) => string;
}

const VERBS = [
  {
    fn: "archive_leave_type",
    event: "leave_type.archived",
    summary: "archived leave type",
    archivedAt: (column: string) => `coalesce(x.${column}, now())`,
    comment: "Hides a type from new requests; its requests and ledger stay.",
  },
  {
    fn: "restore_leave_type",
    event: "leave_type.restored",
    summary: "restored leave type",
    archivedAt: () => "null",
    comment: "Makes an archived type available to new requests again.",
  },
] as const;

/**
 * `archive_leave_type` and `restore_leave_type`: both lock the type, need
 * `leave.manage`, record `leave_type.archived` or `.restored` and return the
 * type.
 */
export function typeArchiveFunctions(deps: TypeArchiveDeps): string {
  const { ctx, fail, forbidden, manage, typeJson } = deps;
  const types = ctx.table("types");
  const ty = (column: string): string => ctx.col("types", column);

  const record = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${ty("tenant")}, 'id', v_row.${ty("id")}, 'name', v_row.${ty("name")})`,
      subject: `'leave-types/' || v_row.${ty("id")}::text`,
      tenant: `v_row.${ty("tenant")}`,
      audit: {
        category: "data",
        targetType: "leave_type",
        recordId: `v_row.${ty("id")}::text`,
        summary: `${sqlString(summary)} || ' ' || v_row.${ty("name")}`,
      },
    });

  return VERBS.map(
    (verb) => `-- ${verb.comment}
create or replace function ${ctx.fn(verb.fn)}(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${types}%rowtype;
begin
  select * into v_row from ${types} x where x.${ty("id")} = ${verb.fn}.type_id for update;
  if not found then
    ${fail("LEAVE_TYPE_NOT_FOUND", "leave type not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${ty("tenant")}`, manage)}) then
    ${forbidden("not allowed to manage leave types")}
  end if;
  update ${types} x set ${ty("archivedAt")} = ${verb.archivedAt(ty("archivedAt"))}, ${ty("updatedAt")} = now()
    where x.${ty("id")} = v_row.${ty("id")}
    returning * into v_row;
  ${record(verb.event, verb.summary)}
  return ${typeJson("v_row")};
end;
$$;
${userGrant(`${ctx.fn(verb.fn)}(uuid)`)}
`,
  ).join("\n");
}
