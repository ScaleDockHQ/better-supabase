SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_agent"(uuid);

DROP FUNCTION "api"."list_agents"(uuid, text, text, integer);

DROP FUNCTION "better_supabase"."delete_agent"(uuid);

DROP FUNCTION "better_supabase"."list_agents"(uuid, text, text, integer);

ALTER TABLE "better_supabase"."agents"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_agent (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_agent"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_agents (
  tenant           uuid,
  filter           text    DEFAULT 'store'::text,
  search           text    DEFAULT NULL::text,
  max_rows         integer DEFAULT 50,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_agents"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.purge_agent (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_agent"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_agent (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_agent"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_agent (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = archive_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', archive_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent.archived', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.archived',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_agent (
  id     uuid DEFAULT NULL::uuid,
  tenant uuid DEFAULT NULL::uuid,
  slug   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."tenant_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference", 'name', k."name", 'files', k."files", 'content_hash', k."content_hash", 'latest_version', k."latest_version", 'provider_refs', k."provider_refs") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_agent (
  tenant    uuid,
  agent_id  uuid,
  installed boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'agents.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."tenant_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      perform "better_supabase".emit_event('agent.uninstalled', jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid()), 'organizations/' || install_agent.tenant::text || '/agents/' || install_agent.agent_id::text, (install_agent.tenant)::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.uninstalled',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and x."archived_at" is not null) then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "tenant_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    perform "better_supabase".emit_event('agent.installed', jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid()), 'organizations/' || install_agent.tenant::text || '/agents/' || install_agent.agent_id::text, (install_agent.tenant)::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.installed',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
  end if;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_agents (
  tenant           uuid,
  filter           text    DEFAULT 'store'::text,
  search           text    DEFAULT NULL::text,
  max_rows         integer DEFAULT 50,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at", 'archived_at', x."archived_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."tenant_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."tenant_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."tenant_id" = list_agents.tenant)
      end
      and (coalesce(list_agents.include_archived, false) or x."archived_at" is null)
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_agent (
  id         uuid,
  visibility text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)
    or (coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.publish'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent.published', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.published',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility)
  );
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_agent (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = purge_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'you may not purge agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('agent.purged', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.purged',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rate_agent (
  agent_id uuid,
  rating   integer,
  comment  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."tenant_id" in (select better_supabase.tenant_ids_with('agents.read'))))) or x."tenant_id" in (select better_supabase.tenant_ids_with('agents.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_agent (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = restore_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', restore_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
  end if;
  update "better_supabase"."agents" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('agent.restored', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.restored',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_agent (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("tenant_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."tenant_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
    if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
  
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    perform "better_supabase".emit_event('agent.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.created',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  else
    perform "better_supabase".emit_event('agent.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."tenant_id"::text || '/agents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.updated',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at", 'archived_at', v_row."archived_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_agent_skills (
  agent_id uuid,
  skills   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'agents.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'agent is archived; restore it first' using errcode = '55000', hint = 'AGENT_ARCHIVED';
  end if;
    if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference", "name", "files", "content_hash", "latest_version", "provider_refs")
  select v_row."id", e ->> 'provider', coalesce(e -> 'reference', '{}'), e ->> 'name', coalesce(e -> 'files', '[]'), e ->> 'content_hash', e ->> 'latest_version', coalesce(e -> 'provider_refs', '{}')
  from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_agents"(uuid, text, text, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_agents"(uuid, text, text, integer, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_agents"(uuid, text, text, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_agents"(uuid, text, text, integer, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_agent"(uuid) TO "authenticated", "service_role";
