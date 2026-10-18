SET local check_function_bodies = off;

DROP POLICY "activity_entries_read" ON "better_supabase"."activity_entries";

DROP POLICY "status_history_read" ON "better_supabase"."status_history";

DROP POLICY "status_stages_read" ON "better_supabase"."status_stages";

DROP POLICY "subject_lifecycles_read" ON "better_supabase"."subject_lifecycles";

CREATE OR REPLACE FUNCTION api.billing_invoices (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id,
    'kind', i.kind,
    'identifier', i.identifier,
    'title', i.title,
    'status', i.status,
    'currency', i.currency,
    'total', i.total::text,
    'balance', (i.total - i.credited_total - i.paid_total)::text,
    'issuedOn', i.issued_on,
    'dueOn', i.due_on,
    'overdue', i.status in ('issued', 'partially_paid') and i.due_on < current_date
  ) order by i.created_at desc), '[]'::jsonb)
  from better_supabase.invoices i
  where i.tenant_id = billing_invoices.tenant;
$function$;

CREATE OR REPLACE FUNCTION api.delete_reminder (
  reminder uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_reminder"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_bin (
  tenant    uuid,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_bin"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_purge (
  item uuid
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_purge"($1) $function$;

CREATE OR REPLACE FUNCTION api.drive_restore (
  item     uuid,
  conflict text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_restore"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_trash (
  node uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_trash"($1) $function$;

CREATE OR REPLACE FUNCTION api.end_my_session (
  session uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."end_my_session"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_quote (
  quote uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select better_supabase.app_quote_json(q)
  from better_supabase.quotes q
  where q.id = get_quote.quote;
$function$;

CREATE OR REPLACE FUNCTION api.list_applications (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'job_id', a.job_id,
    'stage_id', a.stage_id,
    'state', a.state,
    'candidate_type', a.candidate_type,
    'candidate_id', a.candidate_id,
    'candidate_name', better_supabase.subject_title(a.candidate_type, a.candidate_id)
  ) order by a.stage_id, a.rank collate "C"), '[]'::jsonb)
  from better_supabase.applications a
  where a.tenant_id = list_applications.tenant;
$function$;

CREATE OR REPLACE FUNCTION api.list_field_definitions (
  tenant uuid,
  entity text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_field_definitions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_jobs (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', j.id,
    'title', j.title,
    'status', j.status,
    'location', j.location
  ) order by j.created_at desc), '[]'::jsonb)
  from better_supabase.jobs j
  where j.tenant_id = list_jobs.tenant;
$function$;

CREATE OR REPLACE FUNCTION api.list_my_reminders (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_my_reminders"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_my_sessions()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_my_sessions"() $function$;

CREATE OR REPLACE FUNCTION api.list_quotes (
  tenant    uuid,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(better_supabase.app_quote_json(x.q) order by (x.q).created_at desc), '[]'::jsonb)
  from (
    select q
    from better_supabase.quotes q
    where q.tenant_id = list_quotes.tenant
    order by q.created_at desc
    limit least(greatest(list_quotes.page_size, 1), 100)
  ) x;
$function$;

CREATE OR REPLACE FUNCTION api.shop_orders (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'number', o.number,
        'status', o.status,
        'currency', o.currency,
        'total', o.total::text,
        'placedAt', o.placed_at,
        'lines', (select count(*) from better_supabase.order_lines ol where ol.order_id = o.id)
      ) order by o.placed_at desc)
      from better_supabase.orders o
      where o.tenant_id = shop_orders.tenant
    ), '[]'::jsonb),
    'drafts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'currency', c.currency,
        'createdAt', c.created_at,
        'lines', (select count(*) from better_supabase.cart_lines cl where cl.cart_id = c.id)
      ) order by c.created_at desc)
      from better_supabase.carts c
      where c.tenant_id = shop_orders.tenant
        and c.user_id = (select auth.uid())
        and c.status = 'open'
    ), '[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION api.shop_products (
  tenant   uuid,
  currency text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(r.item order by p.created_at desc), '[]'::jsonb)
  from better_supabase.products p
  join lateral (
    select v.id, v.sku
    from better_supabase.product_variants v
    where v.product_id = p.id
    order by v.rank collate "C"
    limit 1
  ) first_variant on true
  left join lateral (
    select pr.amount
    from better_supabase.product_prices pr
    where pr.variant_id = first_variant.id
      and pr.currency = shop_products.currency
      and pr.price_list_id is null
      and (pr.valid_from is null or pr.valid_from <= now())
      and (pr.valid_until is null or pr.valid_until > now())
    order by pr.valid_from desc nulls last
    limit 1
  ) price on true
  left join lateral (
    select sum(l.available)::int as available
    from better_supabase.stock_levels l
    join better_supabase.product_variants v on v.id = l.variant_id
    where v.product_id = p.id
  ) stock on true
  cross join lateral (
    select jsonb_build_object(
      'id', p.id,
      'title', p.title,
      'slug', p.slug,
      'description', p.description,
      'kind', p.kind,
      'status', p.status,
      'variantId', first_variant.id,
      'sku', first_variant.sku,
      'amount', price.amount::text,
      'available', stock.available
    ) as item
  ) r
  where p.tenant_id = shop_products.tenant;
$function$;

