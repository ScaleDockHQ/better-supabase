import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { accountingConfig, GENERIC_CHART } from "./accounting-shared.ts";

const DISPOSAL_ROLES = ["disposal_gain", "disposal_loss"] as const;

/**
 * The data step that adds the disposal gain and loss accounts to the charts of
 * organizations that set up accounting before they existed. Without them a
 * disposal fell back to the suspense account. It adds an account only when the
 * organization has a chart, no account plays the role yet and the code is free,
 * so a chart the organization changed stays as it is and running it again adds
 * nothing.
 */
export function seedDisposalAccounts(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom" || accountingConfig(ctx).chart !== "generic") {
    return "";
  }

  const accounts = ctx.table("accounts");
  const roles = ctx.table("roles");
  const settings = ctx.table("settings");
  const a = (column: string): string => ctx.col("accounts", column);
  const r = (column: string): string => ctx.col("roles", column);
  const s = (column: string): string => ctx.col("settings", column);

  const seeded = GENERIC_CHART.filter(
    (account) =>
      account.role !== undefined &&
      new Set<string>(DISPOSAL_ROLES).has(account.role),
  );

  const values = seeded
    .map(
      (account) =>
        `(${sqlString(account.role ?? "")}, ${sqlString(account.code)}, ${sqlString(account.name)}, ${sqlString(account.type)}, ${sqlString(account.subtype)})`,
    )
    .join(", ");

  return `-- Adds the disposal gain and loss accounts to existing charts of accounts.
insert into ${accounts} (${a("tenant")}, ${a("code")}, ${a("name")}, ${a("type")}, ${a("subtype")}, ${a("reconcilable")})
select s.${s("tenant")}, c.code, c.name, c.type, c.subtype, false
from ${settings} s
cross join (values ${values}) c (role, code, name, type, subtype)
where exists (select 1 from ${accounts} y where y.${a("tenant")} = s.${s("tenant")})
  and not exists (select 1 from ${roles} z where z.${r("tenant")} = s.${s("tenant")} and z.${r("role")} = c.role)
  and not exists (select 1 from ${accounts} y where y.${a("tenant")} = s.${s("tenant")} and y.${a("code")} = c.code);
insert into ${roles} (${r("tenant")}, ${r("role")}, ${r("account")})
select s.${s("tenant")}, c.role, y.${a("id")}
from ${settings} s
cross join (values ${seeded.map((account) => `(${sqlString(account.role ?? "")}, ${sqlString(account.code)}, ${sqlString(account.name)})`).join(", ")}) c (role, code, name)
join ${accounts} y on y.${a("tenant")} = s.${s("tenant")} and y.${a("code")} = c.code and y.${a("name")} = c.name
where not exists (select 1 from ${roles} z where z.${r("tenant")} = s.${s("tenant")} and z.${r("role")} = c.role)
on conflict (${r("tenant")}, ${r("role")}) do nothing;`;
}
