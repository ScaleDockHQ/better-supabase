SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.get_incident (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'title', x."title", 'description', x."description", 'severity', x."severity", 'status', x."status", 'public', x."public", 'commanderId', x."commander_id", 'startedAt', x."started_at", 'resolvedAt', x."resolved_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'impacts', (select coalesce(jsonb_agg(jsonb_build_object('componentId', im."component_id", 'name', ic."name", 'impact', im."impact") order by ic."position", ic."name"), '[]'::jsonb) from "better_supabase"."incident_impacts" im join "better_supabase"."incident_status_components" ic on ic."id" = im."component_id" where im."incident_id" = x."id")) || jsonb_build_object(
    'updates', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'incidentId', y."incident_id", 'status', y."status", 'body', y."body", 'public', y."public", 'authorId', y."author_id", 'createdAt', y."created_at") order by y."created_at", y."id"), '[]'::jsonb) from "better_supabase"."incident_updates" y where y."incident_id" = x."id"),
    'postmortem', (select jsonb_build_object('id', z."id", 'incidentId', z."incident_id", 'summary', z."summary", 'impact', z."impact", 'rootCause', z."root_cause", 'resolution', z."resolution", 'actions', "better_supabase"."incident_postmortem_action_list"(z."id"), 'status', z."status", 'publishedAt', z."published_at", 'authorId', z."author_id", 'createdAt', z."created_at", 'updatedAt', z."updated_at") from "better_supabase"."incident_postmortems" z where z."incident_id" = x."id")
  )
  from "better_supabase"."incidents" x
  where x."id" = get_incident.incident_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_incident_postmortem (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = publish_incident_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.manage'), false)) then
    raise exception 'not allowed to publish postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if v_row."status" <> 'resolved' then
    raise exception 'only a resolved incident''s postmortem can be published' using errcode = '55000', hint = 'INCIDENT_NOT_RESOLVED';
  end if;
  update "better_supabase"."incident_postmortems" x set "status" = 'published', "published_at" = coalesce(x."published_at", now()), "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  if not found then
    raise exception 'the incident has no postmortem' using errcode = 'P0002', hint = 'INCIDENT_POSTMORTEM_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('incident_postmortem.published', jsonb_build_object('organizationId', v_row."tenant_id", 'postmortemId', v_post."id", 'incidentId', v_row."id"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident_postmortem.published',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'published the postmortem of incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'postmortemId', v_post."id", 'incidentId', v_row."id")
  );
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actions', "better_supabase"."incident_postmortem_action_list"(v_post."id"), 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_incident_postmortem_action (
  action_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_action "better_supabase"."incident_postmortem_actions"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_action from "better_supabase"."incident_postmortem_actions" x where x."id" = remove_incident_postmortem_action.action_id;
  if not found then
    raise exception 'postmortem action not found' using errcode = 'P0002', hint = 'INCIDENT_POSTMORTEM_ACTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_action."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to write postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  delete from "better_supabase"."incident_postmortem_actions" x where x."id" = v_action."id";
  select * into v_post from "better_supabase"."incident_postmortems" x where x."id" = v_action."postmortem_id";
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actions', "better_supabase"."incident_postmortem_action_list"(v_post."id"), 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_incident_postmortem (
  incident_id uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = save_incident_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.write'), false)) then
    raise exception 'not allowed to write postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if jsonb_typeof(save_incident_postmortem.attrs) is distinct from 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  if save_incident_postmortem.attrs ? 'actionItems' then
    raise exception 'actionItems was removed: add_incident_postmortem_action writes action items as tasks' using errcode = '22023', hint = 'INCIDENTS_INVALID';
  end if;
  insert into "better_supabase"."incident_postmortems" ("tenant_id", "incident_id", "author_id")
  values (v_row."tenant_id", v_row."id", auth.uid())
  on conflict ("incident_id") do nothing;
  update "better_supabase"."incident_postmortems" x set
    "summary" = case when save_incident_postmortem.attrs ? 'summary' then save_incident_postmortem.attrs ->> 'summary' else x."summary" end,
    "impact" = case when save_incident_postmortem.attrs ? 'impact' then save_incident_postmortem.attrs ->> 'impact' else x."impact" end,
    "root_cause" = case when save_incident_postmortem.attrs ? 'rootCause' then save_incident_postmortem.attrs ->> 'rootCause' else x."root_cause" end,
    "resolution" = case when save_incident_postmortem.attrs ? 'resolution' then save_incident_postmortem.attrs ->> 'resolution' else x."resolution" end,
    "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actions', "better_supabase"."incident_postmortem_action_list"(v_post."id"), 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
end;
$function$;
