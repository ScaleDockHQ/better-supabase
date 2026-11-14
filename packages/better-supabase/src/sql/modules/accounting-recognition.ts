import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";
import type {
  AccountingContribution,
  PeriodContribution,
} from "../contributions.ts";

import { serviceGrant, userGrant } from "../shared.ts";
import { accountingSql } from "./accounting-shared.ts";

const TENANT_TABLE = { tenant: "tenant", export: true } as const;

/** The tables that hold revenue recognition schedules and their monthly rows. */
export const RECOGNITION_TABLES: Readonly<Record<string, BlockSqlTableSpec>> = {
  recognitionSchedules: {
    name: "accounting_recognition_schedules",
    app: {},
    lifecycle: TENANT_TABLE,
    columns: {
      id: "id",
      tenant: "tenant_id",
      sourceType: "source_type",
      sourceId: "source_id",
      lineRef: "line_ref",
      amount: "amount",
      currency: "currency",
      startsOn: "starts_on",
      endsOn: "ends_on",
      deferralEntry: "deferral_entry_id",
      createdAt: "created_at",
    },
  },
  recognitionRows: {
    name: "accounting_recognition_rows",
    app: {},
    lifecycle: TENANT_TABLE,
    columns: {
      id: "id",
      schedule: "schedule_id",
      tenant: "tenant_id",
      dueOn: "due_on",
      amount: "amount",
      status: "status",
      entry: "entry_id",
      postedAt: "posted_at",
    },
  },
};

/** Whether `options.recognition` turns the schedule engine on. */
function recognizes(ctx: BlockSqlContext): boolean {
  return ctx.mode !== "custom" && ctx.option("recognition") === true;
}

/**
 * The tables behind `options.recognition`: one schedule per invoice line (or
 * any other source) and one row per calendar month the amount is earned in.
 */
export function recognitionTables(ctx: BlockSqlContext): string {
  const schedules = ctx.table("recognitionSchedules");
  const rows = ctx.table("recognitionRows");
  const s = (column: string): string => ctx.col("recognitionSchedules", column);
  const r = (column: string): string => ctx.col("recognitionRows", column);
  const id = ctx.idType;

  return `
-- A schedule defers amount (minor units of currency) over [starts_on, ends_on]:
-- one per source line, so scheduling a line twice returns the first schedule.
create table if not exists ${schedules} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${id} not null,
  ${s("sourceType")} text not null check (length(${s("sourceType")}) between 1 and 100),
  ${s("sourceId")} text not null check (length(${s("sourceId")}) between 1 and 200),
  ${s("lineRef")} text not null default '' check (length(${s("lineRef")}) <= 200),
  ${s("amount")} bigint not null check (${s("amount")} > 0),
  ${s("currency")} text not null check (${s("currency")} ~ '^[A-Z]{3}$'),
  ${s("startsOn")} date not null,
  ${s("endsOn")} date not null,
  ${s("deferralEntry")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  check (${s("endsOn")} >= ${s("startsOn")}),
  unique (${s("tenant")}, ${s("sourceType")}, ${s("sourceId")}, ${s("lineRef")})
);
alter table ${schedules} enable row level security;
revoke all on ${schedules} from anon, authenticated;
grant all on ${schedules} to service_role;

-- The part of a schedule earned in one month, due on the month's last day (or
-- the schedule's end). The period close posts pending rows into the books.
create table if not exists ${rows} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("schedule")} uuid not null references ${schedules} (${s("id")}) on delete cascade,
  ${r("tenant")} ${id} not null,
  ${r("dueOn")} date not null,
  ${r("amount")} bigint not null check (${r("amount")} > 0),
  ${r("status")} text not null default 'pending' check (${r("status")} in ('pending', 'posted')),
  ${r("entry")} uuid,
  ${r("postedAt")} timestamptz
);
create index if not exists accounting_recognition_rows_schedule_idx on ${rows} (${r("schedule")});
create index if not exists accounting_recognition_rows_due_idx on ${rows} (${r("tenant")}, ${r("dueOn")}) where ${r("status")} = 'pending';
alter table ${rows} enable row level security;
revoke all on ${rows} from anon, authenticated;
grant all on ${rows} to service_role;
`;
}

/**
 * Revenue recognition (ADR 0197): `schedule_revenue_recognition` spreads an
 * amount over the months it is earned in and books the deferral (revenue
 * against deferred revenue); the `revenue_recognition` period kind posts each
 * month's row when that period closes.
 */
