import type { PeriodsEvents } from "../../blocks/periods/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { PeriodContribution } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { PERIOD_STATUSES } from "./periods-values.ts";
import { OPERATIONS } from "./permissions-model.ts";

const PAYLOAD = [
  "organizationId",
  "id",
  "kind",
  "startsOn",
  "endsOn",
  "status",
] as const;

const period = { subject: "periods", payload: [...PAYLOAD] } as const;

const EVENTS: BlockSqlEvents<PeriodsEvents> = {
  "period.created": period,
  "period.locked": period,
  "period.closed": period,
  "period.reopened": period,
};

const NAMES: BlockSqlNames = {
  entities: { period: { table: "periods", singular: "period", primary: true } },
  events: EVENTS,
  hooks: [],
  options: [],
  tables: {
    periods: {
      name: "periods",
      app: {},
      lifecycle: { tenant: "tenant", user: "closedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        startsOn: "starts_on",
        endsOn: "ends_on",
        status: "status",
        closedAt: "closed_at",
        closedBy: "closed_by",
        createdAt: "created_at",
      },
    },
  },
};

const CONTRIBUTORS_KIND = /^[a-z][a-z0-9_]{0,62}$/u;

/** The kinds the installed blocks contribute, checked once. */
function contributed(ctx: BlockSqlContext): readonly PeriodContribution[] {
  const list = ctx.contributions("periods");
  const seen = new Set<string>();

  for (const each of list) {
    if (!CONTRIBUTORS_KIND.test(each.kind)) {
      throw new TypeError(
        `period kind "${each.kind}" is a lower case name such as leave_year`,
      );
    }

    if (seen.has(each.kind)) {
      throw new TypeError(`two blocks contribute the period kind ${each.kind}`);
    }

    seen.add(each.kind);
  }

  return list;
}

