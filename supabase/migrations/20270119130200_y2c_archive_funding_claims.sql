SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_funding_claim"(uuid);

DROP FUNCTION "api"."list_funding_claims"(uuid, text, uuid);

DROP FUNCTION "better_supabase"."delete_funding_claim"(uuid);

DROP FUNCTION "better_supabase"."list_funding_claims"(uuid, text, uuid);

ALTER TABLE "better_supabase"."funding_claims"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_funding_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_funding_claims (
  tenant           uuid,
  status           text    DEFAULT NULL::text,
  funder_id        uuid    DEFAULT NULL::uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_funding_claims"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.purge_funding_claim (
  claim_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_funding_claim"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_funding_claim"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_claims" x where x."id" = archive_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'funderId', v_row."funder_id", 'number', v_row."number", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'format', v_row."format", 'status', v_row."status", 'externalRef', v_row."external_ref", 'sentAt', v_row."sent_at", 'payloadSha256', v_row."payload_sha256", 'response', v_row."response", 'total', v_row."total"::text, 'currency', v_row."currency", 'invoiceId', v_row."invoice_id", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('lines', coalesce((
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
    where z."tenant_id" = v_row."tenant_id" and z."claim_id" = v_row."id"
  ), '[]'::jsonb));
  end if;
  if v_row."status" not in ('accepted', 'rejected', 'partially_accepted') then
    raise exception 'only a claim the funder answered is archived; purge a draft' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('funding_claim.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingClaimId', v_row."id", 'funderId', v_row."funder_id", 'number', v_row."number", 'status', v_row."status", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'total', v_row."total"::text, 'currency', v_row."currency"), 'funding-claims/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.archived',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_row."id"::text,
    summary => 'Funding claim archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingClaimId', v_row."id", 'funderId', v_row."funder_id", 'number', v_row."number", 'status', v_row."status", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'total', v_row."total"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'funderId', v_row."funder_id", 'number', v_row."number", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'format', v_row."format", 'status', v_row."status", 'externalRef', v_row."external_ref", 'sentAt', v_row."sent_at", 'payloadSha256', v_row."payload_sha256", 'response', v_row."response", 'total', v_row."total"::text, 'currency', v_row."currency", 'invoiceId', v_row."invoice_id", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('lines', coalesce((
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
    where z."tenant_id" = v_row."tenant_id" and z."claim_id" = v_row."id"
  ), '[]'::jsonb));
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
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'archivedAt', v_claim."archived_at", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
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
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'archivedAt', v_claim."archived_at", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
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
  if v_claim."archived_at" is not null then
    raise exception 'restore the archived claim before invoicing it' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
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
  return jsonb_build_object('claim', jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'archivedAt', v_claim."archived_at", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at"), 'invoice', v_invoice);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_funding_claims (
  tenant           uuid,
  status           text    DEFAULT NULL::text,
  funder_id        uuid    DEFAULT NULL::uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
    and (list_funding_claims.include_archived or x."archived_at" is null)
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
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'archivedAt', v_claim."archived_at", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_funding_claim (
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
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = purge_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to purge funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  perform "better_supabase".emit_event('funding_claim.purged', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.purged',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Draft funding claim purged',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  return true;
end;
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
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'archivedAt', v_claim."archived_at", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
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

CREATE OR REPLACE FUNCTION better_supabase.restore_funding_claim (
  claim_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_claims" x where x."id" = restore_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'funderId', v_row."funder_id", 'number', v_row."number", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'format', v_row."format", 'status', v_row."status", 'externalRef', v_row."external_ref", 'sentAt', v_row."sent_at", 'payloadSha256', v_row."payload_sha256", 'response', v_row."response", 'total', v_row."total"::text, 'currency', v_row."currency", 'invoiceId', v_row."invoice_id", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('lines', coalesce((
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
    where z."tenant_id" = v_row."tenant_id" and z."claim_id" = v_row."id"
  ), '[]'::jsonb));
  end if;
  update "better_supabase"."funding_claims" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('funding_claim.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingClaimId', v_row."id", 'funderId', v_row."funder_id", 'number', v_row."number", 'status', v_row."status", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'total', v_row."total"::text, 'currency', v_row."currency"), 'funding-claims/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.restored',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_row."id"::text,
    summary => 'Funding claim restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingClaimId', v_row."id", 'funderId', v_row."funder_id", 'number', v_row."number", 'status', v_row."status", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'total', v_row."total"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'funderId', v_row."funder_id", 'number', v_row."number", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'format', v_row."format", 'status', v_row."status", 'externalRef', v_row."external_ref", 'sentAt', v_row."sent_at", 'payloadSha256', v_row."payload_sha256", 'response', v_row."response", 'total', v_row."total"::text, 'currency', v_row."currency", 'invoiceId', v_row."invoice_id", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('lines', coalesce((
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
    where z."tenant_id" = v_row."tenant_id" and z."claim_id" = v_row."id"
  ), '[]'::jsonb));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_funding_claims"(uuid, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_funding_claims"(uuid, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_funding_claims"(uuid, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_funding_claims"(uuid, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_funding_claim"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_funding_claim"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_funding_claim"(uuid) TO "authenticated", "service_role";