export function recognitionFunctions(ctx: BlockSqlContext): string {
  if (!recognizes(ctx)) {
    return "";
  }

  const schedules = ctx.table("recognitionSchedules");
  const rows = ctx.table("recognitionRows");
  const periods = ctx.table("periods");
  const s = (column: string): string => ctx.col("recognitionSchedules", column);
  const r = (column: string): string => ctx.col("recognitionRows", column);
  const p = (column: string): string => ctx.col("periods", column);
  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;
  const sql = accountingSql(ctx);

  return `
-- Schedules the recognition of an amount over [starts_on, ends_on] in whole
-- calendar months, each month's share in proportion to its days (the last row
-- takes the rounding), and books the deferral: revenue against deferred revenue,
-- dated starts_on. A second call for the same source line returns the first
-- schedule. Needs accounting.post.
create or replace function ${fn("schedule_revenue_recognition")}(tenant ${id}, source_type text, source_id text, amount bigint, currency text, starts_on date, ends_on date, line_ref text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_schedule ${schedules}%rowtype;
  v_ref text := coalesce(schedule_revenue_recognition.line_ref, '');
  v_days integer;
  v_from date;
  v_to date;
  v_part bigint;
  v_assigned bigint := 0;
  v_month date;
  v_entry uuid;
begin
  if not ${sql.allowed("schedule_revenue_recognition.tenant", sql.post)} then
    ${sql.forbidden("ACCOUNTING_RECOGNITION", "not allowed to schedule revenue recognition")}
  end if;
  if schedule_revenue_recognition.amount is null or schedule_revenue_recognition.amount <= 0
    or schedule_revenue_recognition.starts_on is null or schedule_revenue_recognition.ends_on is null
    or schedule_revenue_recognition.ends_on < schedule_revenue_recognition.starts_on
    or coalesce(schedule_revenue_recognition.currency, '') !~ '^[A-Z]{3}$'
    or coalesce(schedule_revenue_recognition.source_type, '') = '' or coalesce(schedule_revenue_recognition.source_id, '') = '' then
    ${sql.invalid("ACCOUNTING_RECOGNITION", "a schedule needs a source, a positive amount, a currency and a range that ends on or after it starts")}
  end if;
  select * into v_schedule from ${schedules} y
    where y.${s("tenant")} = schedule_revenue_recognition.tenant and y.${s("sourceType")} = schedule_revenue_recognition.source_type
      and y.${s("sourceId")} = schedule_revenue_recognition.source_id and y.${s("lineRef")} = v_ref;
  if not found then
    insert into ${schedules} (${s("tenant")}, ${s("sourceType")}, ${s("sourceId")}, ${s("lineRef")}, ${s("amount")}, ${s("currency")}, ${s("startsOn")}, ${s("endsOn")})
    values (schedule_revenue_recognition.tenant, schedule_revenue_recognition.source_type, schedule_revenue_recognition.source_id, v_ref,
      schedule_revenue_recognition.amount, schedule_revenue_recognition.currency, schedule_revenue_recognition.starts_on, schedule_revenue_recognition.ends_on)
    returning * into v_schedule;
    v_days := schedule_revenue_recognition.ends_on - schedule_revenue_recognition.starts_on + 1;
    for v_month in
      select m::date from generate_series(date_trunc('month', schedule_revenue_recognition.starts_on::timestamp),
        date_trunc('month', schedule_revenue_recognition.ends_on::timestamp), interval '1 month') m
    loop
      v_from := greatest(v_month, schedule_revenue_recognition.starts_on);
      v_to := least((v_month + interval '1 month')::date - 1, schedule_revenue_recognition.ends_on);
      v_part := case when v_to = schedule_revenue_recognition.ends_on then schedule_revenue_recognition.amount - v_assigned
        else round(schedule_revenue_recognition.amount * (v_to - v_from + 1)::numeric / v_days)::bigint end;
      v_assigned := v_assigned + v_part;
      if v_part > 0 then
        insert into ${rows} (${r("schedule")}, ${r("tenant")}, ${r("dueOn")}, ${r("amount")})
        values (v_schedule.${s("id")}, v_schedule.${s("tenant")}, v_to, v_part);
      end if;
    end loop;
    v_entry := ${fn("accounting_post_source")}('revenue_deferral', v_schedule.${s("id")}::text);
    update ${schedules} y set ${s("deferralEntry")} = v_entry where y.${s("id")} = v_schedule.${s("id")}
      returning * into v_schedule;
  end if;
  return jsonb_build_object('id', v_schedule.${s("id")}, 'amount', v_schedule.${s("amount")}::text, 'currency', v_schedule.${s("currency")},
    'starts_on', v_schedule.${s("startsOn")}, 'ends_on', v_schedule.${s("endsOn")}, 'deferral_entry_id', v_schedule.${s("deferralEntry")},
    'rows', (select count(*) from ${rows} y where y.${r("schedule")} = v_schedule.${s("id")}));
end;
$$;
${userGrant(`${fn("schedule_revenue_recognition")}(${id}, text, text, bigint, text, date, date, text)`)}

-- The monthly rows of a source's schedules, oldest first. Needs accounting.read.
create or replace function ${fn("list_revenue_recognition")}(tenant ${id}, source_type text, source_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${sql.allowed("list_revenue_recognition.tenant", sql.read)} then
    ${sql.forbidden("ACCOUNTING_RECOGNITION", "not allowed to read revenue recognition")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('schedule_id', y.${r("schedule")}, 'due_on', y.${r("dueOn")}, 'amount', y.${r("amount")}::text,
      'status', y.${r("status")}, 'entry_id', y.${r("entry")}) order by y.${r("dueOn")}, y.${r("id")})
    from ${rows} y join ${schedules} z on z.${s("id")} = y.${r("schedule")}
    where z.${s("tenant")} = list_revenue_recognition.tenant and z.${s("sourceType")} = list_revenue_recognition.source_type
      and z.${s("sourceId")} = list_revenue_recognition.source_id
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_revenue_recognition")}(${id}, text, text)`)}

