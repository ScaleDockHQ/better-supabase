SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."accounting_periods"
  DROP CONSTRAINT "accounting_periods_status_check";

DROP FUNCTION "api"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid);

DROP FUNCTION "api"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid);

DROP FUNCTION "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid);

DROP FUNCTION "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid);

CREATE TABLE "better_supabase"."accounting_opening_balances" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "fiscal_year" integer                  NOT NULL,
  "account_id"  uuid                     NOT NULL,
  "party_id"    uuid,
  "amount"      bigint                   NOT NULL,
  "source"      text                     NOT NULL DEFAULT 'imported'::text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_opening_balances_amount_check" CHECK ((amount <> 0)),
  CONSTRAINT "accounting_opening_balances_fiscal_year_check" CHECK (((fiscal_year >= 1900) AND (fiscal_year <= 9999))),
  CONSTRAINT "accounting_opening_balances_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_opening_balances_source_check" CHECK ((source = ANY (ARRAY['imported'::text, 'carried'::text])))
);

ALTER TABLE "better_supabase"."accounting_opening_balances"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD COLUMN "normal_side" text NOT NULL DEFAULT 'debit'::text;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD COLUMN "level" smallint NOT NULL DEFAULT 1;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD COLUMN "default_tax_code_id" uuid;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD COLUMN "active" boolean NOT NULL DEFAULT true;

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ADD COLUMN "tax_amount" bigint NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."accounting_journals"
  ADD COLUMN "contra_account_id" uuid;

ALTER TABLE "better_supabase"."accounting_journals"
  ADD COLUMN "bank_account_id" uuid;

ALTER TABLE "better_supabase"."accounting_periods"
  ADD COLUMN "locked_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."accounting_periods"
  ADD COLUMN "locked_by" uuid;

