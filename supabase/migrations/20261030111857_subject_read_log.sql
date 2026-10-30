SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.record_subject_read (
  subject_type  text,
  subject_id    text,
  purpose       text DEFAULT NULL::text,
  block_name    text DEFAULT NULL::text,
  function_name text DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_subject_read"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.subject_access_log (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_access_log"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'message' then 'better_supabase.messages'
      when 'conversation' then 'better_supabase.conversations'
      when 'channel' then 'better_supabase.channels'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'course' then 'better_supabase.courses'
      when 'post' then 'better_supabase.posts'
      when 'engagement' then 'better_supabase.engagements'
      when 'quote' then 'better_supabase.quotes'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'invoice' then 'better_supabase.invoices'
      when 'ledger_account' then 'better_supabase.ledger_accounts'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'order' then 'better_supabase.orders'
      when 'calendar_event' then 'better_supabase.calendar_events'
      when 'booking' then 'better_supabase.bookings'
      when 'asset' then 'better_supabase.assets'
      when 'asset_location' then 'better_supabase.asset_locations'
      when 'lease' then 'better_supabase.lease_agreements'
      when 'expense_report' then 'better_supabase.expense_reports'
      when 'expense_line' then 'better_supabase.expense_lines'
      when 'donation_fund' then 'better_supabase.donation_funds'
      when 'work_order' then 'better_supabase.work_orders'
      when 'shipment' then 'better_supabase.shipments'
      when 'contract' then 'better_supabase.contracts'
      when 'control' then 'better_supabase.controls'
      when 'policy' then 'better_supabase.policies'
      when 'qualification_type' then 'better_supabase.qualification_types'
      when 'risk' then 'better_supabase.risks'
      when 'incident' then 'better_supabase.incidents'
      when 'content_entry' then 'better_supabase.content_entries'
      when 'form' then 'better_supabase.forms'
      when 'document' then 'better_supabase.documents'
      when 'customer' then 'public.customers'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'change_request' then 'public.change_requests'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
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
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
      and not ((y."type" = 'status.changed' and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources)))
        or (y."type" in ('message.sent', 'comment.posted') and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))))
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', h."id"::text, 'organization_id', h."tenant_id", 'event_id', null::text, 'type', 'status.changed', 'actor_id', h."actor_user_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('from', h."from_status"::text, 'to', h."to_status"::text, 'reason', h."reason")), 'occurred_at', h."created_at", 'source', 'transition') as entry,
      h."created_at" as at, h."id"::text as id
    from "better_supabase"."status_history" h
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources))
      and h."tenant_id" = list_activity.tenant
      and h."subject_type" = list_activity.subject_type
      and h."subject_id" = list_activity.subject_id
      and (list_activity.before is null or h."created_at" < list_activity.before)
    order by h."created_at" desc, h."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', m."id"::text, 'organization_id', m."tenant_id", 'event_id', null::text, 'type', case when c."kind" = 'subject' then 'comment.posted' else 'message.sent' end, 'actor_id', m."author_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', left(m."body", 280), 'data', jsonb_strip_nulls(jsonb_build_object('messageId', m."id", 'conversationId', m."conversation_id", 'threadId', m."thread_id", 'kind', m."kind"::text)), 'occurred_at', m."sent_at", 'source', 'message') as entry,
      m."sent_at" as at, m."id"::text as id
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id"
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))
      and c."tenant_id" = list_activity.tenant
      and c."subject_type" = list_activity.subject_type
      and c."subject_id" = list_activity.subject_id
      and m."sent_at" is not null
      and m."deleted_at" is null
      and (list_activity.before is null or m."sent_at" < list_activity.before)
    order by m."sent_at" desc, m."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  if list_activity.subject_id is not null and jsonb_array_length(v_rows) > 0 then
    perform "better_supabase"."record_subject_read"(list_activity.subject_type, list_activity.subject_id, null, 'timeline', 'list_activity');
  end if;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100,
  skip         integer                  DEFAULT 0,
  after_id     uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  perform "better_supabase"."record_subject_read"(list_comments.subject_type, list_comments.subject_id, null, 'comments', 'list_comments');
  return "better_supabase"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (list_comments.after is null
        or (x."sent_at", x."id") > (list_comments.after, coalesce(list_comments.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_history (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  case list_status_history.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      perform "better_supabase"."record_subject_read"(list_status_history.subject_type, list_status_history.subject_id, null, 'state-machine', 'list_status_history');
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'work_item'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'change_request' then
      if not exists (select 1 from "public"."change_requests" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      perform "better_supabase"."record_subject_read"(list_status_history.subject_type, list_status_history.subject_id, null, 'state-machine', 'list_status_history');
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'change_request'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'drive_node' then
      if not exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      perform "better_supabase"."record_subject_read"(list_status_history.subject_type, list_status_history.subject_id, null, 'state-machine', 'list_status_history');
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'drive_node'
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

CREATE OR REPLACE FUNCTION better_supabase.read_field_values (
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
  v_values jsonb;
  v_key text;
  v_read jsonb;
begin
  v_key := "better_supabase"."field_key"('tenant:' || read_field_values.tenant::text, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', case when coalesce(d."encrypted", false) then "better_supabase"."field_open"(v_key, v."value_text") else v."value_text" end)), '[]'::jsonb),
    jsonb_agg(v."id") filter (where coalesce(d."encrypted", false) or coalesce(d."sensitive", false))
  into v_values, v_read
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or (case when read_field_values.subject_type in ('drive_node') then case read_field_values.subject_type
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (read_field_values.subject_id)::uuid and s."tenant_id" = read_field_values.tenant and (coalesce(better_supabase.can('tenant', read_field_values.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end else coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false) end))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  if v_read is not null then
    perform better_supabase.audit_event(
    event_type => 'field_value.viewed',
    category => 'read',
    target_type => 'field_value',
    record_id => read_field_values.subject_id,
    summary => 'Read ' || jsonb_array_length(v_read)::text || ' protected field value(s) of ' || read_field_values.subject_type,
    tenant => (read_field_values.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', read_field_values.tenant, 'subjectType', read_field_values.subject_type, 'subjectId', read_field_values.subject_id, 'ids', v_read)
  );
  end if;
  if jsonb_array_length(v_values) > 0 then
    perform "better_supabase"."record_subject_read"(read_field_values.subject_type, read_field_values.subject_id, null, 'custom-fields', 'read_field_values');
  end if;
  return v_values;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_subject_read (
  subject_type  text,
  subject_id    text,
  purpose       text DEFAULT NULL::text,
  block_name    text DEFAULT NULL::text,
  function_name text DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_emergency boolean;
  v_purpose text := nullif(btrim(record_subject_read.purpose), '');
begin
  if auth.uid() is null or not (record_subject_read.subject_type = any ('{customer}'::text[])) then
    return;
  end if;
  if length(v_purpose) > 500 then
    raise exception 'purpose takes at most 500 characters' using errcode = '22023', hint = 'SUBJECT_READ_INVALID';
  end if;
  begin
  case record_subject_read.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (record_subject_read.subject_id)::uuid and s."archived_at" is null;
    else
      v_tenant := null;
  end case;
  exception
    when invalid_text_representation then
      return;
  end;
  if v_tenant is null
    or not coalesce("better_supabase"."can_subject"(record_subject_read.subject_type, record_subject_read.subject_id, 'read'), false) then
    return;
  end if;
  v_emergency := exists (
    select 1 from "better_supabase"."subject_members" m
    where m."subject_type" = record_subject_read.subject_type
        and m."subject_id" = record_subject_read.subject_id
        and m."tenant_id" = v_tenant
      and m."emergency"
      and (m."user_id" = auth.uid() or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = auth.uid())))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
  );
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.record_subject_read'),
    pg_catalog.hashtext(auth.uid()::text || ':' || record_subject_read.subject_type || ':' || record_subject_read.subject_id));
  if exists (
    select 1 from "better_supabase"."audit_events" l
    where l."table_name" is null
        and l."record_id" = record_subject_read.subject_id
        and l."event_type" = 'subject.accessed'
        and l."organization_id" = v_tenant
        and l."metadata" ->> 'subjectType' = record_subject_read.subject_type
      and l."actor_id" = auth.uid()
      and l."occurred_at" > now() - make_interval(secs => 60)
      and coalesce((l."metadata" ->> 'emergency')::boolean, false) = v_emergency
      and l."metadata" ->> 'purpose' is not distinct from v_purpose
  ) then
    return;
  end if;
  perform better_supabase.audit_event(
    event_type => 'subject.accessed',
    category => 'read',
    target_type => 'subject',
    record_id => record_subject_read.subject_id,
    summary => 'Read ' || record_subject_read.subject_type || ' ' || record_subject_read.subject_id,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'subjectType', record_subject_read.subject_type, 'subjectId', record_subject_read.subject_id, 'purpose', v_purpose, 'emergency', v_emergency, 'block', record_subject_read.block_name, 'function', record_subject_read.function_name)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_summary (
  subject_type text,
  subject_id   text,
  sections     text[],
  seen_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
  v_seen timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > 20 then
    raise exception 'record_summary takes at most 20 sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not "better_supabase"."can_subject"(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
  perform "better_supabase"."record_subject_read"(record_summary.subject_type, record_summary.subject_id, null, 'subjects', 'record_summary');
  if 'comments' = any (record_summary.sections) then
    select count(*), max(x."sent_at")
      into v_count, v_latest
      from "better_supabase"."messages" x
      join "better_supabase"."conversations" c on c."id" = x."conversation_id"
        and c."kind" = 'subject'
      where c."subject_type"::text = record_summary.subject_type
        and c."subject_id"::text = record_summary.subject_id
        and x."sent_at" is not null and x."deleted_at" is null;
    v_seen := coalesce((select "better_supabase"."conversation_read_at"(c."id") from "better_supabase"."conversations" c
        where c."kind" = 'subject'
          and c."subject_type" = record_summary.subject_type
          and c."subject_id" = record_summary.subject_id), record_summary.seen_at);
    v_counts := v_counts || jsonb_build_object('comments', v_count);
    v_unread := v_unread || jsonb_build_object('comments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  if 'attachments' = any (record_summary.sections) then
    select count(*), max(x."uploaded_at")
      into v_count, v_latest
      from "better_supabase"."attachments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."uploaded_at" is not null and x."status" <> 'infected';
    v_seen := record_summary.seen_at;
    v_counts := v_counts || jsonb_build_object('attachments', v_count);
    v_unread := v_unread || jsonb_build_object('attachments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', "better_supabase"."subject_title"(record_summary.subject_type, record_summary.subject_id),
    'url', "better_supabase"."subject_url"(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_access_log (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (subject_access_log.subject_type = any ('{customer}'::text[])) then
    raise exception 'this subject type does not log reads' using errcode = '22023', hint = 'SUBJECT_READ_INVALID';
  end if;
  begin
  case subject_access_log.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (subject_access_log.subject_id)::uuid and s."archived_at" is null;
    else
      v_tenant := null;
  end case;
  exception
    when invalid_text_representation then
      v_tenant := null;
  end;
  if v_tenant is null then
    raise exception 'subject not found' using errcode = 'P0002', hint = 'SUBJECT_READ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or coalesce(better_supabase.can('tenant', v_tenant, 'audit.read'), false)
    or exists (
      select 1 from "better_supabase"."subject_members" m
      where m."subject_type" = subject_access_log.subject_type
        and m."subject_id" = subject_access_log.subject_id
        and m."tenant_id" = v_tenant
        and m."role" = 'lead'
        and (m."user_id" = auth.uid() or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = auth.uid())))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now()))
    or ((v_tenant)::text, (subject_access_log.subject_type)::text, (subject_access_log.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
    or exists (
      select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = v_tenant::text
        and r."target_type" = subject_access_log.subject_type and r."target_id" = subject_access_log.subject_id
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'you may not see who read this record' using errcode = '42501', hint = 'SUBJECT_READ_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(e.entry order by e.at desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
      'id', l."id"::text,
      'actorId', l."actor_id",
      'actorName', (select coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', u.email::text) from auth.users u where u.id = l."actor_id"),
      'at', l."occurred_at",
      'purpose', l."metadata" ->> 'purpose',
      'emergency', coalesce((l."metadata" ->> 'emergency')::boolean, false),
      'block', l."metadata" ->> 'block',
      'function', l."metadata" ->> 'function') as entry, l."occurred_at" as at
      from "better_supabase"."audit_events" l
      where l."table_name" is null
        and l."record_id" = subject_access_log.subject_id
        and l."event_type" = 'subject.accessed'
        and l."organization_id" = v_tenant
        and l."metadata" ->> 'subjectType' = subject_access_log.subject_type
        and (subject_access_log.since is null or l."occurred_at" >= subject_access_log.since)
      order by l."occurred_at" desc
      limit least(greatest(coalesce(subject_access_log.max_rows, 100), 1), 500)
    ) e
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."record_subject_read"(text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_subject_read"(text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."subject_access_log"(text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."subject_access_log"(text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_subject_read"(text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_subject_read"(text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_access_log"(text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_access_log"(text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";