-- Every schedule of the tenant, newest first, with the months it spreads over
-- and the part already recognized (posted rows), for a list that needs no
-- source. limit_count is 1 to 500 (default 100). Needs accounting.read.
create or replace function ${fn("list_revenue_recognition_schedules")}(tenant ${id}, limit_count integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${sql.allowed("list_revenue_recognition_schedules.tenant", sql.read)} then
    ${sql.forbidden("ACCOUNTING_RECOGNITION", "not allowed to read revenue recognition")}
  end if;
  return coalesce((
    select jsonb_agg(x.item order by x.created_at desc, x.id desc) from (
      select z.${s("id")} as id, z.${s("createdAt")} as created_at, jsonb_build_object(
        'id', z.${s("id")}, 'source_type', z.${s("sourceType")}, 'source_id', z.${s("sourceId")}, 'line_ref', z.${s("lineRef")},
        'amount', z.${s("amount")}::text, 'currency', z.${s("currency")}, 'starts_on', z.${s("startsOn")}, 'ends_on', z.${s("endsOn")},
        'deferral_entry_id', z.${s("deferralEntry")},
        'rows', (select count(*) from ${rows} y where y.${r("schedule")} = z.${s("id")}),
        'recognized', coalesce((select sum(y.${r("amount")}) from ${rows} y where y.${r("schedule")} = z.${s("id")} and y.${r("status")} = 'posted'), 0)::text) as item
      from ${schedules} z
      where z.${s("tenant")} = list_revenue_recognition_schedules.tenant
      order by z.${s("createdAt")} desc, z.${s("id")} desc
      limit least(greatest(coalesce(list_revenue_recognition_schedules.limit_count, 100), 1), 500)
    ) x
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_revenue_recognition_schedules")}(${id}, integer)`)}

-- The entry that moves a schedule's amount out of revenue into deferred
-- revenue when it starts.
create or replace function ${fn("accounting_recognition_deferral_lines")}(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', x.${s("tenant")}, 'entryDate', x.${s("startsOn")}, 'currency', x.${s("currency")},
    'reference', x.${s("sourceType")} || ':' || x.${s("sourceId")}, 'memo', 'Defer revenue',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'revenue', 'debit', x.${s("amount")}::text),
      jsonb_build_object('role', 'deferred_revenue', 'credit', x.${s("amount")}::text)))
  from ${schedules} x where x.${s("id")}::text = accounting_recognition_deferral_lines.source_id
$$;
revoke execute on function ${fn("accounting_recognition_deferral_lines")}(text) from public, anon, authenticated;

-- The entry that recognizes one month of a schedule: deferred revenue back into
-- revenue, dated the row's due date.
create or replace function ${fn("accounting_recognition_lines")}(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', y.${r("tenant")}, 'entryDate', y.${r("dueOn")}, 'currency', x.${s("currency")},
    'reference', x.${s("sourceType")} || ':' || x.${s("sourceId")}, 'memo', 'Recognize revenue',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'deferred_revenue', 'debit', y.${r("amount")}::text),
      jsonb_build_object('role', 'revenue', 'credit', y.${r("amount")}::text)))
  from ${rows} y join ${schedules} x on x.${s("id")} = y.${r("schedule")}
  where y.${r("id")}::text = accounting_recognition_lines.source_id
