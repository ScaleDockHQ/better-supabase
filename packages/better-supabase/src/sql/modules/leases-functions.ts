import type { ModuleContext } from "../context.ts";

import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { moduleOperations } from "./access-model.ts";

/** The length of one rent period of a frequency, as an interval. */
const step = (frequency: string): string =>
  `(case ${frequency} when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end)`;

/** The leases module's functions. */
export function leasesFunctions(ctx: ModuleContext): string {
  const assets = ctx.of("assets");
  const ledger = ctx.of("ledger");
  const members = ctx.of("tenant");
  const leases = ctx.table("leases");
  const charges = ctx.table("charges");
  const maintenance = ctx.table("maintenance");
  const l = (column: string): string => ctx.col("leases", column);
  const c = (column: string): string => ctx.col("charges", column);
  const m = (column: string): string => ctx.col("maintenance", column);
  const as = (column: string): string => assets.col("assets", column);
  const la = (column: string): string => ledger.col("accounts", column);
  const lb = (column: string): string => ledger.col("balances", column);
  const lh = (column: string): string => ledger.col("holds", column);
  const lt = (column: string): string => ledger.col("transactions", column);
  const holds = ledger.table("holds");
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const ops = moduleOperations("leases");
  const read = ctx.permission("read", ops.read);
  const manage = ctx.permission("manage", ops.manage);
  const maintain = ctx.permission("maintain", ops.maintain);

  const can = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("LEASES_FORBIDDEN", message);

  const invalid = (code: string, message: string): string =>
    fail(code, message, "22023");

  const notFound = fail(
    "LEASE_NOT_FOUND",
    "no such lease you can read",
    "P0002",
  );

  const rentCode = (lease: string): string =>
    `'lease:' || ${lease}::text || ':rent'`;

  const depositCode = (lease: string): string =>
    `'lease:' || ${lease}::text || ':deposit'`;

  /** The lease's receivable: what the party owes, rent less payments. */
  const rentAccount = (row: string): string =>
    `${ledger.fn("ledger_account_for")}(${row}.${l("tenant")}, 'lease_rent', ${rentCode(`${row}.${l("id")}`)}, 'Rent ' || ${row}.${l("title")},
      ${row}.${l("currency")}::text, 0::smallint, 'leases', ${row}.${l("id")}::text, null, true, ${read}, 'leases',
      jsonb_build_object('leaseId', ${row}.${l("id")}))`;

  /** The deposit the party paid, held while the lease runs. */
  const depositAccount = (row: string): string =>
    `${ledger.fn("ledger_account_for")}(${row}.${l("tenant")}, 'lease_deposit', ${depositCode(`${row}.${l("id")}`)}, 'Deposit ' || ${row}.${l("title")},
      ${row}.${l("currency")}::text, 0::smallint, 'leases', ${row}.${l("id")}::text, null, false, ${read}, 'leases',
      jsonb_build_object('leaseId', ${row}.${l("id")}))`;

  const sharedAccount = (row: string, kind: string, name: string): string =>
    `${ledger.fn("ledger_account_for")}(${row}.${l("tenant")}, 'lease_${kind}', 'leases:${kind}:' || ${row}.${l("currency")}, '${name} ' || ${row}.${l("currency")},
      ${row}.${l("currency")}::text, 0::smallint, null, null, null, true, ${read}, 'leases', null)`;

  const incomeAccount = (row: string): string =>
    sharedAccount(row, "income", "Rent income");

  const cashAccount = (row: string): string =>
    sharedAccount(row, "cash", "Rent received");

  const balanceDue = (row: string): string =>
    `coalesce((select y.${lb("balance")} from ${ledger.table("accounts")} x join ${ledger.table("balances")} y on y.${lb("account")} = x.${la("id")}
      where x.${la("tenant")} = ${row}.${l("tenant")} and x.${la("code")} = ${rentCode(`${row}.${l("id")}`)}), 0)`;

  const depositHeld = (row: string): string =>
    `coalesce((select h.${lh("amount")} from ${holds} h where h.${lh("id")} = ${row}.${l("depositHold")} and h.${lh("status")} = 'active'), 0)`;

  const leaseJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${l("id")}, 'organizationId', ${row}.${l("tenant")}, 'unitId', ${row}.${l("unit")}, 'partyType', ${row}.${l("partyType")}, 'partyId', ${row}.${l("partyId")}, 'title', ${row}.${l("title")}, 'status', ${row}.${l("status")}, 'startsOn', ${row}.${l("startsOn")}, 'endsOn', ${row}.${l("endsOn")}, 'rent', ${row}.${l("rent")}::text, 'currency', ${row}.${l("currency")}, 'frequency', ${row}.${l("frequency")}, 'deposit', ${row}.${l("deposit")}::text, 'depositHoldId', ${row}.${l("depositHold")}, 'depositHeld', ${depositHeld(row)}::text, 'balanceDue', ${balanceDue(row)}::text, 'renewedAt', ${row}.${l("renewedAt")}, 'terminatedOn', ${row}.${l("terminatedOn")}, 'terminationReason', ${row}.${l("terminationReason")}, 'metadata', ${row}.${l("metadata")}, 'createdBy', ${row}.${l("createdBy")}, 'createdAt', ${row}.${l("createdAt")}, 'updatedAt', ${row}.${l("updatedAt")})`;

  const chargeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'leaseId', ${row}.${c("lease")}, 'periodStart', ${row}.${c("periodStart")}, 'periodEnd', ${row}.${c("periodEnd")}, 'amount', ${row}.${c("amount")}::text, 'currency', ${row}.${c("currency")}, 'transactionId', ${row}.${c("transaction")}, 'createdAt', ${row}.${c("createdAt")})`;

  const maintenanceJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'unitId', ${row}.${m("unit")}, 'leaseId', ${row}.${m("lease")}, 'title', ${row}.${m("title")}, 'description', ${row}.${m("description")}, 'priority', ${row}.${m("priority")}, 'status', ${row}.${m("status")}, 'reportedBy', ${row}.${m("reportedBy")}, 'assigneeId', ${row}.${m("assignee")}, 'resolvedAt', ${row}.${m("resolvedAt")}, 'createdAt', ${row}.${m("createdAt")}, 'updatedAt', ${row}.${m("updatedAt")})`;

  const leaseRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${l("tenant")}, 'id', ${row}.${l("id")}, 'unitId', ${row}.${l("unit")}, 'partyType', ${row}.${l("partyType")}, 'partyId', ${row}.${l("partyId")}, 'status', ${row}.${l("status")}, 'startsOn', ${row}.${l("startsOn")}, 'endsOn', ${row}.${l("endsOn")}, 'rent', ${row}.${l("rent")}::text, 'currency', ${row}.${l("currency")})`,
      subject: `'leases/' || ${row}.${l("id")}::text`,
      tenant: `${row}.${l("tenant")}`,
      audit: {
        category: "billing",
        targetType: "lease",
        recordId: `${row}.${l("id")}::text`,
        targetLabel: `${row}.${l("title")}`,
        summary: `'${summary}'`,
      },
    });

  const maintenanceRecord = (
    type: string,
    row: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${m("tenant")}, 'id', ${row}.${m("id")}, 'unitId', ${row}.${m("unit")}, 'leaseId', ${row}.${m("lease")}, 'priority', ${row}.${m("priority")}, 'status', ${row}.${m("status")})`,
      subject: `'maintenance-requests/' || ${row}.${m("id")}::text`,
      tenant: `${row}.${m("tenant")}`,
      audit: {
        category: "data",
        targetType: "maintenance_request",
        recordId: `${row}.${m("id")}::text`,
        targetLabel: `${row}.${m("title")}`,
        summary: `'${summary}'`,
      },
    });

  const loadLease = (id: string, permission: string, lock = false): string => `
  select * into v_row from ${leases} x where x.${l("id")} = ${id}${lock ? " for update" : ""};
  if not found or not ${can(`v_row.${l("tenant")}`, permission)} then
    ${notFound}
  end if;`;

  const unitInTenant = (unit: string, tenant: string): string =>
    `exists (select 1 from ${assets.table("assets")} u where u.${as("id")} = ${unit} and u.${as("tenant")} = ${tenant})`;

  return `
