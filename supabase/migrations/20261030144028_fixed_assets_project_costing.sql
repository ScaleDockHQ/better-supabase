SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."accounting_account_roles"
  DROP CONSTRAINT "accounting_account_roles_role_check";

DROP FUNCTION "api"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);

DROP FUNCTION "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date);

CREATE TABLE "better_supabase"."asset_depreciations" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "asset_id"     uuid                     NOT NULL,
  "period_start" date                     NOT NULL,
  "amount"       bigint                   NOT NULL,
  "entry_id"     uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "asset_depreciations_amount_check" CHECK ((amount > 0)),
  CONSTRAINT "asset_depreciations_asset_id_period_start_key" UNIQUE (asset_id, period_start),
  CONSTRAINT "asset_depreciations_period_start_check" CHECK ((EXTRACT(day FROM period_start) = (1)::numeric)),
  CONSTRAINT "asset_depreciations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."asset_depreciations"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "acquisition_cost" bigint;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "currency" text;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "acquired_on" date;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "useful_life_months" integer;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "residual_value" bigint NOT NULL DEFAULT 0;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "depreciation_method" text NOT NULL DEFAULT 'none'::text;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "depreciation_rate_bps" integer;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "disposed_on" date;

ALTER TABLE "better_supabase"."assets"
  ADD COLUMN "disposal_amount" bigint;

ALTER TABLE "better_supabase"."time_rates"
  ADD COLUMN "cost_amount" bigint;

ALTER TABLE "better_supabase"."work_projects"
  ADD COLUMN "budget_amount" bigint;

ALTER TABLE "better_supabase"."work_projects"
  ADD COLUMN "budget_currency" text;

ALTER TABLE "better_supabase"."work_projects"
  ADD COLUMN "budget_hours" numeric(12,2);

