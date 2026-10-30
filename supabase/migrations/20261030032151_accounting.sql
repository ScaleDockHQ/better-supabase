SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."accounting_account_roles" (
  "tenant_id"  uuid                     NOT NULL,
  "role"       text                     NOT NULL,
  "account_id" uuid                     NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_account_roles_pkey" PRIMARY KEY (tenant_id, ROLE),
  CONSTRAINT "accounting_account_roles_role_check"
    CHECK
    ((role = ANY (ARRAY['receivable'::text, 'payable'::text, 'bank'::text, 'revenue'::text, 'cogs'::text, 'inventory'::text, 'tax_payable'::text, 'tax_receivable'::text,
    'retained_earnings'::text, 'fx_gain'::text, 'fx_loss'::text, 'fixed_asset'::text, 'accumulated_depreciation'::text, 'depreciation_expense'::text, 'suspense'::text])))
);

ALTER TABLE "better_supabase"."accounting_account_roles"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_accounts" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "code"         text                     NOT NULL,
  "name"         text                     NOT NULL,
  "type"         text                     NOT NULL,
  "subtype"      text,
  "parent_id"    uuid,
  "currency"     text,
  "reconcilable" boolean                  NOT NULL DEFAULT false,
  "archived_at"  timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_accounts_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 50))),
  CONSTRAINT "accounting_accounts_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_accounts_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "accounting_accounts_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_accounts_tenant_id_code_key" UNIQUE (tenant_id, code),
  CONSTRAINT "accounting_accounts_type_check" CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'income'::text, 'expense'::text])))
);

ALTER TABLE "better_supabase"."accounting_accounts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_dimension_values" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "dimension_id" uuid                     NOT NULL,
  "code"         text                     NOT NULL,
  "name"         text                     NOT NULL,
  "archived_at"  timestamp with time zone,
  CONSTRAINT "accounting_dimension_values_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 100))),
  CONSTRAINT "accounting_dimension_values_dimension_id_code_key" UNIQUE (dimension_id, code),
  CONSTRAINT "accounting_dimension_values_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "accounting_dimension_values_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."accounting_dimension_values"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_dimensions" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "key"        text                     NOT NULL,
  "name"       text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_dimensions_key_check" CHECK ((key ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "accounting_dimensions_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "accounting_dimensions_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_dimensions_tenant_id_key_key" UNIQUE (tenant_id, key)
);

ALTER TABLE "better_supabase"."accounting_dimensions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_entries" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "journal_id"  uuid                     NOT NULL,
  "fiscal_year" integer,
  "sequence"    integer,
  "number"      text,
  "entry_date"  date                     NOT NULL,
  "period_id"   uuid,
  "status"      text                     NOT NULL DEFAULT 'draft'::text,
  "reference"   text,
  "source_type" text,
  "source_id"   text,
  "reverses_id" uuid,
  "memo"        text,
  "posted_at"   timestamp with time zone,
  "posted_by"   uuid,
  "created_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_entries_check1" CHECK (((status = 'draft'::text) OR ((number IS NOT NULL) AND (period_id IS NOT NULL) AND (posted_at IS NOT NULL)))),
  CONSTRAINT "accounting_entries_check" CHECK (((source_type IS NULL) = (source_id IS NULL))),
  CONSTRAINT "accounting_entries_memo_check" CHECK (((memo IS NULL) OR (length(memo) <= 2000))),
  CONSTRAINT "accounting_entries_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_entries_reference_check" CHECK (((reference IS NULL) OR (length(reference) <= 200))),
  CONSTRAINT "accounting_entries_source_type_check" CHECK (((source_type IS NULL) OR (source_type ~ '^[a-z][a-z0-9_]{0,62}$'::text))),
  CONSTRAINT "accounting_entries_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'posted'::text, 'reversed'::text])))
);