-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
create or replace function ${fn("create_lease")}(tenant ${idType}, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${leases}%rowtype;
  v_unit text;
begin
  if not ${can("create_lease.tenant", manage)} then
    ${forbidden("not allowed to manage leases")}
  end if;
  select u.${as("name")} into v_unit from ${assets.table("assets")} u
    where u.${as("id")} = create_lease.unit_id and u.${as("tenant")} = create_lease.tenant and u.${as("retiredAt")} is null;
  if not found then
    ${invalid("LEASE_UNIT_INVALID", "the unit is unknown, retired or not in this organization")}
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not ${subjectInTenant(ctx, "create_lease.party_type", "create_lease.party_id", "create_lease.tenant")} then
    ${invalid("LEASE_PARTY_INVALID", "the party is unknown or not in this organization")}
  end if;
  if create_lease.starts_on is null then
    ${invalid("LEASE_TERMS_INVALID", "a lease needs starts_on")}
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    ${invalid("LEASE_TERMS_INVALID", "ends_on must be after starts_on")}
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    ${invalid("LEASE_TERMS_INVALID", "rent is more than zero minor units")}
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    ${invalid("LEASE_TERMS_INVALID", "currency must be a three-letter currency code")}
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    ${invalid("LEASE_TERMS_INVALID", "frequency is weekly, monthly, quarterly or yearly")}
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    ${invalid("LEASE_TERMS_INVALID", "a deposit is zero or more minor units")}
  end if;
  insert into ${leases} (${l("tenant")}, ${l("unit")}, ${l("partyType")}, ${l("partyId")}, ${l("title")}, ${l("startsOn")}, ${l("endsOn")},
    ${l("rent")}, ${l("currency")}, ${l("frequency")}, ${l("deposit")}, ${l("metadata")}, ${l("createdBy")})
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  ${leaseRecord("lease.created", "v_row", "created a lease")}
  return ${leaseJson("v_row")};
end;
$$;
${userGrant(`${fn("create_lease")}(${idType}, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb)`)}

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function ${fn("activate_lease")}(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${leases}%rowtype;
  v_account uuid;
  v_hold ${holds}%rowtype;
begin${loadLease("activate_lease.lease_id", manage, true)}
  if v_row.${l("status")} <> 'draft' then
    ${fail("LEASE_STATUS_INVALID", "only a draft lease can be activated", "55000")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases:unit:' || v_row.${l("unit")}::text, 0));
  if exists (
    select 1 from ${leases} x
    where x.${l("unit")} = v_row.${l("unit")} and x.${l("id")} <> v_row.${l("id")} and x.${l("status")} = 'active'
      and daterange(x.${l("startsOn")}, x.${l("endsOn")}) && daterange(v_row.${l("startsOn")}, v_row.${l("endsOn")})
  ) then
    ${fail("LEASE_OVERLAP", "another active lease of this unit overlaps these dates", "23P01")}
  end if;
  if v_row.${l("deposit")} > 0 then
    v_account := ${depositAccount("v_row")};
    perform ${ledger.fn("ledger_post")}(v_row.${l("tenant")}, 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row.${l("deposit")}),
        jsonb_build_object('account', ${cashAccount("v_row")}, 'amount', -v_row.${l("deposit")})),
      'leases', v_row.${l("id")}::text, 'Deposit received', 'lease:' || v_row.${l("id")}::text || ':deposit', null,
      jsonb_build_object('leaseId', v_row.${l("id")}));
    v_hold := ${ledger.fn("ledger_hold")}(v_account, v_row.${l("deposit")}, 'leases', v_row.${l("id")}::text, null);
  end if;
  update ${leases} x set ${l("status")} = 'active', ${l("depositHold")} = v_hold.${lh("id")}, ${l("updatedAt")} = now()
    where x.${l("id")} = v_row.${l("id")}
    returning * into v_row;
  ${leaseRecord("lease.activated", "v_row", "activated a lease")}
  return ${leaseJson("v_row")};
end;
$$;
${userGrant(`${fn("activate_lease")}(uuid)`)}

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function ${fn("renew_lease")}(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${leases}%rowtype;
begin${loadLease("renew_lease.lease_id", manage, true)}
  if v_row.${l("status")} <> 'active' then
    ${fail("LEASE_STATUS_INVALID", "only an active lease can be renewed", "55000")}
  end if;
  if v_row.${l("endsOn")} is null then
    ${fail("LEASE_STATUS_INVALID", "this lease has no end; it runs until it is terminated", "55000")}
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row.${l("endsOn")} then
    ${invalid("LEASE_TERMS_INVALID", "a renewal ends after the current end")}
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    ${invalid("LEASE_TERMS_INVALID", "rent is more than zero minor units")}
  end if;
  update ${leases} x set ${l("endsOn")} = renew_lease.ends_on, ${l("rent")} = coalesce(renew_lease.rent, x.${l("rent")}),
      ${l("renewedAt")} = now(), ${l("updatedAt")} = now()
    where x.${l("id")} = v_row.${l("id")}
    returning * into v_row;
  ${leaseRecord("lease.renewed", "v_row", "renewed a lease")}
  return ${leaseJson("v_row")};
end;
$$;
${userGrant(`${fn("renew_lease")}(uuid, date, bigint)`)}

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function ${fn("terminate_lease")}(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${leases}%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin${loadLease("terminate_lease.lease_id", manage, true)}
  if v_row.${l("status")} not in ('draft', 'active') then
    ${fail("LEASE_STATUS_INVALID", "this lease has already ended", "55000")}
  end if;
  if v_on < v_row.${l("startsOn")} and v_row.${l("status")} = 'active' then
    ${invalid("LEASE_TERMS_INVALID", "a lease can't end before it starts")}
  end if;
  if exists (select 1 from ${charges} y where y.${c("lease")} = v_row.${l("id")} and y.${c("periodStart")} >= v_on) then
    ${invalid("LEASE_TERMS_INVALID", "rent is already posted for a period from this date; pick a later date")}
  end if;
  v_held := ${depositHeld("v_row")};
  if v_deduction < 0 or v_deduction > v_held then
    ${invalid("LEASE_DEPOSIT_INVALID", "a deduction is zero or more and at most the deposit held")}
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform ${ledger.fn("ledger_capture")}(v_row.${l("depositHold")}, ${incomeAccount("v_row")}, v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform ${ledger.fn("ledger_release")}(v_row.${l("depositHold")});
    end if;
    if v_held - v_deduction > 0 then
      perform ${ledger.fn("ledger_post")}(v_row.${l("tenant")}, 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', ${depositAccount("v_row")}, 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', ${cashAccount("v_row")}, 'amount', v_held - v_deduction)),
        'leases', v_row.${l("id")}::text, 'Deposit refunded', 'lease:' || v_row.${l("id")}::text || ':deposit_refund', null,
        jsonb_build_object('leaseId', v_row.${l("id")}));
    end if;
  end if;
  update ${leases} x set
      ${l("status")} = case when x.${l("status")} = 'active' and x.${l("endsOn")} is not null and v_on >= x.${l("endsOn")} then 'ended' else 'terminated' end,
      ${l("terminatedOn")} = v_on, ${l("terminationReason")} = nullif(trim(terminate_lease.reason), ''), ${l("updatedAt")} = now()
    where x.${l("id")} = v_row.${l("id")}
    returning * into v_row;
  ${leaseRecord("lease.terminated", "v_row", "ended a lease")}
  return ${leaseJson("v_row")};
end;
$$;
${userGrant(`${fn("terminate_lease")}(uuid, date, text, bigint)`)}

create or replace function ${fn("get_lease")}(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${leases}%rowtype;
begin${loadLease("get_lease.lease_id", read)}
  return ${leaseJson("v_row")};
end;
$$;
${userGrant(`${fn("get_lease")}(uuid)`)}

create or replace function ${fn("list_leases")}(tenant ${idType}, status text default null, unit_id uuid default null, party_type text default null, party_id text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${can("list_leases.tenant", read)} then
    ${forbidden("not allowed to read leases")}
  end if;
  return (
    select coalesce(jsonb_agg(${leaseJson("q")} order by q.${l("startsOn")} desc, q.${l("id")}), '[]'::jsonb)
    from (
      select * from ${leases} x
      where x.${l("tenant")} = list_leases.tenant
        and (list_leases.status is null or x.${l("status")} = list_leases.status)
        and (list_leases.unit_id is null or x.${l("unit")} = list_leases.unit_id)
        and (list_leases.party_type is null or (x.${l("partyType")} = list_leases.party_type and x.${l("partyId")} = list_leases.party_id))
      order by x.${l("startsOn")} desc, x.${l("id")}
      limit ${pageSize("list_leases.page_size", 100, 1000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_leases")}(${idType}, text, uuid, text, text, integer)`)}

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function ${fn("post_due_rent")}(tenant ${idType} default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := ${pageSize("post_due_rent.max_rows", 500, 5000)};
  v_count integer := 0;
  v_row ${leases}%rowtype;
  v_charge ${charges}%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if post_due_rent.tenant is null then
    if not ${SERVICE_CALLER} then
      ${forbidden("posting rent for every organization needs the service role")}
    end if;
  elsif not ${can("post_due_rent.tenant", manage)} then
    ${forbidden("not allowed to manage leases")}
  end if;
  <<leases>>
  for v_row in
    select * from ${leases} x
    where x.${l("status")} = 'active' and x.${l("startsOn")} <= v_through
      and (post_due_rent.tenant is null or x.${l("tenant")} = post_due_rent.tenant)
    order by x.${l("id")}
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row.${l("startsOn")} + v_n * ${step(`v_row.${l("frequency")}`)})::date;
      exit when v_start > v_through or (v_row.${l("endsOn")} is not null and v_start >= v_row.${l("endsOn")});
      if not exists (select 1 from ${charges} y where y.${c("lease")} = v_row.${l("id")} and y.${c("periodStart")} = v_start) then
        exit leases when v_count >= v_max;
        v_end := least((v_row.${l("startsOn")} + (v_n + 1) * ${step(`v_row.${l("frequency")}`)})::date, coalesce(v_row.${l("endsOn")}, 'infinity'::date));
        v_tx := ${ledger.fn("ledger_post")}(v_row.${l("tenant")}, 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', ${rentAccount("v_row")}, 'amount', v_row.${l("rent")}),
            jsonb_build_object('account', ${incomeAccount("v_row")}, 'amount', -v_row.${l("rent")})),
          'leases', v_row.${l("id")}::text, 'Rent from ' || v_start::text,
          'lease:' || v_row.${l("id")}::text || ':rent:' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row.${l("id")}, 'periodStart', v_start, 'periodEnd', v_end));
        insert into ${charges} (${c("tenant")}, ${c("lease")}, ${c("periodStart")}, ${c("periodEnd")}, ${c("amount")}, ${c("currency")}, ${c("transaction")})
        values (v_row.${l("tenant")}, v_row.${l("id")}, v_start, v_end, v_row.${l("rent")}, v_row.${l("currency")}, v_tx)
        returning * into v_charge;
        ${ctx.record({
          type: "lease.charged",
          payload: `jsonb_build_object('organizationId', v_charge.${c("tenant")}, 'id', v_charge.${c("id")}, 'leaseId', v_charge.${c("lease")}, 'periodStart', v_charge.${c("periodStart")}, 'periodEnd', v_charge.${c("periodEnd")}, 'amount', v_charge.${c("amount")}::text, 'currency', v_charge.${c("currency")}, 'transactionId', v_charge.${c("transaction")})`,
          subject: `'lease-charges/' || v_charge.${c("id")}::text`,
          tenant: `v_charge.${c("tenant")}`,
          audit: {
            category: "billing",
            targetType: "lease_charge",
            recordId: `v_charge.${c("id")}::text`,
            summary: `'posted rent from ' || v_charge.${c("periodStart")}::text`,
          },
        })}
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("post_due_rent")}(${idType}, date, integer)`)}

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function ${fn("record_rent_payment")}(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${leases}%rowtype;
  v_key text;
  v_tx uuid;
begin${loadLease("record_rent_payment.lease_id", manage)}
  if v_row.${l("status")} = 'draft' then
    ${fail("LEASE_STATUS_INVALID", "a draft lease takes no payments", "55000")}
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    ${invalid("LEASE_PAYMENT_INVALID", "a payment is more than zero minor units")}
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'lease-payment:' || v_row.${l("id")}::text || ':' || trim(record_rent_payment.reference) end;
  select x.${lt("id")} into v_tx from ${ledger.table("transactions")} x
    where x.${lt("tenant")} = v_row.${l("tenant")} and x.${lt("key")} = v_key;
  if v_tx is null then
    v_tx := ${ledger.fn("ledger_post")}(v_row.${l("tenant")}, 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', ${rentAccount("v_row")}, 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', ${cashAccount("v_row")}, 'amount', record_rent_payment.amount)),
      'leases', v_row.${l("id")}::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row.${l("id")}, 'reference', nullif(trim(record_rent_payment.reference), ''))));
    ${ctx.record({
      type: "lease.paid",
      payload: `jsonb_build_object('organizationId', v_row.${l("tenant")}, 'id', v_row.${l("id")}, 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row.${l("currency")})`,
      subject: `'leases/' || v_row.${l("id")}::text`,
      tenant: `v_row.${l("tenant")}`,
      audit: {
        category: "billing",
        targetType: "lease",
        recordId: `v_row.${l("id")}::text`,
        targetLabel: `v_row.${l("title")}`,
        summary: `'recorded a rent payment'`,
      },
    })}
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row.${l("id")}, 'amount', record_rent_payment.amount::text,
    'currency', v_row.${l("currency")}, 'balanceDue', ${balanceDue("v_row")}::text);
end;
$$;
${userGrant(`${fn("record_rent_payment")}(uuid, bigint, timestamptz, text)`)}

create or replace function ${fn("list_lease_charges")}(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${leases}%rowtype;
begin${loadLease("list_lease_charges.lease_id", read)}
  return (
    select coalesce(jsonb_agg(${chargeJson("q")} order by q.${c("periodStart")} desc), '[]'::jsonb)
    from (
      select * from ${charges} y where y.${c("lease")} = v_row.${l("id")}
      order by y.${c("periodStart")} desc
      limit ${pageSize("list_lease_charges.page_size", 200, 2000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_lease_charges")}(uuid, integer)`)}

-- Files a maintenance request on a unit, optionally for one of its leases.
create or replace function ${fn("file_maintenance_request")}(tenant ${idType}, unit_id uuid, title text, description text default null, priority text default 'normal', lease_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${maintenance}%rowtype;
begin
  if not (${can("file_maintenance_request.tenant", maintain)} or ${ctx.can("tenant", "file_maintenance_request.tenant", manage)}) then
    ${forbidden("not allowed to file maintenance requests")}
  end if;
  if not ${unitInTenant("file_maintenance_request.unit_id", "file_maintenance_request.tenant")} then
    ${invalid("LEASE_UNIT_INVALID", "the unit is unknown or not in this organization")}
  end if;
  if file_maintenance_request.lease_id is not null and not exists (
    select 1 from ${leases} x where x.${l("id")} = file_maintenance_request.lease_id
      and x.${l("tenant")} = file_maintenance_request.tenant and x.${l("unit")} = file_maintenance_request.unit_id
  ) then
    ${invalid("LEASE_NOT_FOUND", "the lease is unknown or not a lease of this unit")}
  end if;
  if coalesce(file_maintenance_request.priority, 'normal') not in ('low', 'normal', 'high', 'urgent') then
    ${invalid("MAINTENANCE_INVALID", "priority is low, normal, high or urgent")}
  end if;
  if nullif(trim(file_maintenance_request.title), '') is null then
    ${invalid("MAINTENANCE_INVALID", "a maintenance request needs a title")}
  end if;
  insert into ${maintenance} (${m("tenant")}, ${m("unit")}, ${m("lease")}, ${m("title")}, ${m("description")}, ${m("priority")}, ${m("reportedBy")})
  values (file_maintenance_request.tenant, file_maintenance_request.unit_id, file_maintenance_request.lease_id, trim(file_maintenance_request.title),
    nullif(trim(file_maintenance_request.description), ''), coalesce(file_maintenance_request.priority, 'normal'), auth.uid())
  returning * into v_row;
  ${maintenanceRecord("maintenance_request.filed", "v_row", "filed a maintenance request")}
  return ${maintenanceJson("v_row")};
end;
$$;
${userGrant(`${fn("file_maintenance_request")}(${idType}, uuid, text, text, text, uuid)`)}

-- Moves a maintenance request along (open, in_progress, resolved,
-- cancelled), reprioritizes it or assigns it to a member. Null keeps a value.
create or replace function ${fn("update_maintenance_request")}(request_id uuid, status text default null, priority text default null, assignee_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${maintenance}%rowtype;
begin
  select * into v_row from ${maintenance} x where x.${m("id")} = update_maintenance_request.request_id for update;
  if not found or not ${can(`v_row.${m("tenant")}`, manage)} then
    ${fail("MAINTENANCE_NOT_FOUND", "no such maintenance request you can change", "P0002")}
  end if;
  if update_maintenance_request.status is not null and update_maintenance_request.status not in ('open', 'in_progress', 'resolved', 'cancelled') then
    ${invalid("MAINTENANCE_INVALID", "status is open, in_progress, resolved or cancelled")}
  end if;
  if update_maintenance_request.priority is not null and update_maintenance_request.priority not in ('low', 'normal', 'high', 'urgent') then
    ${invalid("MAINTENANCE_INVALID", "priority is low, normal, high or urgent")}
  end if;
  if update_maintenance_request.assignee_id is not null and not exists (
    select 1 from ${members.table("memberships")} y
    where y.${members.col("memberships", "tenant")} = v_row.${m("tenant")} and y.${members.col("memberships", "user")} = update_maintenance_request.assignee_id
  ) then
    ${invalid("MAINTENANCE_INVALID", "the assignee is not a member of this organization")}
  end if;
  update ${maintenance} x set
      ${m("status")} = coalesce(update_maintenance_request.status, x.${m("status")}),
      ${m("priority")} = coalesce(update_maintenance_request.priority, x.${m("priority")}),
      ${m("assignee")} = coalesce(update_maintenance_request.assignee_id, x.${m("assignee")}),
      ${m("resolvedAt")} = case when coalesce(update_maintenance_request.status, x.${m("status")}) = 'resolved' then coalesce(x.${m("resolvedAt")}, now()) end,
      ${m("updatedAt")} = now()
    where x.${m("id")} = v_row.${m("id")}
    returning * into v_row;
  ${maintenanceRecord("maintenance_request.updated", "v_row", "updated a maintenance request")}
  return ${maintenanceJson("v_row")};
end;
$$;
${userGrant(`${fn("update_maintenance_request")}(uuid, text, text, uuid)`)}

-- Maintenance requests, newest first: every one with leases.read, else the
-- ones the caller filed.
create or replace function ${fn("list_maintenance_requests")}(tenant ${idType}, unit_id uuid default null, lease_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_all boolean := ${can("list_maintenance_requests.tenant", read)};
begin
  if not (v_all or ${ctx.can("tenant", "list_maintenance_requests.tenant", maintain)}) then
    ${forbidden("not allowed to read maintenance requests")}
  end if;
  return (
    select coalesce(jsonb_agg(${maintenanceJson("q")} order by q.${m("createdAt")} desc, q.${m("id")}), '[]'::jsonb)
    from (
      select * from ${maintenance} x
      where x.${m("tenant")} = list_maintenance_requests.tenant
        and (v_all or x.${m("reportedBy")} = auth.uid())
        and (list_maintenance_requests.unit_id is null or x.${m("unit")} = list_maintenance_requests.unit_id)
        and (list_maintenance_requests.lease_id is null or x.${m("lease")} = list_maintenance_requests.lease_id)
        and (list_maintenance_requests.status is null or x.${m("status")} = list_maintenance_requests.status)
      order by x.${m("createdAt")} desc, x.${m("id")}
      limit ${pageSize("list_maintenance_requests.page_size", 100, 1000)}
    ) q
  );
end;
$$;
${userGrant(`${fn("list_maintenance_requests")}(${idType}, uuid, uuid, text, integer)`)}
`;
}