CREATE OR REPLACE FUNCTION api.dispose_asset (
  asset_id    uuid,
  disposed_on date,
  amount      bigint DEFAULT 0,
  currency    text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."dispose_asset"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_asset_depreciations (
  asset_id  uuid,
  page_size integer DEFAULT 600
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_asset_depreciations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.project_costs (
  project_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."project_costs"($1) $function$;

CREATE OR REPLACE FUNCTION api.run_asset_depreciation (
  tenant uuid DEFAULT NULL::uuid,
  until  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."run_asset_depreciation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_time_rate (
  tenant         uuid,
  rate           bigint,
  currency       text,
  user_id        uuid   DEFAULT NULL::uuid,
  subject_type   text   DEFAULT NULL::text,
  subject_id     text   DEFAULT NULL::text,
  effective_from date   DEFAULT NULL::date,
  cost_amount    bigint DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_time_rate"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_asset_depreciation_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."period_start" + interval '1 month' - interval '1 day')::date,
    'currency', a."currency",
    'reference', left(coalesce(a."tag" || ' ' || a."name", a."name"), 200),
    'memo', left('Depreciation of ' || a."name" || ' for ' || to_char(y."period_start", 'YYYY-MM'), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'depreciation_expense', 'debit', y."amount"::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'credit', y."amount"::text))
  )
  from "better_supabase"."asset_depreciations" y join "better_supabase"."assets" a on a."id" = y."asset_id"
  where y."id"::text = source_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_asset_disposal_lines (
  source_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', a."tenant_id",
    'entryDate', a."disposed_on",
    'currency', a."currency",
    'reference', left(coalesce(a."tag" || ' ' || a."name", a."name"), 200),
    'memo', left('Disposal of ' || a."name", 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', a."disposal_amount"::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'debit', q.total::text),
      jsonb_build_object('role', 'fixed_asset', 'credit', a."acquisition_cost"::text),
      jsonb_build_object('role', 'disposal_gain', 'credit', greatest(q.result, 0)::text),
      jsonb_build_object('role', 'disposal_loss', 'debit', greatest(-q.result, 0)::text))
  )
  from "better_supabase"."assets" a
  cross join lateral (
    select coalesce(sum(y."amount"), 0) as total,
      a."disposal_amount" + coalesce(sum(y."amount"), 0) - a."acquisition_cost" as result
    from "better_supabase"."asset_depreciations" y where y."asset_id" = a."id"
  ) q
  where a."id"::text = source_id and a."disposed_on" is not null and a."acquisition_cost" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_post_source (
  source_type text,
  source_id   text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc jsonb;
  v_kind text;
  v_tenant uuid;
  v_settings "better_supabase"."accounting_settings"%rowtype;
  v_journal "better_supabase"."accounting_journals"%rowtype;
  v_period "better_supabase"."accounting_periods"%rowtype;
  v_row "better_supabase"."accounting_entries"%rowtype;
  v_date date;
  v_line record;
  v_amount bigint;
  v_functional bigint;
  v_rate numeric;
  v_currency text;
  v_account uuid;
  v_tax "better_supabase"."accounting_tax_codes"%rowtype;
  v_diff bigint;
  v_largest integer;
  v_accounts uuid[] := '{}';
  v_functionals bigint[] := '{}';
  v_amounts bigint[] := '{}';
  v_currencies text[] := '{}';
  v_rates numeric[] := '{}';
  v_taxes uuid[] := '{}';
  v_parties uuid[] := '{}';
  v_dimensions jsonb[] := '{}';
  v_descriptions text[] := '{}';
begin
  if accounting_post_source.source_type is null or accounting_post_source.source_id is null
    or accounting_post_source.source_type not in ('stock_movement', 'invoice', 'invoice_payment', 'asset_depreciation', 'asset_disposal', 'lease_rent', 'lease_payment', 'expense_report', 'expense_reimbursement', 'gift') then
    raise exception 'no installed block books this source type' using errcode = '22023', hint = 'ACCOUNTING_SOURCE_INVALID';
  end if;
  v_doc := case accounting_post_source.source_type
    when 'stock_movement' then "better_supabase"."accounting_stock_movement_lines"(accounting_post_source.source_id)
    when 'invoice' then "better_supabase"."accounting_invoice_lines"(accounting_post_source.source_id)
    when 'invoice_payment' then "better_supabase"."accounting_invoice_payment_lines"(accounting_post_source.source_id)
    when 'asset_depreciation' then "better_supabase"."accounting_asset_depreciation_lines"(accounting_post_source.source_id)
    when 'asset_disposal' then "better_supabase"."accounting_asset_disposal_lines"(accounting_post_source.source_id)
    when 'lease_rent' then "better_supabase"."accounting_lease_rent_lines"(accounting_post_source.source_id)
    when 'lease_payment' then "better_supabase"."accounting_lease_payment_lines"(accounting_post_source.source_id)
    when 'expense_report' then "better_supabase"."accounting_expense_report_lines"(accounting_post_source.source_id)
    when 'expense_reimbursement' then "better_supabase"."accounting_expense_reimbursement_lines"(accounting_post_source.source_id)
    when 'gift' then "better_supabase"."accounting_gift_lines"(accounting_post_source.source_id)
  end;
  v_kind := case accounting_post_source.source_type
    when 'stock_movement' then 'general'
    when 'invoice' then 'sales'
    when 'invoice_payment' then 'bank'
    when 'asset_depreciation' then 'general'
    when 'asset_disposal' then 'general'
    when 'lease_rent' then 'sales'
    when 'lease_payment' then 'bank'
    when 'expense_report' then 'purchase'
    when 'expense_reimbursement' then 'bank'
    when 'gift' then 'bank'
  end;
  if v_doc is null or jsonb_typeof(v_doc -> 'lines') is distinct from 'array' then
    return null;
  end if;
  v_tenant := (v_doc ->> 'organizationId')::uuid;
  select * into v_settings from "better_supabase"."accounting_settings" y where y."tenant_id" = v_tenant;
  if not found then
    return null;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'accounting-source:' || v_tenant::text || ':' || accounting_post_source.source_type || ':' || accounting_post_source.source_id, 0));
  select * into v_row from "better_supabase"."accounting_entries" y
  where y."tenant_id" = v_tenant and y."source_type" = accounting_post_source.source_type
    and y."source_id" = accounting_post_source.source_id and y."status" <> 'reversed';
  if found then
    return v_row."id";
  end if;
  v_date := coalesce((v_doc ->> 'entryDate')::date, current_date);
  v_kind := coalesce(v_doc ->> 'journal', v_kind);
  select * into v_journal from "better_supabase"."accounting_journals" y
  where y."tenant_id" = v_tenant and y."type" = v_kind order by y."code" limit 1;
  if not found then
    raise exception 'the organization has no journal of the type this document books in' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
  end if;
  for v_line in select q.value from jsonb_array_elements(v_doc -> 'lines') q loop
    v_amount := coalesce((v_line.value ->> 'debit')::bigint, 0) - coalesce((v_line.value ->> 'credit')::bigint, 0);
    continue when v_amount = 0;
    v_tax := null;
    if v_line.value ->> 'taxCode' is not null then
      select * into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."tenant_id" = v_tenant and y."code" = v_line.value ->> 'taxCode' and y."archived_at" is null;
    end if;
    if v_tax."id" is null and coalesce(v_line.value ->> 'taxRateBps', '') ~ '^[0-9]{1,6}$' then
      select * into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."tenant_id" = v_tenant and y."rate_bps" = (v_line.value ->> 'taxRateBps')::integer
        and y."kind" = case when v_journal."type" = 'purchase' then 'purchase' else 'sales' end
        and y."archived_at" is null
      order by y."code" limit 1;
    end if;
    v_account := null;
    if v_line.value ->> 'role' in ('tax_payable', 'tax_receivable') and v_tax."id" is not null then
      v_account := v_tax."account_id";
    elsif v_line.value ->> 'accountCode' is not null then
      select y."id" into v_account from "better_supabase"."accounting_accounts" y where y."code" = v_line.value ->> 'accountCode' and y."tenant_id" = v_tenant and y."archived_at" is null;
    elsif v_line.value ->> 'role' is not null then
      select y."id" into v_account from "better_supabase"."accounting_account_roles" z join "better_supabase"."accounting_accounts" y on y."id" = z."account_id"
      where z."tenant_id" = v_tenant and z."role" = v_line.value ->> 'role' and y."archived_at" is null;
    end if;
    if v_account is null then
      select y."id" into v_account from "better_supabase"."accounting_account_roles" z join "better_supabase"."accounting_accounts" y on y."id" = z."account_id"
      where z."tenant_id" = v_tenant and z."role" = 'suspense' and y."archived_at" is null;
    end if;
    if v_account is null then
      raise exception 'no account plays the role a document line needs, and no account plays suspense' using errcode = 'P0002', hint = 'ACCOUNTING_ROLE_UNMAPPED';
    end if;
    v_currency := upper(coalesce(v_line.value ->> 'currency', v_doc ->> 'currency', v_settings."functional_currency"));
    v_rate := null;
    v_functional := v_amount;
    if v_currency <> v_settings."functional_currency" then
      v_rate := "better_supabase"."accounting_fx_rate"(v_tenant, v_currency, v_settings."functional_currency", v_date);
      v_functional := round(v_amount * v_rate)::bigint;
      continue when v_functional = 0;
    end if;
    v_accounts := v_accounts || v_account;
    v_functionals := v_functionals || v_functional;
    v_amounts := v_amounts || v_amount;
    v_currencies := v_currencies || v_currency;
    v_rates := v_rates || v_rate;
    v_taxes := v_taxes || v_tax."id";
    v_parties := v_parties || case when coalesce(v_line.value ->> 'partyId', '') ~ '^[0-9a-fA-F-]{36}$' then (v_line.value ->> 'partyId')::uuid end;
    v_dimensions := v_dimensions || case when jsonb_typeof(v_line.value -> 'dimensions') = 'object' then v_line.value -> 'dimensions' else '{}'::jsonb end;
    v_descriptions := v_descriptions || left(nullif(trim(v_line.value ->> 'description'), ''), 500);
  end loop;
  if coalesce(array_length(v_accounts, 1), 0) < 2 then
    return null;
  end if;
  -- Converting each line rounds on its own; the difference goes to the
  -- largest line on the side that is short.
  select coalesce(sum(u), 0) into v_diff from unnest(v_functionals) u;
  if v_diff <> 0 then
    select q.n into v_largest from unnest(v_functionals) with ordinality q(amount, n)
    where sign(q.amount) = -sign(v_diff) order by abs(q.amount) desc limit 1;
    if v_largest is null then
      raise exception 'the document''s lines don''t balance' using errcode = '23514', hint = 'ACCOUNTING_ENTRY_UNBALANCED';
    end if;
    v_functionals[v_largest] := v_functionals[v_largest] - v_diff;
  end if;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "source_type", "source_id", "memo", "created_by", "period_id")
  values (v_tenant, v_journal."id", v_date, left(nullif(trim(v_doc ->> 'reference'), ''), 200),
    accounting_post_source.source_type, accounting_post_source.source_id, left(nullif(trim(v_doc ->> 'memo'), ''), 2000), auth.uid(),
    (select y."id" from "better_supabase"."accounting_periods" y where y."tenant_id" = v_tenant and v_date >= y."starts_on" and v_date <= y."ends_on"))
  returning * into v_row;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
    "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
  select v_tenant, v_row."id", u.n, u.account, greatest(u.functional, 0), greatest(-u.functional, 0), u.currency,
    case when u.rate is null then u.functional else u.amount end, u.rate, u.tax, u.party, u.dimensions, u.description
  from unnest(v_accounts, v_functionals, v_amounts, v_currencies, v_rates, v_taxes, v_parties, v_dimensions, v_descriptions)
    with ordinality u(account, functional, amount, currency, rate, tax, party, dimensions, description, n);
  select * into v_period from "better_supabase"."accounting_periods" y where y."id" = v_row."period_id";
  if found and v_period."status" = 'open'
    and (v_settings."lock_date" is null or v_date > v_settings."lock_date") then
    perform "better_supabase"."accounting_post"(v_row."id");
  end if;
  return v_row."id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_sync_dimension_value (
  tenant         uuid,
  dimension_key  text,
  dimension_name text,
  code           text,
  value_name     text,
  archived       boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_dimension uuid;