ALTER TABLE "better_supabase"."accounting_entries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_entry_lines" (
  "id"              uuid     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid     NOT NULL,
  "entry_id"        uuid     NOT NULL,
  "position"        smallint NOT NULL DEFAULT 0,
  "account_id"      uuid     NOT NULL,
  "debit"           bigint   NOT NULL DEFAULT 0,
  "credit"          bigint   NOT NULL DEFAULT 0,
  "currency"        text     NOT NULL,
  "amount_currency" bigint   NOT NULL,
  "fx_rate"         numeric,
  "tax_code_id"     uuid,
  "party_id"        uuid,
  "dimensions"      jsonb    NOT NULL DEFAULT '{}'::jsonb,
  "description"     text,
  CONSTRAINT "accounting_entry_lines_check" CHECK (((debit = 0) <> (credit = 0))),
  CONSTRAINT "accounting_entry_lines_credit_check" CHECK ((credit >= 0)),
  CONSTRAINT "accounting_entry_lines_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_entry_lines_debit_check" CHECK ((debit >= 0)),
  CONSTRAINT "accounting_entry_lines_description_check" CHECK (((description IS NULL) OR (length(description) <= 500))),
  CONSTRAINT "accounting_entry_lines_dimensions_check" CHECK ((jsonb_typeof(dimensions) = 'object'::text)),
  CONSTRAINT "accounting_entry_lines_fx_rate_check" CHECK (((fx_rate IS NULL) OR (fx_rate > (0)::numeric))),
  CONSTRAINT "accounting_entry_lines_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_fx_rates" (
  "tenant_id"  uuid                     NOT NULL,
  "base"       text                     NOT NULL,
  "quote"      text                     NOT NULL,
  "on_date"    date                     NOT NULL,
  "rate"       numeric                  NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_fx_rates_base_check" CHECK ((base ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_fx_rates_check" CHECK ((base <> quote)),
  CONSTRAINT "accounting_fx_rates_pkey" PRIMARY KEY (tenant_id, base, quote, on_date),
  CONSTRAINT "accounting_fx_rates_quote_check" CHECK ((quote ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_fx_rates_rate_check" CHECK ((rate > (0)::numeric))
);

ALTER TABLE "better_supabase"."accounting_fx_rates"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_journals" (
  "id"                 uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"          uuid                     NOT NULL,
  "code"               text                     NOT NULL,
  "name"               text                     NOT NULL,
  "type"               text                     NOT NULL,
  "default_account_id" uuid,
  "currency"           text,
  "created_at"         timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_journals_code_check" CHECK ((code ~ '^[A-Z0-9][A-Z0-9_-]{0,15}$'::text)),
  CONSTRAINT "accounting_journals_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_journals_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "accounting_journals_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_journals_tenant_id_code_key" UNIQUE (tenant_id, code),
  CONSTRAINT "accounting_journals_type_check" CHECK ((type = ANY (ARRAY['sales'::text, 'purchase'::text, 'bank'::text, 'cash'::text, 'general'::text])))
);

ALTER TABLE "better_supabase"."accounting_journals"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_periods" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "fiscal_year" integer                  NOT NULL,
  "number"      smallint                 NOT NULL,
  "starts_on"   date                     NOT NULL,
  "ends_on"     date                     NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'open'::text,
  "closed_at"   timestamp with time zone,
  "closed_by"   uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_periods_check" CHECK ((ends_on >= starts_on)),
  CONSTRAINT "accounting_periods_fiscal_year_check" CHECK (((fiscal_year >= 1900) AND (fiscal_year <= 9999))),
  CONSTRAINT "accounting_periods_number_check" CHECK (((number >= 1) AND (number <= 12))),
  CONSTRAINT "accounting_periods_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_periods_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text]))),
  CONSTRAINT "accounting_periods_tenant_id_fiscal_year_number_key" UNIQUE (tenant_id, fiscal_year, number)
);

ALTER TABLE "better_supabase"."accounting_periods"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_settings" (
  "tenant_id"               uuid                     NOT NULL,
  "functional_currency"     text                     NOT NULL,
  "fiscal_year_start_month" smallint                 NOT NULL DEFAULT 1,
  "lock_date"               date,
  "created_at"              timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"              timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_settings_fiscal_year_start_month_check" CHECK (((fiscal_year_start_month >= 1) AND (fiscal_year_start_month <= 12))),
  CONSTRAINT "accounting_settings_functional_currency_check" CHECK ((functional_currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "accounting_settings_pkey" PRIMARY KEY (tenant_id)
);

ALTER TABLE "better_supabase"."accounting_settings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."accounting_tax_codes" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "code"         text                     NOT NULL,
  "name"         text                     NOT NULL,
  "rate_bps"     integer                  NOT NULL,
  "kind"         text                     NOT NULL,
  "account_id"   uuid                     NOT NULL,
  "report_boxes" text[]                   NOT NULL DEFAULT '{}'::text[],
  "archived_at"  timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "accounting_tax_codes_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 50))),
  CONSTRAINT "accounting_tax_codes_kind_check" CHECK ((kind = ANY (ARRAY['sales'::text, 'purchase'::text]))),
  CONSTRAINT "accounting_tax_codes_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "accounting_tax_codes_pkey" PRIMARY KEY (id),
  CONSTRAINT "accounting_tax_codes_rate_bps_check" CHECK (((rate_bps >= 0) AND (rate_bps <= 100000))),
  CONSTRAINT "accounting_tax_codes_tenant_id_code_key" UNIQUE (tenant_id, code)
);

ALTER TABLE "better_supabase"."accounting_tax_codes"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.accounting_balance_sheet (
  tenant     uuid,
  as_of      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_balance_sheet"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.accounting_fx_rate (
  tenant  uuid,
  base    text,
  quote   text,
  on_date date
)
  RETURNS numeric
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_fx_rate"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.accounting_general_ledger (
  account_id uuid,
  since      date DEFAULT NULL::date,
  until      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_general_ledger"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.accounting_period_close_blockers (
  period_id uuid
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_period_close_blockers"($1) $function$;

CREATE OR REPLACE FUNCTION api.accounting_profit_and_loss (
  tenant     uuid,
  since      date  DEFAULT NULL::date,
  until      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_profit_and_loss"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.accounting_trial_balance (
  tenant     uuid,
  since      date  DEFAULT NULL::date,
  until      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."accounting_trial_balance"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.archive_accounting_account (
  account_id uuid,
  archived   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_accounting_account"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.close_accounting_period (
  period_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."close_accounting_period"($1) $function$;

CREATE OR REPLACE FUNCTION api.close_fiscal_year (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."close_fiscal_year"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_accounting_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_accounting_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_accounting_settings (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_accounting_settings"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_accounts (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_dimensions (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_dimensions"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_entries (
  tenant     uuid,
  journal_id uuid    DEFAULT NULL::uuid,
  status     text    DEFAULT NULL::text,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  page_size  integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_entries"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_journals (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_journals"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_periods (
  tenant      uuid,
  fiscal_year integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_periods"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_accounting_tax_codes (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_accounting_tax_codes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.open_fiscal_year (
  tenant      uuid,
  fiscal_year integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_fiscal_year"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.post_accounting_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_accounting_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.reopen_accounting_period (
  period_id uuid,
  reason    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reopen_accounting_period"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.reverse_accounting_entry (
  entry_id   uuid,
  entry_date date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reverse_accounting_entry"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_account (
  tenant       uuid,
  code         text,
  name         text,
  type         text,
  subtype      text    DEFAULT NULL::text,
  parent_id    uuid    DEFAULT NULL::uuid,
  currency     text    DEFAULT NULL::text,
  reconcilable boolean DEFAULT false,
  account_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_account"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_dimension (
  tenant uuid,
  key    text,
  name   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_dimension"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_dimension_value (
  dimension_id uuid,
  code         text,
  name         text,
  archived     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_dimension_value"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_entry (
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
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_entry"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_journal (
  tenant             uuid,
  code               text,
  name               text,
  type               text,
  default_account_id uuid DEFAULT NULL::uuid,
  currency           text DEFAULT NULL::text,
  journal_id         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_journal"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_accounting_tax_code (
  tenant       uuid,
  code         text,
  name         text,
  rate_bps     integer,
  kind         text,
  account_id   uuid,
  report_boxes text[]  DEFAULT NULL::text[],
  archived     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_accounting_tax_code"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.set_accounting_account_role (
  tenant     uuid,
  role       text,
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_accounting_account_role"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_accounting_fx_rate (
  tenant  uuid,
  base    text,
  quote   text,
  on_date date,
  rate    numeric
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_accounting_fx_rate"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.set_accounting_lock_date (
  tenant    uuid,
  lock_date date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_accounting_lock_date"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.setup_accounting (
  tenant                  uuid,
  functional_currency     text    DEFAULT NULL::text,
  fiscal_year_start_month integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."setup_accounting"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_balance_sheet (
  tenant     uuid,
  as_of      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with sums as (
    select y."account_id" as account, sum(y."debit") - sum(y."credit") as debit_balance
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_balance_sheet.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_balance_sheet.dimensions, '{}'::jsonb)
      and z."entry_date" <= coalesce(accounting_balance_sheet.as_of, current_date)
    group by y."account_id"
  ),
  kept as (
    select w.*, c.debit_balance from sums c join "better_supabase"."accounting_accounts" w on w."id" = c.account
    where c.debit_balance <> 0
  ),
  totals as (
    select
      coalesce(sum(w.debit_balance) filter (where w."type" = 'asset'), 0) as assets,
      coalesce(-sum(w.debit_balance) filter (where w."type" = 'liability'), 0) as liabilities,
      coalesce(-sum(w.debit_balance) filter (where w."type" = 'equity'), 0) as equity,
      coalesce(-sum(w.debit_balance) filter (where w."type" in ('income', 'expense')), 0) as earnings
    from kept w
  )
  select jsonb_build_object(
    'asOf', coalesce(accounting_balance_sheet.as_of, current_date),
    'assets', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (w.debit_balance)::text) order by w."code") from kept w where w."type" = 'asset'), '[]'::jsonb),
    'liabilities', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (-w.debit_balance)::text) order by w."code") from kept w where w."type" = 'liability'), '[]'::jsonb),
    'equity', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (-w.debit_balance)::text) order by w."code") from kept w where w."type" = 'equity'), '[]'::jsonb),
    'currentEarnings', t.earnings::text,
    'totalAssets', t.assets::text,
    'totalLiabilities', t.liabilities::text,
    'totalEquity', (t.equity + t.earnings)::text,
    'balanced', t.assets = t.liabilities + t.equity + t.earnings
  )
  from totals t
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_entry_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_after" <= now()
    ) then
      return old;
    end if;
  end if;
  if tg_op = 'UPDATE' and old."status" = 'draft' then
    return new;
  end if;
  if tg_op = 'DELETE' and old."status" = 'draft' then
    return old;
  end if;
  if tg_op = 'UPDATE' and old."status" = 'posted' and new."status" = 'reversed'
    and (to_jsonb(new) - 'status' - 'updated_at')
      = (to_jsonb(old) - 'status' - 'updated_at') then
    return new;
  end if;
  raise exception 'a posted entry can''t be changed or deleted; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_entry_line_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_entry uuid := case when tg_op = 'DELETE' then old."entry_id" else new."entry_id" end;
