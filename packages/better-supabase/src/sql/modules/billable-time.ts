import type { BillableTimeEvents } from "../../blocks/billable-time/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
} from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const GROUPINGS = ["subject", "member", "entry"] as const;

const EVENTS: BlockSqlEvents<BillableTimeEvents> = {
  "time.invoiced": {
    subject: "invoices",
    payload: ["organizationId", "invoiceId", "entryIds", "currency", "total"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    time_rate: {
      table: "rates",
      singular: "time_rate",
      plural: "time_rates",
      primary: true,
    },
  },
  events: EVENTS,
  options: [],
  tables: {
    rates: {
      name: "time_rates",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        rate: "rate",
        currency: "currency",
        effectiveFrom: "effective_from",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["createdBy", "createdAt"],
    },
    billed: {
      name: "time_invoice_entries",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        entry: "entry_id",
        tenant: "tenant_id",
        invoice: "invoice_id",
        rate: "rate",
        currency: "currency",
        seconds: "seconds",
        createdAt: "created_at",
      },
      optional: ["createdAt"],
    },
  },
};

function weekZone(ctx: BlockSqlContext): string {
  const zone = ctx.of("time-tracking").option("timeZone");

  return typeof zone === "string" && zone.length > 0 ? zone : "UTC";
}

function tables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const time = ctx.of("time-tracking");
  const invoices = ctx.of("invoices");
  const rates = ctx.table("rates");
  const billed = ctx.table("billed");
  const r = (column: string): string => ctx.col("rates", column);
  const b = (column: string): string => ctx.col("billed", column);
  const read = ctx.permission("read", moduleOperations("billable-time").read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  const rateKey = [
    "tenant",
    "user",
    "subjectType",
    "subjectId",
    "effectiveFrom",
  ].map(r);

  // set_time_rate upserts on the rate key; the app's table needs an index for it.
  const rateKeyIndex = ctx.owns("rates")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("rates").name}_rate_key`)} on ${rates} (${rateKey.join(", ")}) nulls not distinct;`;

  return `
create table if not exists ${rates} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("user")} uuid,
  ${r("subjectType")} text,
  ${r("subjectId")} text,
  -- Minor units of currency per hour (ADR 0037).
  ${r("rate")} bigint not null check (${r("rate")} >= 0),
  ${r("currency")} char(3) not null check (${r("currency")} ~ '^[A-Z]{3}$'),
  ${r("effectiveFrom")} date not null default current_date,${column("rates", "createdBy", (name) => `${name} uuid`)}${column("rates", "createdAt", (name) => `${name} timestamptz not null default now()`)}
  check ((${r("subjectType")} is null) = (${r("subjectId")} is null)),
  unique nulls not distinct (${rateKey.join(", ")})
);${rateKeyIndex}
create index if not exists ${index("rates", "lookup_idx")} on ${rates} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("user")}, ${r("effectiveFrom")} desc);
${lockModuleTable(ctx, "rates", { read: true })}
drop policy if exists ${index("rates", "read")} on ${rates};
create policy ${index("rates", "read")} on ${rates} for select to authenticated
  using (${ctx.scope.check(r("tenant"), read)});

-- One row per billed time entry: the invoice and the rate it was billed at.
create table if not exists ${billed} (
  ${b("entry")} uuid primary key references ${time.table("entries")} (${time.col("entries", "id")}) on delete restrict,
  ${b("tenant")} ${ctx.idType} not null,
  ${b("invoice")} uuid not null references ${invoices.table("invoices")} (${invoices.col("invoices", "id")}) on delete cascade,
  ${b("rate")} bigint not null,
  ${b("currency")} char(3) not null,
  ${b("seconds")} bigint not null${ctx.has("billed", "createdAt") ? `,\n  ${b("createdAt")} timestamptz not null default now()` : ""}
);
create index if not exists ${index("billed", "invoice_idx")} on ${billed} (${b("invoice")});
create index if not exists ${index("billed", "tenant_idx")} on ${billed} (${b("tenant")});
${lockModuleTable(ctx, "billed", { read: true })}
drop policy if exists ${index("billed", "read")} on ${billed};
create policy ${index("billed", "read")} on ${billed} for select to authenticated
  using (${ctx.scope.check(b("tenant"), read)});
`;
}