$$;
revoke execute on function ${fn("accounting_recognition_lines")}(text) from public, anon, authenticated;

-- What keeps a revenue_recognition range from closing: pending rows due in it
-- whose accounting period is already closed or locked, which can't take the entry.
create or replace function ${fn("accounting_recognition_blockers")}(tenant ${id}, starts_on date, ends_on date)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case when exists (
    select 1 from ${rows} y
    where y.${r("tenant")} = accounting_recognition_blockers.tenant and y.${r("status")} = 'pending'
      and y.${r("dueOn")} between accounting_recognition_blockers.starts_on and accounting_recognition_blockers.ends_on
      and exists (
        select 1 from ${periods} q
        where q.${p("tenant")} = y.${r("tenant")} and q.${p("status")} <> 'open'
          and y.${r("dueOn")} between q.${p("startsOn")} and q.${p("endsOn")})
  ) then array['recognition_period_closed'] else '{}'::text[] end
$$;
${serviceGrant(`${fn("accounting_recognition_blockers")}(${id}, date, date)`)}

-- Posts the pending rows due in the range, oldest first, in the closing
-- transaction of the revenue_recognition period.
create or replace function ${fn("accounting_recognition_close")}(tenant ${id}, starts_on date, ends_on date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row record;
  v_entry uuid;
begin
  for v_row in
    select y.${r("id")} as id from ${rows} y
    where y.${r("tenant")} = accounting_recognition_close.tenant and y.${r("status")} = 'pending'
      and y.${r("dueOn")} between accounting_recognition_close.starts_on and accounting_recognition_close.ends_on
    order by y.${r("dueOn")}, y.${r("id")}
    for update
  loop
    v_entry := ${fn("accounting_post_source")}('revenue_recognition', v_row.id::text);
    if v_entry is not null then
      update ${rows} y set ${r("status")} = 'posted', ${r("entry")} = v_entry, ${r("postedAt")} = now()
        where y.${r("id")} = v_row.id;
    end if;
  end loop;
end;
$$;
${serviceGrant(`${fn("accounting_recognition_close")}(${id}, date, date)`)}
`;
}

/** The public functions of the schedule engine. */
export function recognitionContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return recognizes(ctx)
    ? [
        {
          name: "schedule_revenue_recognition",
          args: [
            "{id}",
            "text",
            "text",
            "bigint",
            "text",
            "date",
            "date",
            "text",
          ],
          returns: "jsonb",
        },
        {
          name: "list_revenue_recognition",
          args: ["{id}", "text", "text"],
          returns: "jsonb",
        },
        {
          name: "list_revenue_recognition_schedules",
          args: ["{id}", "integer"],
          returns: "jsonb",
        },
      ]
    : [];
}

/** The two entries the schedule engine books through `accounting_post_source`. */
export function recognitionSources(
  own: BlockSqlContext,
): readonly AccountingContribution[] {
  return recognizes(own)
    ? [
        {
          source: "revenue_deferral",
          journal: "general",
          lines: own.fn("accounting_recognition_deferral_lines"),
        },
        {
          source: "revenue_recognition",
          journal: "general",
          lines: own.fn("accounting_recognition_lines"),
        },
      ]
    : [];
}

/** The `revenue_recognition` period kind, closed month by month. */
export function recognitionPeriods(
  own: BlockSqlContext,
): readonly PeriodContribution[] {
  return recognizes(own)
    ? [
        {
          kind: "revenue_recognition",
          cadence: "month",
          blockers: own.fn("accounting_recognition_blockers"),
          onClose: own.fn("accounting_recognition_close"),
        },
      ]
    : [];
}