begin
  if tg_op = 'DELETE' and current_setting('better_supabase.purge_tenant', true) = to_jsonb(old) ->> tg_argv[0] then
    if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and exists (
      select 1 from "better_supabase"."organization_deletions" x
      where x."organization_id"::text = to_jsonb(old) ->> tg_argv[0]
        and x."cancelled_at" is null and x."purged_at" is null and x."purge_after" <= now()
    ) then
      return old;
    end if;
  end if;
  if exists (select 1 from "better_supabase"."accounting_entries" y where y."id" = v_entry and y."status" <> 'draft')
    or (tg_op = 'UPDATE' and exists (select 1 from "better_supabase"."accounting_entries" y where y."id" = old."entry_id" and y."status" <> 'draft')) then
    raise exception 'the lines of a posted entry can''t change; reverse it' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_POSTED';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_fx_rate (
  tenant  uuid,
  base    text,
  quote   text,
  on_date date
)
  RETURNS numeric
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_base text := upper(trim(accounting_fx_rate.base));
  v_quote text := upper(trim(accounting_fx_rate.quote));
  v_rate numeric;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', accounting_fx_rate.tenant, 'accounting.read'), false)) then
    raise exception 'not allowed to read accounting' using errcode = '42501', hint = 'ACCOUNTING_FX_RATE_FORBIDDEN';
  end if;
  if v_base = v_quote then
    return 1;
  end if;
  select y."rate" into v_rate from "better_supabase"."accounting_fx_rates" y
  where y."tenant_id" = accounting_fx_rate.tenant and y."base" = v_base and y."quote" = v_quote and y."on_date" <= accounting_fx_rate.on_date
  order by y."on_date" desc limit 1;
  if v_rate is null then
    select 1 / y."rate" into v_rate from "better_supabase"."accounting_fx_rates" y
    where y."tenant_id" = accounting_fx_rate.tenant and y."base" = v_quote and y."quote" = v_base and y."on_date" <= accounting_fx_rate.on_date
    order by y."on_date" desc limit 1;
  end if;
  if v_rate is null then
    raise exception 'no exchange rate for the currency pair on or before the date' using errcode = 'P0002', hint = 'ACCOUNTING_FX_RATE_MISSING';
  end if;
  return v_rate;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_general_ledger (
  account_id uuid,
  since      date DEFAULT NULL::date,
  until      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with account as (
    select w.* from "better_supabase"."accounting_accounts" w where w."id" = accounting_general_ledger.account_id
  ),
  booked as (
    select y.*, z."entry_date" as entry_date, z."number" as entry_number, z."journal_id" as journal_id, z."memo" as memo
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where y."account_id" = accounting_general_ledger.account_id and z."status" in ('posted', 'reversed')
      and (accounting_general_ledger.until is null or z."entry_date" <= accounting_general_ledger.until)
  ),
  opening as (
    select coalesce(sum(b."debit" - b."credit"), 0) as amount from booked b
    where b.entry_date < accounting_general_ledger.since
  ),
  period as (
    select b.*, (select o.amount from opening o) + sum(b."debit" - b."credit") over (order by b.entry_date, b.entry_number, b."position", b."id") as balance
    from booked b
    where accounting_general_ledger.since is null or b.entry_date >= accounting_general_ledger.since
  )
  select jsonb_build_object(
    'account', jsonb_build_object('id', w."id", 'code', w."code", 'name', w."name", 'type', w."type"),
    'opening', (select o.amount from opening o)::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('entryId', b."entry_id", 'number', b.entry_number, 'entryDate', b.entry_date, 'journalId', b.journal_id,
      'description', coalesce(b."description", b.memo), 'partyId', b."party_id", 'debit', b."debit"::text, 'credit', b."credit"::text, 'balance', b.balance::text)
      order by b.entry_date, b.entry_number, b."position", b."id") from period b), '[]'::jsonb),
    'closing', ((select o.amount from opening o) + coalesce((select sum(b."debit" - b."credit") from period b), 0))::text
  )
  from account w
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_period_close_blockers (
  period_id uuid
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(array_remove(array[
    case when exists (
      select 1 from "better_supabase"."accounting_entries" y
      where y."tenant_id" = x."tenant_id" and y."status" = 'draft'
        and y."entry_date" >= x."starts_on" and y."entry_date" <= x."ends_on"
    ) then 'draft_entries' end
  ], null), '{}'::text[])
  from "better_supabase"."accounting_periods" x where x."id" = accounting_period_close_blockers.period_id
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
    where y."entry_id" = v_row."id" and z."archived_at" is not null
  ) then
    raise exception 'an account of the entry is archived' using errcode = '22023', hint = 'ACCOUNTING_ACCOUNT_INVALID';
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
  if not coalesce(accounting_post.closing, false) and (
    v_period."status" = 'closed'
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

CREATE OR REPLACE FUNCTION better_supabase.accounting_profit_and_loss (
  tenant     uuid,
  since      date  DEFAULT NULL::date,
  until      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with sums as (
    select y."account_id" as account, sum(y."credit") - sum(y."debit") as credit_balance
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_profit_and_loss.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_profit_and_loss.dimensions, '{}'::jsonb)
      and z."source_type" is distinct from 'fiscal_year'
      and (accounting_profit_and_loss.since is null or z."entry_date" >= accounting_profit_and_loss.since)
      and (accounting_profit_and_loss.until is null or z."entry_date" <= accounting_profit_and_loss.until)
    group by y."account_id"
  ),
  kept as (
    select w.*, c.credit_balance from sums c join "better_supabase"."accounting_accounts" w on w."id" = c.account
    where w."type" in ('income', 'expense') and c.credit_balance <> 0
  )
  select jsonb_build_object(
    'income', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (w.credit_balance)::text) order by w."code") from kept w where w."type" = 'income'), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type", 'subtype', w."subtype", 'amount', (-w.credit_balance)::text) order by w."code") from kept w where w."type" = 'expense'), '[]'::jsonb),
    'totalIncome', coalesce((select sum(w.credit_balance) from kept w where w."type" = 'income'), 0)::text,
    'totalExpenses', coalesce((select -sum(w.credit_balance) from kept w where w."type" = 'expense'), 0)::text,
    'netIncome', coalesce((select sum(w.credit_balance) from kept w), 0)::text
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accounting_trial_balance (
  tenant     uuid,
  since      date  DEFAULT NULL::date,
  until      date  DEFAULT NULL::date,
  dimensions jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with sums as (
    select y."account_id" as account,
      sum(case when z."entry_date" < accounting_trial_balance.since then y."debit" - y."credit" else 0 end) as opening,
      sum(case when accounting_trial_balance.since is null or z."entry_date" >= accounting_trial_balance.since then y."debit" else 0 end) as debit,
      sum(case when accounting_trial_balance.since is null or z."entry_date" >= accounting_trial_balance.since then y."credit" else 0 end) as credit
    from "better_supabase"."accounting_entry_lines" y join "better_supabase"."accounting_entries" z on z."id" = y."entry_id"
    where z."tenant_id" = accounting_trial_balance.tenant and z."status" in ('posted', 'reversed')
      and y."dimensions" @> coalesce(accounting_trial_balance.dimensions, '{}'::jsonb)
      and (accounting_trial_balance.until is null or z."entry_date" <= accounting_trial_balance.until)
    group by y."account_id"
  )
  select jsonb_build_object(
    'accounts', coalesce(jsonb_agg(jsonb_build_object('accountId', w."id", 'code', w."code", 'name', w."name", 'type', w."type",
      'opening', c.opening::text, 'debit', c.debit::text, 'credit', c.credit::text, 'closing', (c.opening + c.debit - c.credit)::text) order by w."code"), '[]'::jsonb),
    'totals', jsonb_build_object('opening', coalesce(sum(c.opening), 0)::text, 'debit', coalesce(sum(c.debit), 0)::text, 'credit', coalesce(sum(c.credit), 0)::text,
      'closing', coalesce(sum(c.opening + c.debit - c.credit), 0)::text)
  )
  from sums c join "better_supabase"."accounting_accounts" w on w."id" = c.account
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
    or exists (select 1 from "better_supabase"."accounting_tax_codes" y where y."account_id" = v_row."id" and y."archived_at" is null)
  ) then
    raise exception 'the account is mapped to a role, a journal or a tax code' using errcode = '55000', hint = 'ACCOUNTING_ACCOUNT_IN_USE';
  end if;
  update "better_supabase"."accounting_accounts" y set "archived_at" = case when coalesce(archive_accounting_account.archived, true) then coalesce(y."archived_at", now()) end,
    "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'subtype', v_row."subtype", 'parentId', v_row."parent_id", 'currency', v_row."currency", 'reconcilable', v_row."reconcilable", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = v_row."id"), '[]'::jsonb), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if v_period."status" = 'closed' then
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
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
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
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
    ('organization', 'better_supabase.accounting_tax_codes', '"better_supabase"."accounting_tax_codes"', 'tenant_id', true, '{}'::text[], true)
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
  v_json := jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
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
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = x."id"), '[]'::jsonb)) from "better_supabase"."accounting_entries" x where x."id" = get_accounting_entry.entry_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_accounting_settings (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('organizationId', x."tenant_id", 'functionalCurrency', x."functional_currency", 'fiscalYearStartMonth', x."fiscal_year_start_month", 'lockDate', x."lock_date", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."accounting_settings" x where x."tenant_id" = get_accounting_settings.tenant
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
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'subtype', x."subtype", 'parentId', x."parent_id", 'currency', x."currency", 'reconcilable', x."reconcilable", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = x."id"), '[]'::jsonb), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_accounts" x
  where x."tenant_id" = list_accounting_accounts.tenant
    and (coalesce(list_accounting_accounts.include_archived, false) or x."archived_at" is null)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_dimensions (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv."id", 'code', dv."code", 'name', dv."name", 'archivedAt', dv."archived_at") order by dv."code") from "better_supabase"."accounting_dimension_values" dv where dv."dimension_id" = x."id"), '[]'::jsonb), 'createdAt', x."created_at") order by x."key"), '[]'::jsonb)
  from "better_supabase"."accounting_dimensions" x
  where x."tenant_id" = list_accounting_dimensions.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_entries (
  tenant     uuid,
  journal_id uuid    DEFAULT NULL::uuid,
  status     text    DEFAULT NULL::text,
  since      date    DEFAULT NULL::date,
  until      date    DEFAULT NULL::date,
  page_size  integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.entry order by z.entry_date desc, z.created_at desc), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'journalId', x."journal_id", 'number', x."number", 'fiscalYear', x."fiscal_year", 'entryDate', x."entry_date", 'periodId', x."period_id", 'status', x."status", 'reference', x."reference", 'sourceType', x."source_type", 'sourceId', x."source_id", 'reversesId', x."reverses_id", 'memo', x."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = x."id"), 0)::text, 'postedAt', x."posted_at", 'postedBy', x."posted_by", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as entry, x."entry_date" as entry_date, x."created_at" as created_at
    from "better_supabase"."accounting_entries" x
    where x."tenant_id" = list_accounting_entries.tenant
      and (list_accounting_entries.journal_id is null or x."journal_id" = list_accounting_entries.journal_id)
      and (list_accounting_entries.status is null or x."status" = list_accounting_entries.status)
      and (list_accounting_entries.since is null or x."entry_date" >= list_accounting_entries.since)
      and (list_accounting_entries.until is null or x."entry_date" <= list_accounting_entries.until)
    order by x."entry_date" desc, x."created_at" desc
    limit least(greatest(coalesce(list_accounting_entries.page_size, 50), 1), 500)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_journals (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'type', x."type", 'defaultAccountId', x."default_account_id", 'currency', x."currency", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_journals" x
  where x."tenant_id" = list_accounting_journals.tenant
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
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'fiscalYear', x."fiscal_year", 'number', x."number", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'closedAt', x."closed_at", 'closedBy', x."closed_by") order by x."starts_on"), '[]'::jsonb)
  from "better_supabase"."accounting_periods" x
  where x."tenant_id" = list_accounting_periods.tenant
    and (list_accounting_periods.fiscal_year is null or x."fiscal_year" = list_accounting_periods.fiscal_year)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_accounting_tax_codes (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'rateBps', x."rate_bps", 'kind', x."kind", 'accountId', x."account_id", 'reportBoxes', to_jsonb(x."report_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."accounting_tax_codes" x
  where x."tenant_id" = list_accounting_tax_codes.tenant
    and (coalesce(list_accounting_tax_codes.include_archived, false) or x."archived_at" is null)
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
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'fiscalYear', y."fiscal_year", 'number', y."number", 'startsOn', y."starts_on", 'endsOn', y."ends_on", 'status', y."status", 'closedAt', y."closed_at", 'closedBy', y."closed_by") order by y."number") from "better_supabase"."accounting_periods" y
    where y."tenant_id" = open_fiscal_year.tenant and y."fiscal_year" = open_fiscal_year.fiscal_year
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'activities.manage' then 'engagements.manage'
    when 'activities.read' then 'engagements.read'
    when 'activities.write' then 'engagements.write'
    when 'agents.create' then 'ai.create'
    when 'agents.moderate' then 'ai.moderate'
    when 'agents.publish' then 'ai.share'
    when 'agents.read' then 'ai.read'
    when 'ai-chat.admin' then 'ai_chat.admin'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai.admin'
    when 'ai-files.upload' then 'ai.create'
    when 'ai-keys.manage' then 'ai.admin'
    when 'ai-keys.use' then 'ai.create'
    when 'ai-schedules.create' then 'ai.create'
    when 'ai-schedules.manage' then 'ai.admin'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'rules.admin'
    when 'automations.edit' then 'rules.edit'
    when 'automations.publish' then 'rules.publish'
    when 'automations.read' then 'rules.read'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'controls.acknowledge'
    when 'compliance.collect' then 'controls.collect'
    when 'compliance.manage' then 'controls.manage'
    when 'compliance.read' then 'controls.read'
    when 'connectors.manage' then 'ai.admin'
    when 'connectors.read' then 'ai.read'
    when 'connectors.use' then 'ai.create'
    when 'contacts.manage' then 'parties.manage'
    when 'contacts.read' then 'parties.read'
    when 'contacts.write' then 'parties.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.sensitive.read'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'organization.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'employees.read' then 'employees.read'
    when 'employees.viewSensitive' then 'employees.view_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'targets.manage'
    when 'goals.read' then 'targets.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'ai.admin'
    when 'knowledge.read' then 'ai.read'
    when 'knowledge.write' then 'ai.create'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail.connect'
    when 'mail-sync.manage' then 'mail.manage'
    when 'mail-sync.read' then 'mail.read'
    when 'mail-sync.send' then 'mail.send'
    when 'memory.manage' then 'ai.admin'
    when 'memory.read' then 'ai.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'number_sequences.assign'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'views.read'
    when 'saved-views.share' then 'views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.edit'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_principals.manage'
    when 'service-accounts.read' then 'service_principals.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'work_items.manage'
    when 'tasks.read' then 'work_items.read'
    when 'tasks.write' then 'work_items.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'activity.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'members.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow.admin'
    when 'workflow-editor.edit' then 'workflow.edit'
    when 'workflow-editor.publish' then 'workflow.publish'
    when 'workflow-editor.read' then 'workflow.read'
    when 'workflow-editor.run' then 'workflow.run'
    when 'workflows.admin' then 'workflow.admin'
    when 'workflows.read' then 'workflow.read'
    when 'workflows.run' then 'workflow.run'
  end
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
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
    return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
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
  return jsonb_build_object('id', v_period."id", 'organizationId', v_period."tenant_id", 'fiscalYear', v_period."fiscal_year", 'number', v_period."number", 'startsOn', v_period."starts_on", 'endsOn', v_period."ends_on", 'status', v_period."status", 'closedAt', v_period."closed_at", 'closedBy', v_period."closed_by");
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
  v_reversal "better_supabase"."accounting_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."accounting_entries" y where y."id" = reverse_accounting_entry.entry_id for update;
  if not found then
    raise exception 'entry not found' using errcode = 'P0002', hint = 'ACCOUNTING_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'accounting.post'), false)) then
    raise exception 'not allowed to post accounting entries' using errcode = '42501', hint = 'ACCOUNTING_ENTRY_FORBIDDEN';
  end if;
  if v_row."status" = 'reversed' then
    raise exception 'the entry is already reversed' using errcode = '55000', hint = 'ACCOUNTING_ENTRY_REVERSED';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted entry can be reversed; delete a draft instead' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_accounting_entry_reverse"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  insert into "better_supabase"."accounting_entries" ("tenant_id", "journal_id", "entry_date", "reference", "reverses_id", "memo", "created_by")
  values (v_row."tenant_id", v_row."journal_id", coalesce(reverse_accounting_entry.entry_date, v_row."entry_date"), v_row."number",
    v_row."id", 'Reversal of ' || v_row."number", auth.uid())
  returning * into v_reversal;
  insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
    "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
  select y."tenant_id", v_reversal."id", y."position", y."account_id", y."credit", y."debit", y."currency",
    -y."amount_currency", y."fx_rate", y."tax_code_id", y."party_id", y."dimensions", y."description"
  from "better_supabase"."accounting_entry_lines" y where y."entry_id" = v_row."id";
  v_reversal := "better_supabase"."accounting_post"(v_reversal."id");
  update "better_supabase"."accounting_entries" y set "status" = 'reversed', "updated_at" = now() where y."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('accounting_entry.reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversalId', v_reversal."id"), 'accounting-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/accounting');
  perform better_supabase.audit_event(
    event_type => 'accounting_entry.reversed',
    category => 'data',
    target_type => 'accounting_entry',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'reversed entry ' || v_row."number" || ' with ' || v_reversal."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'journalId', v_row."journal_id", 'number', v_row."number", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversalId', v_reversal."id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_accounting_entry_reverse"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_reversal."id", 'organizationId', v_reversal."tenant_id", 'journalId', v_reversal."journal_id", 'number', v_reversal."number", 'fiscalYear', v_reversal."fiscal_year", 'entryDate', v_reversal."entry_date", 'periodId', v_reversal."period_id", 'status', v_reversal."status", 'reference', v_reversal."reference", 'sourceType', v_reversal."source_type", 'sourceId', v_reversal."source_id", 'reversesId', v_reversal."reverses_id", 'memo', v_reversal."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_reversal."id"), 0)::text, 'postedAt', v_reversal."posted_at", 'postedBy', v_reversal."posted_by", 'createdBy', v_reversal."created_by", 'createdAt', v_reversal."created_at", 'updatedAt', v_reversal."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_reversal."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_account (
  tenant       uuid,
  code         text,
  name         text,
  type         text,
  subtype      text    DEFAULT NULL::text,
  parent_id    uuid    DEFAULT NULL::uuid,
  currency     text    DEFAULT NULL::text,
  reconcilable boolean DEFAULT false,
  account_id   uuid    DEFAULT NULL::uuid
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
    insert into "better_supabase"."accounting_accounts" ("tenant_id", "code", "name", "type", "subtype", "parent_id", "currency", "reconcilable")
    values (save_accounting_account.tenant, trim(save_accounting_account.code), trim(save_accounting_account.name), save_accounting_account.type,
      save_accounting_account.subtype, save_accounting_account.parent_id, v_currency, coalesce(save_accounting_account.reconcilable, false))
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
      "currency" = v_currency, "reconcilable" = coalesce(save_accounting_account.reconcilable, false), "updated_at" = now()
    where y."id" = v_id
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'subtype', v_row."subtype", 'parentId', v_row."parent_id", 'currency', v_row."currency", 'reconcilable', v_row."reconcilable", 'roles', coalesce((select jsonb_agg(ar."role" order by ar."role") from "better_supabase"."accounting_account_roles" ar where ar."account_id" = v_row."id"), '[]'::jsonb), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_dimension (
  tenant uuid,
  key    text,
  name   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_dimensions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_dimension.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage dimensions' using errcode = '42501', hint = 'ACCOUNTING_DIMENSION_FORBIDDEN';
  end if;
  if coalesce(save_accounting_dimension.key, '') !~ '^[a-z][a-z0-9_]{0,62}$' or nullif(trim(save_accounting_dimension.name), '') is null then
    raise exception 'a dimension needs a lower-case key and a name' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  insert into "better_supabase"."accounting_dimensions" ("tenant_id", "key", "name")
  values (save_accounting_dimension.tenant, save_accounting_dimension.key, trim(save_accounting_dimension.name))
  on conflict ("tenant_id", "key") do update set "name" = excluded."name"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv."id", 'code', dv."code", 'name', dv."name", 'archivedAt', dv."archived_at") order by dv."code") from "better_supabase"."accounting_dimension_values" dv where dv."dimension_id" = v_row."id"), '[]'::jsonb), 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_dimension_value (
  dimension_id uuid,
  code         text,
  name         text,
  archived     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_dimension "better_supabase"."accounting_dimensions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_dimension from "better_supabase"."accounting_dimensions" y where y."id" = save_accounting_dimension_value.dimension_id;
  if not found then
    raise exception 'dimension not found' using errcode = 'P0002', hint = 'ACCOUNTING_DIMENSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_dimension."tenant_id", 'accounting.manage'), false)) then
    raise exception 'not allowed to manage dimensions' using errcode = '42501', hint = 'ACCOUNTING_DIMENSION_FORBIDDEN';
  end if;
  if nullif(trim(save_accounting_dimension_value.code), '') is null or nullif(trim(save_accounting_dimension_value.name), '') is null then
    raise exception 'a dimension value needs a code and a name' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
  end if;
  insert into "better_supabase"."accounting_dimension_values" as y ("tenant_id", "dimension_id", "code", "name", "archived_at")
  values (v_dimension."tenant_id", v_dimension."id", trim(save_accounting_dimension_value.code), trim(save_accounting_dimension_value.name),
    case when coalesce(save_accounting_dimension_value.archived, false) then now() end)
  on conflict ("dimension_id", "code") do update
    set "name" = excluded."name", "archived_at" = case when excluded."archived_at" is null then null else coalesce(y."archived_at", excluded."archived_at") end;
  return jsonb_build_object('id', v_dimension."id", 'organizationId', v_dimension."tenant_id", 'key', v_dimension."key", 'name', v_dimension."name", 'values', coalesce((select jsonb_agg(jsonb_build_object('id', dv."id", 'code', dv."code", 'name', dv."name", 'archivedAt', dv."archived_at") order by dv."code") from "better_supabase"."accounting_dimension_values" dv where dv."dimension_id" = v_dimension."id"), '[]'::jsonb), 'createdAt', v_dimension."created_at");
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
    if coalesce(v_line.value ->> 'debit', '0') !~ '^[0-9]{1,18}$' or coalesce(v_line.value ->> 'credit', '0') !~ '^[0-9]{1,18}$'
      or coalesce(v_line.value ->> 'amountCurrency', '0') !~ '^-?[0-9]{1,18}$'
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
    v_tax := null;
    if v_line.value ->> 'taxCodeId' is not null then
      select y."id" into v_tax from "better_supabase"."accounting_tax_codes" y
      where y."id"::text = v_line.value ->> 'taxCodeId' and y."tenant_id" = v_journal."tenant_id";
      if v_tax is null then
        raise exception 'tax code not found' using errcode = 'P0002', hint = 'ACCOUNTING_TAX_CODE_NOT_FOUND';
      end if;
    end if;
    if coalesce(v_line.value ->> 'partyId', '00000000-0000-0000-0000-000000000000') !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'partyId must be a uuid' using errcode = '22023', hint = 'ACCOUNTING_ENTRY_INVALID';
    end if;
    v_party := (v_line.value ->> 'partyId')::uuid;
    v_dimensions := coalesce(v_line.value -> 'dimensions', '{}'::jsonb);
    if jsonb_typeof(v_dimensions) = 'null' then
      v_dimensions := '{}'::jsonb;
    end if;
    if jsonb_typeof(v_dimensions) <> 'object' then
      raise exception 'a line''s dimensions are an object of dimension keys to value codes' using errcode = '22023', hint = 'ACCOUNTING_DIMENSION_INVALID';
    end if;
    insert into "better_supabase"."accounting_entry_lines" ("tenant_id", "entry_id", "position", "account_id", "debit", "credit", "currency",
      "amount_currency", "fx_rate", "tax_code_id", "party_id", "dimensions", "description")
    values (v_journal."tenant_id", v_row."id", v_line.ordinality, v_account."id", v_debit, v_credit, v_currency,
      v_amount, v_rate, v_tax, v_party, v_dimensions, nullif(trim(v_line.value ->> 'description'), ''));
  end loop;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'journalId', v_row."journal_id", 'number', v_row."number", 'fiscalYear', v_row."fiscal_year", 'entryDate', v_row."entry_date", 'periodId', v_row."period_id", 'status', v_row."status", 'reference', v_row."reference", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'reversesId', v_row."reverses_id", 'memo', v_row."memo", 'total', coalesce((select sum(et."debit") from "better_supabase"."accounting_entry_lines" et where et."entry_id" = v_row."id"), 0)::text, 'postedAt', v_row."posted_at", 'postedBy', v_row."posted_by", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'lines', coalesce((select jsonb_agg(jsonb_build_object('id', el."id", 'accountId', el."account_id", 'accountCode', ea."code", 'accountName', ea."name", 'debit', el."debit"::text, 'credit', el."credit"::text, 'currency', el."currency", 'amountCurrency', el."amount_currency"::text, 'fxRate', el."fx_rate"::text, 'taxCodeId', el."tax_code_id", 'partyId', el."party_id", 'dimensions', el."dimensions", 'description', el."description") order by el."position", el."id") from "better_supabase"."accounting_entry_lines" el join "better_supabase"."accounting_accounts" ea on ea."id" = el."account_id" where el."entry_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_journal (
  tenant             uuid,
  code               text,
  name               text,
  type               text,
  default_account_id uuid DEFAULT NULL::uuid,
  currency           text DEFAULT NULL::text,
  journal_id         uuid DEFAULT NULL::uuid
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
  if v_id is null then
    select y."id" into v_id from "better_supabase"."accounting_journals" y where y."tenant_id" = save_accounting_journal.tenant and y."code" = v_code;
  end if;
  if v_id is null then
    insert into "better_supabase"."accounting_journals" ("tenant_id", "code", "name", "type", "default_account_id", "currency")
    values (save_accounting_journal.tenant, v_code, trim(save_accounting_journal.name), save_accounting_journal.type, save_accounting_journal.default_account_id, v_currency)
    returning * into v_row;
  else
    update "better_supabase"."accounting_journals" y set "code" = v_code, "name" = trim(save_accounting_journal.name), "type" = save_accounting_journal.type,
      "default_account_id" = save_accounting_journal.default_account_id, "currency" = v_currency, "updated_at" = now()
    where y."id" = v_id and y."tenant_id" = save_accounting_journal.tenant
    returning * into v_row;
    if not found then
      raise exception 'journal not found' using errcode = 'P0002', hint = 'ACCOUNTING_JOURNAL_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'defaultAccountId', v_row."default_account_id", 'currency', v_row."currency", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_accounting_tax_code (
  tenant       uuid,
  code         text,
  name         text,
  rate_bps     integer,
  kind         text,
  account_id   uuid,
  report_boxes text[]  DEFAULT NULL::text[],
  archived     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."accounting_tax_codes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_accounting_tax_code.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'ACCOUNTING_TAX_CODE_FORBIDDEN';
  end if;
  if nullif(trim(save_accounting_tax_code.code), '') is null or nullif(trim(save_accounting_tax_code.name), '') is null
    or save_accounting_tax_code.rate_bps is null or save_accounting_tax_code.rate_bps < 0 or save_accounting_tax_code.rate_bps > 100000
    or save_accounting_tax_code.kind is null or save_accounting_tax_code.kind not in ('sales', 'purchase') then
    raise exception 'a tax code needs a code, a name, a rate in basis points and a kind (sales or purchase)' using errcode = '22023', hint = 'ACCOUNTING_TAX_CODE_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."accounting_accounts" y where y."id" = save_accounting_tax_code.account_id
      and y."tenant_id" = save_accounting_tax_code.tenant and y."archived_at" is null
  ) then
    raise exception 'account not found' using errcode = 'P0002', hint = 'ACCOUNTING_ACCOUNT_NOT_FOUND';
  end if;
  insert into "better_supabase"."accounting_tax_codes" ("tenant_id", "code", "name", "rate_bps", "kind", "account_id", "report_boxes", "archived_at")
  values (save_accounting_tax_code.tenant, trim(save_accounting_tax_code.code), trim(save_accounting_tax_code.name), save_accounting_tax_code.rate_bps,
    save_accounting_tax_code.kind, save_accounting_tax_code.account_id, coalesce(save_accounting_tax_code.report_boxes, '{}'),
    case when coalesce(save_accounting_tax_code.archived, false) then now() end)
  on conflict ("tenant_id", "code") do update
    set "name" = excluded."name", "rate_bps" = excluded."rate_bps", "kind" = excluded."kind",
      "account_id" = excluded."account_id", "report_boxes" = excluded."report_boxes", "archived_at" = excluded."archived_at",
      "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'rateBps', v_row."rate_bps", 'kind', v_row."kind", 'accountId', v_row."account_id", 'reportBoxes', to_jsonb(v_row."report_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if set_accounting_account_role.role is null or set_accounting_account_role.role not in ('receivable', 'payable', 'bank', 'revenue', 'cogs', 'inventory', 'tax_payable', 'tax_receivable', 'retained_earnings', 'fx_gain', 'fx_loss', 'fixed_asset', 'accumulated_depreciation', 'depreciation_expense', 'suspense') then
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

CREATE OR REPLACE FUNCTION better_supabase.set_accounting_fx_rate (
  tenant  uuid,
  base    text,
  quote   text,
  on_date date,
  rate    numeric
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_base text := upper(trim(set_accounting_fx_rate.base));
  v_quote text := upper(trim(set_accounting_fx_rate.quote));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_fx_rate.tenant, 'accounting.manage'), false)) then
    raise exception 'not allowed to manage exchange rates' using errcode = '42501', hint = 'ACCOUNTING_FX_RATE_FORBIDDEN';
  end if;
  if coalesce(v_base, '') !~ '^[A-Z]{3}$' or coalesce(v_quote, '') !~ '^[A-Z]{3}$' or v_base = v_quote
    or set_accounting_fx_rate.on_date is null or coalesce(set_accounting_fx_rate.rate, 0) <= 0 then
    raise exception 'a rate needs two different ISO 4217 codes, a date and a positive rate' using errcode = '22023', hint = 'ACCOUNTING_FX_RATE_INVALID';
  end if;
  insert into "better_supabase"."accounting_fx_rates" ("tenant_id", "base", "quote", "on_date", "rate")
  values (set_accounting_fx_rate.tenant, v_base, v_quote, set_accounting_fx_rate.on_date, set_accounting_fx_rate.rate)
  on conflict ("tenant_id", "base", "quote", "on_date") do update set "rate" = excluded."rate";
  return jsonb_build_object('organizationId', set_accounting_fx_rate.tenant, 'base', v_base, 'quote', v_quote,
    'onDate', set_accounting_fx_rate.on_date, 'rate', set_accounting_fx_rate.rate::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_accounting_lock_date (
  tenant    uuid,
  lock_date date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_settings "better_supabase"."accounting_settings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_accounting_lock_date.tenant, 'accounting.close'), false)) then
    raise exception 'not allowed to close accounting periods' using errcode = '42501', hint = 'ACCOUNTING_SETTING_FORBIDDEN';
  end if;
  select * into v_settings from "better_supabase"."accounting_settings" st where st."tenant_id" = set_accounting_lock_date.tenant;
  if not found then
    raise exception 'accounting isn''t set up for this organization; call setup_accounting first' using errcode = 'P0002', hint = 'ACCOUNTING_SETTING_NOT_FOUND';
  end if;
  update "better_supabase"."accounting_settings" y set "lock_date" = set_accounting_lock_date.lock_date, "updated_at" = now()
  where y."tenant_id" = set_accounting_lock_date.tenant
  returning * into v_settings;
  return jsonb_build_object('organizationId', v_settings."tenant_id", 'functionalCurrency', v_settings."functional_currency", 'fiscalYearStartMonth', v_settings."fiscal_year_start_month", 'lockDate', v_settings."lock_date", 'createdAt', v_settings."created_at", 'updatedAt', v_settings."updated_at");
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
      (setup_accounting.tenant, '5000', 'Cost of goods sold', 'expense', 'cogs', false),
      (setup_accounting.tenant, '6000', 'Operating expenses', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6800', 'Depreciation', 'expense', 'operating_expense', false),
      (setup_accounting.tenant, '6900', 'Exchange losses', 'expense', 'other_expense', false);
    insert into "better_supabase"."accounting_account_roles" ("tenant_id", "role", "account_id")
    select setup_accounting.tenant, c.role, y."id"
    from (values ('bank', '1000'), ('receivable', '1200'), ('inventory', '1300'), ('tax_receivable', '1400'), ('fixed_asset', '1500'), ('accumulated_depreciation', '1510'), ('suspense', '1900'), ('payable', '2000'), ('tax_payable', '2100'), ('retained_earnings', '3900'), ('revenue', '4000'), ('fx_gain', '4900'), ('cogs', '5000'), ('depreciation_expense', '6800'), ('fx_loss', '6900')) c (role, code)
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

ALTER TABLE "better_supabase"."accounting_account_roles"
  ADD CONSTRAINT "accounting_account_roles_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_accounts"
  ADD CONSTRAINT "accounting_accounts_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_dimension_values"
  ADD CONSTRAINT "accounting_dimension_values_dimension_id_fkey" FOREIGN KEY (dimension_id) REFERENCES better_supabase.accounting_dimensions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."accounting_entries"
  ADD CONSTRAINT "accounting_entries_reverses_id_fkey" FOREIGN KEY (reverses_id) REFERENCES better_supabase.accounting_entries(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ADD CONSTRAINT "accounting_entry_lines_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ADD CONSTRAINT "accounting_entry_lines_entry_id_fkey" FOREIGN KEY (entry_id) REFERENCES better_supabase.accounting_entries(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."accounting_journals"
  ADD CONSTRAINT "accounting_journals_default_account_id_fkey" FOREIGN KEY (default_account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_entries"
  ADD CONSTRAINT "accounting_entries_journal_id_fkey" FOREIGN KEY (journal_id) REFERENCES better_supabase.accounting_journals(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_entries"
  ADD CONSTRAINT "accounting_entries_period_id_fkey" FOREIGN KEY (period_id) REFERENCES better_supabase.accounting_periods(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_tax_codes"
  ADD CONSTRAINT "accounting_tax_codes_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.accounting_accounts(id) ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."accounting_entry_lines"
  ADD CONSTRAINT "accounting_entry_lines_tax_code_id_fkey" FOREIGN KEY (tax_code_id) REFERENCES better_supabase.accounting_tax_codes(id) ON DELETE RESTRICT;

CREATE INDEX accounting_account_roles_account_idx ON better_supabase.accounting_account_roles USING btree (account_id);

CREATE INDEX accounting_accounts_parent_idx ON better_supabase.accounting_accounts USING btree (parent_id)
  WHERE (parent_id IS NOT NULL);

CREATE INDEX accounting_entries_date_idx ON better_supabase.accounting_entries USING btree (tenant_id, entry_date DESC);

CREATE UNIQUE INDEX accounting_entries_number_idx ON better_supabase.accounting_entries USING btree (journal_id, fiscal_year, SEQUENCE)
  WHERE (SEQUENCE IS NOT NULL);

CREATE INDEX accounting_entries_period_idx ON better_supabase.accounting_entries USING btree (period_id, status);

CREATE UNIQUE INDEX accounting_entries_reverses_idx ON better_supabase.accounting_entries USING btree (reverses_id)
  WHERE (reverses_id IS NOT NULL);

CREATE UNIQUE INDEX accounting_entries_source_idx ON better_supabase.accounting_entries USING btree (tenant_id, source_type, source_id)
  WHERE ((source_type IS NOT NULL) AND (status <> 'reversed'::text));

CREATE INDEX accounting_entry_lines_account_idx ON better_supabase.accounting_entry_lines USING btree (account_id);

CREATE INDEX accounting_entry_lines_entry_idx ON better_supabase.accounting_entry_lines USING btree (entry_id, "position");

CREATE INDEX accounting_entry_lines_party_idx ON better_supabase.accounting_entry_lines USING btree (tenant_id, party_id)
  WHERE (party_id IS NOT NULL);

CREATE INDEX accounting_entry_lines_tax_idx ON better_supabase.accounting_entry_lines USING btree (tax_code_id)
  WHERE (tax_code_id IS NOT NULL);

CREATE INDEX accounting_journals_account_idx ON better_supabase.accounting_journals USING btree (default_account_id)
  WHERE (default_account_id IS NOT NULL);

CREATE INDEX accounting_periods_dates_idx ON better_supabase.accounting_periods USING btree (tenant_id, starts_on, ends_on);

CREATE INDEX accounting_tax_codes_account_idx ON better_supabase.accounting_tax_codes USING btree (account_id);

CREATE TRIGGER bsb_accounting_entries_guard
  BEFORE DELETE OR UPDATE ON better_supabase.accounting_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.accounting_entry_guard('tenant_id');

CREATE TRIGGER bsb_accounting_entry_lines_guard
  BEFORE INSERT OR DELETE OR UPDATE ON better_supabase.accounting_entry_lines
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.accounting_entry_line_guard('tenant_id');

CREATE POLICY "accounting_account_roles_read" ON "better_supabase"."accounting_account_roles"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_account_roles"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_account_roles"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_account_roles"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_account_roles"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_accounts_read" ON "better_supabase"."accounting_accounts"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_accounts"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_accounts"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_accounts"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_accounts"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_dimension_values_read" ON "better_supabase"."accounting_dimension_values"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_dimension_values"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_dimension_values"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_dimension_values"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_dimension_values"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_dimensions_read" ON "better_supabase"."accounting_dimensions"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_dimensions"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_dimensions"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_dimensions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_dimensions"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_entries_read" ON "better_supabase"."accounting_entries"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_entries"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_entries"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_entries"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_entries"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_entry_lines_read" ON "better_supabase"."accounting_entry_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_entry_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_entry_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_entry_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_entry_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_fx_rates_read" ON "better_supabase"."accounting_fx_rates"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_fx_rates"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_fx_rates"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_fx_rates"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_fx_rates"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_journals_read" ON "better_supabase"."accounting_journals"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_journals"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_journals"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_journals"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_journals"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_periods_read" ON "better_supabase"."accounting_periods"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_periods"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_periods"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_periods"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_periods"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_settings_read" ON "better_supabase"."accounting_settings"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_settings"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_settings"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_settings"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_settings"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "accounting_tax_codes_read" ON "better_supabase"."accounting_tax_codes"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."accounting_tax_codes"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."accounting_tax_codes"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."accounting_tax_codes"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('accounting.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."accounting_tax_codes"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."accounting_balance_sheet"(uuid, date, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_balance_sheet"(uuid, date, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_fx_rate"(uuid, text, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_fx_rate"(uuid, text, text, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_general_ledger"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_general_ledger"(uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_period_close_blockers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_period_close_blockers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_profit_and_loss"(uuid, date, date, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_profit_and_loss"(uuid, date, date, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."accounting_trial_balance"(uuid, date, date, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."accounting_trial_balance"(uuid, date, date, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_accounting_account"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_accounting_account"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."close_accounting_period"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."close_accounting_period"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."close_fiscal_year"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."close_fiscal_year"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_accounting_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_accounting_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_accounting_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_accounting_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_accounting_settings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_accounting_settings"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_accounts"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_accounts"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_dimensions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_dimensions"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_entries"(uuid, uuid, text, date, date, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_entries"(uuid, uuid, text, date, date, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_journals"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_journals"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_periods"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_periods"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_accounting_tax_codes"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_accounting_tax_codes"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_fiscal_year"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_fiscal_year"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_accounting_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_accounting_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reopen_accounting_period"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reopen_accounting_period"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reverse_accounting_entry"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reverse_accounting_entry"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_dimension"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_dimension"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_dimension_value"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_dimension_value"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_accounting_tax_code"(uuid, text, text, integer, text, uuid, text[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_accounting_tax_code"(uuid, text, text, integer, text, uuid, text[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_accounting_account_role"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_accounting_account_role"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_accounting_fx_rate"(uuid, text, text, date, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_accounting_fx_rate"(uuid, text, text, date, numeric) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_accounting_lock_date"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_accounting_lock_date"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."setup_accounting"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."setup_accounting"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_balance_sheet"(uuid, date, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_balance_sheet"(uuid, date, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_entry_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_entry_line_guard"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_fx_rate"(uuid, text, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_fx_rate"(uuid, text, text, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_general_ledger"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_general_ledger"(uuid, date, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_period_close_blockers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_period_close_blockers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_post"(uuid, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."accounting_profit_and_loss"(uuid, date, date, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_profit_and_loss"(uuid, date, date, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."accounting_trial_balance"(uuid, date, date, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."accounting_trial_balance"(uuid, date, date, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_accounting_account"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_accounting_account"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."close_accounting_period"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."close_accounting_period"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."close_fiscal_year"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."close_fiscal_year"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_accounting_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_accounting_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_accounting_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_accounting_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_accounting_settings"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_accounting_settings"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_accounts"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_accounts"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_dimensions"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_dimensions"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_entries"(uuid, uuid, text, date, date, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_entries"(uuid, uuid, text, date, date, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_journals"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_journals"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_periods"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_periods"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_accounting_tax_codes"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_accounting_tax_codes"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_fiscal_year"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_fiscal_year"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."post_accounting_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."post_accounting_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reopen_accounting_period"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reopen_accounting_period"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."reverse_accounting_entry"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."reverse_accounting_entry"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_account"(uuid, text, text, text, text, uuid, text, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_dimension"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_dimension"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_dimension_value"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_dimension_value"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_entry"(uuid, date, jsonb, text, text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_journal"(uuid, text, text, text, uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_accounting_tax_code"(uuid, text, text, integer, text, uuid, text[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_accounting_tax_code"(uuid, text, text, integer, text, uuid, text[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_accounting_account_role"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_accounting_account_role"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_accounting_fx_rate"(uuid, text, text, date, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_accounting_fx_rate"(uuid, text, text, date, numeric) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_accounting_lock_date"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_accounting_lock_date"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."setup_accounting"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."setup_accounting"(uuid, text, integer) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_account_roles" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_account_roles" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_accounts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_accounts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_dimension_values" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_dimension_values" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_dimensions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_dimensions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_entries" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_entries" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_entry_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_entry_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_fx_rates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_fx_rates" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_journals" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_journals" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_periods" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_periods" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_settings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_settings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."accounting_tax_codes" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."accounting_tax_codes" TO "service_role";
