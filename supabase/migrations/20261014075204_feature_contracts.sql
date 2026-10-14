SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."notification_suppressions" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "channel"           text                     NOT NULL DEFAULT 'email'::text,
  "address"           text                     NOT NULL,
  "user_id"           uuid,
  "reason"            text                     NOT NULL,
  "provider"          text,
  "provider_event_id" text,
  "detail"            jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "notification_suppressions_address_check" CHECK ((address = lower(address))),
  CONSTRAINT "notification_suppressions_channel_address_key" UNIQUE (channel, address),
  CONSTRAINT "notification_suppressions_pkey" PRIMARY KEY (id),
  CONSTRAINT "notification_suppressions_reason_check" CHECK ((reason = ANY (ARRAY['bounce'::text, 'complaint'::text, 'manual'::text])))
);

ALTER TABLE "better_supabase"."notification_suppressions"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD COLUMN "published_by" uuid;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD COLUMN "owner_kind" text;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD COLUMN "permissions" text[] NOT NULL DEFAULT '{}'::text[];

CREATE OR REPLACE FUNCTION api.list_notification_suppressions (
  max_items integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_notification_suppressions"($1) $function$;

CREATE OR REPLACE FUNCTION api.suppress_notification_address (
  address           text,
  reason            text,
  channel           text  DEFAULT 'email'::text,
  provider          text  DEFAULT NULL::text,
  provider_event_id text  DEFAULT NULL::text,
  detail            jsonb DEFAULT '{}'::jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."suppress_notification_address"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.unsuppress_notification_address (
  address text,
  channel text DEFAULT 'email'::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unsuppress_notification_address"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_graph_permissions (
  graph jsonb
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_graph_permissions"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_run_principal (
  version uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_run_principal"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_notification_deliveries (
  channel      text,
  max_items    integer  DEFAULT 50,
  lease        interval DEFAULT '00:05:00'::interval,
  max_attempts integer  DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  claimed jsonb;
begin
  -- A delivery whose lease ran out on its last attempt lost its worker.
  update "better_supabase"."notification_deliveries" d
  set "status" = 'failed', "error" = 'The lease ran out on the last attempt'
  where d."channel" = claim_notification_deliveries.channel
    and d."status" = 'pending'
    and d."attempts" >= greatest(1, coalesce(claim_notification_deliveries.max_attempts, 5))
    and d."attempted_at" < now() - claim_notification_deliveries.lease;

  with picked as (
    select d."id" as id from "better_supabase"."notification_deliveries" d
    where d."channel" = claim_notification_deliveries.channel
      and d."status" = 'pending'
      and d."next_attempt_at" <= now()
      and (d."attempted_at" is null or d."attempted_at" < now() - claim_notification_deliveries.lease)
    order by d."created_at"
    limit claim_notification_deliveries.max_items
    for update skip locked
  ), leased as (
    update "better_supabase"."notification_deliveries" d set "attempted_at" = now(), "attempts" = d."attempts" + 1
    from picked where d."id" = picked.id
    returning d.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'delivery_id', l."id",
    'channel', l."channel",
    'attempts', l."attempts",
    'user_id', rc."user_id",
    'email', u.email,
    'notification', jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at"),
    'suppressed', s."reason"
  )), '[]') into claimed
  from leased l
  join "better_supabase"."notification_recipients" rc on rc."id" = l."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  left join auth.users u on u.id = rc."user_id"
  left join "better_supabase"."notification_suppressions" s on s."channel" = l."channel" and s."address" = lower(u.email);
  return claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notification_suppressions (
  max_items integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or (select auth.role()) = 'service_role'
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
  v_permissions text[];
  v_missing text;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if compiled is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    if compiled is not null then
      update "better_supabase"."workflow_versions" x set "compiled" = compiled
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  v_permissions := "better_supabase"."workflow_graph_permissions"(v_row."graph");
  if not v_service then
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(v_permissions) p
    where not coalesce(better_supabase.can('tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'You may not publish a workflow whose steps need %', v_missing
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_FORBIDDEN';
    end if;
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set
    "status" = 'published',
    "compiled" = compiled,
    "published_at" = now(),
    "published_by" = case when v_service then null else (select auth.uid()) end,
    "owner_kind" = case when v_service then 'organization' else 'user' end,
    "permissions" = v_permissions
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'workflow.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow.published:' || v_row."id"::text
  );
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_draft (
  definition uuid,
  graph      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition for update;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "graph" = graph, "compiled" = null
  where x."definition_id" = definition and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "created_by")
    values (
      definition,
      coalesce((select max(y."version") from "better_supabase"."workflow_versions" y where y."definition_id" = definition), 0) + 1,
      graph,
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."workflow_definitions" x set "updated_at" = now() where x."id" = definition;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.suppress_notification_address (
  address           text,
  reason            text,
  channel           text  DEFAULT 'email'::text,
  provider          text  DEFAULT NULL::text,
  provider_event_id text  DEFAULT NULL::text,
  detail            jsonb DEFAULT '{}'::jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_address text := lower(btrim(suppress_notification_address.address));
begin
  if v_address is null or v_address = '' then
    raise exception 'address is required' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_ADDRESS';
  end if;
  if suppress_notification_address.reason is null or suppress_notification_address.reason not in ('bounce', 'complaint', 'manual') then
    raise exception 'reason must be bounce, complaint or manual' using errcode = '22023', hint = 'NOTIFICATION_SUPPRESSION_REASON';
  end if;
  insert into "better_supabase"."notification_suppressions" ("channel", "address", "user_id", "reason", "provider", "provider_event_id", "detail")
  values (
    coalesce(suppress_notification_address.channel, 'email'),
    v_address,
    (select u.id from auth.users u where lower(u.email) = v_address order by u.created_at limit 1),
    suppress_notification_address.reason,
    suppress_notification_address.provider,
    suppress_notification_address.provider_event_id,
    coalesce(suppress_notification_address.detail, '{}')
  )
  on conflict ("channel", "address") do nothing;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unsuppress_notification_address (
  address text,
  channel text DEFAULT 'email'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."notification_suppressions" s
  where s."channel" = coalesce(unsuppress_notification_address.channel, 'email')
    and s."address" = lower(btrim(unsuppress_notification_address.address));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_graph_permissions (
  graph jsonb
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(distinct x.p order by x.p), '{}'::text[])
  from (
    select coalesce('{}'::jsonb ->> (n.value ->> 'step'), 'workflow.run') as p
    from jsonb_array_elements(
      case when jsonb_typeof(workflow_graph_permissions.graph -> 'nodes') = 'array'
        then workflow_graph_permissions.graph -> 'nodes' else '[]'::jsonb end
    ) n
    where n.value ->> 'kind' = 'step'
  ) x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_run_principal (
  version uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_missing text;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'This workflow version was never published' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if v_row."owner_kind" is null then
    raise exception 'This workflow version was published before publishers were recorded; publish it again'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
  end if;
  if v_row."owner_kind" = 'user' then
    if v_row."published_by" is null then
      raise exception 'The user who published this workflow no longer exists'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(array_append(v_row."permissions", 'workflow.publish')) p
    where not coalesce(better_supabase.can_user(v_row."published_by", 'tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'The user who published this workflow no longer holds %', v_missing
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
  end if;
  return jsonb_build_object(
    'publisher', v_row."published_by",
    'tenant', v_tenant,
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_start_target (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.run'), false))) then
    raise exception 'You may not run this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."definition_id" = definition and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  return jsonb_build_object('definition', jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ), 'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_version_get (
  version uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at",
    'publishedBy', x."published_by",
    'owner', x."owner_kind",
    'permissions', to_jsonb(x."permissions"),
    'graph', x."graph",
    'compiled', x."compiled"
  ) from "better_supabase"."workflow_versions" x where x."id" = workflow_version_get.version;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_versions_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at",
    'publishedBy', x."published_by",
    'owner', x."owner_kind",
    'permissions', to_jsonb(x."permissions")
  ) order by x."version" desc), '[]'::jsonb)
  from "better_supabase"."workflow_versions" x where x."definition_id" = workflow_versions_list.definition;
$function$;

ALTER TABLE "better_supabase"."notification_suppressions"
  ADD CONSTRAINT "notification_suppressions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD CONSTRAINT "workflow_versions_owner_kind_check" CHECK ((owner_kind = ANY (ARRAY['user'::text, 'organization'::text])));

ALTER TABLE "better_supabase"."workflow_versions"
  ADD CONSTRAINT "workflow_versions_published_by_fkey" FOREIGN KEY (published_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX notification_suppressions_user_idx ON better_supabase.notification_suppressions USING btree (user_id);

CREATE INDEX workflow_versions_published_by_idx ON better_supabase.workflow_versions USING btree (published_by);

CREATE POLICY "bs_notification_suppressions_read" ON "better_supabase"."notification_suppressions"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

REVOKE ALL ON FUNCTION "api"."list_notification_suppressions"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_notification_suppressions"(integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."suppress_notification_address"(text, text, text, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."suppress_notification_address"(text, text, text, text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."unsuppress_notification_address"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unsuppress_notification_address"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_graph_permissions"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_graph_permissions"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_run_principal"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_run_principal"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_notification_suppressions"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_notification_suppressions"(integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."suppress_notification_address"(text, text, text, text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unsuppress_notification_address"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unsuppress_notification_address"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_graph_permissions"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_graph_permissions"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_run_principal"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_run_principal"(uuid) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."notification_suppressions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."notification_suppressions" TO "service_role";
