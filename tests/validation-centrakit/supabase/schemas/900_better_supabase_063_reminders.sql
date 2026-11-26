-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:a2aac760870403476c7fac16d52261b24a197e2a3f5f9f46002ff20792329cf3
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- centrakit.recurrence_rules is the app's table, and it has every column this block needs.
alter table "centrakit"."recurrence_rules" enable row level security;
grant select on "centrakit"."recurrence_rules" to authenticated;
grant all on "centrakit"."recurrence_rules" to service_role;
create index if not exists "recurrence_rules_subject_idx" on "centrakit"."recurrence_rules" ("subject_type", "subject_id");
-- centrakit.reminders is the app's table, and it has every column this block needs.
alter table "centrakit"."reminders" add column if not exists "remind_at" timestamptz;
alter table "centrakit"."reminders" enable row level security;
grant select on "centrakit"."reminders" to authenticated;
grant all on "centrakit"."reminders" to service_role;
create index if not exists "reminders_subject_idx" on "centrakit"."reminders" ("subject_type", "subject_id");
create index if not exists "reminders_tenant_idx" on "centrakit"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
-- centrakit.reminder_deliveries is the app's table, and it has every column this block needs.
alter table "centrakit"."reminder_deliveries" enable row level security;
grant select on "centrakit"."reminder_deliveries" to authenticated;
grant all on "centrakit"."reminder_deliveries" to service_role;
create or replace function "better_supabase"."upsert_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', upsert_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  if not (auth.role() = 'service_role')
    and upsert_reminder.subject_type in ('message', 'conversation', 'file_node', 'task', 'project', 'customer')
    and not (case upsert_reminder.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (upsert_reminder.subject_id)::uuid and s."tenant_id" = upsert_reminder.tenant) and coalesce(better_supabase.can('tenant', upsert_reminder.tenant, 'comments.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (upsert_reminder.subject_id)::uuid and s."tenant_id" = upsert_reminder.tenant) and coalesce(better_supabase.can('tenant', upsert_reminder.tenant, 'comments.read'), false)
    when 'file_node' then exists (select 1 from "centrakit"."file_node" s where s."id" = (upsert_reminder.subject_id)::uuid and s."organization_id" = upsert_reminder.tenant and (coalesce(better_supabase.can('tenant', upsert_reminder.tenant, 'fileNode.read'), false) or s."id"::text in (select r.id::text from centrakit.authz_file_node_rows('fileNode.read', array[s."id"::text]) as r(id))))
    when 'task' then exists (select 1 from "centrakit"."tasks" s where s."id" = (upsert_reminder.subject_id)::uuid and s."organization_id" = upsert_reminder.tenant)
    when 'project' then exists (select 1 from "centrakit"."projects" s where s."id" = (upsert_reminder.subject_id)::uuid and s."organization_id" = upsert_reminder.tenant)
    when 'customer' then exists (select 1 from "centrakit"."customers" s where s."id" = (upsert_reminder.subject_id)::bigint and s."organization_id" = upsert_reminder.tenant)
    else false
  end) then
    raise exception 'the record was not found in this organization' using errcode = 'P0002', hint = 'REMINDER_SUBJECT_NOT_FOUND';
  end if;
  insert into "centrakit"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (upsert_reminder.tenant, upsert_reminder.subject_type, upsert_reminder.subject_id, auth.uid(), coalesce(upsert_reminder.offset_minutes, 0), upsert_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."upsert_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."upsert_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, or on every subject when both are
-- null, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'subjectType', r."subject_type",
      'subjectId', r."subject_id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "centrakit"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and (list_my_reminders.subject_type is null
        or r."subject_type" = list_my_reminders.subject_type)
      and (list_my_reminders.subject_id is null
        or r."subject_id" = list_my_reminders.subject_id)
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- The caller's reminders in the tenant as a keyset page, the earliest before
-- the occurrence first (ADR 1077). filters is { subjectType, subjectId, method
-- (each a value or a list), sort (offsetMinutes, subjectType), direction,
-- facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_my_reminders"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_my_reminders.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('method', 'subjectType') then
      raise exception 'facet is one of method, subjectType' using errcode = '22023', hint = 'REMINDER_INVALID';
    end if;
    with s as (
      select (case v_facet when 'method' then (x."method")::text when 'subjectType' then (x."subject_type")::text end) as v
      from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('offsetMinutes', 'subjectType') then
    raise exception 'sort is one of offsetMinutes, subjectType' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."offset_minutes" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes" <= (v_after ->> 0)::integer and ((x."offset_minutes" < (v_after ->> 0)::integer) or (x."offset_minutes" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."offset_minutes" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'offsetMinutes' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes", x."id") > ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."offset_minutes" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'offsetMinutes' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."offset_minutes")::text, (x."id")::text) as k
    from (
      select * from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."offset_minutes" <= (v_after ->> 0)::integer and ((x."offset_minutes" < (v_after ->> 0)::integer) or (x."offset_minutes" = (v_after ->> 0)::integer and x."id" > (v_after ->> 1)::uuid))))
      order by x."offset_minutes" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subjectType' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."subject_type")::text, (x."id")::text) as k
    from (
      select * from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."subject_type", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."subject_type" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subjectType' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'REMINDER_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'method', x."method", 'offsetMinutes', x."offset_minutes", 'remindAt', x."remind_at") as j, jsonb_build_array((x."subject_type")::text, (x."id")::text) as k
    from (
      select * from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
        and (v_after is null or (x."subject_type" <= (v_after ->> 0)::text and ((x."subject_type" < (v_after ->> 0)::text) or (x."subject_type" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."subject_type" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "centrakit"."reminders" x
      where x."tenant_id" = page_my_reminders.tenant
        and x."user_id" = auth.uid()
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or (x."subject_type")::text = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or (x."subject_id")::text = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'method' is not null and jsonb_typeof(v_filters -> 'method') <> 'null' and not (jsonb_typeof(v_filters -> 'method') = 'array' and jsonb_array_length(v_filters -> 'method') = 0)) or (x."method")::text = any((case when jsonb_typeof(v_filters -> 'method') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'method')) else array[v_filters ->> 'method'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_my_reminders"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_my_reminders"(uuid, jsonb) to authenticated, service_role;

-- One of the caller's reminders, or null.
create or replace function "better_supabase"."get_my_reminder"(reminder uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', r."id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'method', r."method", 'offsetMinutes', r."offset_minutes", 'remindAt', r."remind_at")
  from "centrakit"."reminders" r
  where r."id" = get_my_reminder.reminder
    and r."user_id" = auth.uid()
    and coalesce(better_supabase.can('tenant', r."tenant_id", 'reminders.manage'), false);
$$;
revoke execute on function "better_supabase"."get_my_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."get_my_reminder"(uuid) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "centrakit"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "centrakit"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "centrakit"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "centrakit"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('reminder.sent', jsonb_build_object('organizationId', v_tenant, 'id', mark_reminder_sent.reminder, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'userId', v_user), 'reminders/' || mark_reminder_sent.reminder::text, (v_tenant)::text, null, 'domain');
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).

create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "centrakit"."reminders" r
  join "centrakit"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "centrakit"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "centrakit"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "centrakit"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "centrakit"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "centrakit"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "centrakit"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on "centrakit"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "centrakit"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "centrakit"."reminders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
