SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.capture_ledger_hold (
  hold_id    uuid,
  to_account uuid,
  amount     bigint DEFAULT NULL::bigint,
  kind       text   DEFAULT 'ledger.capture'::text,
  memo       text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."capture_ledger_hold"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.close_ledger_account (
  account_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."close_ledger_account"($1) $function$;

CREATE OR REPLACE FUNCTION api.expire_ledger_holds (
  max_rows integer DEFAULT 500
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."expire_ledger_holds"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ledger_transaction (
  transaction_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ledger_transaction"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_many (
  tenant uuid,
  ids    uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_many"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.ledger_account_entries (
  account_id uuid,
  before     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size  integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ledger_account_entries"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_ledger_accounts (
  tenant      uuid,
  kind        text    DEFAULT NULL::text,
  holder_type text    DEFAULT NULL::text,
  holder_id   text    DEFAULT NULL::text,
  page_size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ledger_accounts"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.open_ledger_account (
  tenant          uuid,
  kind            text,
  code            text,
  name            text,
  unit            text,
  scale           smallint DEFAULT 0,
  holder_type     text     DEFAULT NULL::text,
  holder_id       text     DEFAULT NULL::text,
  owner_id        uuid     DEFAULT NULL::uuid,
  allow_negative  boolean  DEFAULT false,
  read_permission text     DEFAULT NULL::text,
  metadata        jsonb    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_ledger_account"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $function$;

CREATE OR REPLACE FUNCTION api.place_ledger_hold (
  account_id     uuid,
  amount         bigint,
  reference_type text                     DEFAULT NULL::text,
  reference_id   text                     DEFAULT NULL::text,
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."place_ledger_hold"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.post_ledger_transaction (
  tenant          uuid,
  kind            text,
  lines           jsonb,
  reference_type  text                     DEFAULT NULL::text,
  reference_id    text                     DEFAULT NULL::text,
  memo            text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text,
  effective_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  metadata        jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."post_ledger_transaction"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.release_ledger_hold (
  hold_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_ledger_hold"($1) $function$;

CREATE OR REPLACE FUNCTION api.reverse_ledger_transaction (
  transaction_id uuid,
  memo           text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."reverse_ledger_transaction"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people'
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
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_reindex (
  subject_type text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
  if search_reindex.subject_type is null or search_reindex.subject_type = 'maintenance_plan' then
    for v_id in select s."id"::text from "better_supabase"."maintenance_plans" s loop
      if "better_supabase"."search_refresh"('maintenance_plan', v_id) then
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
  if search_reindex.subject_type is null or search_reindex.subject_type = 'production_order' then
    for v_id in select s."id"::text from "better_supabase"."production_orders" s loop
      if "better_supabase"."search_refresh"('production_order', v_id) then
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_titles (
  refs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'message', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."messages" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'message')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'conversation', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."conversations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'conversation')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'channel', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."channels" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'channel')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'course', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."courses" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'course')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'post', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."posts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'post')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'activity', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."activities" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'activity')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'quote', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/crm/quotes/' || s."id"::text))
    from "better_supabase"."quotes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'quote')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people'))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/finance'))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'invoice', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/finance/payables'))
    from "better_supabase"."invoices" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'invoice')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'rfq', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/rfqs'))
    from "better_supabase"."rfqs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'rfq')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'till', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/tills'))
    from "better_supabase"."tills" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'till')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'order', 'id', s."id"::text,
      'title', s."number"::text, 'url', '/shop/orders/' || s."id"::text))
    from "better_supabase"."orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'booking', 'id', s."id"::text,
      'title', s."customer_name"::text, 'url', '/calendar'))
    from "better_supabase"."bookings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'booking')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."assets" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset_location', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."asset_locations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset_location')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lease', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."leases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lease')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_report', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."expense_reports" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_report')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_line', 'id', s."id"::text,
      'title', s."description"::text, 'url', null::text))
    from "better_supabase"."expense_lines" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_line')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'donation_fund', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."donation_funds" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'donation_fund')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_order', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/field/dispatch'))
    from "better_supabase"."work_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'shipment', 'id', s."id"::text,
      'title', s."reference"::text, 'url', '/field/shipments'))
    from "better_supabase"."shipments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'shipment')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'contract', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."contracts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'contract')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'control', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."controls" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'control')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'compliance_policy', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."compliance_policies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'compliance_policy')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'qualification_type', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."qualification_types" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'qualification_type')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'risk', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."risks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'risk')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'case', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."cases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'case')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspections" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_program', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."inspection_programs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_program')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_finding', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspection_findings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_finding')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'form', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/forms/' || s."id"::text))
    from "better_supabase"."forms" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'form')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meetings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting_decision', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meeting_decisions" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting_decision')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'maintenance_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/maintenance'))
    from "better_supabase"."maintenance_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'maintenance_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'dam_usage_right', 'id', s."id"::text,
      'title', s."licensee"::text, 'url', null::text))
    from "better_supabase"."dam_usage_rights" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'dam_usage_right')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lims_sample', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/lims'))
    from "better_supabase"."lims_samples" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lims_sample')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'tax_code', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."tax_codes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'tax_code')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'production_order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."production_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'production_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_center', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."work_centers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_center')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'bank_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."bank_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'bank_account')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'care_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/care-plans'))
    from "better_supabase"."care_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'care_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'incident', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."incidents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'incident')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'content_entry', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."content_entries" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'content_entry')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/documents/' || s."id"::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'organization', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "public"."organizations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'organization')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'change_request', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/change-requests/' || s."id"::text))
    from "public"."change_requests" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'change_request')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_url (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_url.subject_type
    when 'company' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."companies" s where s."id" = (subject_url.subject_id)::uuid);
    when 'person' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."people" s where s."id" = (subject_url.subject_id)::uuid);
    when 'deal' then
      return (select '/crm/deals' from "better_supabase"."deals" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'quote' then
      return (select '/crm/quotes/' || s."id"::text from "better_supabase"."quotes" s where s."id" = (subject_url.subject_id)::uuid);
    when 'work_item' then
      return (select '/work' from "better_supabase"."work_items" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select '/people' from "better_supabase"."employees" s where s."id" = (subject_url.subject_id)::uuid);
    when 'ledger_account' then
      return (select '/finance' from "better_supabase"."ledger_accounts" s where s."id" = (subject_url.subject_id)::uuid);
    when 'invoice' then
      return (select '/finance/payables' from "better_supabase"."invoices" s where s."id" = (subject_url.subject_id)::uuid);
    when 'product' then
      return (select '/shop' from "better_supabase"."products" s where s."id" = (subject_url.subject_id)::uuid);
    when 'rfq' then
      return (select '/rfqs' from "better_supabase"."rfqs" s where s."id" = (subject_url.subject_id)::uuid);
    when 'till' then
      return (select '/tills' from "better_supabase"."tills" s where s."id" = (subject_url.subject_id)::uuid);
    when 'order' then
      return (select '/shop/orders/' || s."id"::text from "better_supabase"."orders" s where s."id" = (subject_url.subject_id)::uuid);
    when 'booking' then
      return (select '/calendar' from "better_supabase"."bookings" s where s."id" = (subject_url.subject_id)::uuid);
    when 'work_order' then
      return (select '/field/dispatch' from "better_supabase"."work_orders" s where s."id" = (subject_url.subject_id)::uuid);
    when 'shipment' then
      return (select '/field/shipments' from "better_supabase"."shipments" s where s."id" = (subject_url.subject_id)::uuid);
    when 'form' then
      return (select '/forms/' || s."id"::text from "better_supabase"."forms" s where s."id" = (subject_url.subject_id)::uuid);
    when 'maintenance_plan' then
      return (select '/maintenance' from "better_supabase"."maintenance_plans" s where s."id" = (subject_url.subject_id)::uuid);
    when 'lims_sample' then
      return (select '/lims' from "better_supabase"."lims_samples" s where s."id" = (subject_url.subject_id)::uuid);
    when 'care_plan' then
      return (select '/care-plans' from "better_supabase"."care_plans" s where s."id" = (subject_url.subject_id)::uuid);
    when 'document' then
      return (select '/documents/' || s."id"::text from "better_supabase"."documents" s where s."id" = (subject_url.subject_id)::uuid);
    when 'customer' then
      return (select '/customers/' || s."id"::text from "public"."customers" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'application' then
      return (select '/people/hiring' from "better_supabase"."applications" s where s."id" = (subject_url.subject_id)::uuid);
    when 'change_request' then
      return (select '/change-requests/' || s."id"::text from "public"."change_requests" s where s."id" = (subject_url.subject_id)::uuid);
    when 'project' then
      return (select '/projects/' || s."id"::text from "public"."projects" s where s."id" = (subject_url.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select '/projects/' || s."project_id"::text from "public"."tasks" s where s."id" = (subject_url.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE TRIGGER bsb_search_asset_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name ON better_supabase.assets
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('asset', 'id');

CREATE TRIGGER bsb_search_booking_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, customer_name ON better_supabase.bookings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('booking', 'id');

CREATE TRIGGER bsb_search_care_plan_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.care_plans
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('care_plan', 'id');

CREATE TRIGGER bsb_search_contract_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.contracts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('contract', 'id');

CREATE TRIGGER bsb_search_document_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name ON better_supabase.documents
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('document', 'id');

CREATE TRIGGER bsb_search_expense_report_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.expense_reports
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('expense_report', 'id');

CREATE TRIGGER bsb_search_form_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.forms
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('form', 'id');

CREATE TRIGGER bsb_search_incident_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.incidents
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('incident', 'id');

CREATE TRIGGER bsb_search_invoice_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.invoices
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('invoice', 'id');

CREATE TRIGGER bsb_search_lease_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.leases
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('lease', 'id');

CREATE TRIGGER bsb_search_ledger_account_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name ON better_supabase.ledger_accounts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('ledger_account', 'id');

CREATE TRIGGER bsb_search_lims_sample_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.lims_samples
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('lims_sample', 'id');

CREATE TRIGGER bsb_search_maintenance_plan_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.maintenance_plans
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('maintenance_plan', 'id');

CREATE TRIGGER bsb_search_order_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, number ON better_supabase.orders
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('order', 'id');

CREATE TRIGGER bsb_search_quote_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.quotes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('quote', 'id');

CREATE TRIGGER bsb_search_rfq_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.rfqs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('rfq', 'id');

CREATE TRIGGER bsb_search_shipment_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, reference ON better_supabase.shipments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('shipment', 'id');

CREATE TRIGGER bsb_search_till_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name ON better_supabase.tills
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('till', 'id');

CREATE TRIGGER bsb_search_work_order_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title ON better_supabase.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('work_order', 'id');

CREATE TRIGGER bsb_search_task_index
  AFTER INSERT OR DELETE OR UPDATE OF id, organization_id, title, project_id ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('task', 'id');

COMMENT ON TABLE "public"."tasks" IS '@bsb subject type=task id-type=uuid tenant=organization_id title=title url=/projects/{project_id} search rank=rank rank-group=status; events include="status, project_id"';

REVOKE ALL ON FUNCTION "api"."capture_ledger_hold"(uuid, uuid, bigint, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."capture_ledger_hold"(uuid, uuid, bigint, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."close_ledger_account"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."close_ledger_account"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."expire_ledger_holds"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."expire_ledger_holds"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_ledger_transaction"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ledger_transaction"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_many"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_many"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ledger_account_entries"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ledger_account_entries"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ledger_accounts"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ledger_accounts"(uuid, text, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_ledger_account"(uuid, text, text, text, text, smallint, text, text, uuid, boolean, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."place_ledger_hold"(uuid, bigint, text, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."place_ledger_hold"(uuid, bigint, text, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."post_ledger_transaction"(uuid, text, jsonb, text, text, text, text, timestamp WITH time zone, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."release_ledger_hold"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_ledger_hold"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."reverse_ledger_transaction"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."reverse_ledger_transaction"(uuid, text) TO "authenticated", "service_role";