function functions(ctx: BlockSqlContext): string {
  const time = ctx.of("time-tracking");
  const invoices = ctx.of("invoices");
  const members = ctx.of("memberships");
  const entries = time.table("entries");
  const e = (column: string): string => time.col("entries", column);
  const rates = ctx.table("rates");
  const billed = ctx.table("billed");
  const r = (column: string): string => ctx.col("rates", column);
  const b = (column: string): string => ctx.col("billed", column);
  const iv = (column: string): string => invoices.col("invoices", column);
  const fn = (name: string): string => ctx.fn(name);
  const ops = moduleOperations("billable-time");
  const read = ctx.permission("read", ops.read);

  // `row.column`, or null when the app's table lacks the column.
  const or = (table: string, row: string, logical: string): string =>
    ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null";

  const manage = ctx.permission("manage", ops.manage);
  const invoice = ctx.permission("invoice", ops.invoice);
  const zone = sqlString(weekZone(ctx));
  const createdBy = ctx.has("rates", "createdBy");

  // The app's table can have columns named like the entry columns joined next to them.
  const billedColumns = ctx.owns("billed")
    ? "d.*"
    : ["entry", "invoice", "rate", "currency", "seconds", "createdAt"]
        .filter((logical) => ctx.has("billed", logical))
        .map((logical) => `d.${b(logical)}`)
        .join(", ");

  const groupings = GROUPINGS.map((each) => sqlString(each)).join(", ");

  const can = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("BILLABLE_TIME_FORBIDDEN", message);

  const rateJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'userId', ${row}.${r("user")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'rate', ${row}.${r("rate")}::text, 'currency', ${row}.${r("currency")}, 'effectiveFrom', ${row}.${r("effectiveFrom")}, 'createdBy', ${or("rates", row, "createdBy")}, 'createdAt', ${or("rates", row, "createdAt")})`;

  const seconds = (row: string): string =>
    `extract(epoch from ${row}.${e("endedAt")} - ${row}.${e("startedAt")})`;

  const billingChanged = [
    "startedAt",
    "endedAt",
    "billable",
    "rate",
    "rateCurrency",
  ]
    .map((column) => `old.${e(column)} is distinct from new.${e(column)}`)
    .join(" or ");

  // The entries a scope selects that are billable, finished and not billed,
  // each with the rate that applies: its own, else the rate card's.
  const unbilled = (tenant: string, scope: string): string => `
    select x.${e("id")} as id, x.${e("user")} as user_id, x.${e("subjectType")} as subject_type, x.${e("subjectId")} as subject_id,
      x.${e("startedAt")} as started_at, x.${e("note")} as note, ${seconds("x")} as seconds,
      coalesce(x.${e("rate")}, card.rate) as rate, coalesce(x.${e("rateCurrency")}, card.currency) as currency
    from ${entries} x
    left join lateral (
      select c.${r("rate")} as rate, c.${r("currency")}::text as currency
      from ${rates} c
      where c.${r("tenant")} = x.${e("tenant")}
        and (c.${r("user")} is null or c.${r("user")} = x.${e("user")})
        and (c.${r("subjectType")} is null or (c.${r("subjectType")} = x.${e("subjectType")} and c.${r("subjectId")} = x.${e("subjectId")}))
        and c.${r("effectiveFrom")} <= (x.${e("startedAt")} at time zone ${zone})::date
      order by (c.${r("subjectType")} is not null) desc, (c.${r("user")} is not null) desc, c.${r("effectiveFrom")} desc
      limit 1
    ) card on x.${e("rate")} is null
    where x.${e("tenant")} = ${tenant}
      and x.${e("billable")} and x.${e("endedAt")} is not null
      and not exists (select 1 from ${billed} d where d.${b("entry")} = x.${e("id")})
      and (${scope} -> 'subject' is null or (x.${e("subjectType")} = ${scope} -> 'subject' ->> 'type' and x.${e("subjectId")} = ${scope} -> 'subject' ->> 'id'))
      and (${scope} ->> 'userId' is null or x.${e("user")} = (${scope} ->> 'userId')::uuid)
      and (${scope} ->> 'starts' is null or x.${e("startedAt")} >= (${scope} ->> 'starts')::timestamptz)
      and (${scope} ->> 'ends' is null or x.${e("startedAt")} < (${scope} ->> 'ends')::timestamptz)
      and (${scope} -> 'entryIds' is null or x.${e("id")}::text in (select jsonb_array_elements_text(${scope} -> 'entryIds')))`;

  // Rated entries as invoice lines: hours to four decimals times the hourly
  // rate, one line per record and rate, per member too, or per entry.
  const lines = (source: string, grouping: string): string => `
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when ${grouping} = 'entry' then min(u.user_id::text) end as user_text,
      case when ${grouping} = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when ${grouping} = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone ${zone}, 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (${source}) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when ${grouping} in ('member', 'entry') then u.user_id end,
      case when ${grouping} = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0`;

  const lineJson = (row: string): string =>
    `jsonb_build_object('description', ${row}.description, 'quantity', ${row}.quantity, 'unitAmount', ${row}.rate::text, 'currency', ${row}.currency, 'amount', round(${row}.quantity * ${row}.rate)::bigint::text, 'entryIds', ${row}.entry_ids, 'subjectType', ${row}.subject_type, 'subjectId', ${row}.subject_id, 'userId', coalesce(${row}.member_text, ${row}.user_text))`;

  const checkGrouping = (
    value: string,
  ): string => `if ${value} not in (${groupings}) then
    ${fail("BILLABLE_TIME_GROUPING_INVALID", "group_by is subject, member or entry", "22023")}
  end if;`;

  return `
-- A billed entry keeps what it was billed for: it can't be deleted, and its
-- time, billable flag and rate can't change until the invoice is voided. Its
-- record can, so a merge can move it.
create or replace function ${fn("billable_time_guard")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from ${billed} d where d.${b("entry")} = old.${e("id")}) then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    ${fail("TIME_ENTRY_INVOICED", "this entry is on an invoice; void the invoice to delete it", "23001")}
  end if;
  if ${billingChanged} then
    ${fail("TIME_ENTRY_INVOICED", "this entry is on an invoice; void the invoice to change it", "55000")}
  end if;
  return new;
end;
$$;
revoke execute on function ${fn("billable_time_guard")}() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_guard on ${entries};
create trigger bsb_billable_time_guard
  before update or delete on ${entries}
  for each row execute function ${fn("billable_time_guard")}();

-- Voiding an invoice releases its entries so they can be billed again.
create or replace function ${fn("billable_time_release")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${billed} d where d.${b("invoice")} = new.${iv("id")};
  return new;
end;
$$;
revoke execute on function ${fn("billable_time_release")}() from public, anon, authenticated;
drop trigger if exists bsb_billable_time_release on ${invoices.table("invoices")};
create trigger bsb_billable_time_release
  after update of ${iv("status")} on ${invoices.table("invoices")}
  for each row when (new.${iv("status")} = 'void' and old.${iv("status")} <> 'void')
  execute function ${fn("billable_time_release")}();

-- Sets the hourly rate for a member, a record, both, or the organization
-- (neither), from effective_from (today by default). The same key and day
-- replaces the rate.
create or replace function ${fn("set_time_rate")}(tenant ${ctx.idType}, rate bigint, currency text, user_id uuid default null, subject_type text default null, subject_id text default null, effective_from date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${rates}%rowtype;
begin
  if not ${can("set_time_rate.tenant", manage)} then
    ${forbidden("not allowed to change the rate card")}
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    ${fail("TIME_RATE_INVALID", "a rate is 0 or more minor units per hour", "22023")}
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    ${fail("TIME_RATE_INVALID", "currency must be a three-letter currency code", "22023")}
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    ${fail("TIME_RATE_INVALID", "name both subject_type and subject_id, or neither", "22023")}
  end if;
  if set_time_rate.subject_type is not null and not ${subjectInTenant(ctx, "set_time_rate.subject_type", "set_time_rate.subject_id", "set_time_rate.tenant")} then
    ${fail("TIME_RATE_SUBJECT_INVALID", "the record is unknown or not in this organization", "22023")}
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from ${members.table("memberships")} m
    where m.${members.col("memberships", "tenant")} = set_time_rate.tenant and m.${members.col("memberships", "user")} = set_time_rate.user_id
  ) then
    ${fail("TIME_RATE_MEMBER_INVALID", "the user is not a member of this organization", "22023")}
  end if;
  insert into ${rates} (${r("tenant")}, ${r("user")}, ${r("subjectType")}, ${r("subjectId")}, ${r("rate")}, ${r("currency")}, ${r("effectiveFrom")}${createdBy ? `, ${r("createdBy")}` : ""})
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date)${createdBy ? ", auth.uid()" : ""})
  on conflict (${r("tenant")}, ${r("user")}, ${r("subjectType")}, ${r("subjectId")}, ${r("effectiveFrom")})
  do update set ${r("rate")} = excluded.${r("rate")}, ${r("currency")} = excluded.${r("currency")}${createdBy ? `, ${r("createdBy")} = excluded.${r("createdBy")}` : ""}
  returning * into v_row;
  return ${rateJson("v_row")};
