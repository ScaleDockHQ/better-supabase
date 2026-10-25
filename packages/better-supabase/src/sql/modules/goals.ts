import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { int8Text } from "../money-sql.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { invoiceLedger } from "./invoices-ledger.ts";
import { moduleOperations } from "./permissions-model.ts";

const NAMES: BlockSqlNames = {
  entities: { target: { table: "targets", singular: "target", primary: true } },
  options: ["extraColumns"],
  tables: {
    targets: {
      name: "targets",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        metric: "metric",
        owner: "owner_user_id",
        team: "team_id",
        periodStart: "period_start",
        periodEnd: "period_end",
        currency: "currency",
        goal: "goal",
        actual: "actual",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["team", "archivedAt", "createdAt", "updatedAt"],
    },
  },
};

/** The metrics `target_progress` computes, by the module that owns the data. */
function metrics(
  ctx: BlockSqlContext,
  c: (column: string) => string,
): Readonly<Record<string, string>> {
  const out: Record<string, string> = {};

  const window = (column: string): string =>
    `${column}::date between x.${c("periodStart")} and x.${c("periodEnd")}`;

  if (ctx.installed("deals")) {
    const deals = ctx.of("deals");
    const d = (column: string): string => `d.${deals.col("deals", column)}`;

    const scope = `${d("tenant")} = x.${c("tenant")} and ${d("outcome")} = 'won' and ${window(d("closedAt"))}
        and (x.${c("owner")} is null or ${d("owner")} = x.${c("owner")})`;

    out["deals.won_amount"] =
      `(select coalesce(sum(${d("amount")}), 0) from ${deals.table("deals")} d where ${scope} and ${d("currency")} = x.${c("currency")})`;
    out["deals.won_count"] =
      `(select count(*) from ${deals.table("deals")} d where ${scope})`;
  }

  if (ctx.installed("tasks")) {
    const items = ctx.of("tasks");
    const w = (column: string): string => `w.${items.col("items", column)}`;
    const a = (column: string): string => `a.${items.col("assignees", column)}`;
    out["work_items.completed"] =
      `(select count(*) from ${items.table("items")} w
      where ${w("tenant")} = x.${c("tenant")} and ${w("state")} = 'completed' and ${window(w("closedAt"))}${
        ctx.has("targets", "team")
          ? `
        and (x.${c("team")} is null or ${w("team")} = x.${c("team")})`
          : ""
      }
        and (x.${c("owner")} is null or exists (select 1 from ${items.table("assignees")} a where ${a("item")} = ${w("id")} and ${a("user")} = x.${c("owner")})))`;
  }

  if (ctx.installed("invoices")) {
    out["invoices.paid_amount"] = invoiceLedger(ctx.of("invoices")).received(
      `x.${c("tenant")}`,
      `x.${c("currency")}`,
      window,
    );
  }

  return out;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const keys = moduleOperations("goals");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);
  const fn = (name: string): string => ctx.fn(name);
  const t = ctx.table("targets");
  const c = (column: string): string => ctx.col("targets", column);
  const known = metrics(ctx, c);

  const actual =
    Object.keys(known).length === 0
      ? `x.${c("actual")}`
      : `case x.${c("metric")}
${Object.entries(known)
  .map(([metric, sql]) => `        when ${sqlString(metric)} then ${sql}`)
  .join("\n")}
        else x.${c("actual")}
      end`;

  // The target's extra columns: attrs.fields writes them, reads return them under fields.
  const extras = ctx.extraColumns("targets", [
    "fields",
    "progress",
    "attainment",
  ]);

  const int8 = [c("goal"), c("actual")];
  const has = (column: string): boolean => ctx.has("targets", column);

  const optional = (column: string, definition: string): string =>
    has(column) ? `\n  ${c(column)} ${definition},` : "";

  const active = has("archivedAt") ? ` and x.${c("archivedAt")} is null` : "";

  const progressRow = withExtraFields(
    `(to_jsonb(p) || ${int8Text("p", int8)})`,
    "p",
    extras,
  );

  return `${schemaPreamble(ctx)}
-- Targets: a goal per period for a metric, for a member, a team or the
-- whole organization, with progress from the data the blocks keep.
${
  ctx.manages
    ? `create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 200),
  ${c("metric")} text not null check (${c("metric")} ~ '^[a-z][a-z0-9_.-]{0,80}$'),
  ${c("owner")} uuid,${optional("team", "uuid")}
  ${c("periodStart")} date not null,
  ${c("periodEnd")} date not null,
  ${c("currency")} char(3) check (${c("currency")} ~ '^[A-Z]{3}$'),
  ${c("goal")} bigint not null check (${c("goal")} > 0),
  ${c("actual")} bigint not null default 0,${optional("archivedAt", "timestamptz")}${optional("createdAt", "timestamptz not null default now()")}${optional("updatedAt", "timestamptz not null default now()")}
  check (${c("periodEnd")} >= ${c("periodStart")})
);${addExtraColumns(t, extras)}
create index if not exists ${ctx.naming.rename("targets_period_idx")} on ${t} (${c("tenant")}, ${c("periodStart")}, ${c("periodEnd")})${has("archivedAt") ? ` where ${c("archivedAt")} is null` : ""};
${lockTable(t, { read: true })}
drop policy if exists ${ctx.naming.rename("targets_read")} on ${t};
create policy ${ctx.naming.rename("targets_read")} on ${t} for select to authenticated
using (${ctx.scope.check(c("tenant"), read)});
`
    : ""
}
-- Creates or changes a target: name, metric, ownerId, teamId, periodStart,
-- periodEnd, currency (for amount metrics), goal, actual (for a metric no
-- block computes), archived.
create or replace function ${fn("save_target")}(tenant ${ctx.idType}, target uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_target.target;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("save_target.tenant", manage)}) then
    ${fail("TARGET_FORBIDDEN", "not allowed to manage targets")}
  end if;
  begin
    if v_id is null then
      insert into ${t} (${c("tenant")}, ${c("name")}, ${c("metric")}, ${c("owner")}, ${has("team") ? `${c("team")}, ` : ""}${c("periodStart")}, ${c("periodEnd")}, ${c("currency")}, ${c("goal")}, ${c("actual")})
      values (save_target.tenant, save_target.attrs ->> 'name', save_target.attrs ->> 'metric', (save_target.attrs ->> 'ownerId')::uuid,
        ${has("team") ? "(save_target.attrs ->> 'teamId')::uuid, " : ""}(save_target.attrs ->> 'periodStart')::date, (save_target.attrs ->> 'periodEnd')::date,
        upper(save_target.attrs ->> 'currency'), (save_target.attrs ->> 'goal')::bigint, coalesce((save_target.attrs ->> 'actual')::bigint, 0))
      returning ${c("id")} into v_id;
    else
      update ${t} x set
        ${c("name")} = coalesce(save_target.attrs ->> 'name', x.${c("name")}),
        ${c("goal")} = coalesce((save_target.attrs ->> 'goal')::bigint, x.${c("goal")}),
        ${c("actual")} = coalesce((save_target.attrs ->> 'actual')::bigint, x.${c("actual")}),
        ${c("periodStart")} = coalesce((save_target.attrs ->> 'periodStart')::date, x.${c("periodStart")}),
        ${c("periodEnd")} = coalesce((save_target.attrs ->> 'periodEnd')::date, x.${c("periodEnd")})${
          has("archivedAt")
            ? `,\n        ${c("archivedAt")} = case when coalesce((save_target.attrs ->> 'archived')::boolean, false) then coalesce(x.${c("archivedAt")}, now()) else x.${c("archivedAt")} end`
            : ""
        }${has("updatedAt") ? `,\n        ${c("updatedAt")} = now()` : ""}
      where x.${c("id")} = v_id and x.${c("tenant")} = save_target.tenant;
      if not found then
        ${fail("TARGET_NOT_FOUND", "target not found", "P0002")}
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    ${fail("TARGET_INVALID", "a target needs a name, a metric, a period and a positive goal", "22023")}
  end;${writeExtraColumns(t, extras, "(save_target.attrs -> 'fields')", `x.${c("id")} = v_id`)}
  return (select ${withExtraFields(`(to_jsonb(x) || ${int8Text("x", int8)})`, "x", extras)} from ${t} x where x.${c("id")} = v_id);
end;
$$;
${userGrant(`${fn("save_target")}(${ctx.idType}, uuid, jsonb)`)}

-- The targets whose period contains on, with their actual value and
-- attainment. Built-in metrics: ${Object.keys(known).join(", ") || "none installed"}. Others read actual.
create or replace function ${fn("target_progress")}(tenant ${ctx.idType}, on_date date, owner uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${progressRow} - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x.${c("goal")}, 4) as attainment, x.${c("periodStart")} as period_start_order, x.${c("name")} as name_order
    from ${t} x
    cross join lateral (select ${actual} as value) v
    where x.${c("tenant")} = target_progress.tenant${active}
      and coalesce(target_progress.on_date, current_date) between x.${c("periodStart")} and x.${c("periodEnd")}
      and (target_progress.owner is null or x.${c("owner")} = target_progress.owner)
  ) p
$$;
${userGrant(`${fn("target_progress")}(${ctx.idType}, date, uuid)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_target", args: ["{id}", "uuid", "jsonb"], returns: "jsonb" },
    {
      name: "target_progress",
      args: ["{id}", "date", "uuid"],
      returns: "jsonb",
    },
  ];
}

export const TARGETS: BlockSqlDefinition = {
  name: "goals",
  scopes: ["tenant"],
  title: "Targets",
  description:
    "Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.",
  requires: ["memberships", "permissions"],
  integrates: ["deals", "tasks", "invoices"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
