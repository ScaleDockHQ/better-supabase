SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.comments_json (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    with e as materialized (
      select x.row, x.n from jsonb_array_elements("better_supabase"."messaging_messages_json"(comments_json.ids)) with ordinality x(row, n)
    ),
    c as materialized (
      select c."id" as id, c."subject_type" as subject_type, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."id" = any (array(select distinct (e.row ->> 'conversation_id')::uuid from e))
    ),
    t as materialized (
      select t."message_id" as message, t."task_id" as task from "better_supabase"."comment_tasks" t
      where t."message_id" = any (comments_json.ids)
    )
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.subject_type,
      'subject_id', c.subject_id,
      'task_id', t.task
    ) order by e.n), '[]'::jsonb)
    from e
    join c on c.id = (e.row ->> 'conversation_id')::uuid
    left join t on t.message = (e.row ->> 'id')::uuid
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.message_authors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(y."id"::text, jsonb_build_object('id', pr."id", 'name', coalesce(nullif(pr."full_name", ''), nullif(trim(concat_ws(' ', pr."first_name", pr."last_name")), ''), pr."username"), 'avatarUrl', pr."avatar_url")), '{}'::jsonb)
  from "better_supabase"."messages" y
  join "better_supabase"."profiles" pr on pr."id" = y."author_id"
  where y."id" = any ($1)
    and y."conversation_id" = any (array(select c."id" from "better_supabase"."conversations" c where c."id" = any (array(select distinct v."conversation_id" from "better_supabase"."messages" v where v."id" = any ($1))) and (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else ((coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    or (c."access" = 'subject' and c."subject_type" in ('drive_node')))
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end)
    or (c."kind" = 'subject' and ((c."tenant_id")::text, (c."subject_type")::text, (c."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) end)))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_overview (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.read'), false)) then
    raise exception 'Not allowed to read usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  return (
    with scoped as materialized (
      select q.* from "better_supabase"."usage_quotas" q
      where q."tenant_id" = usage_overview.tenant
        or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any ((select better_supabase.tenant_entitlements(usage_overview.tenant))::text[]) or q."plan" = any ((select better_supabase.tenant_plans(usage_overview.tenant))::text[])))
    ),
    meters as (
      select jsonb_object_keys("better_supabase"."usage_meters"()) as meter
      union
      select q."meter" from scoped q
      union
      select distinct c."meter" from "better_supabase"."usage_counters" c
      where c."tenant_id" = usage_overview.tenant
    ),
    quota as (
      select distinct on (q."meter")
        q."meter" as meter,
        q."limit" as quota_limit,
        q."period" as period
      from scoped q
      join meters m on m.meter = q."meter"
      order by q."meter", (q."tenant_id" is not null) desc, q."limit" desc nulls first
    ),
    chosen as (
      select m.meter,
        quota.quota_limit,
        quota.period as quota_period,
        coalesce(quota.period, 'month') as period
      from meters m
      left join quota on quota.meter = m.meter
    ),
    win as (
      select p.period, w.starts_at, w.ends_at
      from (select distinct chosen.period from chosen) p
      cross join lateral "better_supabase"."usage_window"(usage_overview.tenant, p.period) w
    ),
    used as (
      select ch.meter, coalesce(sum(c."value"), 0)::numeric as used
      from chosen ch
      join win w on w.period = ch.period
      left join "better_supabase"."usage_counters" c
        on c."tenant_id" = usage_overview.tenant
        and c."meter" = ch.meter
        and c."day" >= (w.starts_at at time zone 'utc')::date
        and c."day" < greatest((w.ends_at at time zone 'utc')::date, (w.starts_at at time zone 'utc')::date + 1)
      group by ch.meter
    ),
    catalog as (
      select "better_supabase"."usage_meters"() as meters
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'meter', ch.meter,
        'used', u.used,
        'limit', ch.quota_limit,
        'remaining', case
          when ch.quota_limit is null then null
          else greatest(ch.quota_limit - u.used, 0)
        end,
        'unlimited', ch.quota_period is not null and ch.quota_limit is null,
        'period', ch.period,
        'resets_at', w.ends_at,
        'starts_at', w.starts_at
      ) || coalesce(catalog.meters -> ch.meter, '{}'::jsonb)
      order by ch.meter
    ), '[]'::jsonb)
    from chosen ch
    join used u on u.meter = ch.meter
    join win w on w.period = ch.period
    cross join catalog
  );
end;
$function$;