/** The first and last day of the calendar unit around date `d`, in SQL. */
function bounds(cadence: string, d: string) {
  const unit = sqlString(cadence);

  return {
    from: `date_trunc(${unit}, ${d}::timestamp)::date`,
    to: `(date_trunc(${unit}, ${d}::timestamp) + case ${unit} when 'week' then interval '1 week' when 'month' then interval '1 month' when 'quarter' then interval '3 months' else interval '1 year' end - interval '1 day')::date`,
  };
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const idType = ctx.idType;
  const list = contributed(ctx);
  const fn = (name: string): string => ctx.fn(name);
  const t = (column: string): string => ctx.col("periods", column);
  const periods = ctx.table("periods");
  const read = ctx.permission("read", OPERATIONS["periods.read"]);
  const write = ctx.permission("write", OPERATIONS["periods.write"]);
  const manage = ctx.permission("manage", OPERATIONS["periods.manage"]);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const missing = fail("PERIOD_NOT_FOUND", "no such period", "P0002");

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'kind', ${row}.${t("kind")}, 'startsOn', ${row}.${t("startsOn")}, 'endsOn', ${row}.${t("endsOn")}, 'status', ${row}.${t("status")}, 'closedAt', ${row}.${t("closedAt")}, 'closedBy', ${row}.${t("closedBy")}, 'createdAt', ${row}.${t("createdAt")})`;

  const record = (
    type:
      | "period.created"
      | "period.locked"
      | "period.closed"
      | "period.reopened",
    row: string,
    extra = "",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, 'kind', ${row}.${t("kind")}, 'startsOn', ${row}.${t("startsOn")}, 'endsOn', ${row}.${t("endsOn")}, 'status', ${row}.${t("status")}${extra})`,
      subject: `'periods/' || ${row}.${t("id")}::text`,
      tenant: `${row}.${t("tenant")}`,
      audit: {
        category: "data",
        targetType: "period",
        recordId: `${row}.${t("id")}::text`,
        targetLabel: `${row}.${t("kind")} || ' ' || ${row}.${t("startsOn")}::text`,
        summary: sqlString(type.replace("period.", "period ")),
      },
    });

  const cadences = list.filter((each) => each.cadence !== undefined);

  const created = (kind: string, cadence: string): string => {
    const span = bounds(cadence, "period_for.on_date");

    return `if period_for.kind = ${sqlString(kind)} then
      insert into ${periods} (${t("tenant")}, ${t("kind")}, ${t("startsOn")}, ${t("endsOn")})
      values (period_for.tenant, period_for.kind, ${span.from}, ${span.to})
      on conflict do nothing;
      select * into v_row from ${periods} x
      where x.${t("tenant")} = period_for.tenant and x.${t("kind")} = period_for.kind
        and period_for.on_date between x.${t("startsOn")} and x.${t("endsOn")};
    end if;`;
  };

  const blockers = list
    .filter((each) => each.blockers !== undefined)
    .map(
      (each) =>
        `if v_row.${t("kind")} = ${sqlString(each.kind)} then
    v_blockers := v_blockers || coalesce(${each.blockers}(v_row.${t("tenant")}, v_row.${t("startsOn")}, v_row.${t("endsOn")}), '{}'::text[]);
  end if;`,
    )
    .join("\n  ");

  const onClose = list
    .filter((each) => each.onClose !== undefined)
    .map(
      (each) =>
        `if v_row.${t("kind")} = ${sqlString(each.kind)} then
    perform ${each.onClose}(v_row.${t("tenant")}, v_row.${t("startsOn")}, v_row.${t("endsOn")});
  end if;`,
    )
    .join("\n  ");

  const readPolicy = renderPolicy(
    makePolicy({
      table: periods,
      name: sqlIdent(`${ctx.tableName("periods").name}_read`),
      command: "select",
      roles: ["authenticated"],
      using: ctx.scope.check(t("tenant"), read),
    }),
    { target: periods },
  );

  const appKey = ctx.owns("periods")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("periods").name}_tenant_id_key`)} on ${periods} (${t("tenant")}, ${t("id")});`;

  return `${schemaPreamble(ctx)}
-- Periods: one table of dated ranges per kind with a status, a lookup by date
-- and a close protocol. Blocks add kinds through contributions; closing asks
-- each kind's blockers first and runs its on-close step in the same transaction.
-- Kinds installed now: ${list.length === 0 ? "none" : list.map((each) => each.kind).join(", ")}.
create table if not exists ${periods} (
  ${t("id")} uuid primary key default gen_random_uuid(),
  ${t("tenant")} ${idType} not null,
  ${t("kind")} text not null check (${t("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${t("startsOn")} date not null,
  ${t("endsOn")} date not null,
  ${t("status")} text not null default 'open' check (${t("status")} in (${PERIOD_STATUSES.map((status) => `'${status}'`).join(", ")})),
  ${t("closedAt")} timestamptz,
  ${t("closedBy")} uuid,
  ${t("createdAt")} timestamptz not null default now(),
  check (${t("endsOn")} >= ${t("startsOn")}),
  unique (${t("tenant")}, ${t("kind")}, ${t("startsOn")})
);${appKey}
create index if not exists ${sqlIdent(`${ctx.tableName("periods").name}_range_idx`)} on ${periods} (${t("tenant")}, ${t("kind")}, ${t("startsOn")}, ${t("endsOn")});
${lockTable(periods, { read: true })}
${readPolicy}

-- Creates a period of a kind. The range may not overlap another period of the
-- same kind in the organization. Needs periods.write.
create or replace function ${fn("create_period")}(tenant ${idType}, kind text, starts_on date, ends_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${periods};
begin
  if not ${allowed("create_period.tenant", write)} then
    ${fail("PERIOD_FORBIDDEN", "not allowed to create periods")}
  end if;
  if create_period.kind is null or create_period.kind !~ '^[a-z][a-z0-9_]{0,62}$' or create_period.starts_on is null
    or create_period.ends_on is null or create_period.ends_on < create_period.starts_on then
    ${fail("PERIOD_INVALID", "a period needs a lower case kind and a range that ends on or after it starts", "22023")}
  end if;
  if exists (
    select 1 from ${periods} x
    where x.${t("tenant")} = create_period.tenant and x.${t("kind")} = create_period.kind
      and daterange(x.${t("startsOn")}, x.${t("endsOn")}, '[]') && daterange(create_period.starts_on, create_period.ends_on, '[]')
  ) then
    ${fail("PERIOD_OVERLAP", "the range overlaps a period of this kind", "23P01")}
  end if;
  insert into ${periods} (${t("tenant")}, ${t("kind")}, ${t("startsOn")}, ${t("endsOn")})
  values (create_period.tenant, create_period.kind, create_period.starts_on, create_period.ends_on)
  returning * into v_row;
  ${record("period.created", "v_row")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("create_period")}(${idType}, text, date, date)`)}

