SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."purge_notifications"(interval, integer);

CREATE OR REPLACE FUNCTION better_supabase.purge_ai_chats (
  batch integer DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  with doomed as (
    select x."id" from "better_supabase"."ai_chats" x
    where x."is_temporary" and x."expires_at" <= now()
      and not false
    limit greatest(coalesce(purge_ai_chats.batch, 1000), 1)
  )
  delete from "better_supabase"."ai_chats" c using doomed where c."id" = doomed."id";
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_audit_log (
  older_than interval DEFAULT '1 year'::interval,
  batch      integer  DEFAULT 10000,
  tenant     uuid     DEFAULT NULL::uuid,
  for_tenant boolean  DEFAULT false
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  purged integer := 0;
  gone integer;
  v_tenant uuid;
  v_older interval;
begin
  perform set_config('better_supabase.audit_purge', 'on', true);
  if not for_tenant and to_regprocedure('"public"."audit_retention"(uuid)') is not null then
    -- One delete per tenant with that tenant's interval as a constant, so
    -- each runs on the (tenant, occurred_at) index. The tenants come from a
    -- skip scan of that index, not a scan of the log.
    for v_tenant in
      with recursive t (v) as (
        (select l."organization_id" from "better_supabase"."audit_events" l where l."organization_id" is not null order by l."organization_id" limit 1)
        union all
        select (select l."organization_id" from "better_supabase"."audit_events" l where l."organization_id" > t.v order by l."organization_id" limit 1)
        from t where t.v is not null
      )
      select t.v from t where t.v is not null
    loop
      exit when purged >= batch;
      continue when false;
      -- Not a literal name, so plpgsql_check passes without the hook.
      execute format('select %s($1)', to_regprocedure('"public"."audit_retention"(uuid)')::oid::regproc)
        into v_older using v_tenant;
      v_older := coalesce(v_older, older_than);
      with deleted as (
        delete from "better_supabase"."audit_events"
        where "id" in (
          select l."id" from "better_supabase"."audit_events" l
          where l."organization_id" = v_tenant and l."occurred_at" < now() - v_older
          order by l."occurred_at"
          limit batch - purged
        )
        returning 1
      )
      select count(*)::integer into gone from deleted;
      purged := purged + gone;
    end loop;
    if purged < batch then
      with deleted as (
        delete from "better_supabase"."audit_events"
        where "id" in (
          select l."id" from "better_supabase"."audit_events" l
          where l."organization_id" is null and l."occurred_at" < now() - older_than
          order by l."occurred_at"
          limit batch - purged
        )
        returning 1
      )
      select count(*)::integer into gone from deleted;
      purged := purged + gone;
    end if;
  else
    with deleted as (
      delete from "better_supabase"."audit_events"
      where "id" in (
        select l."id" from "better_supabase"."audit_events" l
        where l."occurred_at" < now() - older_than
          and (not for_tenant or l."organization_id" is not distinct from purge_audit_log.tenant)
        order by l."occurred_at"
        limit greatest(batch - purged, 0)
      )
      returning 1
    )
    select purged + count(*)::integer into purged from deleted;
  end if;
  perform set_config('better_supabase.audit_purge', 'off', true);
  return purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_job_archive (
  queue           text,
  older_than      interval DEFAULT '7 days'::interval,
  batch           integer  DEFAULT 10000,
  dead_older_than interval DEFAULT '30 days'::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  purged integer;
begin
  null;
  execute format(
    'with purged as (delete from pgmq.%1$I where msg_id in (select a.msg_id from pgmq.%1$I a where a.archived_at < now() - case when a.message ? ''dead'' then $3 else $1 end order by a.msg_id limit $2) returning 1) select count(*)::integer from purged',
    'a_' || queue
  ) into purged using older_than, batch, dead_older_than;
  return purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_notifications (
  older_than interval DEFAULT '90 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare v_purged integer;
begin
  delete from "better_supabase"."notification_events"
  where "id" in (
    select ev."id" from "better_supabase"."notification_events" ev
    where ev."created_at" < now() - coalesce(older_than, '90 days')
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."purge_notifications"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_notifications"(interval, integer) TO "service_role";