CREATE OR REPLACE FUNCTION api.accounting_column_balance (
  tenant     uuid,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  dimensions jsonb   DEFAULT '{}'::jsonb,
  rollup     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_column_balance"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.accounting_journal_listing (
  tenant     uuid,
  since      date DEFAULT NULL::date,
  until      date DEFAULT NULL::date,
  journal_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_journal_listing"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.accounting_period_trial_balance (
  period_id  uuid,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_period_trial_balance"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_accounting_account (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_accounting_account"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_accounting_entry (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_accounting_entry"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_accounting_journal (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_accounting_journal"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_accounting_opening_balance (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_accounting_opening_balance"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_opening_balances"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.lock_accounting_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."lock_accounting_period"($1) $function$;

CREATE OR REPLACE FUNCTION api.post_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer,
  journal_id  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_accounting_opening_balances"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_account (
  tenant              uuid,
  code                text,
  name                text,
  type                text,
  subtype             text    DEFAULT NULL::text,
  parent_id           uuid    DEFAULT NULL::uuid,
  currency            text    DEFAULT NULL::text,
  reconcilable        boolean DEFAULT false,
  account_id          uuid    DEFAULT NULL::uuid,
  normal_side         text    DEFAULT NULL::text,
  default_tax_code_id uuid    DEFAULT NULL::uuid,
  active              boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_account"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_journal (
  tenant             uuid,
  code               text,
  name               text,
  type               text,
  default_account_id uuid DEFAULT NULL::uuid,
  currency           text DEFAULT NULL::text,
  journal_id         uuid DEFAULT NULL::uuid,
  contra_account_id  uuid DEFAULT NULL::uuid,
  bank_account_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_journal"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer,
  balances    jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_opening_balances"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.unlock_accounting_period (
  period_id uuid,
  reason    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unlock_accounting_period"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.wip_valuation (
  tenant uuid,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."wip_valuation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_account_level()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id" then
    new."level" := coalesce((select y."level" from "better_supabase"."accounting_accounts" y where y."id" = new."parent_id"), 0) + 1;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_account_level_children()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  with recursive down (id, level) as (
    select y."id", new."level" + 1 from "better_supabase"."accounting_accounts" y where y."parent_id" = new."id"
    union all
    select y."id", down.level + 1 from "better_supabase"."accounting_accounts" y join down on y."parent_id" = down.id
  )
  update "better_supabase"."accounting_accounts" y set "level" = down.level from down where y."id" = down.id and y."level" <> down.level;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_column_balance (
  tenant     uuid,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  dimensions jsonb   DEFAULT '{}'::jsonb,
  rollup     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with recursive sums as (
    select y."account_id" as account,
      sum(case when z."entry_date" < accounting_column_balance.since then y."debit" - y."credit" else 0 end) as opening,
      sum(case when accounting_column_balance.since is null or z."entry_date" >= accounting_column_balance.since then y."debit" else 0 end) as debit,
      sum(case when accounting_column_balance.since is null or z."entry_date" >= accounting_column_balance.since then y."credit" else 0 end) as credit
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_column_balance.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_column_balance.dimensions, '{}'::jsonb)
      and (accounting_column_balance.until is null or z."entry_date" <= accounting_column_balance.until)
    group by y."account_id"
  ),
  tree (leaf, node) as (
    select w."id", w."id" from "better_supabase"."accounting_accounts" w where w."tenant_id" = accounting_column_balance.tenant
    union all
    select t.leaf, w."parent_id" from tree t join "better_supabase"."accounting_accounts" w on w."id" = t.node
    where w."parent_id" is not null and coalesce(accounting_column_balance.rollup, false)
  ),
  rolled as (
    select t.node as account, sum(c.opening) as opening, sum(c.debit) as debit, sum(c.credit) as credit
    from tree t join sums c on c.account = t.leaf group by t.node
  )
  select jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type",
        'parentId', w."parent_id", 'level', w."level",
        'openingDebit', greatest(r.opening, 0)::text, 'openingCredit', greatest(-r.opening, 0)::text,
        'debit', r.debit::text, 'credit', r.credit::text,
        'closingDebit', greatest(r.opening + r.debit - r.credit, 0)::text, 'closingCredit', greatest(r.credit - r.debit - r.opening, 0)::text) order by w."code")
      from rolled r join "better_supabase"."accounting_accounts" w on w."id" = r.account), '[]'::jsonb),
    'totals', (select jsonb_build_object(
        'openingDebit', coalesce(sum(greatest(c.opening, 0)), 0)::text, 'openingCredit', coalesce(sum(greatest(-c.opening, 0)), 0)::text,
        'debit', coalesce(sum(c.debit), 0)::text, 'credit', coalesce(sum(c.credit), 0)::text,
        'closingDebit', coalesce(sum(greatest(c.opening + c.debit - c.credit, 0)), 0)::text,
        'closingCredit', coalesce(sum(greatest(c.credit - c.debit - c.opening, 0)), 0)::text)
      from sums c)
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_journal_listing (
  tenant     uuid,
  since      date DEFAULT NULL::date,
  until      date DEFAULT NULL::date,
  journal_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('journals', coalesce(jsonb_agg(jsonb_build_object(
      'journalId', g."id", 'code', g."code", 'name', g."name", 'type', g."type",
      'entries', g.entries, 'totalDebit', g.total_debit::text, 'totalCredit', g.total_credit::text) order by g."code"), '[]'::jsonb))
  from (
    select w.*,
      (select jsonb_agg(jsonb_build_object('id', z."id", 'number', z."number", 'entryDate', z."entry_date", 'status', z."status",
          'reference', z."reference", 'memo', z."memo",
          'lines', (select jsonb_agg(jsonb_build_object('accountId', y."account_id", 'accountCode', x."code", 'accountName', x."name",
              'debit', y."debit"::text, 'credit', y."credit"::text, 'taxAmount', y."tax_amount"::text, 'partyId', y."party_id",
              'description', y."description") order by y."position", y."id")
            from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_accounts" x on x."id" = y."account_id" where y."entry_id" = z."id"))
        order by z."entry_date", z."number", z."id")
        from "better_supabase"."accounting_entries" z
        where z."journal_id" = w."id" and z."status" in ('posted', 'reversed')
          and (accounting_journal_listing.since is null or z."entry_date" >= accounting_journal_listing.since)
          and (accounting_journal_listing.until is null or z."entry_date" <= accounting_journal_listing.until)) as entries,
      (select coalesce(sum(y."debit"), 0) from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
        where z."journal_id" = w."id" and z."status" in ('posted', 'reversed')
          and (accounting_journal_listing.since is null or z."entry_date" >= accounting_journal_listing.since)
          and (accounting_journal_listing.until is null or z."entry_date" <= accounting_journal_listing.until)) as total_debit,
      (select coalesce(sum(y."credit"), 0) from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
        where z."journal_id" = w."id" and z."status" in ('posted', 'reversed')
          and (accounting_journal_listing.since is null or z."entry_date" >= accounting_journal_listing.since)
          and (accounting_journal_listing.until is null or z."entry_date" <= accounting_journal_listing.until)) as total_credit
    from "better_supabase"."accounting_journals" w
    where w."tenant_id" = accounting_journal_listing.tenant
      and (accounting_journal_listing.journal_id is null or w."id" = accounting_journal_listing.journal_id)
  ) g
  where g.entries is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_opening_posted (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = accounting_opening_posted.tenant and y."source_type" = 'opening_balance'
      and y."source_id" = accounting_opening_posted.fiscal_year::text and y."status" <> 'reversed'
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_opening_write (
  tenant      uuid,
  fiscal_year integer,
  account_id  uuid,
  party_id    uuid,
  amount      bigint
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if accounting_opening_write.fiscal_year is null or accounting_opening_write.fiscal_year < 1900 or accounting_opening_write.fiscal_year > 9999 then
    raise exception 'the fiscal year must be a year' using errcode = '22023', hint = 'ACCOUNTING_OPENING_INVALID';
  end if;
  if accounting_opening_write.amount is null or accounting_opening_write.amount = 0 then
    raise exception 'an opening balance needs a non-zero amount; a debit balance is positive' using errcode = '22023', hint = 'ACCOUNTING_OPENING_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."accounting_accounts" y where y."id" = accounting_opening_write.account_id and y."tenant_id" = accounting_opening_write.tenant
  ) then
    raise exception 'an opening balance''s account isn''t an account of the organization' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  if "better_supabase"."accounting_opening_posted"(accounting_opening_write.tenant, accounting_opening_write.fiscal_year) then
    raise exception 'the opening entry of the fiscal year is posted; reverse it first' using errcode = '55000', hint = 'ACCOUNTING_OPENING_POSTED';
  end if;
  insert into "better_supabase"."accounting_opening_balances" ("tenant_id", "fiscal_year", "account_id", "party_id", "amount", "source")
  values (accounting_opening_write.tenant, accounting_opening_write.fiscal_year, accounting_opening_write.account_id, accounting_opening_write.party_id, accounting_opening_write.amount, 'imported')
  on conflict ("tenant_id", "fiscal_year", "account_id", coalesce("party_id", '00000000-0000-0000-0000-000000000000'::uuid))
  do update set "amount" = excluded."amount", "source" = 'imported', "updated_at" = now()
  returning "id" into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_period_trial_balance (
  period_id  uuid,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."accounting_trial_balance"(y."tenant_id", y."starts_on", y."ends_on", accounting_period_trial_balance.dimensions)
  from "better_supabase"."accounting_periods" y where y."id" = accounting_period_trial_balance.period_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_post (
  entry_id uuid,
  closing  boolean DEFAULT false
)
  RETURNS better_supabase.accounting_entries
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_total numeric;
  v_credits numeric;
  v_count integer;
  v_sequence integer;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = accounting_post.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_row."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  select count(*), coalesce(sum(y."debit"), 0), coalesce(sum(y."credit"), 0) into v_count, v_total, v_credits
  from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
  if v_count < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if v_total <> v_credits then
    raise exception 'the debits and credits of the entry differ in the functional currency' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_accounts" z on z."id" = y."account_id"
    where y."entry_id" = v_row."id" and (z."archived_at" is not null or not z."active")
  ) then
    raise exception 'an account of the entry is archived or inactive' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entry_lines" y, jsonb_each(y."dimensions") dim
    where y."entry_id" = v_row."id"
      and (jsonb_typeof(dim.value) <> 'string' or not exists (
        select 1 from "better_supabase"."accounting_dimensions" z join "better_supabase"."accounting_dimension_values" w on w."dimension_id" = z."id"
        where z."tenant_id" = v_row."tenant_id" and z."key" = dim.key
          and w."code" = dim.value #>> '{}' and w."archived_at" is null
      ))
  ) then
    raise exception 'a line names a dimension or value that doesn''t exist or is archived' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y
  where y."tenant_id" = v_row."tenant_id" and v_row."entry_date" >= y."starts_on" and v_row."entry_date" <= y."ends_on";
  if not found then
    raise exception 'no period covers the entry date; open its fiscal year first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if v_period."status" = 'locked' then
    raise exception 'the entry date is in a locked period' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_LOCKED';
  end if;
  if not coalesce(accounting_post.closing, false) and (
    (v_period."status" = 'closed' and better_supabase.import_run() is null)
    or (v_settings."lock_date" is not null and v_row."entry_date" <= v_settings."lock_date")
  ) then
    raise exception 'the entry date is in a closed period or on or before the lock date' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_accounting_entry_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  select * into v_journal from "better_supabase"."accounting_journals" y where y."id" = v_row."journal_id";
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_journal."id"::text || ':' || v_period."fiscal_year"::text, 0));
  select coalesce(max(y."sequence"), 0) + 1 into v_sequence from "better_supabase"."accounting_entries" y
  where y."journal_id" = v_journal."id" and y."fiscal_year" = v_period."fiscal_year";
  update "better_supabase"."accounting_entries" y set "status" = 'posted', "fiscal_year" = v_period."fiscal_year", "sequence" = v_sequence,
    "number" = v_journal."code" || '-' || v_period."fiscal_year"::text || '-' || lpad(v_sequence::text, 5, '0'),
    "period_id" = v_period."id", "posted_at" = now(), "posted_by" = auth.uid(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('accounting_entry.posted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'entryDate', v_row."entry_date", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'total', v_total::text), 'accounting-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_entry.posted',
    category => 'data',
    target_type => 'accounting_entry',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'posted entry ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'entryDate', v_row."entry_date", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'total', v_total::text)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_accounting_entry_post"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_accounting_account (
  account_id uuid,
  archived   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_accounts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."accounting_accounts" y where y."id" = archive_accounting_account.account_id for update;
  if not found then
    raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if coalesce(archive_accounting_account.archived, true) and (
    exists (select 1 from "better_supabase"."accounting_account_roles" y where y."account_id" = v_row."id")
    or exists (select 1 from "better_supabase"."accounting_journals" y where y."default_account_id" = v_row."id")
    or exists (select 1 from "better_supabase"."tax_codes" y where (y."sales_account_id" = v_row."id" or y."purchase_account_id" = v_row."id") and y."archived_at" is null)
  ) then
    raise exception 'the account is mapped to a role, a journal or a tax code' using errcode = '55000', hint = 'ACCOUNTING_ACCOUNT_IN_USE';
  end if;
  update "better_supabase"."accounting_accounts" y set "archived_at" = case when coalesce(archive_accounting_account.archived, true) then coalesce(y."archived_at", now()) end,
    "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'subtype', v_row."subtype", 'parentId', v_row."parent_id", 'currency', v_row."currency", 'reconcilable', v_row."reconcilable", 'normalSide', v_row."normal_side", 'level', v_row."level", 'defaultTaxCodeId', v_row."default_tax_code_id", 'active', v_row."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = v_row."id"), '[]'::jsonb), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_accounting_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_blockers text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = close_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to close accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if v_period."status" in ('closed', 'locked') then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  v_blockers := "better_supabase"."accounting_period_close_blockers"(v_period."id");
  if cardinality(v_blockers) > 0 then
    raise exception 'the period can''t close yet: %', array_to_string(v_blockers, ', ') using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
    where y."id" = v_period."id"
    returning * into v_period;
    perform "better_supabase".emit_event('accounting_period.closed', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on"), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.closed',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'closed period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on")
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_fiscal_year (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_starts date;
  v_ends date;
  v_open integer;
  v_retained uuid;
  v_journal uuid;
  v_entry "better_supabase"."accounting_entries"%rowtype;
  v_net numeric;
  v_count integer;
  v_closing uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_fiscal_year.tenant, 'accounting.close'), false)) then
    raise exception 'not allowed to close fiscal years' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = close_fiscal_year.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  select min(y."starts_on"), max(y."ends_on"), count(*) filter (where y."status" = 'open')
  into v_starts, v_ends, v_open
  from "better_supabase"."accounting_periods" y where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year;
  if v_starts is null then
    raise exception 'the fiscal year has no periods; open it first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(close_fiscal_year.tenant::text || ':fiscal_year:' || close_fiscal_year.fiscal_year::text, 0));
  if exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = close_fiscal_year.tenant and y."source_type" = 'fiscal_year'
      and y."source_id" = close_fiscal_year.fiscal_year::text and y."status" <> 'reversed'
  ) then
    raise exception 'the fiscal year is already closed; reverse its closing entry to close it again' using errcode = '55000', hint = 'FISCAL_YEAR_CLOSED';
  end if;
  if exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = close_fiscal_year.tenant and y."status" = 'draft'
      and y."entry_date" >= v_starts and y."entry_date" <= v_ends
  ) then
    raise exception 'the fiscal year can''t close yet: draft_entries' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  select y."account_id" into v_retained from "better_supabase"."accounting_account_roles" y
  where y."tenant_id" = close_fiscal_year.tenant and y."role" = 'retained_earnings';
  if v_retained is null then
    raise exception 'no account has the retained_earnings role' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_ROLE_MISSING';
  end if;
  select y."id" into v_journal from "better_supabase"."accounting_journals" y
  where y."tenant_id" = close_fiscal_year.tenant and y."type" = 'general'
  order by y."code" limit 1;
  if v_journal is null then
    raise exception 'the year-end close needs a general journal' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  select count(*), coalesce(sum(c.net), 0) into v_count, v_net from (select y."account_id" as account, sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."fiscal_year" = close_fiscal_year.fiscal_year
      and z."status" in ('posted', 'reversed') and w."type" in ('income', 'expense')
    group by y."account_id"
    having sum(y."debit") <> sum(y."credit")) c;
  if v_count > 0 then
    insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "source_type", "source_id", "memo", "created_by")
    values (close_fiscal_year.tenant, v_journal, v_ends, 'fiscal_year', close_fiscal_year.fiscal_year::text,
      'Closing of fiscal year ' || close_fiscal_year.fiscal_year::text, auth.uid())
    returning * into v_entry;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency")
    select close_fiscal_year.tenant, v_entry."id", (row_number() over (order by w."code"))::smallint, c.account,
      greatest(-c.net, 0)::bigint, greatest(c.net, 0)::bigint, v_settings."functional_currency", (-c.net)::bigint
    from (select y."account_id" as account, sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."fiscal_year" = close_fiscal_year.fiscal_year
      and z."status" in ('posted', 'reversed') and w."type" in ('income', 'expense')
    group by y."account_id"
    having sum(y."debit") <> sum(y."credit")) c join "better_supabase"."accounting_accounts" w on w."id" = c.account;
    if v_net <> 0 then
      insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency")
      values (close_fiscal_year.tenant, v_entry."id", 32767, v_retained,
        greatest(v_net, 0)::bigint, greatest(-v_net, 0)::bigint, v_settings."functional_currency", v_net::bigint);
    end if;
    v_entry := "better_supabase"."accounting_post"(v_entry."id", true);
    v_closing := v_entry."id";
  elsif v_open = 0 then
    raise exception 'the fiscal year is already closed' using errcode = '55000', hint = 'FISCAL_YEAR_CLOSED';
  end if;
  delete from "better_supabase"."accounting_opening_balances" y
  where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year + 1 and y."source" = 'carried';
  insert into "better_supabase"."accounting_opening_balances" ("tenant_id", "fiscal_year", "account_id", "party_id", "amount", "source")
  select close_fiscal_year.tenant, close_fiscal_year.fiscal_year + 1, c.account, c.party, c.net, 'carried'
  from (
    select y."account_id" as account, case when w."reconcilable" then y."party_id" end as party,
      sum(y."debit") - sum(y."credit") as net
    from "better_supabase"."accounting_entry_lines" y
    join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
    where z."tenant_id" = close_fiscal_year.tenant and z."status" in ('posted', 'reversed')
      and z."entry_date" <= v_ends and w."type" in ('asset', 'liability', 'equity')
    group by y."account_id", case when w."reconcilable" then y."party_id" end
    having sum(y."debit") <> sum(y."credit")
  ) c
  on conflict do nothing;
  for v_period in
    select * from "better_supabase"."accounting_periods" y
    where y."tenant_id" = close_fiscal_year.tenant and y."fiscal_year" = close_fiscal_year.fiscal_year and y."status" = 'open'
    order by y."number"
    for update
  loop
    update "better_supabase"."accounting_periods" y set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid()
    where y."id" = v_period."id"
    returning * into v_period;
    perform "better_supabase".emit_event('accounting_period.closed', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on"), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.closed',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'closed period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on")
  );
  end loop;
  perform "better_supabase".emit_event('fiscal_year.closed', jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing), 'fiscal-years/' || close_fiscal_year.tenant::text || '/' || close_fiscal_year.fiscal_year::text, (close_fiscal_year.tenant)::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'fiscal_year.closed',
    category => 'data',
    target_type => 'fiscal_year',
    record_id => close_fiscal_year.fiscal_year::text,
    target_label => close_fiscal_year.fiscal_year::text,
    summary => 'closed fiscal year ' || close_fiscal_year.fiscal_year::text,
    tenant => (close_fiscal_year.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing)
  );
  return jsonb_build_object('organizationId', close_fiscal_year.tenant, 'fiscalYear', close_fiscal_year.fiscal_year, 'closingEntryId', v_closing);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_json jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = delete_accounting_entry.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.write'), false)) then
    raise exception 'not allowed to write accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  v_json := jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
  delete from "better_supabase"."accounting_entries" y where y."id" = v_row."id";
  return v_json;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = x."id"), '[]'::jsonb)) from "better_supabase"."accounting_entries" x where x."id" = get_accounting_entry.entry_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_account (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_account.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_account.item -> 'data';
  v_parent uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_account.item -> 'data') is distinct from 'object' then
    raise exception 'an account item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_parent := coalesce(nullif(v_data ->> 'parentId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'parentCode'));
    if nullif(v_data ->> 'parentCode', '') is not null and v_parent is null then
      raise exception 'the parent account code isn''t an account of the organization; import parents first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    v_row := "better_supabase"."save_accounting_account"(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', nullif(v_data ->> 'subtype', ''),
      v_parent, nullif(v_data ->> 'currency', ''), coalesce((v_data ->> 'reconcilable')::boolean, false),
      import_accounting_account.subject_id::uuid, nullif(v_data ->> 'normalSide', ''), nullif(v_data ->> 'defaultTaxCodeId', '')::uuid,
      coalesce((v_data ->> 'active')::boolean, true));
  exception
    when invalid_text_representation then
      raise exception 'an account''s ids are uuids and its flags booleans' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_entry (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_entry.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_entry.item -> 'data';
  v_journal uuid;
  v_lines jsonb;
  v_debit numeric;
  v_credit numeric;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_entry.item -> 'data') is distinct from 'object' then
    raise exception 'an entry item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_journal := coalesce(nullif(v_data ->> 'journalId', '')::uuid,
      (select y."id" from "better_supabase"."accounting_journals" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'journalCode'));
    select jsonb_agg((e.value - 'accountCode') || jsonb_build_object('accountId', coalesce(nullif(e.value ->> 'accountId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = e.value ->> 'accountCode'))) order by e.ordinality),
      coalesce(sum((coalesce(nullif(e.value ->> 'debit', ''), '0'))::numeric), 0),
      coalesce(sum((coalesce(nullif(e.value ->> 'credit', ''), '0'))::numeric), 0)
    into v_lines, v_debit, v_credit
    from jsonb_array_elements(v_data -> 'lines') with ordinality e;
  exception
    when invalid_text_representation then
      raise exception 'an entry''s ids are uuids and its amounts integers' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_journal is null then
    raise exception 'the journal isn''t a journal of the organization; import journals first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(v_lines) e where e.value ->> 'accountId' is null) then
    raise exception 'a line''s account isn''t an account of the organization; import accounts first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_debit <> v_credit then
    raise exception 'the lines don''t balance: debits and credits differ' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."save_accounting_entry"(v_journal, (v_data ->> 'entryDate')::date, v_lines, nullif(v_data ->> 'memo', ''), nullif(v_data ->> 'reference', ''),
    null, null, import_accounting_entry.subject_id::uuid);
  if coalesce((v_data ->> 'post')::boolean, true) then
    v_row := "better_supabase"."post_accounting_entry"((v_row ->> 'id')::uuid);
  end if;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_journal (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_journal.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_journal.item -> 'data';
  v_default uuid;
  v_contra uuid;
  v_bank uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_accounting_journal.item -> 'data') is distinct from 'object' then
    raise exception 'a journal item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_default := coalesce(nullif(v_data ->> 'defaultAccountId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'defaultAccountCode'));
    v_contra := coalesce(nullif(v_data ->> 'contraAccountId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'contraAccountCode'));
    v_bank := coalesce(nullif(v_data ->> 'bankAccountId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'bankAccountCode'));
  exception
    when invalid_text_representation then
      raise exception 'a journal''s account ids are uuids' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if (nullif(v_data ->> 'defaultAccountCode', '') is not null and v_default is null)
    or (nullif(v_data ->> 'contraAccountCode', '') is not null and v_contra is null)
    or (nullif(v_data ->> 'bankAccountCode', '') is not null and v_bank is null) then
    raise exception 'an account code of the journal isn''t an account of the organization; import accounts first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."save_accounting_journal"(v_tenant, v_data ->> 'code', v_data ->> 'name', v_data ->> 'type', v_default,
    nullif(v_data ->> 'currency', ''), import_accounting_journal.subject_id::uuid, v_contra, v_bank);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_accounting_opening_balance (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_accounting_opening_balance.item ->> 'tenant')::uuid;
  v_data jsonb := import_accounting_opening_balance.item -> 'data';
  v_account uuid;
begin
  if jsonb_typeof(import_accounting_opening_balance.item -> 'data') is distinct from 'object' then
    raise exception 'an opening balance item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'fiscalYear', '') !~ '^[0-9]{4}$' or coalesce(v_data ->> 'amount', '') !~ '^-?[0-9]{1,18}$' then
    raise exception 'an opening balance needs a fiscalYear and an integer amount' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_account := coalesce(nullif(v_data ->> 'accountId', '')::uuid, (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = v_tenant and y."code" = v_data ->> 'accountCode'));
    return jsonb_build_object('subjectId', "better_supabase"."accounting_opening_write"(v_tenant, (v_data ->> 'fiscalYear')::integer, v_account,
      nullif(v_data ->> 'partyId', '')::uuid, (v_data ->> 'amount')::bigint));
  exception
    when invalid_text_representation then
      raise exception 'an opening balance''s ids are uuids' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'order', 'quote', 'invoice', 'credit_note', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          if jsonb_typeof(v_subject -> 'warnings') = 'array' then
            v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
          end if;
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_accounts (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'normalSide', x."normal_side", 'level', x."level", 'defaultTaxCodeId', x."default_tax_code_id", 'active', x."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_accounts" x
  where x."tenant_id" = list_accounting_accounts.tenant
    and (coalesce(list_accounting_accounts.include_archived, false) or x."archived_at" is null)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_journals (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'defaultAccountId', x."default_account_id", 'currency', x."currency", 'contraAccountId', x."contra_account_id", 'bankAccountId', x."bank_account_id", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_journals" x
  where x."tenant_id" = list_accounting_journals.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', list_accounting_opening_balances.tenant,
    'fiscalYear', list_accounting_opening_balances.fiscal_year,
    'posted', "better_supabase"."accounting_opening_posted"(list_accounting_opening_balances.tenant, list_accounting_opening_balances.fiscal_year),
    'balances', coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'fiscalYear', y."fiscal_year", 'accountId', y."account_id", 'partyId', y."party_id", 'amount', y."amount"::text, 'source', y."source") order by y."account_id", y."party_id"), '[]'::jsonb),
    'total', coalesce(sum(y."amount"), 0)::text)
  from "better_supabase"."accounting_opening_balances" y
  where y."tenant_id" = list_accounting_opening_balances.tenant and y."fiscal_year" = list_accounting_opening_balances.fiscal_year
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_periods (
  tenant      uuid,
  fiscal_year integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'fiscalYear', x."fiscal_year", 'number', x."number", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'lockedAt', x."locked_at", 'lockedBy', x."locked_by") order by x."starts_on"), '[]'::jsonb)
  from "better_supabase"."accounting_periods" x
  where x."tenant_id" = list_accounting_periods.tenant
    and (list_accounting_periods.fiscal_year is null or x."fiscal_year" = list_accounting_periods.fiscal_year)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.lock_accounting_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = lock_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to lock accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if v_period."status" = 'locked' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  if v_period."status" <> 'closed' then
    raise exception 'close the period before you lock it' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSE_BLOCKED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'locked', "locked_at" = now(), "locked_by" = auth.uid()
  where y."id" = v_period."id"
  returning * into v_period;
  perform "better_supabase".emit_event('accounting_period.locked', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on"), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.locked',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'locked period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on")
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_fiscal_year (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_start date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_fiscal_year.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if open_fiscal_year.fiscal_year is null or open_fiscal_year.fiscal_year < 1900 or open_fiscal_year.fiscal_year > 9998 then
    raise exception 'the fiscal year is a calendar year such as 2026' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = open_fiscal_year.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  v_start := make_date(open_fiscal_year.fiscal_year, v_settings."fiscal_year_start_month", 1);
  insert into "better_supabase"."accounting_periods" ("tenant_id", "fiscal_year", "number", "starts_on", "ends_on")
  select open_fiscal_year.tenant, open_fiscal_year.fiscal_year, n,
    (v_start + make_interval(months => n - 1))::date,
    (v_start + make_interval(months => n) - interval '1 day')::date
  from generate_series(1, 12) n
  on conflict ("tenant_id", "fiscal_year", "number") do nothing;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'fiscalYear', y."fiscal_year", 'number', y."number", 'startsOn', y."starts_on", 'endsOn', y."ends_on", 'status', y."status", 'closedAt', y."closed_at", 'closedBy', y."closed_by", 'lockedAt', y."locked_at", 'lockedBy', y."locked_by") order by y."number") from "better_supabase"."accounting_periods" y
    where y."tenant_id" = open_fiscal_year.tenant and y."fiscal_year" = open_fiscal_year.fiscal_year
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = post_accounting_entry.entry_id;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  v_row := "better_supabase"."accounting_post"(v_row."id");
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer,
  journal_id  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_journal uuid := post_accounting_opening_balances.journal_id;
  v_starts date;
  v_net numeric;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_accounting_opening_balances.tenant, 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_OPENING_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = post_accounting_opening_balances.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(post_accounting_opening_balances.tenant::text || ':opening:' || post_accounting_opening_balances.fiscal_year::text, 0));
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."source_type" = 'opening_balance'
    and y."source_id" = post_accounting_opening_balances.fiscal_year::text and y."status" <> 'reversed';
  if found then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
  end if;
  select count(*), coalesce(sum(y."amount"), 0) into v_count, v_net from "better_supabase"."accounting_opening_balances" y
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."fiscal_year" = post_accounting_opening_balances.fiscal_year and y."source" = 'imported';
  if v_count = 0 then
    raise exception 'the fiscal year has no imported opening balances' using errcode = 'P0002', hint = 'ACCOUNTING_OPENING_NOT_FOUND';
  end if;
  if v_net <> 0 then
    raise exception 'the opening balances don''t add up to zero' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
  end if;
  select min(y."starts_on") into v_starts from "better_supabase"."accounting_periods" y
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."fiscal_year" = post_accounting_opening_balances.fiscal_year;
  if v_starts is null then
    raise exception 'the fiscal year has no periods; open it first' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if v_journal is null then
    select y."id" into v_journal from "better_supabase"."accounting_journals" y
    where y."tenant_id" = post_accounting_opening_balances.tenant and y."type" = 'general'
    order by y."code" limit 1;
  elsif not exists (select 1 from "better_supabase"."accounting_journals" y where y."id" = v_journal and y."tenant_id" = post_accounting_opening_balances.tenant) then
    raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  if v_journal is null then
    raise exception 'the opening entry needs a general journal' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "source_type", "source_id", "memo", "created_by")
  values (post_accounting_opening_balances.tenant, v_journal, v_starts, 'opening_balance', post_accounting_opening_balances.fiscal_year::text,
    'Opening balances of fiscal year ' || post_accounting_opening_balances.fiscal_year::text, auth.uid())
  returning * into v_row;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency", "amount_currency", "party_id")
  select post_accounting_opening_balances.tenant, v_row."id", (row_number() over (order by w."code", y."party_id"))::smallint, y."account_id",
    greatest(y."amount", 0)::bigint, greatest(-y."amount", 0)::bigint, v_settings."functional_currency", y."amount", y."party_id"
  from "better_supabase"."accounting_opening_balances" y join "better_supabase"."accounting_accounts" w on w."id" = y."account_id"
  where y."tenant_id" = post_accounting_opening_balances.tenant and y."fiscal_year" = post_accounting_opening_balances.fiscal_year and y."source" = 'imported';
  v_row := "better_supabase"."accounting_post"(v_row."id", true);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.post_accounting_source (
  source_type text,
  source_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  v_id := "better_supabase"."accounting_post_source"(post_accounting_source.source_type, post_accounting_source.source_id);
  if v_id is null then
    return null;
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = v_id;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reopen_accounting_period (
  period_id uuid,
  reason    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = reopen_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to reopen accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if nullif(trim(reopen_accounting_period.reason), '') is null then
    raise exception 'reopening a period needs a reason' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  if v_period."status" = 'open' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  if v_period."status" = 'locked' then
    raise exception 'the period is locked; unlock it first' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_LOCKED';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_period."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  if v_settings."lock_date" is not null and v_period."starts_on" <= v_settings."lock_date" then
    raise exception 'the period is on or before the lock date' using errcode = '55000', hint = 'ACCOUNTING_PERIOD_CLOSED';
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'open', "closed_at" = null, "closed_by" = null
  where y."id" = v_period."id"
  returning * into v_period;
  perform "better_supabase".emit_event('accounting_period.reopened', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(reopen_accounting_period.reason)), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.reopened',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'reopened period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(reopen_accounting_period.reason))
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reverse_accounting_entry (
  entry_id   uuid,
  entry_date date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = reverse_accounting_entry.entry_id;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  v_row := "better_supabase"."accounting_reverse"(v_row."id", reverse_accounting_entry.entry_date);
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_account (
  tenant              uuid,
  code                text,
  name                text,
  type                text,
  subtype             text    DEFAULT NULL::text,
  parent_id           uuid    DEFAULT NULL::uuid,
  currency            text    DEFAULT NULL::text,
  reconcilable        boolean DEFAULT false,
  account_id          uuid    DEFAULT NULL::uuid,
  normal_side         text    DEFAULT NULL::text,
  default_tax_code_id uuid    DEFAULT NULL::uuid,
  active              boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_accounts"%rowtype;
  v_id uuid := save_accounting_account.account_id;
  v_currency text := upper(nullif(trim(save_accounting_account.currency), ''));
  v_side text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_account.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if nullif(trim(save_accounting_account.code), '') is null or nullif(trim(save_accounting_account.name), '') is null then
    raise exception 'an account needs a code and a name' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if save_accounting_account.type is null or save_accounting_account.type not in ('asset', 'liability', 'equity', 'income', 'expense') then
    raise exception 'the account type is asset, liability, equity, income or expense' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if save_accounting_account.subtype is not null and save_accounting_account.subtype not in ('bank', 'cash', 'receivable', 'inventory', 'current_asset', 'fixed_asset', 'payable', 'tax', 'current_liability', 'long_term_liability', 'equity', 'revenue', 'other_income', 'cogs', 'operating_expense', 'other_expense') then
    raise exception 'the subtype isn''t one of blocks.accounting.options.subtypes' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  v_side := coalesce(save_accounting_account.normal_side, case when save_accounting_account.type in ('asset', 'expense') then 'debit' else 'credit' end);
  if v_side not in ('debit', 'credit') then
    raise exception 'the normal side is debit or credit' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
  end if;
  if save_accounting_account.default_tax_code_id is not null and not exists (
    select 1 from "better_supabase"."tax_codes" y where y."id" = save_accounting_account.default_tax_code_id and y."tenant_id" = save_accounting_account.tenant
  ) then
    raise exception 'tax code not found' using errcode = 'P0002', hint = 'ACCOUNTING_TAX_CODE_NOT_FOUND';
  end if;
  if v_id is null then
    select y."id" into v_id from "better_supabase"."accounting_accounts" y
    where y."tenant_id" = save_accounting_account.tenant and y."code" = trim(save_accounting_account.code);
  end if;
  if save_accounting_account.parent_id is not null then
    if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_account.parent_id and y."tenant_id" = save_accounting_account.tenant) then
      raise exception 'parent account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if v_id is not null and exists (
      with recursive up (id) as (
        select save_accounting_account.parent_id
        union
        select y."parent_id" from "better_supabase"."accounting_accounts" y join up on y."id" = up.id where y."parent_id" is not null
      )
      select 1 from up where up.id = v_id
    ) then
      raise exception 'an account can''t be its own parent' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
    end if;
  end if;
  if v_id is null then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "parent_id", "currency", "reconcilable",
      "normal_side", "default_tax_code_id", "active")
    values (save_accounting_account.tenant, trim(save_accounting_account.code), trim(save_accounting_account.name), save_accounting_account.type,
      save_accounting_account.subtype, save_accounting_account.parent_id, v_currency, coalesce(save_accounting_account.reconcilable, false),
      v_side, save_accounting_account.default_tax_code_id, coalesce(save_accounting_account.active, true))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."accounting_accounts" y where y."id" = v_id and y."tenant_id" = save_accounting_account.tenant for update;
    if not found then
      raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if exists (
      select 1 from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
      where y."account_id" = v_id and z."status" <> 'draft'
        and (v_row."type" <> save_accounting_account.type or (v_currency is not null and y."currency" <> v_currency))
    ) then
      raise exception 'the account has posted lines, so its type and currency stay' using errcode = '55000', hint = 'ACCOUNTING_ACCOUNT_IN_USE';
    end if;
    update "better_supabase"."accounting_accounts" y set "code" = trim(save_accounting_account.code), "name" = trim(save_accounting_account.name),
      "type" = save_accounting_account.type, "subtype" = save_accounting_account.subtype, "parent_id" = save_accounting_account.parent_id,
      "currency" = v_currency, "reconcilable" = coalesce(save_accounting_account.reconcilable, false),
      "normal_side" = v_side, "default_tax_code_id" = save_accounting_account.default_tax_code_id,
      "active" = coalesce(save_accounting_account.active, true), "updated_at" = now()
    where y."id" = v_id
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'subtype', v_row."subtype", 'parentId', v_row."parent_id", 'currency', v_row."currency", 'reconcilable', v_row."reconcilable", 'normalSide', v_row."normal_side", 'level', v_row."level", 'defaultTaxCodeId', v_row."default_tax_code_id", 'active', v_row."active", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = v_row."id"), '[]'::jsonb), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_entry (
  journal_id  uuid,
  entry_date  date,
  lines       jsonb,
  memo        text  DEFAULT NULL::text,
  reference   text  DEFAULT NULL::text,
  source_type text  DEFAULT NULL::text,
  source_id   text  DEFAULT NULL::text,
  entry_id    uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_line record;
  v_account "better_supabase"."accounting_accounts"%rowtype;
  v_currency text;
  v_debit bigint;
  v_credit bigint;
  v_amount bigint;
  v_rate numeric;
  v_functional bigint;
  v_tax uuid;
  v_party uuid;
  v_dimensions jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_journal from "better_supabase"."accounting_journals" y where y."id" = save_accounting_entry.journal_id;
  if not found then
    raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_journal."tenant_id", 'accounting.write'), false)) then
    raise exception 'not allowed to write accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = v_journal."tenant_id";
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  if save_accounting_entry.entry_date is null then
    raise exception 'an entry needs a date' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if jsonb_typeof(save_accounting_entry.lines) is distinct from 'array' or jsonb_array_length(save_accounting_entry.lines) < 2 then
    raise exception 'an entry needs at least two lines' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if (save_accounting_entry.source_type is null) <> (save_accounting_entry.source_id is null)
    or coalesce(save_accounting_entry.source_type, 'x') !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'source_type (lower-case) and source_id go together' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  if save_accounting_entry.source_type is not null and exists (
    select 1 from "better_supabase"."accounting_entries" y
    where y."tenant_id" = v_journal."tenant_id" and y."source_type" = save_accounting_entry.source_type
      and y."source_id" = save_accounting_entry.source_id and y."status" <> 'reversed'
      and y."id" is distinct from save_accounting_entry.entry_id
  ) then
    raise exception 'the source already has an entry; reverse it first' using errcode = '23505', hint = 'ACCOUNTING_ENTRY_DUPLICATE';
  end if;
  if save_accounting_entry.entry_id is null then
    insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "created_by", "period_id")
    values (v_journal."tenant_id", v_journal."id", save_accounting_entry.entry_date, nullif(trim(save_accounting_entry.reference), ''),
      save_accounting_entry.source_type, save_accounting_entry.source_id, nullif(trim(save_accounting_entry.memo), ''), auth.uid(),
      (select y."id" from "better_supabase"."accounting_periods" y where y."tenant_id" = v_journal."tenant_id" and save_accounting_entry.entry_date >= y."starts_on" and save_accounting_entry.entry_date <= y."ends_on"))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."accounting_entries" y where y."id" = save_accounting_entry.entry_id and y."tenant_id" = v_journal."tenant_id" for update;
    if not found then
      raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
    end if;
    delete from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
    update "better_supabase"."accounting_entries" y set "journal_id" = v_journal."id", "entry_date" = save_accounting_entry.entry_date,
      "reference" = nullif(trim(save_accounting_entry.reference), ''), "source_type" = save_accounting_entry.source_type,
      "source_id" = save_accounting_entry.source_id, "memo" = nullif(trim(save_accounting_entry.memo), ''),
      "period_id" = (select z."id" from "better_supabase"."accounting_periods" z where z."tenant_id" = v_journal."tenant_id" and save_accounting_entry.entry_date >= z."starts_on" and save_accounting_entry.entry_date <= z."ends_on"),
      "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  for v_line in select q.value, q.ordinality from jsonb_array_elements(save_accounting_entry.lines) with ordinality q loop
    if jsonb_typeof(v_line.value) is distinct from 'object' then
      raise exception 'every line is an object' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    if coalesce(v_line.value ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_account from "better_supabase"."accounting_accounts" y where y."id" = (v_line.value ->> 'accountId')::uuid and y."tenant_id" = v_journal."tenant_id";
    else
      select * into v_account from "better_supabase"."accounting_accounts" y where y."code" = v_line.value ->> 'accountCode' and y."tenant_id" = v_journal."tenant_id";
    end if;
    if v_account."id" is null or v_account."archived_at" is not null then
      raise exception 'a line''s account doesn''t exist here or is archived' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    if not v_account."active" then
      raise exception 'a line''s account is inactive' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
    end if;
    if coalesce(v_line.value ->> 'debit', '0') !~ '^[0-9]{1,18}$' or coalesce(v_line.value ->> 'credit', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'amountCurrency', '0') !~ '^-?[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'taxAmount', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'fxRate', '1') !~ '^[0-9]+(\.[0-9]+)?$' then
      raise exception 'debit and credit are non-negative integers, amountCurrency an integer and fxRate a positive decimal' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_debit := coalesce((v_line.value ->> 'debit')::bigint, 0);
    v_credit := coalesce((v_line.value ->> 'credit')::bigint, 0);
    v_currency := upper(coalesce(nullif(v_line.value ->> 'currency', ''), v_settings."functional_currency"));
    if v_currency !~ '^[A-Z]{3}$' then
      raise exception 'a line''s currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    if v_account."currency" is not null and v_account."currency" <> v_currency then
      raise exception 'the account takes lines in its own currency only' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_rate := null;
    if v_currency = v_settings."functional_currency" then
      v_amount := v_debit - v_credit;
    else
      v_amount := (v_line.value ->> 'amountCurrency')::bigint;
      if v_amount is null or v_amount = 0 then
        raise exception 'a line in another currency needs a non-zero amountCurrency' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
      v_rate := coalesce((v_line.value ->> 'fxRate')::numeric,
        "better_supabase"."accounting_fx_rate"(v_journal."tenant_id", v_currency, v_settings."functional_currency", save_accounting_entry.entry_date));
      if v_rate <= 0 then
        raise exception 'fxRate must be positive' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
      if v_debit = 0 and v_credit = 0 then
        v_functional := round(abs(v_amount) * v_rate)::bigint;
        if v_amount > 0 then
          v_debit := v_functional;
        else
          v_credit := v_functional;
        end if;
      elsif (v_amount > 0) <> (v_debit > 0) then
        raise exception 'amountCurrency and the functional amount must be on the same side' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
      end if;
    end if;
    if (v_debit = 0) = (v_credit = 0) then
      raise exception 'every line has either a debit or a credit' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_tax := case when v_line.value ? 'taxCodeId' then null else v_account."default_tax_code_id" end;
    if v_line.value ->> 'taxCodeId' is not null then
      select y."id" into v_tax from "better_supabase"."tax_codes" y
      where y."id"::text = v_line.value ->> 'taxCodeId' and y."tenant_id" = v_journal."tenant_id";
      if v_tax is null then
        raise exception 'tax code not found' using errcode = 'P0002', hint = 'ACCOUNTING_TAX_CODE_NOT_FOUND';
      end if;
    end if;
    if coalesce(v_line.value ->> 'partyId', '00000000-0000-0000-0000-000000000000') !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'partyId must be a uuid' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_party := (v_line.value ->> 'partyId')::uuid;
    if coalesce((v_line.value ->> 'taxAmount')::bigint, 0) > v_debit + v_credit then
      raise exception 'a line''s taxAmount can''t exceed its amount' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_dimensions := coalesce(v_line.value -> 'dimensions', '{}'::jsonb);
    if jsonb_typeof(v_dimensions) = 'null' then
      v_dimensions := '{}'::jsonb;
    end if;
    if jsonb_typeof(v_dimensions) <> 'object' then
      raise exception 'a line''s dimensions are an object of dimension keys to value codes' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
    end if;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
      "amount_currency", "fx_rate", "tax_code_id", "tax_amount", "party_id", "dimensions", "description")
    values (v_journal."tenant_id", v_row."id", v_line.ordinality, v_account."id", v_debit, v_credit, v_currency,
      v_amount, v_rate, v_tax, coalesce((v_line.value ->> 'taxAmount')::bigint, 0), v_party, v_dimensions, nullif(trim(v_line.value ->> 'description'), ''));
  end loop;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'taxAmount', el."tax_amount"::text, 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_journal (
  tenant             uuid,
  code               text,
  name               text,
  type               text,
  default_account_id uuid DEFAULT NULL::uuid,
  currency           text DEFAULT NULL::text,
  journal_id         uuid DEFAULT NULL::uuid,
  contra_account_id  uuid DEFAULT NULL::uuid,
  bank_account_id    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_journals"%rowtype;
  v_id uuid := save_accounting_journal.journal_id;
  v_code text := upper(trim(save_accounting_journal.code));
  v_currency text := upper(nullif(trim(save_accounting_journal.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_journal.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage journals' using errcode = '42501', hint = 'ACCOUNTING_JOURNAL_FORBIDDEN';
  end if;
  if v_code is null or v_code !~ '^[A-Z0-9][A-Z0-9_-]{0,15}$' or nullif(trim(save_accounting_journal.name), '') is null then
    raise exception 'a journal needs a short code (letters, digits, - and _) and a name' using errcode = '22023', hint = 'ACCOUNTING_JOURNAL_INVALID';
  end if;
  if save_accounting_journal.type is null or save_accounting_journal.type not in ('sales', 'purchase', 'bank', 'cash', 'general') then
    raise exception 'the journal type is sales, purchase, bank, cash or general' using errcode = '22023', hint = 'ACCOUNTING_JOURNAL_INVALID';
  end if;
  if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_JOURNAL_INVALID';
  end if;
  if save_accounting_journal.default_account_id is not null and not exists (
    select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_journal.default_account_id
      and y."tenant_id" = save_accounting_journal.tenant and y."archived_at" is null
  ) then
    raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  if save_accounting_journal.contra_account_id is not null and not exists (
    select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_journal.contra_account_id
      and y."tenant_id" = save_accounting_journal.tenant and y."archived_at" is null
  ) then
    raise exception 'contra account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  if v_id is null then
    select y."id" into v_id from "better_supabase"."accounting_journals" y where y."tenant_id" = save_accounting_journal.tenant and y."code" = v_code;
  end if;
  if v_id is null then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id", "currency", "contra_account_id", "bank_account_id")
    values (save_accounting_journal.tenant, v_code, trim(save_accounting_journal.name), save_accounting_journal.type, save_accounting_journal.default_account_id, v_currency,
      save_accounting_journal.contra_account_id, save_accounting_journal.bank_account_id)
    returning * into v_row;
  else
    update "better_supabase"."accounting_journals" y set "code" = v_code, "name" = trim(save_accounting_journal.name), "type" = save_accounting_journal.type,
      "default_account_id" = save_accounting_journal.default_account_id, "currency" = v_currency,
      "contra_account_id" = save_accounting_journal.contra_account_id, "bank_account_id" = save_accounting_journal.bank_account_id, "updated_at" = now()
    where y."id" = v_id and y."tenant_id" = save_accounting_journal.tenant
    returning * into v_row;
    if not found then
      raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'defaultAccountId', v_row."default_account_id", 'currency', v_row."currency", 'contraAccountId', v_row."contra_account_id", 'bankAccountId', v_row."bank_account_id", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_opening_balances (
  tenant      uuid,
  fiscal_year integer,
  balances    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row record;
  v_account uuid;
  v_ids uuid[] := '{}';
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_opening_balances.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_OPENING_FORBIDDEN';
  end if;
  if jsonb_typeof(save_accounting_opening_balances.balances) is distinct from 'array' then
    raise exception 'balances is an array' using errcode = '22023', hint = 'ACCOUNTING_OPENING_INVALID';
  end if;
  for v_row in select e.value from jsonb_array_elements(save_accounting_opening_balances.balances) e loop
    if jsonb_typeof(v_row.value) is distinct from 'object' or coalesce(v_row.value ->> 'amount', '') !~ '^-?[0-9]{1,18}$' then
      raise exception 'every balance is an object with an integer amount' using errcode = '22023', hint = 'ACCOUNTING_OPENING_INVALID';
    end if;
    begin
      v_account := coalesce(
        nullif(v_row.value ->> 'accountId', '')::uuid,
        (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = save_accounting_opening_balances.tenant and y."code" = v_row.value ->> 'accountCode')
      );
      v_ids := v_ids || "better_supabase"."accounting_opening_write"(save_accounting_opening_balances.tenant, save_accounting_opening_balances.fiscal_year,
        v_account, nullif(v_row.value ->> 'partyId', '')::uuid, (v_row.value ->> 'amount')::bigint);
    exception
      when invalid_text_representation then
        raise exception 'accountId and partyId are uuids' using errcode = '22023', hint = 'ACCOUNTING_OPENING_INVALID';
    end;
  end loop;
  return jsonb_build_object('organizationId', save_accounting_opening_balances.tenant, 'fiscalYear', save_accounting_opening_balances.fiscal_year,
    'balances', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'fiscalYear', y."fiscal_year", 'accountId', y."account_id", 'partyId', y."party_id", 'amount', y."amount"::text, 'source', y."source") order by y."account_id", y."party_id"), '[]'::jsonb)
      from "better_supabase"."accounting_opening_balances" y where y."id" = any (v_ids)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.setup_accounting (
  tenant                  uuid,
  functional_currency     text    DEFAULT NULL::text,
  fiscal_year_start_month integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_settings"%rowtype;
  v_currency text := upper(coalesce(nullif(trim(setup_accounting.functional_currency), ''), 'EUR'));
  v_month integer := coalesce(setup_accounting.fiscal_year_start_month, 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', setup_accounting.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage accounting' using errcode = '42501', hint = 'ACCOUNTING_SETTING_FORBIDDEN';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'the functional currency must be an ISO 4217 code such as EUR' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  if v_month < 1 or v_month > 12 then
    raise exception 'the fiscal year starts in a month from 1 to 12' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
  end if;
  select * into v_row from "better_supabase"."accounting_settings" y where y."tenant_id" = setup_accounting.tenant for update;
  if found then
    if setup_accounting.functional_currency is not null and v_row."functional_currency" <> v_currency
      and exists (select 1 from "better_supabase"."accounting_entries" y where y."tenant_id" = setup_accounting.tenant and y."status" <> 'draft') then
      raise exception 'the functional currency can''t change once entries are posted' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    if setup_accounting.fiscal_year_start_month is not null and v_row."fiscal_year_start_month" <> v_month
      and exists (select 1 from "better_supabase"."accounting_periods" y where y."tenant_id" = setup_accounting.tenant) then
      raise exception 'the fiscal year start can''t change once periods exist' using errcode = '22023', hint = 'ACCOUNTING_SETTING_INVALID';
    end if;
    update "better_supabase"."accounting_settings" y set
      "functional_currency" = case when setup_accounting.functional_currency is null then y."functional_currency" else v_currency end,
      "fiscal_year_start_month" = case when setup_accounting.fiscal_year_start_month is null then y."fiscal_year_start_month" else v_month end,
      "updated_at" = now()
    where y."tenant_id" = setup_accounting.tenant
    returning * into v_row;
  else
    insert into "better_supabase"."accounting_settings" ("tenant_id", "functional_currency", "fiscal_year_start_month")
    values (setup_accounting.tenant, v_currency, v_month)
    returning * into v_row;
  end if;
  -- Cost center and cost object are built in: every organization has both.
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  values (setup_accounting.tenant, 'cost_center', 'Cost center'), (setup_accounting.tenant, 'cost_object', 'Cost object')
  on conflict ("tenant_id", "key") do nothing;
  if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable", "normal_side")
    values
      (setup_accounting.tenant, '1000', 'Bank', 'asset', 'bank', true, 'debit'),
      (setup_accounting.tenant, '1100', 'Cash', 'asset', 'cash', false, 'debit'),
      (setup_accounting.tenant, '1200', 'Accounts receivable', 'asset', 'receivable', true, 'debit'),
      (setup_accounting.tenant, '1300', 'Inventory', 'asset', 'inventory', false, 'debit'),
      (setup_accounting.tenant, '1350', 'Work in progress', 'asset', 'inventory', false, 'debit'),
      (setup_accounting.tenant, '1400', 'Tax receivable', 'asset', 'current_asset', false, 'debit'),
      (setup_accounting.tenant, '1500', 'Fixed assets', 'asset', 'fixed_asset', false, 'debit'),
      (setup_accounting.tenant, '1510', 'Accumulated depreciation', 'asset', 'fixed_asset', false, 'debit'),
      (setup_accounting.tenant, '1900', 'Suspense', 'asset', 'current_asset', false, 'debit'),
      (setup_accounting.tenant, '2000', 'Accounts payable', 'liability', 'payable', true, 'credit'),
      (setup_accounting.tenant, '2100', 'Tax payable', 'liability', 'tax', false, 'credit'),
      (setup_accounting.tenant, '3000', 'Share capital', 'equity', 'equity', false, 'credit'),
      (setup_accounting.tenant, '3900', 'Retained earnings', 'equity', 'equity', false, 'credit'),
      (setup_accounting.tenant, '4000', 'Revenue', 'income', 'revenue', false, 'credit'),
      (setup_accounting.tenant, '4900', 'Exchange gains', 'income', 'other_income', false, 'credit'),
      (setup_accounting.tenant, '4910', 'Gains on asset disposals', 'income', 'other_income', false, 'credit'),
      (setup_accounting.tenant, '5000', 'Cost of goods sold', 'expense', 'cogs', false, 'debit'),
      (setup_accounting.tenant, '6000', 'Operating expenses', 'expense', 'operating_expense', false, 'debit'),
      (setup_accounting.tenant, '6800', 'Depreciation', 'expense', 'operating_expense', false, 'debit'),
      (setup_accounting.tenant, '6900', 'Exchange losses', 'expense', 'other_expense', false, 'debit'),
      (setup_accounting.tenant, '6910', 'Losses on asset disposals', 'expense', 'other_expense', false, 'debit');
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select setup_accounting.tenant, c.role, y."id"
    from (values ('bank', '1000'), ('receivable', '1200'), ('inventory', '1300'), ('work_in_progress', '1350'), ('tax_receivable', '1400'), ('fixed_asset', '1500'), ('accumulated_depreciation', '1510'), ('suspense', '1900'), ('payable', '2000'), ('tax_payable', '2100'), ('retained_earnings', '3900'), ('revenue', '4000'), ('fx_gain', '4900'), ('disposal_gain', '4910'), ('cogs', '5000'), ('expense', '6000'), ('depreciation_expense', '6800'), ('fx_loss', '6900'), ('disposal_loss', '6910')) c (role, code)
    join "better_supabase"."accounting_accounts" y on y."tenant_id" = setup_accounting.tenant and y."code" = c.code
    on conflict ("tenant_id", "role") do nothing;
  end if;
  if not exists (select 1 from "better_supabase"."accounting_journals" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id")
    select setup_accounting.tenant, c.code, c.name, c.type,
      (select y."id" from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant and y."code" = c.account)
    from (values ('SAL', 'Sales', 'sales', null::text), ('PUR', 'Purchases', 'purchase', null::text), ('BNK', 'Bank', 'bank', '1000'), ('CSH', 'Cash', 'cash', '1100'), ('GEN', 'General', 'general', null::text)) c (code, name, type, account);
  end if;
  return jsonb_build_object('organizationId', v_row."tenant_id", 'functionalCurrency', v_row."functional_currency", 'fiscalYearStartMonth', v_row."fiscal_year_start_month", 'lockDate', v_row."lock_date", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlock_accounting_period (
  period_id uuid,
  reason    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_period "better_supabase"."accounting_periods"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = unlock_accounting_period.period_id for update;
  if not found then
    raise exception 'period not found' using errcode = 'P0002', hint = 'ACCOUNTING_PERIOD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_period."tenant_id", 'accounting.close'), false)) then
    raise exception 'not allowed to unlock accounting periods' using errcode = '42501', hint = 'ACCOUNTING_PERIOD_FORBIDDEN';
  end if;
  if nullif(trim(unlock_accounting_period.reason), '') is null then
    raise exception 'unlocking a period needs a reason' using errcode = '22023', hint = 'ACCOUNTING_PERIOD_INVALID';
  end if;
  if v_period."status" <> 'locked' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
  end if;
  update "better_supabase"."accounting_periods" y set "status" = 'closed', "locked_at" = null, "locked_by" = null
  where y."id" = v_period."id"
  returning * into v_period;
  perform "better_supabase".emit_event('accounting_period.unlocked', jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(unlock_accounting_period.reason)), 'accounting-periods/' || v_period."id"::text, (v_period."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_period.unlocked',
    category => 'data',
    target_type => 'accounting_period',
    record_id => v_period."id"::text,
    target_label => v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    summary => 'unlocked period ' || v_period."fiscal_year"::text || '-' || lpad(v_period."number"::text, 2, '0'),
    tenant => (v_period."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_period."tenant_id", 'id', v_period."id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'reason', trim(unlock_accounting_period.reason))
  );
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by", 'lockedAt', v_period."locked_at", 'lockedBy', v_period."locked_by");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.wip_valuation (
  tenant uuid,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_as_of date := coalesce(wip_valuation.as_of, current_date);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', wip_valuation.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    with open as (
      select extract(epoch from x."ended_at" - x."started_at") as seconds,
        card.cost, card.currency as cost_currency,
        coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as rate_currency
      from "better_supabase"."time_entries" x
      left join lateral (
        select c."cost_amount" as cost, c."rate" as rate, c."currency"::text as currency
        from "better_supabase"."time_rates" c
        where c."tenant_id" = x."tenant_id"
          and (c."user_id" is null or c."user_id" = x."user_id")
          and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
          and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
        order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
        limit 1
      ) card on true
      where x."tenant_id" = wip_valuation.tenant
        and x."billable" and x."ended_at" is not null
        and (x."started_at" at time zone 'UTC')::date <= v_as_of
        and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
    ),
    amounts as (
      select o.cost_currency as currency, round(o.seconds / 3600.0 * o.cost)::bigint as cost, 0::bigint as billable
      from open o where o.cost is not null
      union all
      select o.rate_currency, 0, round(o.seconds / 3600.0 * o.rate)::bigint
      from open o where o.rate is not null
    )
    select jsonb_build_object(
      'asOf', v_as_of,
      'hours', (select round(coalesce(sum(o.seconds), 0) / 3600.0, 2) from open o),
      'uncostedHours', (select round(coalesce(sum(o.seconds) filter (where o.cost is null), 0) / 3600.0, 2) from open o),
      'unratedHours', (select round(coalesce(sum(o.seconds) filter (where o.rate is null), 0) / 3600.0, 2) from open o),
      'totals', (select coalesce(jsonb_agg(jsonb_build_object('currency', t.currency, 'cost', t.cost::text, 'billable', t.billable::text) order by t.currency), '[]'::jsonb)
        from (select a.currency, sum(a.cost)::bigint as cost, sum(a.billable)::bigint as billable from amounts a group by a.currency) t)
    )
  );
end;
$function$;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD CONSTRAINT "accounting_accounts_default_tax_code_id_fkey" FOREIGN KEY (default_tax_code_id) REFERENCES better_supabase.tax_codes(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD CONSTRAINT "accounting_accounts_level_check" CHECK ((level >= 1));

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD CONSTRAINT "accounting_accounts_normal_side_check" CHECK ((normal_side = ANY (ARRAY['debit'::text, 'credit'::text])));

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ADD CONSTRAINT "accounting_entry_lines_check1" CHECK ((tax_amount <= (debit + credit)));

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ADD CONSTRAINT "accounting_entry_lines_tax_amount_check" CHECK ((tax_amount >= 0));

ALTER TABLE "better_supabase"."accounting_journals"
  ADD CONSTRAINT "accounting_journals_contra_account_id_fkey" FOREIGN KEY (contra_account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_opening_balances"
  ADD CONSTRAINT "accounting_opening_balances_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_periods"
  ADD CONSTRAINT "accounting_periods_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'locked'::text])));

CREATE INDEX accounting_accounts_tax_idx ON better_supabase.accounting_accounts USING btree (default_tax_code_id)
  WHERE (default_tax_code_id IS NOT NULL);

CREATE INDEX accounting_journals_contra_idx ON better_supabase.accounting_journals USING btree (contra_account_id)
  WHERE (contra_account_id IS NOT NULL);

CREATE INDEX accounting_opening_balances_account_idx ON better_supabase.accounting_opening_balances USING btree (account_id);

CREATE UNIQUE INDEX accounting_opening_balances_key_idx ON better_supabase.accounting_opening_balances
  USING btree (tenant_id, fiscal_year, account_id, COALESCE(party_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE TRIGGER bsb_accounting_accounts_level_children
  AFTER UPDATE OF parent_id ON better_supabase.accounting_accounts
  FOR EACH ROW
  WHEN ((old.parent_id IS DISTINCT FROM new.parent_id))
  EXECUTE FUNCTION better_supabase.accounting_account_level_children();

CREATE TRIGGER bsb_accounting_accounts_level
  BEFORE INSERT OR UPDATE OF parent_id ON better_supabase.accounting_accounts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.accounting_account_level();

CREATE POLICY "accounting_opening_balances_read" ON "better_supabase"."accounting_opening_balances"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_opening_balances"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_opening_balances"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_opening_balances"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_opening_balances"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."accounting_column_balance"(uuid, date, date, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_column_balance"(uuid, date, date, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_journal_listing"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_journal_listing"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_period_trial_balance"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_period_trial_balance"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_accounting_account"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_accounting_account"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_accounting_entry"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_accounting_entry"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_accounting_journal"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_accounting_journal"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_accounting_opening_balance"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_accounting_opening_balance"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_opening_balances"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_opening_balances"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."lock_accounting_period"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."lock_accounting_period"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_accounting_opening_balances"(uuid, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_accounting_opening_balances"(uuid, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_opening_balances"(uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_opening_balances"(uuid, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."unlock_accounting_period"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unlock_accounting_period"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."wip_valuation"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."wip_valuation"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_account_level"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_account_level_children"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_column_balance"(uuid, date, date, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_column_balance"(uuid, date, date, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_journal_listing"(uuid, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_journal_listing"(uuid, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_period_trial_balance"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_period_trial_balance"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_accounting_account"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_accounting_account"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_accounting_entry"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_accounting_entry"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_accounting_journal"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_accounting_journal"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_accounting_opening_balance"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_accounting_opening_balance"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_opening_balances"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_opening_balances"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."lock_accounting_period"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."lock_accounting_period"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_accounting_opening_balances"(uuid, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_accounting_opening_balances"(uuid, integer, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid, text, uuid, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_opening_balances"(uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_opening_balances"(uuid, integer, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unlock_accounting_period"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unlock_accounting_period"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."wip_valuation"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."wip_valuation"(uuid, date) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_opening_balances" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_opening_balances" TO "service_role";