-- The period of a kind that holds a date, or null. A kind a block gave a
-- cadence${cadences.length === 0 ? "" : ` (${cadences.map((each) => `${each.kind}: ${each.cadence}`).join(", ")})`} gets its calendar period created the first time
-- a date in it is asked for. Needs periods.read.
create or replace function ${fn("period_for")}(tenant ${idType}, kind text, on_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${periods};
begin
  if not ${allowed("period_for.tenant", read)} then
    ${fail("PERIOD_FORBIDDEN", "not allowed to read periods")}
  end if;
  select * into v_row from ${periods} x
  where x.${t("tenant")} = period_for.tenant and x.${t("kind")} = period_for.kind
    and period_for.on_date between x.${t("startsOn")} and x.${t("endsOn")};
  if found then
    return ${json("v_row")};
  end if;${cadences.map((each) => `\n  ${created(each.kind, each.cadence ?? "month")}`).join("")}
  if v_row.${t("id")} is null then
    return null;
  end if;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("period_for")}(${idType}, text, date)`)}

-- Whether writes dated on_date may still land in the kind's period: true when
-- there is no period or it is open. Blocks call it before they write.
create or replace function ${fn("period_is_open")}(tenant ${idType}, kind text, on_date date)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select not exists (
    select 1 from ${periods} x
    where x.${t("tenant")} = period_is_open.tenant and x.${t("kind")} = period_is_open.kind
      and period_is_open.on_date between x.${t("startsOn")} and x.${t("endsOn")}
      and x.${t("status")} <> 'open'
  )
$$;
${userGrant(`${fn("period_is_open")}(${idType}, text, date)`)}

-- What keeps a period from closing, from every block that contributes its
-- kind. An empty array means it can close. Needs periods.read.
create or replace function ${fn("period_close_blockers")}(period_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${periods};
  v_blockers text[] := '{}';
begin
  select * into v_row from ${periods} x where x.${t("id")} = period_close_blockers.period_id;
  if not found or not ${allowed(`v_row.${t("tenant")}`, read)} then
    ${missing}
  end if;
  ${blockers === "" ? "-- No installed block adds blockers." : blockers}
  return v_blockers;
end;
$$;
${userGrant(`${fn("period_close_blockers")}(uuid)`)}

-- Stops writes into an open period without closing it. Needs periods.manage.
create or replace function ${fn("lock_period")}(period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${periods};
begin
  select * into v_row from ${periods} x where x.${t("id")} = lock_period.period_id for update;
  if not found or not ${allowed(`v_row.${t("tenant")}`, read)} then
    ${missing}
  end if;
  if not ${allowed(`v_row.${t("tenant")}`, manage)} then
    ${fail("PERIOD_FORBIDDEN", "not allowed to lock periods")}
  end if;
  if v_row.${t("status")} <> 'open' then
    return ${json("v_row")};
  end if;
  update ${periods} x set ${t("status")} = 'locked' where x.${t("id")} = v_row.${t("id")} returning * into v_row;
  ${record("period.locked", "v_row")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("lock_period")}(uuid)`)}

