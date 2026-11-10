SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.is_held_memo (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."is_held_memo"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.retention_for_memo (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS interval
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."retention_for_memo"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.is_held_memo (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_key text := 'ih' || md5(statement_timestamp()::text || is_held_memo.kind || coalesce(is_held_memo.tenant, ''));
  v_memo text := better_supabase.memo_get(v_key);
  v_held boolean;
begin
  if v_memo is not null then
    return v_memo = 't';
  end if;
  v_held := "better_supabase"."is_held"(is_held_memo.kind, is_held_memo.tenant);
  perform better_supabase.memo_set(v_key, case when v_held then 't' else 'f' end);
  return v_held;
end;
$function$;

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
      and not "better_supabase"."is_held_memo"('ai_chats', (x."tenant_id")::text)
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
        (select l."tenant_id" from "better_supabase"."audit_events" l where l."tenant_id" is not null order by l."tenant_id" limit 1)
        union all
        select (select l."tenant_id" from "better_supabase"."audit_events" l where l."tenant_id" > t.v order by l."tenant_id" limit 1)
        from t where t.v is not null
      )
      select t.v from t where t.v is not null
    loop
      exit when purged >= batch;
      continue when "better_supabase"."is_held_memo"('audit', (v_tenant)::text);
      -- Not a literal name, so plpgsql_check passes without the hook.
      execute format('select %s($1)', to_regprocedure('"public"."audit_retention"(uuid)')::oid::regproc)
        into v_older using v_tenant;
      v_older := coalesce(v_older, coalesce("better_supabase"."retention_for_memo"('audit', (v_tenant)::text), older_than));
      with deleted as (
        delete from "better_supabase"."audit_events"
        where "id" in (
          select l."id" from "better_supabase"."audit_events" l
          where l."tenant_id" = v_tenant and l."occurred_at" < now() - v_older
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
          where l."tenant_id" is null and (l."occurred_at" < now() - least(older_than, "better_supabase"."retention_floor"('audit'))
      and l."occurred_at" < now() - coalesce("better_supabase"."retention_for_memo"('audit', (null)::text), older_than)
      and not "better_supabase"."is_held_memo"('audit', (null)::text))
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
        where (l."occurred_at" < now() - least(older_than, "better_supabase"."retention_floor"('audit'))
      and l."occurred_at" < now() - coalesce("better_supabase"."retention_for_memo"('audit', (l."tenant_id")::text), older_than)
      and not "better_supabase"."is_held_memo"('audit', (l."tenant_id")::text))
          and (not for_tenant or l."tenant_id" is not distinct from purge_audit_log.tenant)
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

CREATE OR REPLACE FUNCTION better_supabase.purge_expired_trash (
  max_batches integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch uuid;
  v_count integer := 0;
begin
  for v_batch in
    select t."batch_id" from "better_supabase"."trash_items" t
    where t."depth" = 0 and t."purge_at" <= now()
      and not "better_supabase"."is_held_memo"('trash', (t."tenant_id")::text)
    order by t."purge_at"
    limit greatest(coalesce(purge_expired_trash.max_batches, 100), 1)
  loop
    v_count := v_count + "better_supabase"."trash_purge_batch"(v_batch);
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_inbound_events (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."inbox_inbound_events" e where e."id" in (
    select x."id" from "better_supabase"."inbox_inbound_events" x
    where (x."received_at" < now() - least(coalesce(older_than, interval '30 days'), "better_supabase"."retention_floor"('inbound_events'))
      and x."received_at" < now() - coalesce("better_supabase"."retention_for_memo"('inbound_events', (x."tenant_id")::text), coalesce(older_than, interval '30 days'))
      and not "better_supabase"."is_held_memo"('inbound_events', (x."tenant_id")::text))
      and x."status" in ('processed', 'ignored')
    limit greatest(coalesce(batch, 1000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
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
  if "better_supabase"."is_held_memo"('job_archive', (null)::text) then
    return 0;
  end if;
  older_than := coalesce("better_supabase"."retention_for_memo"('job_archive', (null)::text), older_than);
  dead_older_than := coalesce("better_supabase"."retention_for_memo"('job_archive', (null)::text), dead_older_than);
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
    where (ev."created_at" < now() - least(coalesce(older_than, '90 days'), "better_supabase"."retention_floor"('notifications'))
      and ev."created_at" < now() - coalesce("better_supabase"."retention_for_memo"('notifications', (ev."tenant_id")::text), coalesce(older_than, '90 days'))
      and not "better_supabase"."is_held_memo"('notifications', (ev."tenant_id")::text))
    order by ev."created_at"
    limit coalesce(batch, 10000)
  );
  get diagnostics v_purged = row_count;
  return v_purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_outbox (
  older_than  interval DEFAULT '30 days'::interval,
  batch       integer  DEFAULT 10000,
  ignore_idle interval DEFAULT NULL::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_purged integer;
begin
  with active as (
    select k."cursor_xid", k."cursor_position" from "better_supabase"."outbox_consumers" k
    where ignore_idle is null or k."updated_at" >= now() - ignore_idle
  ),
  letters as (
    delete from "better_supabase"."outbox_dead_letters" x
    where (x."dead_at" < now() - least(coalesce(older_than, '30 days'::interval), "better_supabase"."retention_floor"('outbox'))
      and x."dead_at" < now() - coalesce("better_supabase"."retention_for_memo"('outbox', (null)::text), coalesce(older_than, '30 days'::interval))
      and not "better_supabase"."is_held_memo"('outbox', (null)::text))
  ),
  gone as (
    delete from "better_supabase"."outbox_events" e
    where e."id" in (
      select d."id" from "better_supabase"."outbox_events" d
      where (d."created_at" < now() - least(coalesce(older_than, '30 days'::interval), "better_supabase"."retention_floor"('outbox'))
      and d."created_at" < now() - coalesce("better_supabase"."retention_for_memo"('outbox', (d."tenant_id")::text), coalesce(older_than, '30 days'::interval))
      and not "better_supabase"."is_held_memo"('outbox', (d."tenant_id")::text))
        and (
          not exists (select 1 from active)
          or (d."xid", d."position") <= (
            select a."cursor_xid", a."cursor_position" from active a
            order by a."cursor_xid", a."cursor_position"
            limit 1
          )
        )
      order by d."created_at"
      limit coalesce(batch, 10000)
    )
    returning 1
  )
  select count(*)::integer into v_purged from gone;
  return v_purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_usage_history (
  older_than interval DEFAULT '400 days'::interval,
  batch      integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  purged integer;
begin
  with gone as (
    delete from "better_supabase"."usage_history" where "id" in (
      select h."id" from "better_supabase"."usage_history" h
      where (h."recorded_at" < now() - least(older_than, "better_supabase"."retention_floor"('usage'))
      and h."recorded_at" < now() - coalesce("better_supabase"."retention_for_memo"('usage', (h."tenant_id")::text), older_than)
      and not "better_supabase"."is_held_memo"('usage', (h."tenant_id")::text))
      order by h."id" limit batch
    )
    returning 1
  )
  select count(*)::integer into purged from gone;
  return purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_webhook_deliveries (
  older_than   interval DEFAULT '30 days'::interval,
  include_dead boolean  DEFAULT false,
  batch        integer  DEFAULT 10000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_purged integer;
begin
  with purged as (
    delete from "better_supabase"."webhook_deliveries"
    where "id" in (
      select v."id" from "better_supabase"."webhook_deliveries" v
      where (v."created_at" < now() - least(purge_webhook_deliveries.older_than, "better_supabase"."retention_floor"('webhook_deliveries'))
      and v."created_at" < now() - coalesce("better_supabase"."retention_for_memo"('webhook_deliveries', (v."tenant_id")::text), purge_webhook_deliveries.older_than)
      and not "better_supabase"."is_held_memo"('webhook_deliveries', (v."tenant_id")::text))
        and (
          v."status" in ('succeeded', 'canceled')
          or (purge_webhook_deliveries.include_dead and v."status" = 'dead')
        )
      limit purge_webhook_deliveries.batch
    )
    returning 1
  )
  select count(*)::integer into v_purged from purged;
  return v_purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_workflow_runs (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_runs integer;
begin
  with doomed as (
    select "id" from "better_supabase"."workflow_runs"
    where "status" in ('completed', 'failed', 'cancelled')
      and (coalesce("completed_at", "updated_at") < now() - least(coalesce(older_than, interval '30 days'), "better_supabase"."retention_floor"('workflow_runs'))
      and coalesce("completed_at", "updated_at") < now() - coalesce("better_supabase"."retention_for_memo"('workflow_runs', ("tenant_id")::text), coalesce(older_than, interval '30 days'))
      and not "better_supabase"."is_held_memo"('workflow_runs', ("tenant_id")::text))
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."workflow_runs" x using doomed where x."id" = doomed."id";
  get diagnostics v_runs = row_count;
  with doomed as (
    select "id" from "better_supabase"."workflow_start_requests"
    where "status" <> 'pending'
      and "created_at" < now() - coalesce(older_than, interval '30 days')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."workflow_start_requests" x using doomed where x."id" = doomed."id";
  delete from "better_supabase"."workflow_semaphores" where "expires_at" < now();
  return v_runs;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.retention_for_memo (
  kind   text,
  tenant text DEFAULT NULL::text
)
  RETURNS interval
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_key text := 'rf' || md5(statement_timestamp()::text || retention_for_memo.kind || coalesce(retention_for_memo.tenant, ''));
  v_memo text := better_supabase.memo_get(v_key);
  v_keep interval;
begin
  if v_memo is not null then
    return nullif(v_memo, '-')::interval;
  end if;
  v_keep := "better_supabase"."retention_for"(retention_for_memo.kind, retention_for_memo.tenant);
  perform better_supabase.memo_set(v_key, coalesce(v_keep::text, '-'));
  return v_keep;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."is_held_memo"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."is_held_memo"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."retention_for_memo"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."retention_for_memo"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."is_held_memo"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."is_held_memo"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."retention_for_memo"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."retention_for_memo"(text, text) TO "service_role";