CREATE OR REPLACE FUNCTION api.shop_stock_levels (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', loc.id, 'code', loc.code, 'name', loc.name, 'active', loc.active
      ) order by loc.code)
      from better_supabase.inventory_locations loc
      where loc.tenant_id = shop_stock_levels.tenant
    ), '[]'::jsonb),
    'levels', coalesce((
      select jsonb_agg(jsonb_build_object(
        'variantId', v.id,
        'productTitle', p.title,
        'sku', v.sku,
        'locationId', loc.id,
        'onHand', coalesce(l.on_hand, 0),
        'reserved', coalesce(l.reserved, 0),
        'available', coalesce(l.available, 0),
        'reorderPoint', l.reorder_point
      ) order by p.title, v.sku, loc.code)
      from better_supabase.product_variants v
      join better_supabase.products p on p.id = v.product_id
      join better_supabase.inventory_locations loc
        on loc.tenant_id = v.tenant_id and loc.active
      left join better_supabase.stock_levels l
        on l.variant_id = v.id and l.location_id = loc.id
      where v.tenant_id = shop_stock_levels.tenant
        and v.track_inventory
        and p.status <> 'archived'
    ), '[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_quote_json (
  q better_supabase.quotes
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select (to_jsonb(q) - 'token_hash')
    || jsonb_build_object(
      'number', q.number::text,
      'list_total', q.list_total::text,
      'discount_total', q.discount_total::text,
      'subtotal', q.subtotal::text,
      'tax_total', q.tax_total::text,
      'total', q.total::text,
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
          'description', ql.description,
          'quantity', ql.quantity,
          'unitAmount', ql.unit_amount::text,
          'discountBps', ql.discount_bps,
          'taxRateBps', ql.tax_rate_bps,
          'taxCode', ql.tax_code
        ) order by ql.position)
        from better_supabase.quote_lines ql
        where ql.parent_id = q.id
      ), '[]'::jsonb)
    );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_to_job (
  job       uuid,
  candidate jsonb,
  source    text,
  owner     uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_job "better_supabase"."jobs";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."jobs" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'HIRING_JOB_NOT_OPEN';
  end if;
  if v_id is null or not (case v_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_type, v_id, 'read')) then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_user_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case approval_policy.subject_type || ':' || approval_policy.action
    when 'customer:discount' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    else null::jsonb
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approvals_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."approval_requests" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_object_allowed (
  bucket text,
  path   text,
  action text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."attachments" a
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" in ('pending', 'clean', 'failed') and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select subject_type is null or case subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'hiring.read'), false)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attachments_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bs_transition_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state" when 'triage' then new."state" = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state" = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state" = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state" = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state" = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state" = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason")
        values (new."tenant_id", 'work_item', new."id"::text, old."state", new."state", auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));
  
  null;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_id)::uuid and s."organization_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_id)::uuid and s."tenant_id" = tenant) and coalesce(better_supabase.can('tenant', tenant, 'hiring.read'), false)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_after_write()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."deleted_at" is not null then
    perform better_supabase.audit_event(
    event_type => 'comment.deleted',
    category => 'data',
    target_type => 'comment',
    record_id => new."id"::text,
    tenant => (new."organization_id")::uuid,
    metadata => jsonb_build_object('commentId', new."id", 'organizationId', new."organization_id"::text, 'subjectType', new."subject_type", 'subjectId', new."subject_id", 'authorId', new."author_id")
  );
    return null;
  end if;
  v_new := array(
    select x from unnest(new."mentions") x
    where (tg_op = 'INSERT' or not x = any(old."mentions"))
      and coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'comments.read'), false)
      and case new."subject_type" when 'customer' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'customers.read'), false) when 'company' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'parties.read'), false) when 'person' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'parties.read'), false) when 'deal' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'deals.read'), false) when 'work_item' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'work_items.read'), false) when 'employee' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'employees.read'), false) when 'product' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'catalog.read'), false) when 'product_variant' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'catalog.read'), false) when 'drive_node' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'drive.read'), false) when 'application' then coalesce(better_supabase.can_user(x, 'tenant', new."organization_id", 'hiring.read'), false) else true end
  );
  if tg_op = 'INSERT' then
    null;
  end if;
  if cardinality(v_new) > 0 then
    null;
  end if;
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new."organization_id",
      'actor', new."author_id",
      'subject_type', new."subject_type",
      'subject_id', new."subject_id",
      'summary', left(new."body", 140),
      'subject_label', null::text,
      'action_path', null::text,
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  -- The author and newly mentioned members follow the subject
  -- (participating); a level a member already chose stays.
  insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
  select distinct new."organization_id", f.x, new."subject_type", new."subject_id", 'participating'
  from unnest(case when tg_op = 'INSERT' then array[new."author_id"] else '{}'::uuid[] end || v_new) f(x)
  where f.x is not null
  on conflict do nothing;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comments_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."comments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.confirm_attachment (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."attachments";
  v_meta jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = confirm_attachment.id for update;
  if v_row."id" is null or (v_row."uploaded_by" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No pending attachment of yours has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    return to_jsonb(v_row);
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = v_row."object_path";
  if not found then
    raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
  end if;
  update "better_supabase"."attachments" a set
    "uploaded_at" = now(),
    "size" = coalesce((v_meta ->> 'size')::bigint, a."size"),
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type"),
    "status" = 'clean'
  where a."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'attachment.uploaded',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_deal (
  tenant   uuid,
  attrs    jsonb,
  contacts jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."deals";
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_deal.tenant, 'deals.write'), false)) then
    raise exception 'not allowed to change deals' using errcode = '42501', hint = 'DEAL_FORBIDDEN';
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    raise exception 'a deal needs a name and a close date' using errcode = '23502', hint = 'DEAL_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_deal.tenant, create_deal.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id",
      "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period",
      "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind",
      "flags", "source", "note", "created_by")
    values (create_deal.tenant, v_seq, v_identifier, trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion', create_deal.attrs ->> 'priority', create_deal.attrs ->> 'product', (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0), coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')), coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid, (create_deal.attrs ->> 'stageId')::uuid, (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast', (create_deal.attrs ->> 'closeOn')::date, create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz, create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source', create_deal.attrs ->> 'note', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a deal field has an invalid value' using errcode = '22023', hint = 'DEAL_ATTRS_INVALID';
  end;
  v_deal := v_row."id";
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
  if create_deal.contacts is not null then
    perform "better_supabase"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = v_deal);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_invoice (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_company_type text := coalesce(create_invoice.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_invoice.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_invoice.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    raise exception 'an invoice needs a title' using errcode = '23502', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."invoices" ("tenant_id", "title", "company_type", "company_id", "contact_type", "contact_id", "currency",
      "terms_days", "note", "origin_type", "origin_id", "deposit_bps", "created_by")
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), coalesce((create_invoice.attrs ->> 'termsDays')::integer, 30),
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if create_invoice.lines is not null then
    perform "better_supabase"."set_invoice_lines"(v_row."id", create_invoice.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'invoice', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'invoice' and x."source_id" = v_row."id"::text
    );
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'balance', (x."total" - x."credited_total" - x."paid_total")::text,
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = x."id"), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_quote (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'quote', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'quote' and x."source_id" = v_row."id"::text
    );
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_reminder (
  reminder uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_access (
  document_id uuid,
  write       boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = document_access.document_id;
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if document_access.write then
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end and case v_doc."subject_type"
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.documents_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."documents" d where d."subject_type" = v_type and d."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_bin (
  tenant    uuid,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_bin.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', b.item_id, 'batchId', b.batch_id, 'count', b.n, 'trashedBy', b.trashed_by, 'trashedAt', b.trashed_at, 'purgeAfter', b.purge_after, 'node', b.node) order by b.trashed_at desc, b.item_id), '[]'::jsonb)
    from (
      select i."id" as item_id, i."batch_id" as batch_id, i."trashed_by" as trashed_by, i."trashed_at" as trashed_at, i."purge_after" as purge_after,
        (select count(*) from "better_supabase"."trash_items" c where c."batch_id" = i."batch_id")::integer as n,
        "better_supabase"."drive_node_json"(x) as node
      from "better_supabase"."trash_items" i
      join "better_supabase"."drive_nodes" x on x."id"::text = i."subject_id"
      where i."tenant_id" = drive_bin.tenant and i."subject_type" = 'drive_node' and i."depth" = 0
        and (drive_bin.before is null or i."trashed_at" < drive_bin.before)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor'))
      order by i."trashed_at" desc, i."id"
      limit least(greatest(coalesce(drive_bin.page_size, 50), 1), 200)
    ) b
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_purge (
  item uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_root "better_supabase"."trash_items"%rowtype;
begin
  select r.* into v_root from "better_supabase"."trash_items" i
  join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
  where i."id" = drive_purge.item and r."subject_type" = 'drive_node';
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_root."subject_id"::uuid, 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_root."subject_id"::uuid, 'owner')) then
    raise exception 'not allowed to delete this item for good' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  return "better_supabase"."trash_purge_batch"(v_root."batch_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_restore (
  item     uuid,
  conflict text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_root "better_supabase"."trash_items"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_name text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r.* into v_root from "better_supabase"."trash_items" i
  join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
  where i."id" = drive_restore.item and r."subject_type" = 'drive_node';
  if not found then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_root."subject_id"::uuid;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to restore this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."parent_id" is not null and exists (
    select 1 from "better_supabase"."drive_nodes" p where p."id" = v_node."parent_id" and p."deleted_at" is not null
  ) then
    raise exception 'restore the folder this item was in first' using errcode = '22023', hint = 'DRIVE_PARENT_TRASHED';
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", v_node."parent_id", v_node."name", v_node."id", "better_supabase"."drive_conflict"(drive_restore.conflict));
  if v_name <> v_node."name" then
    update "better_supabase"."drive_nodes" x set "name" = v_name where x."id" = v_node."id";
  end if;
  v_count := "better_supabase"."trash_restore_batch"(v_root."batch_id");
  delete from "better_supabase"."trash_items" where "batch_id" = v_root."batch_id";
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  return jsonb_build_object('id', v_root."id", 'batchId', v_root."batch_id", 'count', v_count, 'node', "better_supabase"."drive_node_json"(v_node));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_trash (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_batch uuid := gen_random_uuid();
  v_count integer := 0;
  v_child record;
  v_id uuid;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_trash.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item to the bin' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  for v_child in
    select s.node_id, s.depth from "better_supabase"."drive_subtree"(v_node."id") s
    join "better_supabase"."drive_nodes" x on x."id" = s.node_id
    where x."deleted_at" is null
    order by s.depth
  loop
    v_count := v_count + "better_supabase"."trash_cascade"(v_node."tenant_id", 'drive_node', v_child.node_id::text, v_batch, v_child.depth, auth.uid());
  end loop;
  select i."id" into v_id from "better_supabase"."trash_items" i
  where i."subject_type" = 'drive_node' and i."subject_id" = v_node."id"::text;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.employee_from_application (
  application uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_application "better_supabase"."applications";
  v_job "better_supabase"."jobs";
  v_existing "better_supabase"."employees";
begin
  select * into v_application from "better_supabase"."applications" x where x."id" = employee_from_application.application;
  if v_application."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_application."tenant_id", 'employees.write'), false)) then
    raise exception 'no such application you can turn into an employee' using errcode = 'P0002', hint = 'EMPLOYEE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_existing from "better_supabase"."employees" x
  where x."tenant_id" = v_application."tenant_id" and x."origin_type" = 'application' and x."origin_id" = v_application."id"::text;
  if v_existing."id" is not null then
    return to_jsonb(v_existing);
  end if;
  if v_application."state" <> 'hired' then
    raise exception 'only a hired application becomes an employee' using errcode = '55000', hint = 'EMPLOYEE_APPLICATION_NOT_HIRED';
  end if;
  select * into v_job from "better_supabase"."jobs" x where x."id" = v_application."job_id";
  return "better_supabase"."create_employee"(v_application."tenant_id", jsonb_strip_nulls(jsonb_build_object(
      'name', (case v_application."candidate_type"
      when 'customer' then (select s."name"::text from "public"."customers" s where s."id" = (v_application."candidate_id")::uuid)
      when 'company' then (select s."name"::text from "better_supabase"."companies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'person' then (select s."name"::text from "better_supabase"."people" s where s."id" = (v_application."candidate_id")::uuid)
      when 'deal' then (select s."name"::text from "better_supabase"."deals" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_item' then (select s."title"::text from "better_supabase"."work_items" s where s."id" = (v_application."candidate_id")::uuid)
      when 'employee' then (select s."name"::text from "better_supabase"."employees" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product' then (select s."title"::text from "better_supabase"."products" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product_variant' then (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (v_application."candidate_id")::uuid)
      when 'drive_node' then (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (v_application."candidate_id")::uuid)
      else null::text
    end),
      'jobTitle', v_job."title",
      'teamId', v_job."team_id",
      'employmentType', case when v_job."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[]) then v_job."employment_type" end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application."id"::text)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_my_session (
  session uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_approval (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = get_approval.request_id;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_req."requested_by" = auth.uid() or "better_supabase"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet') or case v_req."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    else false
  end)))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'createdAt', v_req."created_at") || jsonb_build_object(
    'canDecide', "better_supabase"."approval_eligible"(v_req."id"),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
      from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id"
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_document_version (
  document_id uuid,
  version_id  uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_state text;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = get_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."content" ->> 'state' into v_state from "better_supabase"."versions" x
  where x."id" = get_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text;
  if v_state is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  return v_state;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text,
  data        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', link.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to link records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    raise exception 'data must be an object' using errcode = '22023', hint = 'RELATION_INVALID';
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    raise exception 'a record can''t link to itself' using errcode = '22023', hint = 'RELATION_SELF';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := link.target_type; v_source_id := link.target_id;
    v_target_type := link.source_type; v_target_id := link.source_id;
  else
    v_source_type := link.source_type; v_source_id := link.source_id;
    v_target_type := link.target_type; v_target_id := link.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case link.source_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    else false
  end)
     or not (case link.target_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to link these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_relation_link"(uuid, text, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text)', v_hook::oid::regproc)
        using link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id;
    end if;
  end;
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relations:' || v_kind));
  end if;
  select "id", "data" into v_id, v_previous from "better_supabase"."relations"
    where "tenant_id" = link.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id;
  if v_id is null then
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r."target_type", r."target_id", reach.depth + 1
        from "better_supabase"."relations" r join reach
          on r."source_type" = reach.t and r."source_id" = reach.i
        where r."tenant_id" = link.tenant and r."kind" = v_kind and reach.depth < 1000
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      raise exception 'this link would create a cycle' using errcode = '23514', hint = 'RELATION_CYCLE';
    end if;
    if v_single then
      delete from "better_supabase"."relations"
        where "tenant_id" = link.tenant and "kind" = v_kind
          and "source_type" = v_source_type and "source_id" = v_source_id
        returning * into v_old;
      if v_old."id" is not null then
        v_replaced := jsonb_build_object('targetType', v_old."target_type", 'targetId', v_old."target_id", 'data', v_old."data");
        null;
      end if;
    end if;
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "data", "created_by")
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning "id" into v_id;
    v_created := true;
    null;
  elsif link.data is not null then
    update "better_supabase"."relations" set "data" = link.data where "id" = v_id;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_relation_link"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{customer,company,person,deal,work_item,employee,product,product_variant,drive_node,application}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'customer' then 'public.customers'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_approvals (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  assigned     boolean                  DEFAULT false,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
  v_read boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approvals.tenant, 'approvals.read'), false);
begin
  select coalesce(jsonb_agg(t.j order by t.at desc, t.id), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "better_supabase"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet') or case x."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    else false
  end)))) or "better_supabase"."approval_eligible"(x."id")
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_versions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" x
    where x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_field_definitions (
  tenant uuid,
  entity text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_reminders (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and r."subject_type" = list_my_reminders.subject_type
      and r."subject_id" = list_my_reminders.subject_id
      and r."user_id" = auth.uid()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_sessions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_history (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case list_status_history.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'work_item'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_stages (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case list_status_stages.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_trash (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_trash.tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'subjectType', t."subject_type", 'subjectId', t."subject_id", 'title', t."title", 'batchId', t."batch_id", 'count', t.n, 'trashedBy', t."trashed_by", 'trashedAt', t."trashed_at", 'purgeAfter', t."purge_after") order by t."trashed_at" desc, t."id"), '[]'::jsonb)
    into v_rows
  from (
    select x.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = x."batch_id")::integer as n
    from "better_supabase"."trash_items" x
    where x."tenant_id" = list_trash.tenant
      and x."depth" = 0
      and (list_trash.subject_type is null or x."subject_type" = list_trash.subject_type)
      and (list_trash.before is null or x."trashed_at" < list_trash.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    else false
  end)
    order by x."trashed_at" desc, x."id"
    limit least(greatest(coalesce(list_trash.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_engagement (
  tenant   uuid,
  attrs    jsonb,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner,
    (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz,
    (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid())
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at",
    "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  null;
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_time (
  tenant        uuid,
  started_at    timestamp with time zone,
  ended_at      timestamp with time zone,
  subject_type  text                     DEFAULT NULL::text,
  subject_id    text                     DEFAULT NULL::text,
  billable      boolean                  DEFAULT false,
  rate          bigint                   DEFAULT NULL::bigint,
  rate_currency text                     DEFAULT NULL::text,
  note          text                     DEFAULT NULL::text,
  user_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "public"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case log_time.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (log_time.rate is null) <> (log_time.rate_currency is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if log_time.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."rate_currency" := log_time.rate_currency;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move (
  subject_type text,
  subject_id   text,
  previous_id  text,
  next_id      text,
  to_group     text
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_group text;
  v_other_tenant text;
  v_other_group text;
  v_previous text;
  v_next text;
  v_key text;
begin
  if not "better_supabase"."can_subject"(move.subject_type, move.subject_id, 'write') then
    raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
  end if;
  case move.subject_type
    when 'deal' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."deals" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."deals" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."deals" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."deals" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."deals", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'work_item' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."work_items" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."work_items" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."work_items" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."work_items" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."work_items", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'application' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."applications" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."applications" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."applications" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."applications" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."applications", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    else
      raise exception 'this subject type has no rank column in config.subjects' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  end case;
  if length(v_key) > 24 then
    perform "better_supabase"."enqueue_job"(queue => 'rank.rebalance', payload => jsonb_build_object('subjectType', move.subject_type, 'tenant', v_tenant, 'group', v_group), dedupe_key => 'rank:' || move.subject_type || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_group, ''), dedupe_running => false);
  end if;
  return v_key;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_document (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  name         text DEFAULT 'body'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
  v_write boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d
  where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
  if found and v_doc."tenant_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."tenant_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end and case v_doc."subject_type"
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end) then
        raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
      end if;
      raise exception 'not allowed to open this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name;
    end if;
  end;
    insert into "better_supabase"."documents" ("tenant_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      perform better_supabase.audit_event(
    event_type => 'document.created',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name")
  );
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_doc."id";
    end if;
  end;
    else
      select * into v_doc from "better_supabase"."documents" d
      where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end and case v_doc."subject_type"
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'snapshot', case when v_snapshot."document_id" is null then null else replace(encode(v_snapshot."state", 'base64'), E'\n', '') end,
    'snapshotSeq', coalesce(v_snapshot."seq", 0),
    'updates', "better_supabase"."document_updates_after"(v_doc."id", coalesce(v_snapshot."seq", 0))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pause_lifecycle (
  subject_type text,
  subject_id   text,
  until        timestamp with time zone,
  reason       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  case pause_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pipeline_board (
  subject_type text,
  pipeline     uuid,
  owner        uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case pipeline_board.subject_type
    when 'deal' then
      return (
        with rows as (
          select r."stage_id" as stage_id, r."currency"::text as currency, r."amount"::bigint as amount,
            r."amount" * coalesce(r."probability", st."probability", 0) / 100.0 as weighted
          from "better_supabase"."deals" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null and (pipeline_board.owner is null or r."owner_user_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'work_item' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."work_items" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'application' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."applications" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and (pipeline_board.owner is null or r."owner_user_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pull_document_updates (
  document_id uuid,
  after_seq   bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = pull_document_updates.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  if v_snapshot."document_id" is not null and pull_document_updates.after_seq < v_snapshot."seq" then
    return jsonb_build_object(
      'snapshot', replace(encode(v_snapshot."state", 'base64'), E'\n', ''),
      'snapshotSeq', v_snapshot."seq",
      'updates', "better_supabase"."document_updates_after"(v_doc."id", v_snapshot."seq")
    );
  end if;
  return jsonb_build_object('updates', "better_supabase"."document_updates_after"(v_doc."id", pull_document_updates.after_seq));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.push_document_update (
  document_id uuid,
  payload     text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = push_document_update.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end and case v_doc."subject_type"
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(push_document_update.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  return v_seq;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case reaction_subject_visible.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" c where c."id"::text = reaction_subject_visible.subject_id and c."organization_id" = reaction_subject_visible.tenant and c."deleted_at" is null)
    when 'inbox_message' then exists (select 1 from "better_supabase"."inbox_messages" m where m."id"::text = reaction_subject_visible.subject_id and m."tenant_id" = reaction_subject_visible.tenant)
    else case reaction_subject_visible.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    else false
  end
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reactions_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."reactions" r where r."subject_type" = v_type and r."subject_id" = v_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebalance_ranks (
  subject_type text,
  tenant       text,
  rank_group   text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
begin
  case rebalance_ranks.subject_type
    when 'deal' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."deals" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."deals" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'work_item' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."work_items" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."work_items" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'application' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."applications" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."applications" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    else
      raise exception 'this subject type has no rank column in config.subjects' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  end case;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_sla_event (
  subject_type text,
  subject_id   text,
  event        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := (case record_sla_event.subject_type
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_sla_event.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_sla_event.subject_id)::uuid)
      else null::text
    end);
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or (case record_sla_event.subject_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_sla_event.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_sla_event.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_sla_event.subject_type, record_sla_event.subject_id, 'read'))) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    null;
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relation_rollup (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text,
  of_type      text,
  column_name  text,
  agg          text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_table text;
  v_id_col text;
  v_tenant_col text;
  v_ids text[];
  v_result jsonb;
begin
  if relation_rollup.agg is null or relation_rollup.agg not in ('count', 'sum', 'avg', 'min', 'max') then
    raise exception 'agg must be count, sum, avg, min or max' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  if relation_rollup.agg <> 'count' and relation_rollup.column_name is null then
    raise exception 'this aggregate needs a column' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  case relation_rollup.of_type
    when 'customer' then v_table := '"public"."customers"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'company' then v_table := '"better_supabase"."companies"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'person' then v_table := '"better_supabase"."people"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'deal' then v_table := '"better_supabase"."deals"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'work_item' then v_table := '"better_supabase"."work_items"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'employee' then v_table := '"better_supabase"."employees"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product' then v_table := '"better_supabase"."products"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product_variant' then v_table := '"better_supabase"."product_variants"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'drive_node' then v_table := '"better_supabase"."drive_nodes"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'application' then v_table := '"better_supabase"."applications"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    else null;
  end case;
  if v_table is null then
    raise exception 'this subject type has no table' using errcode = '22023', hint = 'RELATION_SUBJECT_UNKNOWN';
  end if;
  select array_agg(w.id) into v_ids
  from "better_supabase"."relation_walk"(relation_rollup.tenant, relation_rollup.kind, relation_rollup.subject_type, relation_rollup.subject_id, false, null) w
  where w.type = relation_rollup.of_type;
  execute format(
    'select to_jsonb(%s) from %s s where s.%I::text = any ($1)%s',
    case when relation_rollup.agg = 'count' and relation_rollup.column_name is null then 'count(*)'
      else format('%s(s.%I)', relation_rollup.agg, relation_rollup.column_name) end,
    v_table,
    v_id_col,
    case when v_tenant_col is null then '' else format(' and s.%I = $2', v_tenant_col) end
  ) into v_result using coalesce(v_ids, '{}'::text[]), relation_rollup.tenant;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relations_subject_deleted()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."relations"
  where ("source_type" = v_type and "source_id" = v_id)
     or ("target_type" = v_type and "target_id" = v_id);
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  reason       text  DEFAULT NULL::text,
  payload      jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_policy jsonb := "better_supabase"."approval_policy"(request_approval.subject_type, request_approval.action);
begin
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and case request_approval.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'hiring.read'), false)
    else false
  end)) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  return "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_trash (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_root "better_supabase"."trash_items"%rowtype;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r.* into v_root from "better_supabase"."trash_items" i
    join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
    where i."id" = restore_trash.item_id;
  if not found then
    raise exception 'trash item not found' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_root."tenant_id", 'trash.restore'), false) and case v_root."subject_type"
    when 'customer' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'customers.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'work_items.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'drive.manage'), false)
    else true
  end)) then
    raise exception 'not allowed to restore this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_untrash"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_root."id";
    end if;
  end;
  v_count := "better_supabase"."trash_restore_batch"(v_root."batch_id");
  delete from "better_supabase"."trash_items" where "batch_id" = v_root."batch_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_untrash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_root."id", v_root."batch_id";
    end if;
  end;
  return jsonb_build_object('id', v_root."id", 'batchId', v_root."batch_id", 'subjectType', v_root."subject_type", 'subjectId', v_root."subject_id", 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_version (
  version_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_number integer;
  v_content jsonb;
  v_result jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "subject_type", "subject_id", "number", "content"
    into v_tenant, v_subject_type, v_subject_id, v_number, v_content
    from "better_supabase"."versions" where "id" = restore_version.version_id;
  if v_subject_type is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'versions.restore'), false) and case v_subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    else false
  end and case v_subject_type
    when 'customer' then coalesce(better_supabase.can('tenant', v_tenant, 'customers.write'), false)
    else true
  end)) then
    raise exception 'not allowed to restore this version' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  if v_content is null then
    raise exception 'a version kept in Storage is restored by the app' using errcode = '22023', hint = 'VERSION_RESTORE_UNSUPPORTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_version_restore"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using restore_version.version_id;
    end if;
  end;
  perform set_config('better_supabase.versions_restoring', 'on', true);
  case v_subject_type
    when 'customer' then
      update "public"."customers" s set "name" = r."name", "kvk" = r."kvk"
      from jsonb_populate_record(null::"public"."customers", v_content) r
      where s."id" = (v_subject_id)::uuid;
    else
      raise exception 'this subject type has no columns or apply function to restore into' using errcode = '22023', hint = 'VERSION_RESTORE_UNSUPPORTED';
  end case;
  perform set_config('better_supabase.versions_restoring', '', true);
  v_result := "better_supabase"."version_insert"(v_tenant, v_subject_type, v_subject_id, v_content, null, null, 'restore', false, auth.uid());
  perform better_supabase.audit_event(
    event_type => 'version.restored',
    category => 'data',
    target_type => 'version',
    record_id => restore_version.version_id::text,
    summary => 'restored version ' || v_number::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', (v_result ->> 'id')::uuid, 'number', (v_result ->> 'number')::integer, 'restoredFrom', v_number)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_version_restore"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using restore_version.version_id, (v_result ->> 'id')::uuid;
    end if;
  end;
  return v_result || jsonb_build_object('content', v_content, 'restoredFrom', v_number);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resume_lifecycle (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  case resume_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_version (
  document_id uuid,
  state       text,
  label       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = save_document_version.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    else false
  end and case v_doc."subject_type"
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  return "better_supabase"."version_insert"(v_doc."tenant_id", 'document', v_doc."id"::text,
    jsonb_build_object('state', save_document_version.state, 'name', v_doc."name"),
    null, nullif(trim(save_document_version.label), ''), 'manual', false, auth.uid());
end;
$function$;

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
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
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
    when 'drive_node' then
      select s."tenant_id", s."name"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."drive_nodes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.subjects' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
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
    "updated_at" = now();
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
  if search_reindex.subject_type is null or search_reindex.subject_type = 'customer' then
    for v_id in select s."id"::text from "public"."customers" s loop
      if "better_supabase"."search_refresh"('customer', v_id) then
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
  if search_reindex.subject_type is null or search_reindex.subject_type = 'drive_node' then
    for v_id in select s."id"::text from "better_supabase"."drive_nodes" s loop
      if "better_supabase"."search_refresh"('drive_node', v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_deal_contacts (
  deal     uuid,
  contacts jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_contacts.deal;
  v_item jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not (case coalesce(v_item ->> 'type', 'person')
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(v_item ->> 'type', 'person'), (v_item ->> 'id'), 'read')) then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_contacts" ("tenant_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
  select v_tenant, v_deal, coalesce(x.value ->> 'type', 'person'), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_lifecycle_flag (
  subject_type text,
  subject_id   text,
  flag         text,
  enabled      boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  case set_lifecycle_flag.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.snapshot_version (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  content      jsonb DEFAULT NULL::jsonb,
  label        text  DEFAULT NULL::text,
  storage_path text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_content jsonb := snapshot_version.content;
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', snapshot_version.tenant, 'versions.create'), false) and case snapshot_version.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (snapshot_version.subject_id)::uuid and s."organization_id" = snapshot_version.tenant) and coalesce(better_supabase.can('tenant', snapshot_version.tenant, 'customers.read'), false)
    else false
  end)) then
    raise exception 'not allowed to snapshot this record' using errcode = '42501', hint = 'VERSION_FORBIDDEN';
  end if;
  if v_content is null and snapshot_version.storage_path is null then
    case snapshot_version.subject_type
    when 'customer' then
      select jsonb_object_agg(e.key, e.value) into v_content
      from "public"."customers" s, jsonb_each(to_jsonb(s)) e
      where s."id" = (snapshot_version.subject_id)::uuid
        and e.key = any ('{name,kvk}'::text[]);
    else null;
  end case;
    if v_content is null then
      raise exception 'pass content or a storage path, or list the subject''s columns' using errcode = '22023', hint = 'VERSION_CONTENT_REQUIRED';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_version_snapshot"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using snapshot_version.tenant, snapshot_version.subject_type, snapshot_version.subject_id;
    end if;
  end;
  v_result := "better_supabase"."version_insert"(snapshot_version.tenant, snapshot_version.subject_type, snapshot_version.subject_id, v_content, snapshot_version.storage_path, nullif(trim(snapshot_version.label), ''), 'manual', false, auth.uid());
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_version_snapshot"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using (v_result ->> 'id')::uuid, snapshot_version.subject_type, snapshot_version.subject_id;
    end if;
  end;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_sla_clocks (
  subject_type text,
  subject_id   text,
  priority     text,
  trusted      boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text := (case start_sla_clocks.subject_type
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (start_sla_clocks.subject_id)::uuid)
      else null::text
    end);
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or (case start_sla_clocks.subject_type
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_sla_clocks.subject_id)::uuid and s."tenant_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(start_sla_clocks.subject_type, start_sla_clocks.subject_id, 'read'))) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_timer (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  billable      boolean DEFAULT false,
  rate          bigint  DEFAULT NULL::bigint,
  rate_currency text    DEFAULT NULL::text,
  note          text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case start_timer.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.rate is null) <> (start_timer.rate_currency is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if start_timer.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    null;
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."rate_currency" := start_timer.rate_currency;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.status_state (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  case status_state.subject_type
    when 'work_item' then
      select s."state"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."work_items" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position('{triage,backlog,unstarted,started,completed}'::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'work_item', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb('{triage,backlog,unstarted,started,completed}'::text[]), 'step', v_step, 'steps', 5, 'progress', case when v_step is null then null when 5 = 1 then 1 else round((v_step - 1)::numeric / 4, 4) end,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_tags (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case subject_tags.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_title.subject_type
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_types()
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select '{customer,company,person,deal,work_item,employee,product,product_variant,drive_node,application}'::text[]
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
    when 'customer' then
      return (select '/customers/' || s."id"::text from "public"."customers" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'company' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."companies" s where s."id" = (subject_url.subject_id)::uuid);
    when 'person' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."people" s where s."id" = (subject_url.subject_id)::uuid);
    when 'deal' then
      return (select '/crm/deals' from "better_supabase"."deals" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'work_item' then
      return (select '/work' from "better_supabase"."work_items" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select '/people' from "better_supabase"."employees" s where s."id" = (subject_url.subject_id)::uuid);
    when 'product' then
      return (select '/shop' from "better_supabase"."products" s where s."id" = (subject_url.subject_id)::uuid);
    when 'application' then
      return (select '/people/hiring' from "better_supabase"."applications" s where s."id" = (subject_url.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_form (
  form_id       uuid,
  answers       jsonb,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  submission_id uuid    DEFAULT NULL::uuid,
  draft         boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case submit_form.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case tag.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when 'customer' then true
    when 'company' then true
    when 'person' then true
    when 'deal' then true
    when 'work_item' then true
    when 'employee' then true
    when 'product' then true
    when 'product_variant' then true
    when 'drive_node' then true
    when 'application' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transition (
  subject_type text,
  subject_id   text,
  to_status    text,
  reason       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  case transition.subject_type
    when 'work_item' then
      update "better_supabase"."work_items" s set "state" = transition.to_status
      where s."id" = (transition.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch uuid := gen_random_uuid();
  v_count integer;
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', trash.tenant, 'trash.create'), false) and case trash.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (trash.subject_id)::uuid and s."organization_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'customers.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'work_items.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'drive.read'), false)
    else false
  end and case trash.subject_type
    when 'customer' then coalesce(better_supabase.can('tenant', trash.tenant, 'customers.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', trash.tenant, 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', trash.tenant, 'work_items.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', trash.tenant, 'drive.manage'), false)
    else true
  end)) then
    raise exception 'not allowed to trash this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_trash"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using trash.tenant, trash.subject_type, trash.subject_id;
    end if;
  end;
  v_count := "better_supabase"."trash_cascade"(trash.tenant, trash.subject_type, trash.subject_id, v_batch, 0, auth.uid());
  if v_count = 0 then
    raise exception 'no live record to trash' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  select i."id" into v_id from "better_supabase"."trash_items" i
    where i."subject_type" = trash.subject_type and i."subject_id" = trash.subject_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_trash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, v_batch;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_cascade (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  batch        uuid,
  depth        integer,
  actor        uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_title text;
  v_count integer := 1;
  v_child text;
  v_item "better_supabase"."trash_items"%rowtype;
begin
  case trash_cascade.subject_type
    when 'customer' then
      update "public"."customers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "deleted_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."deleted_at" is null
        returning s."name"::text into v_title;
    else
      raise exception 'this subject type has no deletedAt column' using errcode = '22023', hint = 'TRASH_UNSUPPORTED';
  end case;
  if not found then
    return 0;
  end if;
  delete from "better_supabase"."trash_items" i
    where i."subject_type" = trash_cascade.subject_type and i."subject_id" = trash_cascade.subject_id;
  insert into "better_supabase"."trash_items" ("tenant_id", "subject_type", "subject_id", "title", "batch_id", "depth", "trashed_by", "trashed_at", "purge_after")
  values (trash_cascade.tenant, trash_cascade.subject_type, trash_cascade.subject_id, v_title, trash_cascade.batch, trash_cascade.depth, trash_cascade.actor, now(), now() + make_interval(days => 30))
  returning * into v_item;
  perform better_supabase.audit_event(
    event_type => 'subject.trashed',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'trashed' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
  
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_purge_batch (
  batch uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_purge_batch.batch order by "depth" desc loop
    case v_item.subject_type
    when 'customer' then
      delete from "public"."customers" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'deal' then
      delete from "better_supabase"."deals" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_item' then
      delete from "better_supabase"."work_items" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'drive_node' then
      delete from "better_supabase"."drive_nodes" s
        where s."id" = (v_item.subject_id)::uuid;
    else null;
  end case;
    perform better_supabase.audit_event(
    event_type => 'subject.purged',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'purged' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
    v_count := v_count + 1;
  end loop;
  delete from "better_supabase"."trash_items" where "batch_id" = trash_purge_batch.batch;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_restore_batch (
  batch uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_restore_batch.batch order by "depth" loop
    case v_item.subject_type
    when 'customer' then
      update "public"."customers" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "deleted_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    else null;
  end case;
    perform better_supabase.audit_event(
    event_type => 'subject.restored',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'restored' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlink (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', unlink.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to unlink records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = unlink.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := unlink.target_type; v_source_id := unlink.target_id;
    v_target_type := unlink.source_type; v_target_id := unlink.source_id;
  else
    v_source_type := unlink.source_type; v_source_id := unlink.source_id;
    v_target_type := unlink.target_type; v_target_id := unlink.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case unlink.source_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    else false
  end)
     or not (case unlink.target_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to unlink these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."relations"
    where "tenant_id" = unlink.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id
    returning * into v_old;
  if v_old."id" is null then
    return jsonb_build_object('removed', false, 'data', null);
  end if;
  null;
  return jsonb_build_object('removed', true, 'data', v_old."data");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.untag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (case untag.subject_type
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_deals (
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row "better_supabase"."deals";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_deals.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { dealId, field, value }' using errcode = '22023', hint = 'DEAL_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_deals.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_deal := (v_change ->> 'dealId')::uuid;
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or x."owner_user_id" = auth.uid()
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not (case (v_change -> 'value' ->> 'type')
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"((v_change -> 'value' ->> 'type'), (v_change -> 'value' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
      end if;
      if v_field in ('amount', 'existingAmount') and jsonb_typeof(v_change -> 'value') = 'object' then
        if upper(v_change -> 'value' ->> 'currency') is distinct from v_row."currency" then
          raise exception 'an amount must be in the deal''s currency' using errcode = '22023', hint = 'DEAL_CURRENCY_MISMATCH';
        end if;
        v_change := jsonb_set(v_change, '{value}', v_change -> 'value' -> 'amount');
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_deal, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."deals" x set "name" = trim(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'motion' then
        update "better_supabase"."deals" x set "motion" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'priority' then
        update "better_supabase"."deals" x set "priority" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'ownerId' then
        update "better_supabase"."deals" x set "owner_user_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'product' then
        update "better_supabase"."deals" x set "product" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'seats' then
        update "better_supabase"."deals" x set "seats" = (v_change -> 'value' #>> '{}')::integer where x."id" = v_deal returning * into v_row;
      when 'amount' then
        update "better_supabase"."deals" x set "amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'existingAmount' then
        update "better_supabase"."deals" x set "existing_amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'currency' then
        update "better_supabase"."deals" x set "currency" = upper(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'valuePeriod' then
        update "better_supabase"."deals" x set "value_period" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "better_supabase"."deals" x set "amount_source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "better_supabase"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "better_supabase"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "better_supabase"."deals" x set "forecast_category" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'closeOn' then
        update "better_supabase"."deals" x set "expected_close_on" = (v_change -> 'value' #>> '{}')::date where x."id" = v_deal returning * into v_row;
      when 'nextStep' then
        update "better_supabase"."deals" x set "next_step" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'nextAt' then
        update "better_supabase"."deals" x set "next_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_deal returning * into v_row;
      when 'nextKind' then
        update "better_supabase"."deals" x set "next_kind" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'flags' then
        update "better_supabase"."deals" x set "flags" = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(v_change -> 'value') when 'array' then v_change -> 'value' else '[]' end)), '{}') where x."id" = v_deal returning * into v_row;
      when 'source' then
        update "better_supabase"."deals" x set "source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'note' then
        update "better_supabase"."deals" x set "note" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'lostReason' then
        update "better_supabase"."deals" x set "lost_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'company' then
        update "better_supabase"."deals" x set "company_type" = v_change -> 'value' ->> 'type', "company_id" = v_change -> 'value' ->> 'id' where x."id" = v_deal returning * into v_row;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'DEAL_FIELD_UNKNOWN';
      end case;
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('dealId', v_deal, 'field', v_field));
      v_touched := array_append(v_touched, v_deal);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_deal, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('dealId', v_change ->> 'dealId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."deals" x where x."id" = any (v_touched) loop
    null;
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_engagement (
  engagement uuid,
  attrs      jsonb,
  subjects   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := update_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  null;
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_quote (
  quote uuid,
  attrs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'company' ->> 'type', 'company')
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'company' ->> 'type', 'company'), (update_quote.attrs -> 'company' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person')
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person'), (update_quote.attrs -> 'contact' ->> 'id'), 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_time_entry (
  entry_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case v_row."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row."rate" := (v_patch ->> 'rate')::bigint;
    v_row."rate_currency" := v_patch ->> 'rateCurrency';
    if (v_row."rate" is null) <> (v_row."rate_currency" is null) then
    raise exception 'name both rate and rate_currency, or neither' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if v_row."rate_currency" !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "rate_currency" = v_row."rate_currency",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE TRIGGER bs_search_company_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, DOMAIN ON better_supabase.companies
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('company', 'id');

CREATE TRIGGER bs_search_deal_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, identifier, note, archived_at ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('deal', 'id');

CREATE TRIGGER bs_search_drive_node_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, deleted_at ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('drive_node', 'id');

CREATE TRIGGER bs_search_employee_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, email, job_title ON better_supabase.employees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('employee', 'id');

CREATE TRIGGER bs_search_person_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, name, email, title ON better_supabase.people
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('person', 'id');

CREATE TRIGGER bs_approvals_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.approvals_subject_deleted('product_variant', 'id');

CREATE TRIGGER bs_attachments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted('product_variant', 'id');

CREATE TRIGGER bs_comments_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_subject_deleted('product_variant', 'id');

CREATE TRIGGER bs_documents_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.documents_subject_deleted('product_variant', 'id');

CREATE TRIGGER bs_reactions_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted('product_variant', 'id');

CREATE TRIGGER bs_relations_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.relations_subject_deleted('product_variant', 'id');

CREATE TRIGGER bs_search_product_variant_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, sku, title, barcode ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('product_variant', 'id');

CREATE TRIGGER bs_approvals_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.approvals_subject_deleted('product', 'id');

CREATE TRIGGER bs_attachments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.attachments_subject_deleted('product', 'id');

CREATE TRIGGER bs_comments_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.comments_subject_deleted('product', 'id');

CREATE TRIGGER bs_documents_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.documents_subject_deleted('product', 'id');

CREATE TRIGGER bs_reactions_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.reactions_subject_deleted('product', 'id');

CREATE TRIGGER bs_relations_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.relations_subject_deleted('product', 'id');

CREATE TRIGGER bs_search_product_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, description, slug ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('product', 'id');

CREATE TRIGGER bs_search_work_item_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, identifier, body, archived_at ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('work_item', 'id');

CREATE TRIGGER bs_transition_work_item
  BEFORE INSERT OR UPDATE OF state ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bs_transition_work_item();

CREATE POLICY "activity_entries_read" ON "better_supabase"."activity_entries"
  FOR SELECT
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('activity.read'::text) AS tenant_ids_with)) AND ((subject_type IS NULL) OR (subject_id IS NULL) OR (NOT
    (subject_type = ANY ('{customer,company,person,deal,work_item,employee,product,product_variant,drive_node,application}'::text[]))) OR
    better_supabase.activity_subject_readable(subject_type, subject_id))));

CREATE POLICY "status_history_read" ON "better_supabase"."status_history"
  FOR SELECT
  TO "authenticated"
  USING (
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    ELSE false
END);

CREATE POLICY "status_stages_read" ON "better_supabase"."status_stages"
  FOR SELECT
  TO "authenticated"
  USING (
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    ELSE false
END);

CREATE POLICY "subject_lifecycles_read" ON "better_supabase"."subject_lifecycles"
  FOR SELECT
  TO "authenticated"
  USING (
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    ELSE false
END);

REVOKE ALL ON FUNCTION "api"."billing_invoices"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_invoices"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."delete_reminder"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_reminder"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_bin"(uuid, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_bin"(uuid, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_purge"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_purge"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_restore"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_restore"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_trash"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_trash"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."end_my_session"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."end_my_session"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."get_quote"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_quote"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."list_applications"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_applications"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."list_field_definitions"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_field_definitions"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_jobs"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_jobs"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."list_my_reminders"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_my_reminders"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_my_sessions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_my_sessions"() TO "authenticated";

REVOKE ALL ON FUNCTION "api"."list_quotes"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_quotes"(uuid, integer) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."shop_orders"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."shop_orders"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."shop_products"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."shop_products"(uuid, text) TO "authenticated";

REVOKE ALL ON FUNCTION "api"."shop_stock_levels"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."shop_stock_levels"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."app_quote_json"(better_supabase.quotes) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."app_quote_json"(better_supabase.quotes) TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."approvals_subject_deleted"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."attachments_subject_deleted"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."comments_subject_deleted"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."delete_reminder"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_reminder"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."documents_subject_deleted"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_bin"(uuid, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_bin"(uuid, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_purge"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_purge"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_restore"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_restore"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_trash"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_trash"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."end_my_session"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."end_my_session"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."list_field_definitions"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_field_definitions"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_my_reminders"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_my_reminders"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_my_sessions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_my_sessions"() TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."reactions_subject_deleted"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."relations_subject_deleted"() FROM PUBLIC;
