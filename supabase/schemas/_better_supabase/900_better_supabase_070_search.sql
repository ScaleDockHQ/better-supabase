-- better-supabase module: search
-- @bsb-block search@2 managed
-- @bsb-hash sha256:f6a7a9370d9814a7b3d978bb3daf43b76ebf51d5ae9f8156f9ca21f500cbefbf
-- A search_documents index kept up by triggers from each config.recordTypes search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create table "better_supabase"."search_documents" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "title" text,
  "title_search" text not null default '',
  "body" text,
  "url" text,
  "tsv" tsvector not null,
  "content_hash" text not null,
  "updated_at" timestamptz not null default now(),
  primary key ("subject_type", "subject_id")
);
alter table "better_supabase"."search_documents" enable row level security;
revoke all on "better_supabase"."search_documents" from public, anon, authenticated;
grant select on "better_supabase"."search_documents" to authenticated;
grant all on "better_supabase"."search_documents" to service_role;
create index search_documents_tsv_idx on "better_supabase"."search_documents" using gin ("tsv");
create index search_documents_title_trgm_idx on "better_supabase"."search_documents" using gin ("title_search" extensions.gin_trgm_ops);
create index search_documents_tenant_idx on "better_supabase"."search_documents" ("tenant_id", "subject_type");

create policy bsb_search_documents_read on "better_supabase"."search_documents"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')));

