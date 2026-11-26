import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";

/**
 * `archive_field_definition`, `restore_field_definition` and
 * `purge_field_definition`, which replace `delete_field_definition`. The
 * archive pair exists only when the definitions table has `archivedAt`.
 */
export function archiveFunctions(
  ctx: BlockSqlContext,
  input: {
    readonly archivable: boolean;
    readonly archivedAt: string;
    readonly definitions: string;
    readonly inline: boolean;
    readonly manage: string;
    readonly purge: string;
  },
): string {
  const { archivable, archivedAt, definitions, inline, manage, purge } = input;

  return `${
    archivable
      ? ["archive", "restore"]
          .map((verb) => {
            const name = `${verb}_field_definition`;
            const past = verb === "archive" ? "archived" : "restored";

            return `-- ${verb === "archive" ? "Archives a field: it leaves list_field_definitions and upsert_field_definition and set_field_value refuse it. Its values stay and stay readable." : "Restores an archived field."} Needs the manage key; ${verb === "archive" ? "archiving an archived field" : "restoring one that is not archived"} returns it unchanged.
create or replace function ${ctx.fn(name)}(definition uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_archived timestamptz;
begin
  select ${ctx.col("definitions", "tenant")}, ${archivedAt} into v_tenant, v_archived from ${definitions} where ${ctx.col("definitions", "id")} = ${name}.definition;
  if not found then
    ${fail("CUSTOM_FIELD_NOT_FOUND", "field not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("CUSTOM_FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  if (v_archived is not null) = ${verb === "archive" ? "true" : "false"} then
    return jsonb_build_object('id', ${name}.definition, 'archivedAt', v_archived);
  end if;
  update ${definitions} set ${archivedAt} = ${verb === "archive" ? "now()" : "null"} where ${ctx.col("definitions", "id")} = ${name}.definition
  returning ${archivedAt} into v_archived;
  ${ctx.record({
    type: `field_definition.${past}`,
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', ${name}.definition)`,
    subject: `'custom-fields/' || ${name}.definition::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return jsonb_build_object('id', ${name}.definition, 'archivedAt', v_archived);
end;
$$;
${userGrant(`${ctx.fn(name)}(uuid)`)}

`;
          })
          .join("")
      : ""
  }-- Deletes a field for good with every value stored under it; archive keeps
-- them. Needs ${purge}, which falls back to the manage key.
drop function if exists ${ctx.fn("delete_field_definition")}(uuid);
create or replace function ${ctx.fn("purge_field_definition")}(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  ${
    inline
      ? fail("FIELD_INLINE", "inline fields have no definition row", "0A000")
      : `select ${ctx.col("definitions", "tenant")} into v_tenant from ${definitions} where ${ctx.col("definitions", "id")} = purge_field_definition.definition;
  if not found then
    ${fail("CUSTOM_FIELD_NOT_FOUND", "field not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", purge)}) then
    ${fail("CUSTOM_FIELD_FORBIDDEN", "not allowed to purge custom fields")}
  end if;
  delete from ${definitions} where ${ctx.col("definitions", "id")} = purge_field_definition.definition;`
  }
  ${ctx.record({
    type: "field_definition.purged",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', purge_field_definition.definition)`,
    subject: `'custom-fields/' || purge_field_definition.definition::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("purge_field_definition")}(uuid)`)}
`;
}
