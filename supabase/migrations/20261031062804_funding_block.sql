SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."funding_awards" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "funder_id"    uuid                     NOT NULL,
  "product_id"   uuid                     NOT NULL,
  "units"        numeric                  NOT NULL,
  "period"       text                     NOT NULL,
  "starts_on"    date                     NOT NULL,
  "ends_on"      date,
  "reference"    text,
  "status"       text                     NOT NULL DEFAULT 'active'::text,
  "created_by"   uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "funding_awards_check" CHECK (((ends_on IS NULL) OR (ends_on >= starts_on))),
  CONSTRAINT "funding_awards_period_check" CHECK ((period = ANY (ARRAY['week'::text, 'month'::text, 'total'::text]))),
  CONSTRAINT "funding_awards_pkey" PRIMARY KEY (id),
  CONSTRAINT "funding_awards_reference_check" CHECK (((reference IS NULL) OR (length(reference) <= 200))),
  CONSTRAINT "funding_awards_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'active'::text, 'ended'::text, 'canceled'::text]))),
  CONSTRAINT "funding_awards_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "funding_awards_units_check" CHECK ((units > (0)::numeric))
);

ALTER TABLE "better_supabase"."funding_awards"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."funding_claim_lines" (
  "id"             uuid    NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid    NOT NULL,
  "claim_id"       uuid    NOT NULL,
  "award_id"       uuid    NOT NULL,
  "product_id"     uuid    NOT NULL,
  "units"          numeric NOT NULL,
  "amount"         bigint  NOT NULL,
  "status"         text    NOT NULL DEFAULT 'pending'::text,
  "rejection_code" text,
  CONSTRAINT "funding_claim_lines_pkey" PRIMARY KEY (id),
  CONSTRAINT "funding_claim_lines_rejection_code_check" CHECK (((rejection_code IS NULL) OR (length(rejection_code) <= 100))),
  CONSTRAINT "funding_claim_lines_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text]))),
  CONSTRAINT "funding_claim_lines_units_check" CHECK ((units > (0)::numeric))
);

ALTER TABLE "better_supabase"."funding_claim_lines"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."funding_claims" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "funder_id"      uuid                     NOT NULL,
  "number"         text                     NOT NULL,
  "period_start"   date                     NOT NULL,
  "period_end"     date                     NOT NULL,
  "format"         text                     NOT NULL,
  "status"         text                     NOT NULL DEFAULT 'draft'::text,
  "external_ref"   text,
  "sent_at"        timestamp with time zone,
  "payload_sha256" text,
  "response"       jsonb,
  "total"          bigint                   NOT NULL DEFAULT 0,
  "currency"       character(3)             NOT NULL,
  "invoice_id"     uuid,
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "funding_claims_check" CHECK ((period_end >= period_start)),
  CONSTRAINT "funding_claims_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "funding_claims_external_ref_check" CHECK (((external_ref IS NULL) OR (length(external_ref) <= 200))),
  CONSTRAINT "funding_claims_format_check" CHECK ((format ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'::text)),
  CONSTRAINT "funding_claims_number_check" CHECK (((length(number) >= 1) AND (length(number) <= 100))),
  CONSTRAINT "funding_claims_payload_sha256_check" CHECK (((payload_sha256 IS NULL) OR (payload_sha256 ~ '^[0-9a-f]{64}$'::text))),
  CONSTRAINT "funding_claims_pkey" PRIMARY KEY (id),
  CONSTRAINT "funding_claims_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'sent'::text, 'accepted'::text, 'partially_accepted'::text, 'rejected'::text]))),
  CONSTRAINT "funding_claims_tenant_id_id_key" UNIQUE (tenant_id, id)
);

ALTER TABLE "better_supabase"."funding_claims"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."funding_deliveries" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "award_id"      uuid                     NOT NULL,
  "source_type"   text                     NOT NULL DEFAULT 'manual'::text,
  "source_id"     text,
  "delivered_on"  date                     NOT NULL,
  "units"         numeric                  NOT NULL,
  "performer_id"  uuid,
  "status"        text                     NOT NULL DEFAULT 'registered'::text,
  "claim_line_id" uuid,
  "note"          text,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "funding_deliveries_check" CHECK (((source_type = 'manual'::text) OR (source_id IS NOT NULL))),
  CONSTRAINT "funding_deliveries_note_check" CHECK (((note IS NULL) OR (length(note) <= 2000))),
  CONSTRAINT "funding_deliveries_pkey" PRIMARY KEY (id),
  CONSTRAINT "funding_deliveries_source_id_check" CHECK (((source_id IS NULL) OR (length(source_id) <= 200))),
  CONSTRAINT "funding_deliveries_source_type_check" CHECK ((source_type = ANY (ARRAY['time_entry'::text, 'booking'::text, 'manual'::text]))),
  CONSTRAINT "funding_deliveries_status_check" CHECK ((status = ANY (ARRAY['registered'::text, 'approved'::text, 'claimed'::text, 'rejected'::text]))),
  CONSTRAINT "funding_deliveries_units_check" CHECK ((units > (0)::numeric))
);

