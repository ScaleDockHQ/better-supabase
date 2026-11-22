SET local check_function_bodies = off;

DROP FUNCTION "api"."cancel_approval"(uuid);

DROP FUNCTION "better_supabase"."cancel_approval"(uuid);

DROP FUNCTION "better_supabase"."workflow_purge_runs"(interval, text[], integer);

CREATE TABLE "workflow"."eve_session_runs" (
  "run_id"      text                     NOT NULL,
  "session_id"  text                     NOT NULL,
  "eve_version" text,
  "status"      text                     NOT NULL,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "eve_session_runs_pkey" PRIMARY KEY (run_id)
);

ALTER TABLE "workflow"."eve_session_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."eve_sessions" (
  "session_id"     text                     NOT NULL,
  "tenant_id"      text,
  "principal_kind" text,
  "principal_id"   text,
  "eve_version"    text,
  "chat_id"        text,
  "record_type"    text,
  "record_id"      text,
  "run_id"         text,
  "read_cursor"    bigint                   NOT NULL DEFAULT 0,
  "status"         text                     NOT NULL DEFAULT 'open'::text,
  "dirty_at"       timestamp with time zone,
  "synced_at"      timestamp with time zone,
  "lease_id"       text,
  "leased_at"      timestamp with time zone,
  "lease_until"    timestamp with time zone,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_eve_sessions_read_cursor_check" CHECK ((read_cursor >= 0)),
  CONSTRAINT "bsb_eve_sessions_session_id_check" CHECK (((length(session_id) >= 1) AND (length(session_id) <= 200))),
  CONSTRAINT "bsb_eve_sessions_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'ended'::text, 'failed'::text, 'cancelled'::text, 'stranded'::text]))),
  CONSTRAINT "eve_sessions_pkey" PRIMARY KEY (session_id)
);