-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function "better_supabase"."search_normalize"(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
revoke execute on function "better_supabase"."search_normalize"(text) from public, anon;
grant execute on function "better_supabase"."search_normalize"(text) to authenticated, service_role;

-- Reads one registered subject row (config.recordTypes.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function "better_supabase"."search_refresh"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'conversation' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."conversations" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'quote' then
      select s."tenant_id", s."title"::text, null, '/crm/quotes/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."quotes" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'ledger_account' then
      select s."tenant_id", s."name"::text, null, '/finance'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."ledger_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'invoice' then
      select s."tenant_id", s."title"::text, null, '/finance/payables'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."invoices" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'rfq' then
      select s."tenant_id", s."title"::text, null, '/rfqs'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."rfqs" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'till' then
      select s."tenant_id", s."name"::text, null, '/tills'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."tills" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'order' then
      select s."tenant_id", s."number"::text, null, '/shop/orders/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'booking' then
      select s."tenant_id", s."customer_name"::text, null, '/calendar'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."bookings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."assets" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset_location' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."asset_locations" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lease' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."leases" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_report' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."expense_reports" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_line' then
      select s."tenant_id", s."description"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."expense_lines" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'donation_fund' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."donation_funds" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'warranty_claim' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."manufacturer"::text, s."decision"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."warranty_claims" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_order' then
      select s."tenant_id", s."title"::text, null, '/field/dispatch'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."work_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'shipment' then
      select s."tenant_id", s."reference"::text, null, '/field/shipments'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."shipments" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'contract' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."contracts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'control' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."controls" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'compliance_policy' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."compliance_policies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'qualification_type' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."qualification_types" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'inspection_program' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."inspection_programs" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection_finding' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."inspection_findings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'form' then
      select s."tenant_id", s."title"::text, null, '/forms/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."forms" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting_decision' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."meeting_decisions" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'dam_usage_right' then
      select s."tenant_id", s."licensee"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."dam_usage_rights" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'tax_code' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."tax_codes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_center' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."work_centers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'bank_account' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."bank_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'care_plan' then
      select s."tenant_id", s."title"::text, null, '/care-plans'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."care_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'incident' then
      select s."tenant_id", s."title"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."incidents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."tracking_id"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."advisories" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory_product' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."advisory_products" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'vulnerability' then
      select s."tenant_id", s."vuln_id"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."vulnerabilities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'document' then
      select s."tenant_id", s."name"::text, null, '/documents/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."documents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'task' then
      select s."organization_id", s."title"::text, null, '/projects/' || s."project_id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."tasks" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_refresh"(text, text) to service_role;

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function "better_supabase"."search_remove"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."search_documents"
  where "subject_type" = search_remove.subject_type and "subject_id" = search_remove.subject_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_remove"(text, text) to service_role;

-- Indexes every row of one registered type, or of all of them.
create or replace function "better_supabase"."search_reindex"(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
  if search_reindex.subject_type is null or search_reindex.subject_type = 'message' then
    for v_id in select s."id"::text from "better_supabase"."messages" s loop
      if "better_supabase"."search_refresh"('message', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'conversation' then
    for v_id in select s."id"::text from "better_supabase"."conversations" s loop
      if "better_supabase"."search_refresh"('conversation', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'channel' then
    for v_id in select s."id"::text from "better_supabase"."channels" s loop
      if "better_supabase"."search_refresh"('channel', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'company' then
    for v_id in select s."id"::text from "better_supabase"."companies" s loop
      if "better_supabase"."search_refresh"('company', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'person' then
    for v_id in select s."id"::text from "better_supabase"."people" s loop
      if "better_supabase"."search_refresh"('person', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'deal' then
    for v_id in select s."id"::text from "better_supabase"."deals" s loop
      if "better_supabase"."search_refresh"('deal', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'course' then
    for v_id in select s."id"::text from "better_supabase"."courses" s loop
      if "better_supabase"."search_refresh"('course', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'post' then
    for v_id in select s."id"::text from "better_supabase"."posts" s loop
      if "better_supabase"."search_refresh"('post', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'activity' then
    for v_id in select s."id"::text from "better_supabase"."activities" s loop
      if "better_supabase"."search_refresh"('activity', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'quote' then
    for v_id in select s."id"::text from "better_supabase"."quotes" s loop
      if "better_supabase"."search_refresh"('quote', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'work_item' then
    for v_id in select s."id"::text from "better_supabase"."work_items" s loop
      if "better_supabase"."search_refresh"('work_item', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'employee' then
    for v_id in select s."id"::text from "better_supabase"."employees" s loop
      if "better_supabase"."search_refresh"('employee', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'ledger_account' then
    for v_id in select s."id"::text from "better_supabase"."ledger_accounts" s loop
      if "better_supabase"."search_refresh"('ledger_account', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'invoice' then
    for v_id in select s."id"::text from "better_supabase"."invoices" s loop
      if "better_supabase"."search_refresh"('invoice', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'product' then
    for v_id in select s."id"::text from "better_supabase"."products" s loop
      if "better_supabase"."search_refresh"('product', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'product_variant' then
    for v_id in select s."id"::text from "better_supabase"."product_variants" s loop
      if "better_supabase"."search_refresh"('product_variant', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'rfq' then
    for v_id in select s."id"::text from "better_supabase"."rfqs" s loop
      if "better_supabase"."search_refresh"('rfq', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'till' then
    for v_id in select s."id"::text from "better_supabase"."tills" s loop
      if "better_supabase"."search_refresh"('till', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'order' then
    for v_id in select s."id"::text from "better_supabase"."orders" s loop
      if "better_supabase"."search_refresh"('order', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'calendar_event' then
    for v_id in select s."id"::text from "better_supabase"."calendar_events" s loop
      if "better_supabase"."search_refresh"('calendar_event', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'booking' then
    for v_id in select s."id"::text from "better_supabase"."bookings" s loop
      if "better_supabase"."search_refresh"('booking', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'asset' then
    for v_id in select s."id"::text from "better_supabase"."assets" s loop
      if "better_supabase"."search_refresh"('asset', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'asset_location' then
    for v_id in select s."id"::text from "better_supabase"."asset_locations" s loop
      if "better_supabase"."search_refresh"('asset_location', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'lease' then
    for v_id in select s."id"::text from "better_supabase"."leases" s loop
      if "better_supabase"."search_refresh"('lease', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'expense_report' then
    for v_id in select s."id"::text from "better_supabase"."expense_reports" s loop
      if "better_supabase"."search_refresh"('expense_report', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'expense_line' then
    for v_id in select s."id"::text from "better_supabase"."expense_lines" s loop
      if "better_supabase"."search_refresh"('expense_line', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'donation_fund' then
    for v_id in select s."id"::text from "better_supabase"."donation_funds" s loop
      if "better_supabase"."search_refresh"('donation_fund', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'warranty_claim' then
    for v_id in select s."id"::text from "better_supabase"."warranty_claims" s loop
      if "better_supabase"."search_refresh"('warranty_claim', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'work_order' then
    for v_id in select s."id"::text from "better_supabase"."work_orders" s loop
      if "better_supabase"."search_refresh"('work_order', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'shipment' then
    for v_id in select s."id"::text from "better_supabase"."shipments" s loop
      if "better_supabase"."search_refresh"('shipment', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'contract' then
    for v_id in select s."id"::text from "better_supabase"."contracts" s loop
      if "better_supabase"."search_refresh"('contract', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'control' then
    for v_id in select s."id"::text from "better_supabase"."controls" s loop
      if "better_supabase"."search_refresh"('control', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'compliance_policy' then
    for v_id in select s."id"::text from "better_supabase"."compliance_policies" s loop
      if "better_supabase"."search_refresh"('compliance_policy', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'qualification_type' then
    for v_id in select s."id"::text from "better_supabase"."qualification_types" s loop
      if "better_supabase"."search_refresh"('qualification_type', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'risk' then
    for v_id in select s."id"::text from "better_supabase"."risks" s loop
      if "better_supabase"."search_refresh"('risk', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'case' then
    for v_id in select s."id"::text from "better_supabase"."cases" s loop
      if "better_supabase"."search_refresh"('case', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'inspection' then
    for v_id in select s."id"::text from "better_supabase"."inspections" s loop
      if "better_supabase"."search_refresh"('inspection', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'inspection_program' then
    for v_id in select s."id"::text from "better_supabase"."inspection_programs" s loop
      if "better_supabase"."search_refresh"('inspection_program', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'inspection_finding' then
    for v_id in select s."id"::text from "better_supabase"."inspection_findings" s loop
      if "better_supabase"."search_refresh"('inspection_finding', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'form' then
    for v_id in select s."id"::text from "better_supabase"."forms" s loop
      if "better_supabase"."search_refresh"('form', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'meeting' then
    for v_id in select s."id"::text from "better_supabase"."meetings" s loop
      if "better_supabase"."search_refresh"('meeting', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'meeting_decision' then
    for v_id in select s."id"::text from "better_supabase"."meeting_decisions" s loop
      if "better_supabase"."search_refresh"('meeting_decision', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'maintenance_plan' then
    for v_id in select s."id"::text from "better_supabase"."maintenance_plans" s loop
      if "better_supabase"."search_refresh"('maintenance_plan', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'dam_usage_right' then
    for v_id in select s."id"::text from "better_supabase"."dam_usage_rights" s loop
      if "better_supabase"."search_refresh"('dam_usage_right', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'lims_sample' then
    for v_id in select s."id"::text from "better_supabase"."lims_samples" s loop
      if "better_supabase"."search_refresh"('lims_sample', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'tax_code' then
    for v_id in select s."id"::text from "better_supabase"."tax_codes" s loop
      if "better_supabase"."search_refresh"('tax_code', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'production_order' then
    for v_id in select s."id"::text from "better_supabase"."production_orders" s loop
      if "better_supabase"."search_refresh"('production_order', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'work_center' then
    for v_id in select s."id"::text from "better_supabase"."work_centers" s loop
      if "better_supabase"."search_refresh"('work_center', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'bank_account' then
    for v_id in select s."id"::text from "better_supabase"."bank_accounts" s loop
      if "better_supabase"."search_refresh"('bank_account', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'care_plan' then
    for v_id in select s."id"::text from "better_supabase"."care_plans" s loop
      if "better_supabase"."search_refresh"('care_plan', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'incident' then
    for v_id in select s."id"::text from "better_supabase"."incidents" s loop
      if "better_supabase"."search_refresh"('incident', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'advisory' then
    for v_id in select s."id"::text from "better_supabase"."advisories" s loop
      if "better_supabase"."search_refresh"('advisory', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'advisory_product' then
    for v_id in select s."id"::text from "better_supabase"."advisory_products" s loop
      if "better_supabase"."search_refresh"('advisory_product', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'vulnerability' then
    for v_id in select s."id"::text from "better_supabase"."vulnerabilities" s loop
      if "better_supabase"."search_refresh"('vulnerability', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'content_entry' then
    for v_id in select s."id"::text from "better_supabase"."content_entries" s loop
      if "better_supabase"."search_refresh"('content_entry', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'document' then
    for v_id in select s."id"::text from "better_supabase"."documents" s loop
      if "better_supabase"."search_refresh"('document', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'customer' then
    for v_id in select s."id"::text from "public"."customers" s loop
      if "better_supabase"."search_refresh"('customer', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'drive_node' then
    for v_id in select s."id"::text from "better_supabase"."drive_nodes" s loop
      if "better_supabase"."search_refresh"('drive_node', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'project' then
    for v_id in select s."id"::text from "public"."projects" s loop
      if "better_supabase"."search_refresh"('project', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  if search_reindex.subject_type is null or search_reindex.subject_type = 'task' then
    for v_id in select s."id"::text from "public"."tasks" s loop
      if "better_supabase"."search_refresh"('task', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."search_reindex"(text) to service_role;

-- Runs as its caller (the definer trigger functions and import_upsert_batch
-- call it), so it adds no definer function. Indexes a record now, or, while an import batch runs with
-- better_supabase.search_deferred on (import_upsert_batch sets it), notes the
-- key once, one line per key, in one of 256 transaction-local settings
-- (better_supabase.search_dirty_<hash>) so search_refresh_dirty indexes it
-- once at the end of the batch. A setting holds a 256th of the keys: one text
-- setting rewrote the whole list on every note.
create or replace function "better_supabase"."search_enqueue"(subject_type text, subject_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := search_enqueue.subject_type || E'\x1f' || search_enqueue.subject_id;
  v_name text := 'better_supabase.search_dirty_' || (hashtext(v_key) & 255)::text;
  v_dirty text;
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' then
    v_dirty := coalesce(current_setting(v_name, true), '');
    if position(E'\n' || v_key || E'\n' in E'\n' || v_dirty) = 0 then
      perform set_config(v_name, v_dirty || v_key || E'\n', true);
    end if;
  else
    perform "better_supabase"."search_refresh"(search_enqueue.subject_type, search_enqueue.subject_id);
  end if;
end;
$$;
revoke execute on function "better_supabase"."search_enqueue"(text, text) from public, anon, authenticated;

-- Indexes every record noted by search_enqueue in this transaction, once each.
-- Returns how many it indexed.
create or replace function "better_supabase"."search_refresh_dirty"()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_bucket integer;
  v_name text;
  v_dirty text;
  v_line text;
begin
  for v_bucket in 0..255 loop
    v_name := 'better_supabase.search_dirty_' || v_bucket::text;
    v_dirty := coalesce(current_setting(v_name, true), '');
    if v_dirty <> '' then
      perform set_config(v_name, '', true);
      for v_line in select l from string_to_table(v_dirty, E'\n') l where l <> '' loop
        if "better_supabase"."search_refresh"(split_part(v_line, E'\x1f', 1), split_part(v_line, E'\x1f', 2)) then
          v_count := v_count + 1;
        end if;
      end loop;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."search_refresh_dirty"() from public, anon, authenticated;
grant execute on function "better_supabase"."search_refresh_dirty"() to service_role;

create or replace function "better_supabase"."search_index_row"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform "better_supabase"."search_enqueue"(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform "better_supabase"."search_enqueue"(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."search_index_row"() from public, anon, authenticated;
create trigger "bsb_search_product_index"
  after insert or delete or update of "id", "tenant_id", "title", "description", "slug" on "better_supabase"."products"
  for each row execute function "better_supabase"."search_index_row"('product', 'id');
create trigger "bsb_search_product_variant_index"
  after insert or delete or update of "id", "tenant_id", "sku", "title", "barcode" on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."search_index_row"('product_variant', 'id');
create trigger "bsb_search_customer_index"
  after insert or delete or update of "id", "organization_id", "name", "archived_at" on "public"."customers"
  for each row execute function "better_supabase"."search_index_row"('customer', 'id');
create trigger "bsb_search_drive_node_index"
  after insert or delete or update of "id", "tenant_id", "name", "archived_at" on "better_supabase"."drive_nodes"
  for each row execute function "better_supabase"."search_index_row"('drive_node', 'id');
create trigger "bsb_search_project_index"
  after insert or delete or update of "id", "organization_id", "name", "deleted_at" on "public"."projects"
  for each row execute function "better_supabase"."search_index_row"('project', 'id');
create trigger "bsb_search_task_index"
  after insert or delete or update of "id", "organization_id", "title", "project_id" on "public"."tasks"
  for each row execute function "better_supabase"."search_index_row"('task', 'id');
-- A change in better_supabase.drive_node_texts re-indexes the drive_node it points at.
create or replace function "better_supabase"."search_watch_drive_node_0"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text;
begin
  if tg_op in ('UPDATE', 'DELETE') and old."node_id" is not null then
    perform "better_supabase"."search_enqueue"('drive_node', old."node_id"::text);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new."node_id" is not null then
    perform "better_supabase"."search_enqueue"('drive_node', new."node_id"::text);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."search_watch_drive_node_0"() from public, anon, authenticated;
create trigger "bsb_search_drive_node_watch_0" after insert or delete on "better_supabase"."drive_node_texts"
  for each row execute function "better_supabase"."search_watch_drive_node_0"();
create trigger "bsb_search_drive_node_watch_0_u" after update of "node_id", "content" on "better_supabase"."drive_node_texts"
  for each row when (old."node_id" is distinct from new."node_id" or old."content" is distinct from new."content")
  execute function "better_supabase"."search_watch_drive_node_0"();

-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function "better_supabase"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
            + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "better_supabase"."search"(text, text[], uuid, integer) to authenticated, service_role;

-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function "better_supabase"."search_user_state"()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select s."subject_type", s."subject_id", s."starred_at", s."last_opened_at"
  from "better_supabase"."subject_user_state" s
  where s."user_id" = auth.uid()
$$;
revoke execute on function "better_supabase"."search_user_state"() from public, anon;
grant execute on function "better_supabase"."search_user_state"() to authenticated, service_role;

create or replace function "better_supabase"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.opened_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.opened_at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_recents"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.starred_at as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
      and "better_supabase"."can_subject"(s.subject_type, s.subject_id, 'read')
    order by s.starred_at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$$;
revoke execute on function "better_supabase"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "better_supabase"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "better_supabase"."search_touch"(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to keep recents' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  insert into "better_supabase"."subject_user_state" as st ("subject_type", "subject_id", "user_id", "last_opened_at") values (search_touch.subject_type, search_touch.subject_id, auth.uid(), now())
  on conflict ("subject_type", "subject_id", "user_id") do update set "last_opened_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_touch"(text, text) from public, anon;
grant execute on function "better_supabase"."search_touch"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to keep favorites' using errcode = '42501', hint = 'SEARCH_SIGNED_OUT';
  end if;
  insert into "better_supabase"."subject_user_state" as st ("subject_type", "subject_id", "user_id", "starred_at") values (search_star.subject_type, search_star.subject_id, auth.uid(), case when search_star.starred then now() end)
  on conflict ("subject_type", "subject_id", "user_id") do update set "starred_at" = case when search_star.starred then coalesce(st."starred_at", now()) end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."search_star"(text, text, boolean) from public, anon;
grant execute on function "better_supabase"."search_star"(text, text, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."search_documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('search.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."search_documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."search_documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."search_documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.search.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."search_refresh"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_refresh"($1, $2) $$;
revoke execute on function "api"."search_refresh"(text, text) from public, anon, authenticated;
grant execute on function "api"."search_refresh"(text, text) to service_role;

create or replace function "api"."search_remove"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_remove"($1, $2) $$;
revoke execute on function "api"."search_remove"(text, text) from public, anon, authenticated;
grant execute on function "api"."search_remove"(text, text) to service_role;

create or replace function "api"."search_reindex"(subject_type text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_reindex"($1) $$;
revoke execute on function "api"."search_reindex"(text) from public, anon, authenticated;
grant execute on function "api"."search_reindex"(text) to service_role;

create or replace function "api"."search"(q text, types text[] default null, tenant uuid default null, max_results integer default 20)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."search"($1, $2, $3, $4) $$;
revoke execute on function "api"."search"(text, text[], uuid, integer) from public, anon;
grant execute on function "api"."search"(text, text[], uuid, integer) to authenticated, service_role;

create or replace function "api"."search_recents"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."search_recents"($1, $2) $$;
revoke execute on function "api"."search_recents"(integer, text[]) from public, anon;
grant execute on function "api"."search_recents"(integer, text[]) to authenticated, service_role;

create or replace function "api"."search_favorites"(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."search_favorites"($1, $2) $$;
revoke execute on function "api"."search_favorites"(integer, text[]) from public, anon;
grant execute on function "api"."search_favorites"(integer, text[]) to authenticated, service_role;

create or replace function "api"."search_touch"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_touch"($1, $2) $$;
revoke execute on function "api"."search_touch"(text, text) from public, anon;
grant execute on function "api"."search_touch"(text, text) to authenticated, service_role;

create or replace function "api"."search_star"(subject_type text, subject_id text, starred boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."search_star"($1, $2, $3) $$;
revoke execute on function "api"."search_star"(text, text, boolean) from public, anon;
grant execute on function "api"."search_star"(text, text, boolean) to authenticated, service_role;