ALTER TABLE "better_supabase"."funding_deliveries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."funding_products" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "code"        text                     NOT NULL,
  "title"       text                     NOT NULL,
  "unit"        text                     NOT NULL,
  "rate"        bigint                   NOT NULL,
  "currency"    character(3)             NOT NULL,
  "valid_from"  date,
  "valid_until" date,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "funding_products_check" CHECK (((valid_until IS NULL) OR (valid_from IS NULL) OR (valid_until >= valid_from))),
  CONSTRAINT "funding_products_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 50))),
  CONSTRAINT "funding_products_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "funding_products_pkey" PRIMARY KEY (id),
  CONSTRAINT "funding_products_rate_check" CHECK ((rate >= 0)),
  CONSTRAINT "funding_products_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "funding_products_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 300))),
  CONSTRAINT "funding_products_unit_check" CHECK ((unit = ANY (ARRAY['minute'::text, 'hour'::text, 'day_part'::text, 'day'::text, 'visit'::text, 'piece'::text])))
);

ALTER TABLE "better_supabase"."funding_products"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.approve_funding_deliveries (
  ids      uuid[],
  approved boolean DEFAULT true
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."approve_funding_deliveries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.build_funding_claim (
  tenant       uuid,
  funder_id    uuid,
  period_start date,
  period_end   date,
  format       text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."build_funding_claim"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.delete_funding_claim (
  claim_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_funding_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.end_funding_award (
  award_id uuid,
  ends_on  date    DEFAULT NULL::date,
  canceled boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."end_funding_award"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.funding_award_usage (
  award_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."funding_award_usage"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_funding_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.invoice_funding_claim (
  claim_id uuid,
  attrs    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invoice_funding_claim"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_awards (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  include_ended boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_awards"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_claims (
  tenant    uuid,
  status    text DEFAULT NULL::text,
  funder_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_claims"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_deliveries (
  tenant uuid,
  filter jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_deliveries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_products (
  tenant          uuid,
  include_expired boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_products"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.mark_funding_claim_sent (
  claim_id       uuid,
  external_ref   text DEFAULT NULL::text,
  payload_sha256 text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_funding_claim_sent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.record_funding_claim_response (
  claim_id uuid,
  lines    jsonb,
  response jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_funding_claim_response"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.register_funding_deliveries_from_time (
  tenant uuid,
  since  date,
  until  date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."register_funding_deliveries_from_time"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.register_funding_delivery (
  award_id     uuid,
  delivered_on date,
  units        numeric,
  source_type  text    DEFAULT 'manual'::text,
  source_id    text    DEFAULT NULL::text,
  performer_id uuid    DEFAULT NULL::uuid,
  note         text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."register_funding_delivery"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_funding_award (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  attrs        jsonb,
  award_id     uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_funding_award"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_funding_product (
  tenant      uuid,
  code        text,
  title       text,
  unit        text,
  rate        bigint,
  currency    text,
  valid_from  date   DEFAULT NULL::date,
  valid_until date   DEFAULT NULL::date,
  product_id  uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_funding_product"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approve_funding_deliveries (
  ids      uuid[],
  approved boolean DEFAULT true
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "better_supabase"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "better_supabase"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.build_funding_claim (
  tenant       uuid,
  funder_id    uuid,
  period_start date,
  period_end   date,
  format       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "better_supabase"."funding_claims" x where x."tenant_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."funding_claims" ("tenant_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "better_supabase"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "better_supabase"."funding_claim_lines" z
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
    and x."tenant_id" = z."tenant_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "better_supabase"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  perform "better_supabase".emit_event('funding_claim.created', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.created',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Funding claim built',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
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
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_funding_claim (
  claim_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  perform "better_supabase".emit_event('funding_claim.deleted', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.deleted',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Draft funding claim deleted',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_funding_award (
  award_id uuid,
  ends_on  date    DEFAULT NULL::date,
  canceled boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "better_supabase"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('funding_award.ended', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'endsOn', v_row."ends_on"), 'funding-awards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.ended',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_row."id"::text,
    summary => 'Funding award ended',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'endsOn', v_row."ends_on")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.funding_award_usage (
  award_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "better_supabase"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.funding_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.activities' then array['activity'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.leases' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.compliance_policies' then array['compliance_policy'] when 'better_supabase.qualification_types' then array['qualification_type'] when 'better_supabase.risks' then array['risk'] when 'better_supabase.cases' then array['case'] when 'better_supabase.inspections' then array['inspection'] when 'better_supabase.inspection_programs' then array['inspection_program'] when 'better_supabase.inspection_findings' then array['inspection_finding'] when 'better_supabase.forms' then array['form'] when 'better_supabase.meetings' then array['meeting'] when 'better_supabase.meeting_decisions' then array['meeting_decision'] when 'better_supabase.production_orders' then array['production_order'] when 'better_supabase.work_centers' then array['work_center'] when 'better_supabase.bank_accounts' then array['bank_account'] when 'better_supabase.care_plans' then array['care_plan'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.change_requests' then array['change_request'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."funding_awards" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_funding_claim (
  claim_id uuid,
  attrs    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_party jsonb;
  v_lines jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = invoice_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" not in ('accepted', 'partially_accepted') then
    raise exception 'only a claim the funder accepted is invoiced' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_claim."invoice_id" is not null then
    raise exception 'the funding claim is invoiced already' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  v_party := case
    when exists (select 1 from "better_supabase"."companies" x where x."id" = v_claim."funder_id")
      then jsonb_build_object('company', jsonb_build_object('id', v_claim."funder_id"))
    else jsonb_build_object('contact', jsonb_build_object('id', v_claim."funder_id"))
  end;
  select coalesce(jsonb_agg(jsonb_build_object(
    'description', y."code" || ' ' || y."title",
    'quantity', z."units",
    'unitAmount', y."rate"::text
  ) order by y."code", z."id"), '[]'::jsonb) into v_lines
  from "better_supabase"."funding_claim_lines" z
  join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'accepted';
  v_invoice := "better_supabase"."create_invoice"(v_claim."tenant_id",
    v_party || (coalesce(invoice_funding_claim.attrs, '{}'::jsonb) - 'origin' - 'company' - 'contact') || jsonb_build_object('currency', v_claim."currency",
      'title', coalesce(nullif(trim(invoice_funding_claim.attrs ->> 'title'), ''), 'Funding claim ' || v_claim."number")),
    v_lines);
  update "better_supabase"."funding_claims" x set "invoice_id" = (v_invoice ->> 'id')::uuid, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  return jsonb_build_object('claim', jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at"), 'invoice', v_invoice);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_funding_awards (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  include_ended boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."funding_awards" x
  join "better_supabase"."funding_products" y on y."tenant_id" = x."tenant_id" and y."id" = x."product_id"
  where x."tenant_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_funding_claims (
  tenant    uuid,
  status    text DEFAULT NULL::text,
  funder_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_funding_deliveries (
  tenant uuid,
  filter jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_funding_products (
  tenant          uuid,
  include_expired boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "better_supabase"."funding_products" x
  where x."tenant_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_funding_claim_sent (
  claim_id       uuid,
  external_ref   text DEFAULT NULL::text,
  payload_sha256 text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  perform "better_supabase".emit_event('funding_claim.sent', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'externalRef', v_claim."external_ref"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.sent',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Funding claim sent',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'externalRef', v_claim."external_ref")
  );
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
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
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.manage'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
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
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
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
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
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
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
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
    when 'employees.viewSensitive' then 'employees.read_sensitive'
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
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
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
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
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
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
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
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.write'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
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
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'timeline.read'
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
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow_editor.manage'
    when 'workflow-editor.edit' then 'workflow_editor.write'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflows.admin' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_funding_claim_response (
  claim_id uuid,
  lines    jsonb,
  response jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "better_supabase"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "better_supabase"."funding_claim_lines" x set "status" = 'accepted'
  where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id";
  update "better_supabase"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  perform "better_supabase".emit_event('funding_claim.responded', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.responded',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Funding claim response recorded',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_funding_deliveries_from_time (
  tenant uuid,
  since  date,
  until  date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_entry record;
  v_awards uuid[];
  v_units numeric;
  v_award uuid;
  v_unit text;
  v_delivery jsonb;
  v_registered jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
begin
  if register_funding_deliveries_from_time.since is null or register_funding_deliveries_from_time.until is null
    or register_funding_deliveries_from_time.until < register_funding_deliveries_from_time.since then
    raise exception 'since and until are days, until on or after since' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_entry in
    select x."id"::text as id, x."subject_type" as subject_type, x."subject_id"::text as subject_id,
      (x."started_at" at time zone 'UTC')::date as day,
      extract(epoch from x."ended_at" - x."started_at") as seconds,
      x."user_id" as performer, null::text as category
    from "better_supabase"."time_entries" x
    where x."tenant_id" = register_funding_deliveries_from_time.tenant
      and x."ended_at" is not null
      and x."subject_type" is not null
      and x."started_at" >= (register_funding_deliveries_from_time.since::timestamp at time zone 'UTC')
      and x."started_at" < ((register_funding_deliveries_from_time.until + 1)::timestamp at time zone 'UTC')
      and exists (
        select 1 from "better_supabase"."timesheets" s
        where s."tenant_id" = x."tenant_id" and s."user_id" = x."user_id"
          and s."week" = "better_supabase"."time_week"(x."started_at") and s."approved_at" is not null
      )
      and not exists (
        select 1 from "better_supabase"."funding_deliveries" z
        where z."tenant_id" = x."tenant_id" and z."source_type" = 'time_entry' and z."source_id" = x."id"::text
      )
    order by x."started_at", x."id"
  loop
    select array_agg(a."id" order by a."id"), min(y."unit") into v_awards, v_unit
    from "better_supabase"."funding_awards" a
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where a."tenant_id" = register_funding_deliveries_from_time.tenant
      and a."subject_type" = v_entry.subject_type and a."subject_id" = v_entry.subject_id
      and a."status" = 'active'
      and v_entry.day >= a."starts_on" and v_entry.day <= coalesce(a."ends_on", v_entry.day)
      and (y."valid_from" is null or v_entry.day >= y."valid_from")
      and (y."valid_until" is null or v_entry.day <= y."valid_until");
    if coalesce(cardinality(v_awards), 0) <> 1 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', case when coalesce(cardinality(v_awards), 0) = 0 then 'no_award' else 'several_awards' end
      ));
      continue;
    end if;
    v_award := v_awards[1];
    v_units := case v_unit
      when 'minute' then round(v_entry.seconds / 60, 2)
      when 'hour' then round(v_entry.seconds / 3600, 4)
      else 1
    end;
    if v_units <= 0 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', 'no_duration'
      ));
      continue;
    end if;
    v_delivery := "better_supabase"."register_funding_delivery"(v_award, v_entry.day, v_units, 'time_entry', v_entry.id, v_entry.performer, null);
    v_registered := v_registered || jsonb_build_array(v_delivery);
  end loop;
  return jsonb_build_object('registered', v_registered, 'unmatched', v_unmatched);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_funding_delivery (
  award_id     uuid,
  delivered_on date,
  units        numeric,
  source_type  text    DEFAULT 'manual'::text,
  source_id    text    DEFAULT NULL::text,
  performer_id uuid    DEFAULT NULL::uuid,
  note         text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_award "better_supabase"."funding_awards"%rowtype;
  v_product "better_supabase"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "better_supabase"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."tenant_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = v_award."tenant_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "better_supabase"."funding_products" x where x."tenant_id" = v_award."tenant_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source = 'time_entry' and not exists (
    select 1 from "better_supabase"."time_entries" x
    where x."id"::text = v_source_id and x."tenant_id" = v_award."tenant_id"
  ) then
    raise exception 'the time entry isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source = 'booking' and not exists (
    select 1 from "better_supabase"."bookings" x
    where x."id"::text = v_source_id and x."tenant_id" = v_award."tenant_id"
  ) then
    raise exception 'the booking isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."tenant_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  perform "better_supabase".emit_event('funding_delivery.registered', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."award_id", 'fundingDeliveryId', v_row."id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units"), 'funding-awards/' || v_row."award_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_delivery.registered',
    category => 'data',
    target_type => 'funding_delivery',
    record_id => v_row."id"::text,
    summary => 'Funded care registered',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."award_id", 'fundingDeliveryId', v_row."id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units")
  );
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "better_supabase"."funding_deliveries" x
  where x."tenant_id" = v_award."tenant_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    perform "better_supabase".emit_event('funding_award.exceeded', jsonb_build_object('organizationId', v_award."tenant_id", 'fundingAwardId', v_award."id", 'fundingProductId', v_award."product_id", 'funderId', v_award."funder_id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'status', v_award."status", 'periodStart', v_start, 'awarded', v_award."units", 'used', v_used), 'funding-awards/' || v_award."id"::text, (v_award."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.exceeded',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_award."id"::text,
    summary => 'Funding award exceeded',
    tenant => (v_award."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_award."tenant_id", 'fundingAwardId', v_award."id", 'fundingProductId', v_award."product_id", 'funderId', v_award."funder_id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'status', v_award."status", 'periodStart', v_start, 'awarded', v_award."units", 'used', v_used)
  );
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'funding_award.exceeded',
      'tenant', v_award."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', v_award."subject_type",
      'subject_id', v_award."subject_id"::text,
      'summary', 'A funding award went over its units',
      'permission', 'funding.manage',
      'watchers', false,
      'key', 'funding-exceeded:' || v_award."id"::text || ':' || v_start::text,
      'data', jsonb_build_object('awardId', v_award."id", 'periodStart', v_start, 'awarded', v_award."units", 'used', v_used)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_subject_export (
  subject_type text,
  subject_id   text,
  format       text DEFAULT 'ndjson'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."data_exports";
  v_tenant uuid;
  v_record jsonb;
  v_name text;
  v_reveal text;
  v_reveal_schema text;
  v_proc text;
  v_arg text;
  v_sealed text[];
  v_plain jsonb;
  v_rows jsonb;
  v_fields jsonb;
  v_parts jsonb := '{}'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_subject_export.format is null or request_subject_export.format not in ('ndjson', 'csv') then
    raise exception 'format must be ndjson or csv' using errcode = '22023', hint = 'DATA_EXPORT_FORMAT';
  end if;
  case request_subject_export.subject_type
    when 'message' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."messages" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.messages';
      v_reveal := 'messages_reveal';
      v_reveal_schema := 'better_supabase';
    when 'conversation' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."conversations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.conversations';
      v_reveal := 'conversations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'channel' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."channels" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.channels';
      v_reveal := 'channels_reveal';
      v_reveal_schema := 'better_supabase';
    when 'company' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."companies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.companies';
      v_reveal := 'companies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'person' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."people" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.people';
      v_reveal := 'people_reveal';
      v_reveal_schema := 'better_supabase';
    when 'deal' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."deals" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.deals';
      v_reveal := 'deals_reveal';
      v_reveal_schema := 'better_supabase';
    when 'course' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."courses" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.courses';
      v_reveal := 'courses_reveal';
      v_reveal_schema := 'better_supabase';
    when 'post' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."posts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.posts';
      v_reveal := 'posts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'activity' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."activities" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.activities';
      v_reveal := 'activities_reveal';
      v_reveal_schema := 'better_supabase';
    when 'quote' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."quotes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.quotes';
      v_reveal := 'quotes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_item' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_items" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_items';
      v_reveal := 'work_items_reveal';
      v_reveal_schema := 'better_supabase';
    when 'employee' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."employees" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.employees';
      v_reveal := 'employees_reveal';
      v_reveal_schema := 'better_supabase';
    when 'invoice' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."invoices" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.invoices';
      v_reveal := 'invoices_reveal';
      v_reveal_schema := 'better_supabase';
    when 'ledger_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."ledger_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.ledger_accounts';
      v_reveal := 'ledger_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."products" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.products';
      v_reveal := 'products_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product_variant' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."product_variants" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.product_variants';
      v_reveal := 'product_variants_reveal';
      v_reveal_schema := 'better_supabase';
    when 'order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.orders';
      v_reveal := 'orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'calendar_event' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."calendar_events" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.calendar_events';
      v_reveal := 'calendar_events_reveal';
      v_reveal_schema := 'better_supabase';
    when 'booking' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bookings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bookings';
      v_reveal := 'bookings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."assets" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.assets';
      v_reveal := 'assets_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset_location' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."asset_locations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.asset_locations';
      v_reveal := 'asset_locations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lease' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."leases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.leases';
      v_reveal := 'leases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_report' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_reports" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_reports';
      v_reveal := 'expense_reports_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_line' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_lines" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_lines';
      v_reveal := 'expense_lines_reveal';
      v_reveal_schema := 'better_supabase';
    when 'donation_fund' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."donation_funds" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.donation_funds';
      v_reveal := 'donation_funds_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_orders';
      v_reveal := 'work_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'shipment' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."shipments" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.shipments';
      v_reveal := 'shipments_reveal';
      v_reveal_schema := 'better_supabase';
    when 'contract' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."contracts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.contracts';
      v_reveal := 'contracts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'control' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."controls" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.controls';
      v_reveal := 'controls_reveal';
      v_reveal_schema := 'better_supabase';
    when 'compliance_policy' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."compliance_policies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.compliance_policies';
      v_reveal := 'compliance_policies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'qualification_type' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."qualification_types" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.qualification_types';
      v_reveal := 'qualification_types_reveal';
      v_reveal_schema := 'better_supabase';
    when 'risk' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."risks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.risks';
      v_reveal := 'risks_reveal';
      v_reveal_schema := 'better_supabase';
    when 'case' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."cases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.cases';
      v_reveal := 'cases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspections" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspections';
      v_reveal := 'inspections_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_program' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_programs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_programs';
      v_reveal := 'inspection_programs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_finding' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_findings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_findings';
      v_reveal := 'inspection_findings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'form' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."forms" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.forms';
      v_reveal := 'forms_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meetings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meetings';
      v_reveal := 'meetings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting_decision' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meeting_decisions" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meeting_decisions';
      v_reveal := 'meeting_decisions_reveal';
      v_reveal_schema := 'better_supabase';
    when 'production_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."production_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.production_orders';
      v_reveal := 'production_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_center' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_centers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_centers';
      v_reveal := 'work_centers_reveal';
      v_reveal_schema := 'better_supabase';
    when 'bank_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bank_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bank_accounts';
      v_reveal := 'bank_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'care_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."care_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.care_plans';
      v_reveal := 'care_plans_reveal';
      v_reveal_schema := 'better_supabase';
    when 'incident' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."incidents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.incidents';
      v_reveal := 'incidents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'content_entry' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."content_entries" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.content_entries';
      v_reveal := 'content_entries_reveal';
      v_reveal_schema := 'better_supabase';
    when 'document' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."documents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.documents';
      v_reveal := 'documents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'customer' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."customers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.customers';
      v_reveal := 'customers_reveal';
      v_reveal_schema := 'public';
    when 'drive_node' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.drive_nodes';
      v_reveal := 'drive_nodes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'application' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."applications" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.applications';
      v_reveal := 'applications_reveal';
      v_reveal_schema := 'better_supabase';
    when 'change_request' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."change_requests" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.change_requests';
      v_reveal := 'change_requests_reveal';
      v_reveal_schema := 'public';
    when 'project' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."projects" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.projects';
      v_reveal := 'projects_reveal';
      v_reveal_schema := 'public';
    when 'task' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."tasks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.tasks';
      v_reveal := 'tasks_reveal';
      v_reveal_schema := 'public';
    else
      raise exception 'subject_type is not a record type in config.subjects' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end case;
  if v_record is null or not ((v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'data_lifecycle.export'), false))) then
    raise exception 'You may not export this record' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x
  where x."subject" = 'record' and x."subject_type" = request_subject_export.subject_type
    and x."subject_id" = request_subject_export.subject_id and x."requested_by" = auth.uid()
    and x."status" in ('pending', 'running');
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  -- Only the owner's reveal function, so one another role created never runs
  -- with this function's rights.
  select pg_catalog.format('%I.%I', n.nspname, p.proname), pg_catalog.format_type(p.proargtypes[0], null),
    array(select a.name from unnest(p.proargnames, p.proargmodes::text[]) with ordinality a(name, mode, n)
      where a.mode = 't' order by a.n offset 1)
  into v_proc, v_arg, v_sealed
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = v_reveal_schema and p.proname = v_reveal and p.pronargs = 1
    and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
  limit 1;
  -- The stored ciphertext never leaves: a caller the reveal returns no row
  -- for gets the record without its encrypted columns.
  if v_proc is not null then
    execute format('select to_jsonb(r.*) from %s(array[$1]::%s) r', v_proc, v_arg) into v_plain
    using request_subject_export.subject_id;
    v_record := (v_record - coalesce(v_sealed, '{}'::text[])) || coalesce(v_plain, '{}'::jsonb);
  end if;
  v_parts := jsonb_build_object(v_name, jsonb_build_array(v_record));
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_subscriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_subscriptions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."guest_grants" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.guest_grants', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."attachments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.attachments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."enrollments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.enrollments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_runs" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_runs', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_start_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_start_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."knowledge_documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.knowledge_documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."memories" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.memories', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."taggings" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.taggings', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_stages" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_stages', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_lifecycles" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_lifecycles', v_rows);
  end if;
  if v_tenant is not null then
    v_fields := coalesce("better_supabase"."read_field_values"(v_tenant, request_subject_export.subject_type, request_subject_export.subject_id), '[]'::jsonb);
    select coalesce(jsonb_agg(((to_jsonb(t.*)) || jsonb_build_object('value_text', f.value ->> 'text')) order by t.ctid), '[]'::jsonb) into v_rows
    from "better_supabase"."field_values" t
    join jsonb_array_elements(v_fields) f on f.value ->> 'id' = t."id"::text
    where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
    if jsonb_array_length(v_rows) > 0 then
      v_parts := v_parts || jsonb_build_object('better_supabase.field_values', v_rows);
    end if;
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*) - array['token_hash', 'password_hash']::text[]) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."share_links" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.share_links', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."recurrence_rules" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.recurrence_rules', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reminders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reminders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."import_records" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.import_records', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_members" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_members', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."calendar_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.calendar_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."versions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.versions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."trash_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.trash_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reactions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reactions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reaction_scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reaction_scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."approval_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.approval_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."access_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.access_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."form_submissions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.form_submissions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."signature_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.signature_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."template_applications" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.template_applications', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."pipeline_stage_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.pipeline_stage_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."engagement_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.engagement_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."sla_clocks" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.sla_clocks', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."moderation_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.moderation_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."automation_evaluations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.automation_evaluations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."passes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.passes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_rates" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_rates', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."work_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.work_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."shipments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.shipments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."conversations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.conversations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."message_record_mentions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.message_record_mentions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."channels" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.channels', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."timeline_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.timeline_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."mail_thread_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.mail_thread_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."field_changes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.field_changes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgements" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgements', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_notices" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_notices', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."observations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.observations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."medication_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.medication_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_plans" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_plans', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."funding_awards" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.funding_awards', v_rows);
  end if;
  insert into "better_supabase"."data_exports" ("subject", "organization_id", "subject_type", "subject_id", "format")
  values ('record', v_tenant, request_subject_export.subject_type, request_subject_export.subject_id, request_subject_export.format)
  returning * into v_row;
  insert into "better_supabase"."data_export_contents" ("export_id", "parts") values (v_row."id", v_parts);
  perform "better_supabase".emit_event('data_export.requested', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.requested',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_funding_award (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  attrs        jsonb,
  award_id     uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not (case save_funding_award.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (save_funding_award.subject_id)::uuid and s."organization_id"::text = save_funding_award.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (save_funding_award.subject_id)::uuid and s."tenant_id"::text = save_funding_award.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (save_funding_award.subject_id)::uuid and s."organization_id"::text = save_funding_award.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (save_funding_award.subject_id)::uuid and s."organization_id"::text = save_funding_award.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (save_funding_award.subject_id)::uuid and s."organization_id"::text = save_funding_award.tenant::text)
      else false
    end and "better_supabase"."can_subject"(save_funding_award.subject_type, save_funding_award.subject_id, 'read')) then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "better_supabase"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."tenant_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "better_supabase"."funding_products" x where x."id" = v_product and x."tenant_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "better_supabase"."funding_awards" ("tenant_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('funding_award.created', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'funding-awards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.created',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_row."id"::text,
    summary => 'Funding awarded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  else
    update "better_supabase"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('funding_award.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'funding-awards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.updated',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_row."id"::text,
    summary => 'Funding award changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_funding_product (
  tenant      uuid,
  code        text,
  title       text,
  unit        text,
  rate        bigint,
  currency    text,
  valid_from  date   DEFAULT NULL::date,
  valid_until date   DEFAULT NULL::date,
  product_id  uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."funding_products" x
    where x."tenant_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "better_supabase"."funding_products" ("tenant_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "better_supabase"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."tenant_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."funding_claim_lines"
  ADD CONSTRAINT "funding_claim_lines_tenant_id_award_id_fkey" FOREIGN KEY (tenant_id, award_id) REFERENCES better_supabase.funding_awards(tenant_id, id);

ALTER TABLE "better_supabase"."funding_claim_lines"
  ADD CONSTRAINT "funding_claim_lines_tenant_id_claim_id_fkey" FOREIGN KEY (tenant_id, claim_id) REFERENCES better_supabase.funding_claims(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."funding_deliveries"
  ADD CONSTRAINT "funding_deliveries_claim_line_id_fkey" FOREIGN KEY (claim_line_id) REFERENCES better_supabase.funding_claim_lines(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."funding_deliveries"
  ADD CONSTRAINT "funding_deliveries_tenant_id_award_id_fkey" FOREIGN KEY (tenant_id, award_id) REFERENCES better_supabase.funding_awards(tenant_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."funding_awards"
  ADD CONSTRAINT "funding_awards_tenant_id_product_id_fkey" FOREIGN KEY (tenant_id, product_id) REFERENCES better_supabase.funding_products(tenant_id, id);

ALTER TABLE "better_supabase"."funding_claim_lines"
  ADD CONSTRAINT "funding_claim_lines_tenant_id_product_id_fkey" FOREIGN KEY (tenant_id, product_id) REFERENCES better_supabase.funding_products(tenant_id, id);

CREATE INDEX funding_awards_funder_idx ON better_supabase.funding_awards USING btree (tenant_id, funder_id, status);

CREATE INDEX funding_awards_product_idx ON better_supabase.funding_awards USING btree (tenant_id, product_id);

CREATE INDEX funding_awards_subject_idx ON better_supabase.funding_awards USING btree (subject_type, subject_id);

CREATE INDEX funding_claim_lines_award_idx ON better_supabase.funding_claim_lines USING btree (tenant_id, award_id);

CREATE INDEX funding_claim_lines_claim_idx ON better_supabase.funding_claim_lines USING btree (tenant_id, claim_id);

CREATE INDEX funding_claim_lines_product_idx ON better_supabase.funding_claim_lines USING btree (tenant_id, product_id);

CREATE INDEX funding_claims_funder_idx ON better_supabase.funding_claims USING btree (tenant_id, funder_id, status);

CREATE UNIQUE INDEX funding_claims_number_idx ON better_supabase.funding_claims USING btree (tenant_id, number);

CREATE INDEX funding_deliveries_award_idx ON better_supabase.funding_deliveries USING btree (tenant_id, award_id, delivered_on);

CREATE INDEX funding_deliveries_claim_line_idx ON better_supabase.funding_deliveries USING btree (claim_line_id);

CREATE UNIQUE INDEX funding_deliveries_source_idx ON better_supabase.funding_deliveries USING btree (tenant_id, source_type, source_id)
  WHERE (source_id IS NOT NULL);

CREATE INDEX funding_deliveries_status_idx ON better_supabase.funding_deliveries USING btree (tenant_id, status, delivered_on);

CREATE UNIQUE INDEX funding_products_code_idx ON better_supabase.funding_products USING btree (tenant_id, code);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."funding_awards"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."funding_awards"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_awards"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."funding_awards"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "funding_awards_read" ON "better_supabase"."funding_awards"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id,
    'read'::text), false)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."funding_claim_lines"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."funding_claim_lines"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_claim_lines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."funding_claim_lines"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "funding_claim_lines_read" ON "better_supabase"."funding_claim_lines"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."funding_claims"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."funding_claims"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_claims"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."funding_claims"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "funding_claims_read" ON "better_supabase"."funding_claims"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."funding_deliveries"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."funding_deliveries"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_deliveries"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.funding_awards x
  WHERE ((x.tenant_id = x.tenant_id) AND (x.id = funding_deliveries.award_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text), false)))))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."funding_deliveries"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "funding_deliveries_read" ON "better_supabase"."funding_deliveries"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.funding_awards x
  WHERE ((x.tenant_id = x.tenant_id) AND (x.id = funding_deliveries.award_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text), false))))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."funding_products"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."funding_products"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_products"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."funding_products"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "funding_products_read" ON "better_supabase"."funding_products"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)));

COMMENT ON FUNCTION "better_supabase"."funding_subject_merge"(text, text, text) IS 'better-supabase:subject-merge';

REVOKE ALL ON FUNCTION "api"."approve_funding_deliveries"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."approve_funding_deliveries"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."build_funding_claim"(uuid, uuid, date, date, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."build_funding_claim"(uuid, uuid, date, date, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."end_funding_award"(uuid, date, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."end_funding_award"(uuid, date, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."funding_award_usage"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."funding_award_usage"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."invoice_funding_claim"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invoice_funding_claim"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_funding_awards"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_funding_awards"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_funding_claims"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_funding_claims"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_funding_deliveries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_funding_deliveries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_funding_products"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_funding_products"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_funding_claim_sent"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_funding_claim_sent"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_funding_claim_response"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_funding_claim_response"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."register_funding_deliveries_from_time"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."register_funding_deliveries_from_time"(uuid, date, date) TO "service_role";

REVOKE ALL ON FUNCTION "api"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_funding_award"(uuid, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_funding_award"(uuid, text, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approve_funding_deliveries"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approve_funding_deliveries"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."end_funding_award"(uuid, date, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."end_funding_award"(uuid, date, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."funding_award_usage"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."funding_award_usage"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."funding_subject_merge"(text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."get_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invoice_funding_claim"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invoice_funding_claim"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_funding_awards"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_funding_awards"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_funding_claims"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_funding_claims"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_funding_deliveries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_funding_deliveries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_funding_products"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_funding_products"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_funding_claim_sent"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_funding_claim_sent"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."register_funding_deliveries_from_time"(uuid, date, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."register_funding_deliveries_from_time"(uuid, date, date) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."funding_awards" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."funding_awards" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."funding_claim_lines" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."funding_claim_lines" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."funding_claims" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."funding_claims" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."funding_deliveries" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."funding_deliveries" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."funding_products" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."funding_products" TO "service_role";