ALTER TABLE "workflow"."eve_sessions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.cancel_approval (
  request_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_approval"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_approval (
  request_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = cancel_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'only the requester or a manager can cancel this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  perform "better_supabase".emit_event('approval.cancelled', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.cancelled',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'cancelled' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id" || coalesce(': ' || left(nullif(btrim(cancel_approval.reason), ''), 500), ''),
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  if v_req."subject_type" = 'leave_request' then
    perform "better_supabase"."leave_approval_decided"((case when v_req."subject_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_req."subject_id"::uuid end), 'cancelled', null, auth.uid())
    where exists (select 1 from "better_supabase"."leave_requests" x where x."id" = (case when v_req."subject_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_req."subject_id"::uuid end) and x."approval_id" = v_req."id");
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_open_sessions (
  not_version text    DEFAULT NULL::text,
  tenant      text    DEFAULT NULL::text,
  max         integer DEFAULT 100
)
  RETURNS TABLE (
    session_id   text,
    eve_version  text,
    tenant_id    text,
    principal_id text,
    chat_id      text,
    run_id       text,
    created_at   timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select s.session_id, s.eve_version, s.tenant_id, s.principal_id, s.chat_id, s.run_id, s.created_at
  from workflow.eve_sessions s
  where s.status = 'open'
    and (not_version is null or s.eve_version is distinct from not_version)
    and (tenant is null or s.tenant_id = tenant)
  order by s.created_at
  limit least(greatest(coalesce(max, 100), 1), 1000);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_session_commit (
  sid            text,
  token          text,
  cursor_line    bigint,
  tenant         text   DEFAULT NULL::text,
  principal_kind text   DEFAULT NULL::text,
  principal_id   text   DEFAULT NULL::text,
  chat           text   DEFAULT NULL::text,
  record_type    text   DEFAULT NULL::text,
  record_id      text   DEFAULT NULL::text,
  session_status text   DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if session_status is not null and session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_commit: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions s set
    read_cursor = greatest(s.read_cursor, coalesce(cursor_line, 0)),
    tenant_id = coalesce(tenant, s.tenant_id),
    principal_kind = coalesce(eve_session_commit.principal_kind, s.principal_kind),
    principal_id = coalesce(eve_session_commit.principal_id, s.principal_id),
    chat_id = coalesce(chat, s.chat_id),
    record_type = coalesce(eve_session_commit.record_type, s.record_type),
    record_id = coalesce(eve_session_commit.record_id, s.record_id),
    status = coalesce(session_status, s.status),
    synced_at = coalesce(s.leased_at, now()),
    lease_id = null,
    lease_until = null,
    updated_at = now()
  where s.session_id = sid and s.lease_id = token;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_session_lease (
  sid           text,
  lease_seconds integer DEFAULT 60
)
  RETURNS TABLE (
    session_id     text,
    tenant_id      text,
    principal_kind text,
    principal_id   text,
    eve_version    text,
    chat_id        text,
    record_type    text,
    record_id      text,
    run_id         text,
    read_cursor    bigint,
    status         text,
    lease_id       text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_token text := gen_random_uuid()::text;
begin
  insert into workflow.eve_sessions (session_id) values (sid) on conflict (session_id) do nothing;
  return query
    update workflow.eve_sessions s set
      lease_id = v_token,
      leased_at = now(),
      lease_until = now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1)),
      updated_at = now()
    where s.session_id = sid and (s.lease_until is null or s.lease_until < now())
    returning s.session_id, s.tenant_id, s.principal_kind, s.principal_id, s.eve_version, s.chat_id,
      s.record_type, s.record_id, s.run_id, s.read_cursor, s.status, s.lease_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_session_mark (
  sid            text,
  session_status text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_mark: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions set status = session_status, updated_at = now() where session_id = sid;
  if not found then
    return false;
  end if;
  perform "better_supabase"."eve_session_wake"(sid, 0);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_session_release (
  sid   text,
  token text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  update workflow.eve_sessions set lease_id = null, lease_until = null, updated_at = now()
  where session_id = sid and lease_id = token
  returning true;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_session_wake (
  sid           text,
  delay_seconds integer DEFAULT 2
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into workflow.eve_sessions as s (session_id, dirty_at) values (sid, now())
  on conflict (session_id) do update set dirty_at = now(), updated_at = now();
  perform "better_supabase"."enqueue_job"(queue => 'eve_session_sync', payload => jsonb_build_object('sessionId', sid), delay => greatest(coalesce(delay_seconds, 0), 0), dedupe_key => 'eve:' || sid, dedupe_running => false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eve_sessions_behind (
  older_than interval DEFAULT '00:05:00'::interval,
  max        integer  DEFAULT 100
)
  RETURNS TABLE (
    session_id text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select s.session_id
  from workflow.eve_sessions s
  where (s.lease_until is null or s.lease_until < now())
    and (
      (s.dirty_at is not null and (s.synced_at is null or s.synced_at < s.dirty_at))
      or (s.status = 'open' and coalesce(s.synced_at, s.created_at) < now() - coalesce(older_than, interval '5 minutes'))
    )
  order by coalesce(s.synced_at, s.created_at)
  limit least(greatest(coalesce(max, 100), 1), 1000);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_purge_runs (
  older_than       interval DEFAULT '30 days'::interval,
  statuses         text[]   DEFAULT ARRAY['completed'::text,
  'failed'::text,
  'cancelled'::text],
  batch            integer  DEFAULT 500,
  skip_unprojected boolean  DEFAULT false
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_statuses text[] := coalesce(statuses, array['completed', 'failed', 'cancelled']);
  v_ids text[];
  v_count integer;
begin
  if exists (select 1 from unnest(v_statuses) s where s not in ('completed', 'failed', 'cancelled')) then
    raise exception 'workflow_purge_runs deletes only completed, failed or cancelled runs'
      using errcode = '22023', hint = 'WORKFLOW_PURGE_STATUS';
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.status::text = any (v_statuses)
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
      and not (coalesce(skip_unprojected, false) and exists (
        select 1 from workflow.eve_session_runs sr
        join workflow.eve_sessions es on es.session_id = sr.session_id
        where sr.run_id = r.id
          and (es.status = 'open' or es.synced_at is null or es.dirty_at > es.synced_at)
      ))
    order by coalesce(r.completed_at, r.updated_at)
    limit least(greatest(coalesce(batch, 500), 1), 10000)
    for update skip locked
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  delete from workflow.workflow_events where run_id = any (v_ids);
  delete from workflow.workflow_event_slots where run_id = any (v_ids);
  delete from workflow.workflow_steps where run_id = any (v_ids);
  delete from workflow.workflow_waits where run_id = any (v_ids);
  delete from workflow.workflow_stream_chunks where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  delete from workflow.workflow_invocations where run_id = any (v_ids);
  delete from workflow.workflow_hooks
    where run_id = any (v_ids) and (token_retention_until is null or token_retention_until < now());
  delete from workflow.workflow_run_keys where run_id = any (v_ids);
  delete from workflow.eve_session_runs where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_track_eve_run()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_session text;
  v_status text;
begin
  if new.attributes ->> '$eve.type' is distinct from 'session' and nullif(new.attributes ->> '$eve.session', '') is null then
    return null;
  end if;
  v_session := coalesce(nullif(new.attributes ->> '$eve.session', ''), new.id);
  v_status := case new.status::text
    when 'completed' then 'ended'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'open'
  end;
  insert into workflow.eve_sessions as s (session_id, eve_version, run_id, status)
  values (v_session, new.attributes ->> '$eve.version', new.id, v_status)
  on conflict (session_id) do update set
    eve_version = coalesce(new.attributes ->> '$eve.version', s.eve_version),
    run_id = new.id,
    status = case when s.status = 'stranded' then s.status else v_status end,
    updated_at = now()
  where s.run_id is null or s.run_id = new.id
    or new.created_at >= coalesce((select r.created_at from workflow.workflow_runs r where r.id = s.run_id), '-infinity'::timestamptz);
  insert into workflow.eve_session_runs as sr (run_id, session_id, eve_version, status)
  values (new.id, v_session, new.attributes ->> '$eve.version', new.status::text)
  on conflict (run_id) do update set status = new.status::text, updated_at = now();
  perform "better_supabase"."eve_session_wake"(v_session);
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_wake_eve_session()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_session text;
begin
  select sr.session_id into v_session from workflow.eve_session_runs sr where sr.run_id = new.run_id;
  if v_session is not null then
    perform "better_supabase"."eve_session_wake"(v_session);
  end if;
  return null;
end;
$function$;

ALTER TABLE "workflow"."eve_session_runs"
  ADD CONSTRAINT "eve_session_runs_session_id_fkey" FOREIGN KEY (session_id) REFERENCES workflow.eve_sessions(session_id) ON DELETE CASCADE;

CREATE INDEX eve_session_runs_session_idx ON workflow.eve_session_runs USING btree (session_id);

CREATE INDEX eve_sessions_dirty_idx ON workflow.eve_sessions USING btree (dirty_at)
  WHERE (dirty_at IS NOT NULL);

CREATE INDEX eve_sessions_open_idx ON workflow.eve_sessions USING btree (eve_version)
  WHERE (status = 'open'::text);

CREATE TRIGGER bsb_workflow_sdk_eve_events
  AFTER INSERT ON workflow.workflow_events
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_sdk_wake_eve_session();

CREATE TRIGGER bsb_workflow_sdk_eve_runs
  AFTER INSERT OR UPDATE OF status ON workflow.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_sdk_track_eve_run();

REVOKE ALL ON FUNCTION "api"."cancel_approval"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_approval"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_approval"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_approval"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_open_sessions"(text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_open_sessions"(text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_session_lease"(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_session_lease"(text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_session_mark"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_session_mark"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_session_release"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_session_release"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_session_wake"(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_session_wake"(text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eve_sessions_behind"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eve_sessions_behind"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_sdk_track_eve_run"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."workflow_sdk_wake_eve_session"() FROM PUBLIC;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."eve_session_runs" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."eve_sessions" TO "service_role";
