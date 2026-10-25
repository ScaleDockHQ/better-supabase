import type { BlockSqlContext } from "../context.ts";

import { fail, raise } from "../shared.ts";
import { columnOf } from "./automations-tables.ts";

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
 * Stores the version of rule row `v_row` (the module's `rules` names); a
 * version already stored stays.
 */
export function saveVersionSql(ctx: BlockSqlContext): string {
  const r = columnOf(ctx, "rules");
  const rv = columnOf(ctx, "versions");
  const saver = ctx.has("versions", "savedBy");

  return `insert into ${ctx.table("versions")} (${rv("rule")}, ${rv("version")}, ${rv("tenant")}, ${rv("name")}, ${rv("conditions")}, ${rv("actions")}${saver ? `, ${rv("savedBy")}` : ""})
  values (v_row.${r("id")}, v_row.${r("version")}, v_row.${r("tenant")}, v_row.${r("name")}, v_row.${r("conditions")}, v_row.${r("actions")}${saver ? ", auth.uid()" : ""})
  on conflict do nothing;`;
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
  const d = ctx.table("defaults");
  const r = columnOf(ctx, "rules");
  const rd = columnOf(ctx, "defaults");

  const copied = [
    ["tenant", "install_default_rules.tenant"],
    ["subjectType", `x.${rd("subjectType")}`],
    ["trigger", `x.${rd("trigger")}`],
    ["name", `x.${rd("name")}`],
    ["description", `x.${rd("description")}`],
    ["conditions", `x.${rd("conditions")}`],
    ["actions", `x.${rd("actions")}`],
    ["enabled", `x.${rd("enabled")}`],
    ["defaultKey", `x.${rd("key")}`],
    ["createdBy", "null"],
    ["updatedBy", "null"],
  ].filter(([column = ""]) => ctx.has("rules", column));

  // Without a default key column a copy can't be told apart from the
  // organization's own rules, so no defaults are copied.
  const install = ctx.has("rules", "defaultKey")
    ? `  insert into ${t} (${copied.map(([column = ""]) => r(column)).join(", ")})
  select ${copied.map(([, value]) => value).join(", ")}
  from ${d} x
  where not exists (
    select 1 from ${t} y where y.${r("tenant")} = install_default_rules.tenant and y.${r("defaultKey")} = x.${rd("key")}
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;`
    : "  v_count := 0;\n  return v_count;";

  const reset = [
    ["trigger", `v_default.${rd("trigger")}`],
    ["name", `v_default.${rd("name")}`],
    ["description", `v_default.${rd("description")}`],
    ["conditions", `v_default.${rd("conditions")}`],
    ["actions", `v_default.${rd("actions")}`],
    ["enabled", `v_default.${rd("enabled")}`],
    ["stopProcessing", "false"],
    ["version", `x.${r("version")} + 1`],
    ["updatedBy", "auth.uid()"],
    ["updatedAt", "now()"],
  ]
    .filter(([column = ""]) => ctx.has("rules", column))
    .map(([column = "", value]) => `${r(column)} = ${value}`)
    .join(",\n    ");

  const defaultKey = ctx.has("rules", "defaultKey")
    ? `v_row.${r("defaultKey")}`
    : "null::text";

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
${install}
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
  select * into v_default from ${d} x where x.${rd("key")} = ${defaultKey};
  if v_default.${rd("key")} is null then
    ${fail("RULE_NOT_DEFAULT", "No block ships this rule", "22023")}
  end if;
  if not ${canKey(`v_row.${r("tenant")}`, `(v_row.${r("enabled")} or v_default.${rd("enabled")})`)} then
    ${raise("You need % to reset this rule", "42501", "RULE_FORBIDDEN", keyFor(`(v_row.${r("enabled")} or v_default.${rd("enabled")})`))}
  end if;
  update ${t} x set
    ${reset}
  where x.${r("id")} = v_row.${r("id")}
  returning * into v_row;
  ${saveVersionSql(ctx)}
  ${ruleEvent("rule.saved", "v_row")}
  return ${ruleJson("v_row")};
end;
$$;`;
}