begin
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  values (accounting_sync_dimension_value.tenant, accounting_sync_dimension_value.dimension_key, accounting_sync_dimension_value.dimension_name)
  on conflict ("tenant_id", "key") do nothing;
  select y."id" into v_dimension from "better_supabase"."accounting_dimensions" y
  where y."tenant_id" = accounting_sync_dimension_value.tenant and y."key" = accounting_sync_dimension_value.dimension_key;
  insert into "better_supabase"."accounting_dimension_values" as y ("tenant_id", "dimension_id", "code", "name", "archived_at")
  values (accounting_sync_dimension_value.tenant, v_dimension, accounting_sync_dimension_value.code, left(accounting_sync_dimension_value.value_name, 200),
    case when accounting_sync_dimension_value.archived then now() end)
  on conflict ("dimension_id", "code") do update
    set "name" = excluded."name",
      "archived_at" = case when accounting_sync_dimension_value.archived then coalesce(y."archived_at", now()) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.asset_depreciate (
  asset_id uuid,
  until    date
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_asset "better_supabase"."assets"%rowtype;
  v_row "better_supabase"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_entry uuid;
  v_count integer := 0;
begin
  select * into v_asset from "better_supabase"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "better_supabase"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "better_supabase"."asset_depreciations" ("tenant_id", "asset_id", "period_start", "amount")
      values (v_asset."tenant_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      v_entry := "better_supabase"."accounting_post_source"('asset_depreciation', v_row."id"::text);
      if v_entry is not null then
        update "better_supabase"."asset_depreciations" y set "entry_id" = v_entry where y."id" = v_row."id"
        returning * into v_row;
      end if;
      perform "better_supabase".emit_event('asset.depreciated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'assetId', v_row."asset_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_asset."currency", 'entryId', v_row."entry_id"), 'assets/' || v_asset."id"::text, (v_asset."tenant_id")::text, null, 'better-supabase/assets');
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assets_near (
  tenant        uuid,
  latitude      double precision,
  longitude     double precision,
  radius_meters double precision,
  kind          text             DEFAULT NULL::text,
  page_size     integer          DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_point extensions.geography := extensions.st_setsrid(extensions.st_makepoint(assets_near.longitude, assets_near.latitude), 4326)::extensions.geography;
  v_limit integer := least(greatest(coalesce(assets_near.page_size, 50), 1), 500);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assets_near.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if assets_near.latitude is null or assets_near.longitude is null or assets_near.latitude not between -90 and 90 or assets_near.longitude not between -180 and 180 then
    raise exception 'latitude must be between -90 and 90 and longitude between -180 and 180' using errcode = '22023', hint = 'ASSETS_POINT_INVALID';
  end if;
  if assets_near.radius_meters is null or assets_near.radius_meters <= 0 or assets_near.radius_meters > 1000000 then
    raise exception 'radius_meters must be above 0 and at most 1000000' using errcode = '22023', hint = 'ASSETS_RADIUS_INVALID';
  end if;
  return jsonb_build_object(
    'assets', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, extensions.st_distance(x.point, v_point) as distance, x."id" as id
        from "better_supabase"."assets" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."status" <> 'retired'
          and (assets_near.kind is null or x."kind" = assets_near.kind)
          and extensions.st_dwithin(x.point, v_point, assets_near.radius_meters)
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', extensions.st_asgeojson(x.area::extensions.geometry)::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, extensions.st_distance(x.point, v_point) as distance, x."id" as id
        from "better_supabase"."asset_locations" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."archived_at" is null
          and extensions.st_dwithin(x.point, v_point, assets_near.radius_meters)
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_asset (
  asset_id      uuid,
  assignee_type text,
  assignee_id   text,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = assign_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."tenant_id", 'assets.read'), false)
  ) then
    raise exception 'the member can''t see this organization''s assets' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_asset_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", assign_asset.assignee_type, assign_asset.assignee_id;
    end if;
  end;
  update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  insert into "better_supabase"."asset_assignments" ("tenant_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."tenant_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update "better_supabase"."assets" x set "assignee_type" = assign_asset.assignee_type, "assignee_id" = assign_asset.assignee_id, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('asset.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.assigned',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'assigned asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_asset_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_asset (
  tenant        uuid,
  kind          text,
  name          text,
  location_id   uuid             DEFAULT NULL::uuid,
  tag           text             DEFAULT NULL::text,
  serial_number text             DEFAULT NULL::text,
  latitude      double precision DEFAULT NULL::double precision,
  longitude     double precision DEFAULT NULL::double precision,
  metadata      jsonb            DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = create_asset.location_id and y."tenant_id" = create_asset.tenant and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if create_asset.tag is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = create_asset.tenant and x."tag" = create_asset.tag
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  insert into "better_supabase"."assets" ("tenant_id", "location_id", "kind", "name", "tag", "serial_number", "latitude", "longitude", "metadata", "created_by")
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('asset.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.created',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.accounting_tax_codes', '"better_supabase"."accounting_tax_codes"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_time_rate (
  rate_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_rates" x where x."id" = delete_time_rate.rate_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'billable_time.manage'), false)) then
    raise exception 'no such rate you can change' using errcode = 'P0002', hint = 'TIME_RATE_NOT_FOUND';
  end if;
  delete from "better_supabase"."time_rates" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dispose_asset (
  asset_id    uuid,
  disposed_on date,
  amount      bigint DEFAULT 0,
  currency    text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_entry uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  v_entry := "better_supabase"."accounting_post_source"('asset_disposal', v_row."id"::text);
  perform "better_supabase".emit_event('asset.disposed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'disposedOn', v_row."disposed_on", 'amount', v_row."disposal_amount"::text, 'currency', v_row."currency", 'entryId', v_entry), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.disposed',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'disposed of asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'disposedOn', v_row."disposed_on", 'amount', v_row."disposal_amount"::text, 'currency', v_row."currency", 'entryId', v_entry)
  );
  return "better_supabase"."get_asset"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_asset (
  asset_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = get_asset.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name") order by y."name") from "better_supabase"."booking_resources" y where y.asset_id = v_row."id"), '[]'::jsonb), 'workItems', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'title', z.title) order by z.created_at desc) from (select y."id" as id, y."title" as title, y."created_at" as created_at from "better_supabase"."work_items" y where y.asset_id = v_row."id" and y."closed_at" is null order by y."created_at" desc limit 50) z), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_asset_depreciations (
  asset_id  uuid,
  page_size integer DEFAULT 600
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_assets (
  tenant               uuid,
  location_id          uuid                     DEFAULT NULL::uuid,
  include_sublocations boolean                  DEFAULT false,
  kind                 text                     DEFAULT NULL::text,
  status               text                     DEFAULT NULL::text,
  assignee_type        text                     DEFAULT NULL::text,
  assignee_id          text                     DEFAULT NULL::text,
  query                text                     DEFAULT NULL::text,
  before               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size            integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with recursive below as (
    select y."id" as id, 0 as depth from "better_supabase"."asset_locations" y where y."id" = list_assets.location_id
    union all
    select y."id", below.depth + 1 from "better_supabase"."asset_locations" y join below on y."parent_id" = below.id
    where coalesce(list_assets.include_sublocations, false) and below.depth < 64
  )
  select coalesce(jsonb_agg(z.item order by z.created_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_assets.page_size, 50), 1), 500)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_time_rates (
  tenant       uuid,
  user_id      uuid    DEFAULT NULL::uuid,
  subject_type text    DEFAULT NULL::text,
  subject_id   text    DEFAULT NULL::text,
  page_size    integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_time_rates.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'rate', q."rate"::text, 'currency', q."currency", 'effectiveFrom', q."effective_from", 'cost', q."cost_amount"::text, 'createdBy', q."created_by", 'createdAt', q."created_at") order by q."subject_type" nulls first, q."subject_id" nulls first, q."user_id" nulls first, q."effective_from" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."time_rates" x
      where x."tenant_id" = list_time_rates.tenant
        and (list_time_rates.user_id is null or x."user_id" = list_time_rates.user_id)
        and (list_time_rates.subject_type is null or (x."subject_type" = list_time_rates.subject_type and x."subject_id" = list_time_rates.subject_id))
      order by x."effective_from" desc
      limit least(greatest(coalesce(list_time_rates.page_size, 200), 1), 1000)
    ) q
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.project_costs (
  project_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_project "better_supabase"."work_projects"%rowtype;
  v_result jsonb;
begin
  select * into v_project from "better_supabase"."work_projects" x where x."id" = project_costs.project_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_project."tenant_id", 'billable_time.read'), false)) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'WORK_ITEM_PROJECT_NOT_FOUND';
  end if;
  with spent as (
    select extract(epoch from x."ended_at" - x."started_at") as seconds, card.cost, card.currency,
      d."rate" as billed_rate, d."currency"::text as billed_currency, d."seconds" as billed_seconds
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."cost_amount" as cost, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on true
    left join "better_supabase"."time_invoice_entries" d on d."entry_id" = x."id"
    where x."tenant_id" = v_project."tenant_id"
      and x."ended_at" is not null
      and ((x."subject_type" = 'project' and x."subject_id" = v_project."id"::text) or (x."subject_type" = 'work_item' and x."subject_id" in (
        select y."id"::text from "better_supabase"."work_items" y where y."project_id" = v_project."id"
      )))
  ),
  totals as (
    select u.currency, sum(u.time_cost)::bigint as time_cost, sum(u.billed)::bigint as billed,
      sum(u.expenses)::bigint as expenses, sum(u.income)::bigint as income
    from (
      select s.currency, round(s.seconds / 3600.0 * s.cost)::bigint as time_cost, 0::bigint as billed, 0::bigint as expenses, 0::bigint as income
      from spent s where s.cost is not null
      union all
      select s.billed_currency, 0, round(s.billed_seconds / 3600.0 * s.billed_rate)::bigint, 0, 0
      from spent s where s.billed_rate is not null
      union all
      select q.currency, 0, 0, q.expenses, q.income from (select l."currency"::text as currency,
        coalesce(sum(l."debit" - l."credit") filter (where a."type" = 'expense'), 0)::bigint as expenses,
        coalesce(sum(l."credit" - l."debit") filter (where a."type" = 'income'), 0)::bigint as income
      from "better_supabase"."accounting_entry_lines" l
      join "better_supabase"."accounting_entries" n on n."id" = l."entry_id"
      join "better_supabase"."accounting_accounts" a on a."id" = l."account_id"
      where l."tenant_id" = v_project."tenant_id"
        and n."status" in ('posted', 'reversed')
        and l."dimensions" ->> 'project' = v_project."id"::text
      group by l."currency") q
    ) u
    group by u.currency
  )
  select jsonb_build_object(
    'projectId', v_project."id",
    'organizationId', v_project."tenant_id",
    'hours', (select round(coalesce(sum(s.seconds), 0) / 3600.0, 2) from spent s),
    'uncostedHours', (select round(coalesce(sum(s.seconds) filter (where s.cost is null), 0) / 3600.0, 2) from spent s),
    'budgetAmount', v_project."budget_amount"::text,
    'budgetCurrency', v_project."budget_currency",
    'budgetHours', v_project."budget_hours",
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'currency', t.currency,
          'timeCost', t.time_cost::text,
          'billed', t.billed::text,
          'expenses', t.expenses::text,
          'income', t.income::text,
          'margin', (t.billed + t.income - t.time_cost - t.expenses)::text
        ) order by t.currency), '[]'::jsonb)
      from totals t))
  into v_result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_asset (
  asset_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = release_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."assignee_type" is not null then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
    update "better_supabase"."assets" x set "assignee_type" = null, "assignee_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('asset.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.released',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'released asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.run_asset_depreciation (
  tenant uuid DEFAULT NULL::uuid,
  until  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."assets" x
    where (run_asset_depreciation.tenant is null or x."tenant_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."tenant_id", x."id"
  loop
    v_months := "better_supabase"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_project (
  tenant  uuid,
  project uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."work_projects" ("tenant_id", "key", "name", "owner_user_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."work_projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_user_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'WORK_ITEM_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."work_projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'WORK_ITEM_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'WORK_ITEM_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'WORK_ITEM_PROJECT_INVALID';
  end;

  perform "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
  from "better_supabase"."work_projects" x where x."id" = v_id;
  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."work_projects" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_accounting_account_role (
  tenant     uuid,
  role       text,
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_account_role.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage the chart of accounts' using errcode = '42501', hint = 'ACCOUNTING_ACCOUNT_FORBIDDEN';
  end if;
  if set_accounting_account_role.role is null or set_accounting_account_role.role not in ('receivable', 'payable', 'bank', 'revenue', 'cogs', 'inventory', 'tax_payable', 'tax_receivable', 'retained_earnings', 'fx_gain', 'fx_loss', 'fixed_asset', 'accumulated_depreciation', 'depreciation_expense', 'disposal_gain', 'disposal_loss', 'expense', 'suspense') then
    raise exception 'unknown account role' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_ROLE_INVALID';
  end if;
  if set_accounting_account_role.account_id is null then
    delete from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant and y."role" = set_accounting_account_role.role;
  else
    if not exists (
      select 1 from "better_supabase"."accounting_accounts" y where y."id" = set_accounting_account_role.account_id
        and y."tenant_id" = set_accounting_account_role.tenant and y."archived_at" is null
    ) then
      raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
    end if;
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    values (set_accounting_account_role.tenant, set_accounting_account_role.role, set_accounting_account_role.account_id)
    on conflict ("tenant_id", "role") do update set "account_id" = excluded."account_id", "updated_at" = now();
  end if;
  return coalesce((
    select jsonb_object_agg(y."role", y."account_id") from "better_supabase"."accounting_account_roles" y where y."tenant_id" = set_accounting_account_role.tenant
  ), '{}'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_time_rate (
  tenant         uuid,
  rate           bigint,
  currency       text,
  user_id        uuid   DEFAULT NULL::uuid,
  subject_type   text   DEFAULT NULL::text,
  subject_id     text   DEFAULT NULL::text,
  effective_from date   DEFAULT NULL::date,
  cost_amount    bigint DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_rates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_time_rate.tenant, 'billable_time.manage'), false)) then
    raise exception 'not allowed to change the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if set_time_rate.rate is null or set_time_rate.rate < 0 then
    raise exception 'a rate is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.currency is null or set_time_rate.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.cost_amount < 0 then
    raise exception 'a cost is 0 or more minor units per hour' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if (set_time_rate.subject_type is null) <> (set_time_rate.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if set_time_rate.subject_type is not null and not (case set_time_rate.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (set_time_rate.subject_id)::uuid and s."tenant_id"::text = set_time_rate.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (set_time_rate.subject_id)::uuid and s."organization_id"::text = set_time_rate.tenant::text)
      else false
    end and "better_supabase"."can_subject"(set_time_rate.subject_type, set_time_rate.subject_id, 'read')) then
    raise exception 'the record is unknown or not in this organization' using errcode = '22023', hint = 'TIME_RATE_SUBJECT_INVALID';
  end if;
  if set_time_rate.user_id is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = set_time_rate.tenant and m."user_id" = set_time_rate.user_id
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'TIME_RATE_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."time_rates" ("tenant_id", "user_id", "subject_type", "subject_id", "rate", "currency", "effective_from", "cost_amount", "created_by")
  values (set_time_rate.tenant, set_time_rate.user_id, set_time_rate.subject_type, set_time_rate.subject_id, set_time_rate.rate, set_time_rate.currency,
    coalesce(set_time_rate.effective_from, current_date), set_time_rate.cost_amount, auth.uid())
  on conflict ("tenant_id", "user_id", "subject_type", "subject_id", "effective_from")
  do update set "rate" = excluded."rate", "currency" = excluded."currency", "cost_amount" = excluded."cost_amount", "created_by" = excluded."created_by"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'effectiveFrom', v_row."effective_from", 'cost', v_row."cost_amount"::text, 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
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
  if not exists (select 1 from "better_supabase"."accounting_accounts" y where y."tenant_id" = setup_accounting.tenant) then
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "reconcilable")
    values
      (setup_accounting.tenant, '1000', 'Bank', 'asset', 'bank', true),
      (setup_accounting.tenant, '1100', 'Cash', 'asset', 'cash', false),
      (setup_accounting.tenant, '1200', 'Accounts receivable', 'asset', 'receivable', true),
      (setup_accounting.tenant, '1300', 'Inventory', 'asset', 'inventory', false),
      (setup_accounting.tenant, '1400', 'Tax receivable', 'asset', 'current_asset', false),
      (setup_accounting.tenant, '1500', 'Fixed assets', 'asset', 'fixed_asset', false),
      (setup_accounting.tenant, '1510', 'Accumulated depreciation', 'asset', 'fixed_asset', false),
      (setup_accounting.tenant, '1900', 'Suspense', 'asset', 'current_asset', false),
      (setup_accounting.tenant, '2000', 'Accounts payable', 'liability', 'payable', true),
      (setup_accounting.tenant, '2100', 'Tax payable', 'liability', 'tax', false),
      (setup_accounting.tenant, '3000', 'Share capital', 'equity', 'equity', false),
      (setup_accounting.tenant, '3900', 'Retained earnings', 'equity', 'equity', false),
      (setup_accounting.tenant, '4000', 'Revenue', 'income', 'revenue', false),
      (setup_accounting.tenant, '4900', 'Exchange gains', 'income', 'other_income', false),
      (setup_accounting.tenant, '4910', 'Gains on asset disposals', 'income', 'other_income', false),
      (setup_accounting.tenant, '5000', 'Cost of goods sold', 'expense', 'cogs', false),
      (setup_accounting.tenant, '6000', 'Operating expenses', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6800', 'Depreciation', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6900', 'Exchange losses', 'expense', 'other_expense', false),
      (setup_accounting.tenant, '6910', 'Losses on asset disposals', 'expense', 'other_expense', false);
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select setup_accounting.tenant, c.role, y."id"
    from (values ('bank', '1000'), ('receivable', '1200'), ('inventory', '1300'), ('tax_receivable', '1400'), ('fixed_asset', '1500'), ('accumulated_depreciation', '1510'), ('suspense', '1900'), ('payable', '2000'), ('tax_payable', '2100'), ('retained_earnings', '3900'), ('revenue', '4000'), ('fx_gain', '4900'), ('disposal_gain', '4910'), ('cogs', '5000'), ('expense', '6000'), ('depreciation_expense', '6800'), ('fx_loss', '6900'), ('disposal_loss', '6910')) c (role, code)
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

CREATE OR REPLACE FUNCTION better_supabase.time_rate (
  tenant       uuid,
  user_id      uuid DEFAULT NULL::uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text,
  on_day       date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', time_rate.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read the rate card' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('id', c."id", 'organizationId', c."tenant_id", 'userId', c."user_id", 'subjectType', c."subject_type", 'subjectId', c."subject_id", 'rate', c."rate"::text, 'currency', c."currency", 'effectiveFrom', c."effective_from", 'cost', c."cost_amount"::text, 'createdBy', c."created_by", 'createdAt', c."created_at") from "better_supabase"."time_rates" c
    where c."tenant_id" = time_rate.tenant
      and (c."user_id" is null or c."user_id" = time_rate.user_id)
      and (c."subject_type" is null or (c."subject_type" = time_rate.subject_type and c."subject_id" = time_rate.subject_id))
      and c."effective_from" <= coalesce(time_rate.on_day, current_date)
    order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
    limit 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_asset (
  asset_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_location uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = update_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = v_location and y."tenant_id" = v_row."tenant_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
  end if;
  update "better_supabase"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = v_status,
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  perform "better_supabase".emit_event('asset.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.updated',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$function$;

ALTER TABLE "better_supabase"."accounting_account_roles"
  ADD CONSTRAINT "accounting_account_roles_role_check"
    CHECK
    ((role = ANY (ARRAY['receivable'::text, 'payable'::text, 'bank'::text, 'revenue'::text, 'cogs'::text, 'inventory'::text, 'tax_payable'::text, 'tax_receivable'::text,
    'retained_earnings'::text,
    'fx_gain'::text,
    'fx_loss'::text,
    'fixed_asset'::text, 'accumulated_depreciation'::text, 'depreciation_expense'::text, 'disposal_gain'::text, 'disposal_loss'::text, 'expense'::text, 'suspense'::text])));

ALTER TABLE "better_supabase"."asset_depreciations"
  ADD CONSTRAINT "asset_depreciations_asset_id_fkey" FOREIGN KEY (asset_id) REFERENCES better_supabase.assets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_acquisition_cost_check" CHECK ((acquisition_cost >= 0));

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text));

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_depreciation_method_check" CHECK ((depreciation_method = ANY (ARRAY['none'::text, 'straight_line'::text, 'declining_balance'::text])));

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_depreciation_rate_bps_check" CHECK (((depreciation_rate_bps >= 1) AND (depreciation_rate_bps <= 100000)));

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_disposal_amount_check" CHECK ((disposal_amount >= 0));

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_residual_value_check" CHECK ((residual_value >= 0));

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_useful_life_months_check" CHECK (((useful_life_months >= 1) AND (useful_life_months <= 1200)));

ALTER TABLE "better_supabase"."time_rates"
  ADD CONSTRAINT "time_rates_cost_amount_check" CHECK ((cost_amount >= 0));

ALTER TABLE "better_supabase"."work_projects"
  ADD CONSTRAINT "work_projects_budget_amount_check" CHECK ((budget_amount >= 0));

ALTER TABLE "better_supabase"."work_projects"
  ADD CONSTRAINT "work_projects_budget_currency_check" CHECK ((budget_currency ~ '^[A-Z]{3}$'::text));

ALTER TABLE "better_supabase"."work_projects"
  ADD CONSTRAINT "work_projects_budget_hours_check" CHECK ((budget_hours >= (0)::numeric));

CREATE INDEX asset_depreciations_tenant_idx ON better_supabase.asset_depreciations USING btree (tenant_id, period_start);

CREATE POLICY "asset_depreciations_read" ON "better_supabase"."asset_depreciations"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."asset_depreciations"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."asset_depreciations"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."asset_depreciations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."asset_depreciations"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."dispose_asset"(uuid, date, bigint, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."dispose_asset"(uuid, date, bigint, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_asset_depreciations"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_asset_depreciations"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."project_costs"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."project_costs"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."run_asset_depreciation"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."run_asset_depreciation"(uuid, date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_asset_depreciation_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_asset_disposal_lines"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_sync_dimension_value"(uuid, text, text, text, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."asset_depreciate"(uuid, date) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."dispose_asset"(uuid, date, bigint, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."dispose_asset"(uuid, date, bigint, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_asset_depreciations"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_asset_depreciations"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."project_costs"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."project_costs"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."run_asset_depreciation"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."run_asset_depreciation"(uuid, date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_time_rate"(uuid, bigint, text, uuid, text, text, date, bigint) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."asset_depreciations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."asset_depreciations" TO "service_role";