end;
$$;
${userGrant(`${fn("set_time_rate")}(${ctx.idType}, bigint, text, uuid, text, text, date)`)}

create or replace function ${fn("delete_time_rate")}(rate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${rates}%rowtype;
begin
  select * into v_row from ${rates} x where x.${r("id")} = delete_time_rate.rate_id;
  if not found or not ${can(`v_row.${r("tenant")}`, manage)} then
    ${fail("TIME_RATE_NOT_FOUND", "no such rate you can change", "P0002")}
  end if;
  delete from ${rates} x where x.${r("id")} = v_row.${r("id")};
  return ${rateJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_time_rate")}(uuid)`)}

-- The rate card, newest first per key. Filters narrow it to a member or a
-- record (organization-wide rates are those with neither).
create or replace function ${fn("list_time_rates")}(tenant ${ctx.idType}, user_id uuid default null, subject_type text default null, subject_id text default null, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${can("list_time_rates.tenant", read)} then
    ${forbidden("not allowed to read the rate card")}
  end if;
  return (
    select coalesce(jsonb_agg(${rateJson("q")} order by q.${r("subjectType")} nulls first, q.${r("subjectId")} nulls first, q.${r("user")} nulls first, q.${r("effectiveFrom")} desc), '[]'::jsonb)
    from (
      select * from ${rates} x
      where x.${r("tenant")} = list_time_rates.tenant
        and (list_time_rates.user_id is null or x.${r("user")} = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x.${r("subjectType")} = list_time_rates.subject_type and x.${r("subjectId")} = list_time_rates.subject_id))
      order by x.${r("effectiveFrom")} desc
      limit ${pageSize("list_time_rates.page_size", 200, 1000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_time_rates")}(${ctx.idType}, uuid, text, text, integer)`)}

-- The rate card entry that applies to a member's time on a record on a day:
-- member and record first, then the record, the member, the organization.
create or replace function ${fn("time_rate")}(tenant ${ctx.idType}, user_id uuid default null, subject_type text default null, subject_id text default null, on_day date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${can("time_rate.tenant", read)} then
    ${forbidden("not allowed to read the rate card")}
  end if;
  return (
    select ${rateJson("c")} from ${rates} c
    where c.${r("tenant")} = time_rate.tenant
      and (c.${r("user")} is null or c.${r("user")} = time_rate.user_id)
      and (c.${r("subjectType")} is null or (c.${r("subjectType")} = time_rate.subject_type and c.${r("subjectId")} = time_rate.subject_id))
      and c.${r("effectiveFrom")} <= coalesce(time_rate.on_day, current_date)
    order by (c.${r("subjectType")} is not null) desc, (c.${r("user")} is not null) desc, c.${r("effectiveFrom")} desc
    limit 1
  );
end;
$$;
${userGrant(`${fn("time_rate")}(${ctx.idType}, uuid, text, text, date)`)}

-- What invoice_from_time would bill: the lines per currency, their totals,
-- and the billable entries no rate covers. scope: subject ({ type, id }),
-- userId, starts, ends (on started_at) and entryIds.
create or replace function ${fn("unbilled_time")}(tenant ${ctx.idType}, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not ${can("unbilled_time.tenant", read)} then
    ${forbidden("not allowed to read billable time")}
  end if;
  ${checkGrouping("unbilled_time.group_by")}
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(${lineJson("l")} order by l.currency, l.first_at), '[]'::jsonb)
      from (${lines(unbilled("unbilled_time.tenant", "v_scope"), "unbilled_time.group_by")}) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (${lines(unbilled("unbilled_time.tenant", "v_scope"), "unbilled_time.group_by")}) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
      from (${unbilled("unbilled_time.tenant", "v_scope")}) u where u.rate is null)
  );
end;
$$;
${userGrant(`${fn("unbilled_time")}(${ctx.idType}, jsonb, text)`)}

-- Bills the unbilled time a scope selects on a new draft invoice. attrs go to
-- create_invoice (title, default Time; company; contact; termsDays; note); its currency
-- picks the entries in that currency, and without one the entries must share
-- one. Fails while a selected billable entry has no rate.
create or replace function ${fn("invoice_from_time")}(tenant ${ctx.idType}, attrs jsonb, scope jsonb default null, group_by text default 'subject')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not ${can("invoice_from_time.tenant", invoice)} then
    ${forbidden("not allowed to invoice time")}
  end if;
  ${checkGrouping("invoice_from_time.group_by")}
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (${unbilled("invoice_from_time.tenant", "v_scope")}) u;
  if v_unrated > 0 then
    ${fail("TIME_RATE_MISSING", "some billable entries have no rate; set one on the entry or the rate card", "22023")}
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      ${fail("BILLABLE_TIME_CURRENCIES", "the entries are billed in several currencies; name one", "22023")}
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (${lines(unbilled("invoice_from_time.tenant", "v_scope"), "invoice_from_time.group_by")}) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    ${fail("BILLABLE_TIME_EMPTY", "no unbilled billable time matches", "P0002")}
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := ${invoices.fn("create_invoice")}(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into ${billed} (${b("entry")}, ${b("tenant")}, ${b("invoice")}, ${b("rate")}, ${b("currency")}, ${b("seconds")})
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (${unbilled("invoice_from_time.tenant", "v_scope")}) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  ${ctx.record({
    type: "time.invoiced",
    payload: `jsonb_build_object('organizationId', invoice_from_time.tenant, 'invoiceId', v_invoice ->> 'id', 'entryIds', v_entries, 'currency', v_currency, 'total', v_total::text)`,
    subject: `'invoices/' || (v_invoice ->> 'id')`,
    tenant: "invoice_from_time.tenant::text",
    audit: {
      category: "billing",
      targetType: "invoice",
      recordId: "v_invoice ->> 'id'",
      summary: "'invoiced time'",
    },
  })}
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$$;
${userGrant(`${fn("invoice_from_time")}(${ctx.idType}, jsonb, jsonb, text)`)}

-- The entries an invoice billed, with the rate and seconds it billed.
create or replace function ${fn("list_invoiced_time")}(invoice uuid, page_size integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select x.${iv("tenant")} into v_tenant from ${invoices.table("invoices")} x where x.${iv("id")} = list_invoiced_time.invoice;
  if v_tenant is null or not ${can("v_tenant", read)} then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('entryId', q.${b("entry")}, 'invoiceId', q.${b("invoice")}, 'userId', q.user_id,
      'subjectType', q.subject_type, 'subjectId', q.subject_id, 'startedAt', q.started_at, 'seconds', q.${b("seconds")},
      'rate', q.${b("rate")}::text, 'currency', q.${b("currency")}, 'createdAt', ${or("billed", "q", "createdAt")}) order by q.started_at, q.${b("entry")}), '[]'::jsonb)
    from (
      select ${billedColumns}, x.${e("user")} as user_id, x.${e("subjectType")} as subject_type, x.${e("subjectId")} as subject_id, x.${e("startedAt")} as started_at
      from ${billed} d join ${entries} x on x.${e("id")} = d.${b("entry")}
      where d.${b("invoice")} = list_invoiced_time.invoice
      order by x.${e("startedAt")}
      limit ${pageSize("list_invoiced_time.page_size", 500, 2000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_invoiced_time")}(uuid, integer)`)}
`;
}

/** Moves the rates on a merged registered subject to the record it merged into. */
function rateMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("rates"),
        type: ctx.col("rates", "subjectType"),
        id: ctx.col("rates", "subjectId"),
        unique: [
          ctx.col("rates", "tenant"),
          ctx.col("rates", "user"),
          ctx.col("rates", "effectiveFrom"),
        ],
      },
      "v_type",
    ),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  for (const needed of ["time-tracking", "invoices"]) {
    if (ctx.of(needed).mode === "custom") {
      throw new TypeError(
        `blocks.billable-time needs the ${needed} tables; ${needed} can't be in custom mode`,
      );
    }
  }

  return `${schemaPreamble(ctx)}
-- Billable time: a rate card for time entries and invoices drafted from
-- unbilled time, in bigint minor units.
${tables(ctx)}${functions(ctx)}${rateMerges(ctx)}`;
}

function contract(_ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "set_time_rate",
      args: ["{id}", "bigint", "text", "uuid", "text", "text", "date"],
      returns: "jsonb",
    },
    { name: "delete_time_rate", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_time_rates",
      args: ["{id}", "uuid", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "time_rate",
      args: ["{id}", "uuid", "text", "text", "date"],
      returns: "jsonb",
    },
    {
      name: "unbilled_time",
      args: ["{id}", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "invoice_from_time",
      args: ["{id}", "jsonb", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "list_invoiced_time", args: ["uuid", "integer"], returns: "jsonb" },
  ];
}

export const BILLABLE_TIME: BlockSqlDefinition = {
  name: "billable-time",
  scopes: ["tenant"],
  title: "Billable time",
  description:
    "A rate card for time entries, by member, record or organization with effective dates, and draft invoices from unbilled billable time with one line per record, member or entry, in bigint minor units. Billed entries lock until the invoice is voided.",
  requires: [
    "memberships",
    "permissions",
    "subjects",
    "time-tracking",
    "invoices",
  ],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