-- Closes a period. It fails with PERIOD_CLOSE_BLOCKED while any contributing
-- block names a blocker; otherwise it runs each block's on-close step and marks
-- the period closed in one transaction. Closing a closed period returns it
-- unchanged. Needs periods.manage.
create or replace function ${fn("close_period")}(period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${periods};
  v_blockers text[];
begin
  select * into v_row from ${periods} x where x.${t("id")} = close_period.period_id for update;
  if not found or not ${allowed(`v_row.${t("tenant")}`, read)} then
    ${missing}
  end if;
  if not ${allowed(`v_row.${t("tenant")}`, manage)} then
    ${fail("PERIOD_FORBIDDEN", "not allowed to close periods")}
  end if;
  if v_row.${t("status")} = 'closed' then
    return ${json("v_row")};
  end if;
  v_blockers := ${fn("period_close_blockers")}(v_row.${t("id")});
  if cardinality(v_blockers) > 0 then
    raise exception 'the period can''t close yet: %', array_to_string(v_blockers, ', ') using errcode = '55000', hint = 'PERIOD_CLOSE_BLOCKED', detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
  end if;
  ${onClose === "" ? "-- No installed block adds an on-close step." : onClose}
  update ${periods} x set ${t("status")} = 'closed', ${t("closedAt")} = now(), ${t("closedBy")} = auth.uid()
  where x.${t("id")} = v_row.${t("id")} returning * into v_row;
  ${record("period.closed", "v_row")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("close_period")}(uuid)`)}

-- Reopens a locked or closed period. The on-close steps of the blocks are not
-- undone. Needs periods.manage.
create or replace function ${fn("reopen_period")}(period_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${periods};
begin
  select * into v_row from ${periods} x where x.${t("id")} = reopen_period.period_id for update;
  if not found or not ${allowed(`v_row.${t("tenant")}`, read)} then
    ${missing}
  end if;
  if not ${allowed(`v_row.${t("tenant")}`, manage)} then
    ${fail("PERIOD_FORBIDDEN", "not allowed to reopen periods")}
  end if;
  if v_row.${t("status")} = 'open' then
    return ${json("v_row")};
  end if;
  update ${periods} x set ${t("status")} = 'open', ${t("closedAt")} = null, ${t("closedBy")} = null
  where x.${t("id")} = v_row.${t("id")} returning * into v_row;
  ${record("period.reopened", "v_row", `, 'reason', nullif(trim(reopen_period.reason), '')`)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("reopen_period")}(uuid, text)`)}

-- An organization's periods, newest first. filters is { kind, status, limit }.
create or replace function ${fn("list_periods")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_periods.filters, '{}'::jsonb);
begin
  if not ${allowed("list_periods.tenant", read)} then
    ${fail("PERIOD_FORBIDDEN", "not allowed to read periods")}
  end if;
  return coalesce((
    select jsonb_agg(${json("y")} order by y.${t("startsOn")} desc, y.${t("kind")})
    from (
      select * from ${periods} z
      where z.${t("tenant")} = list_periods.tenant
        and (not v_filters ? 'kind' or z.${t("kind")} = v_filters ->> 'kind')
        and (not v_filters ? 'status' or z.${t("status")} = v_filters ->> 'status')
      order by z.${t("startsOn")} desc, z.${t("kind")}
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_periods")}(${idType}, jsonb)`)}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_period",
      args: ["{id}", "text", "date", "date"],
      returns: "jsonb",
    },
    { name: "period_for", args: ["{id}", "text", "date"], returns: "jsonb" },
    {
      name: "period_is_open",
      args: ["{id}", "text", "date"],
      returns: "boolean",
    },
    { name: "period_close_blockers", args: ["uuid"], returns: "text[]" },
    { name: "lock_period", args: ["uuid"], returns: "jsonb" },
    { name: "close_period", args: ["uuid"], returns: "jsonb" },
    { name: "reopen_period", args: ["uuid", "text"], returns: "jsonb" },
    { name: "list_periods", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

export const PERIODS: BlockSqlDefinition = {
  name: "periods",
  scopes: ["tenant"],
  title: "Periods",
  description:
    "Dated periods per kind with open, locked and closed states, a lookup by date and a close protocol where blocks contribute close blockers and an on-close step.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
