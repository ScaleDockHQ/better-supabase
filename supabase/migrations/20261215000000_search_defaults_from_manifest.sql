-- Audit program, lane N: subjects without a search registration of their own
-- register their title column, so search_refresh and search_reindex read them
-- and each table keeps its search index current.

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

create trigger "bsb_search_asset_location_index"
  after insert or delete or update of "id", "tenant_id", "name" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."search_index_row"('asset_location', 'id');

create trigger "bsb_search_expense_line_index"
  after insert or delete or update of "id", "tenant_id", "description" on "better_supabase"."expense_lines"
  for each row execute function "better_supabase"."search_index_row"('expense_line', 'id');

create trigger "bsb_search_donation_fund_index"
  after insert or delete or update of "id", "tenant_id", "name" on "better_supabase"."donation_funds"
  for each row execute function "better_supabase"."search_index_row"('donation_fund', 'id');

create trigger "bsb_search_control_index"
  after insert or delete or update of "id", "tenant_id", "title" on "better_supabase"."controls"
  for each row execute function "better_supabase"."search_index_row"('control', 'id');

create trigger "bsb_search_compliance_policy_index"
  after insert or delete or update of "id", "tenant_id", "title" on "better_supabase"."compliance_policies"
  for each row execute function "better_supabase"."search_index_row"('compliance_policy', 'id');

create trigger "bsb_search_conversation_index"
  after insert or delete or update of "id", "tenant_id", "title", "archived_at" on "better_supabase"."conversations"
  for each row execute function "better_supabase"."search_index_row"('conversation', 'id');

create trigger "bsb_search_qualification_type_index"
  after insert or delete or update of "id", "tenant_id", "name" on "better_supabase"."qualification_types"
  for each row execute function "better_supabase"."search_index_row"('qualification_type', 'id');

create trigger "bsb_search_tax_code_index"
  after insert or delete or update of "id", "tenant_id", "name", "archived_at" on "better_supabase"."tax_codes"
  for each row execute function "better_supabase"."search_index_row"('tax_code', 'id');

create trigger "bsb_search_inspection_program_index"
  after insert or delete or update of "id", "tenant_id", "name", "archived_at" on "better_supabase"."inspection_programs"
  for each row execute function "better_supabase"."search_index_row"('inspection_program', 'id');

create trigger "bsb_search_inspection_finding_index"
  after insert or delete or update of "id", "tenant_id", "title" on "better_supabase"."inspection_findings"
  for each row execute function "better_supabase"."search_index_row"('inspection_finding', 'id');

create trigger "bsb_search_work_center_index"
  after insert or delete or update of "id", "tenant_id", "name", "archived_at" on "better_supabase"."work_centers"
  for each row execute function "better_supabase"."search_index_row"('work_center', 'id');

create trigger "bsb_search_bank_account_index"
  after insert or delete or update of "id", "tenant_id", "name", "archived_at" on "better_supabase"."bank_accounts"
  for each row execute function "better_supabase"."search_index_row"('bank_account', 'id');

create trigger "bsb_search_meeting_decision_index"
  after insert or delete or update of "id", "tenant_id", "title" on "better_supabase"."meeting_decisions"
  for each row execute function "better_supabase"."search_index_row"('meeting_decision', 'id');

create trigger "bsb_search_dam_usage_right_index"
  after insert or delete or update of "id", "tenant_id", "licensee" on "better_supabase"."dam_usage_rights"
  for each row execute function "better_supabase"."search_index_row"('dam_usage_right', 'id');

create trigger "bsb_search_advisory_product_index"
  after insert or delete or update of "id", "tenant_id", "name", "archived_at" on "better_supabase"."advisory_products"
  for each row execute function "better_supabase"."search_index_row"('advisory_product', 'id');
