import type { BlockSqlContext } from "../context.ts";

import { fail, raise } from "../shared.ts";

/** What the default rule functions share with the rest of the module. */
export interface DefaultRulesSqlHelpers {
  readonly ctx: BlockSqlContext;
  readonly read: string;
  readonly can: (tenant: string, key: string) => string;
  readonly canKey: (tenant: string, enabled: string) => string;
  readonly keyFor: (enabled: string) => string;
  readonly ruleEvent: (type: string, row: string) => string;
  readonly ruleJson: (row: string) => string;
}

/**
 * `install_default_rules`, which copies the default automations into an
 * organization's rules, and `reset_default_rule`, which restores one.
 */
export function defaultRulesSql(helpers: DefaultRulesSqlHelpers): string {
  const { ctx, read, can, canKey, keyFor, ruleEvent, ruleJson } = helpers;
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("rules");
  const v = ctx.table("versions");
  const d = ctx.table("defaults");
  const r = (column: string): string => ctx.col("rules", column);
  const rv = (column: string): string => ctx.col("versions", column);
  const rd = (column: string): string => ctx.col("defaults", column);

  return `-- Copies the default automations an organization doesn't have yet into its
-- rules (service role); returns how many it copied.
create or replace function ${fn("install_default_rules")}(tenant ${id})
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into ${t} (${r("tenant")}, ${r("subjectType")}, ${r("trigger")}, ${r("name")}, ${r("description")}, ${r("conditions")}, ${r("actions")}, ${r("enabled")}, ${r("defaultKey")}, ${r("createdBy")}, ${r("updatedBy")})
  select install_default_rules.tenant, x.${rd("subjectType")}, x.${rd("trigger")}, x.${rd("name")}, x.${rd("description")}, x.${rd("conditions")}, x.${rd("actions")}, x.${rd("enabled")}, x.${rd("key")}, null, null
  from ${d} x
  where not exists (
    select 1 from ${t} y where y.${r("tenant")} = install_default_rules.tenant and y.${r("defaultKey")} = x.${rd("key")}
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Restores a default automation to what its block ships: trigger, name,
-- description, conditions, actions and whether it is on. Takes the edit
-- permission, or publish when the rule is or becomes enabled.
create or replace function ${fn("reset_default_rule")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
  v_default ${d};
begin
  select * into v_row from ${t} x where x.${r("id")} = reset_default_rule.id for update;
  if v_row.${r("id")} is null or not ${can(`v_row.${r("tenant")}`, read)} then
    ${fail("RULE_NOT_FOUND", "No rule you can read has this id", "P0002")}
  end if;
  select * into v_default from ${d} x where x.${rd("key")} = v_row.${r("defaultKey")};
  if v_default.${rd("key")} is null then
    ${fail("RULE_NOT_DEFAULT", "No block ships this rule", "22023")}
  end if;
  if not ${canKey(`v_row.${r("tenant")}`, `(v_row.${r("enabled")} or v_default.${rd("enabled")})`)} then
    ${raise("You need % to reset this rule", "42501", "RULE_FORBIDDEN", keyFor(`(v_row.${r("enabled")} or v_default.${rd("enabled")})`))}
  end if;
  update ${t} x set
    ${r("trigger")} = v_default.${rd("trigger")},
    ${r("name")} = v_default.${rd("name")},
    ${r("description")} = v_default.${rd("description")},
    ${r("conditions")} = v_default.${rd("conditions")},
    ${r("actions")} = v_default.${rd("actions")},
    ${r("enabled")} = v_default.${rd("enabled")},
    ${r("stopProcessing")} = false,
    ${r("version")} = x.${r("version")} + 1,
    ${r("updatedBy")} = auth.uid(),
    ${r("updatedAt")} = now()
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  insert into ${v} (${rv("rule")}, ${rv("version")}, ${rv("tenant")}, ${rv("name")}, ${rv("conditions")}, ${rv("actions")}, ${rv("savedBy")})
  values (v_row.${r("id")}, v_row.${r("version")}, v_row.${r("tenant")}, v_row.${r("name")}, v_row.${r("conditions")}, v_row.${r("actions")}, auth.uid())
  on conflict do nothing;
  ${ruleEvent("rule.saved", "v_row")}
  return ${ruleJson("v_row")};
end;
$$;`;
}
