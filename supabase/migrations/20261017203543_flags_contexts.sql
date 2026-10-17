SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."flag_overrides"
  DROP CONSTRAINT "flag_overrides_check";

ALTER TABLE "better_supabase"."flag_overrides"
  DROP CONSTRAINT "flag_overrides_flag_key_organization_id_user_id_key";

DROP FUNCTION "api"."flag_evaluation"(text, uuid, uuid);

DROP FUNCTION "api"."set_flag_override"(text, text, uuid, uuid);

DROP FUNCTION "better_supabase"."flag_evaluation"(text, uuid, uuid);

DROP FUNCTION "better_supabase"."set_flag_override"(text, text, uuid, uuid);

ALTER TABLE "better_supabase"."flag_overrides"
  ADD COLUMN "context" text;

ALTER TABLE "better_supabase"."flag_overrides"
  ADD COLUMN "context_key" text;

ALTER TABLE "better_supabase"."flags"
  ADD COLUMN "archived" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION api.flag_evaluation (
  key      text,
  tenant   uuid  DEFAULT NULL::uuid,
  member   uuid  DEFAULT auth.uid(),
  contexts jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_evaluation"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_flag_override (
  key         text,
  variant     text,
  tenant      uuid DEFAULT NULL::uuid,
  member      uuid DEFAULT NULL::uuid,
  context     text DEFAULT NULL::text,
  context_key text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_flag_override"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_definitions()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', x."key",
    'type', x."type",
    'description', x."description",
    'variants', x."variants",
    'default_variant', x."default_variant",
    'enabled', x."enabled",
    'archived', x."archived",
    'rules', x."rules",
    'rollout_percentage', x."rollout_percentage",
    'rollout_variant', x."rollout_variant",
    'updated_at', x."updated_at",
    'overrides', coalesce((
      select jsonb_agg(jsonb_build_object('organization_id', v."organization_id", 'user_id', v."user_id", 'context', v."context", 'context_key', v."context_key", 'variant', v."variant")
        order by (v."user_id" is not null) desc, (v."organization_id" is not null) desc,
          array_position(array[]::text[], v."context") nulls last, v."context")
      from "better_supabase"."flag_overrides" v where v."flag_key" = x."key"
    ), '[]'::jsonb)
  ) order by x."key"), '[]'::jsonb)
  from "better_supabase"."flags" x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_evaluation (
  key      text,
  tenant   uuid  DEFAULT NULL::uuid,
  member   uuid  DEFAULT auth.uid(),
  contexts jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  flag "better_supabase"."flags";
  chosen text;
  reason text := 'DEFAULT';
  rule jsonb;
  role text;
  tenant_plans text[];
  target text := coalesce(member::text, tenant::text);
  context_values jsonb := case when jsonb_typeof(contexts) = 'object' then contexts else '{}'::jsonb end;
begin
  select * into flag from "better_supabase"."flags" x where x."key" = flag_evaluation.key;
  if flag."key" is null then
    return null;
  end if;
  if not flag."enabled" or flag."archived" then
    return jsonb_build_object('value', flag."variants" -> flag."default_variant", 'variant', flag."default_variant", 'reason', 'DISABLED');
  end if;
  select x."variant" into chosen from "better_supabase"."flag_overrides" x
  where x."flag_key" = flag."key"
    and ((member is not null and x."user_id" = member)
      or (tenant is not null and x."organization_id" = tenant)
      or (x."context" is not null and x."context_key" = context_values ->> x."context"))
  order by (x."user_id" is not null) desc, (x."organization_id" is not null) desc,
    array_position(array[]::text[], x."context") nulls last, x."context"
  limit 1;
  if chosen is not null then
    reason := 'TARGETING_MATCH';
  else
    -- The role and plan lookups run only for flags with rules that read them.
    if tenant is not null and flag."rules" @? '$[*].roles' then
      role := better_supabase.organization_member_role(tenant, member);
    end if;
    if tenant is not null and flag."rules" @? '$[*].plans' then
      tenant_plans := better_supabase.tenant_entitlements(tenant);
    end if;
    for rule in select * from jsonb_array_elements(flag."rules") loop
      if (not rule ? 'tenants' or rule -> 'tenants' ? coalesce(tenant::text, ''))
        and (not rule ? 'users' or rule -> 'users' ? coalesce(member::text, ''))
        and (not rule ? 'roles' or rule -> 'roles' ? coalesce(role, ''))
        and (not rule ? 'plans' or rule -> 'plans' ?| coalesce(tenant_plans, '{}'))
        and (not rule ? 'contexts' or not exists (
          select 1 from jsonb_each(rule -> 'contexts') c(name, keys)
          where not (c.keys ? coalesce(context_values ->> c.name, ''))
        ))
      then
        chosen := rule ->> 'variant';
        reason := 'TARGETING_MATCH';
        exit;
      end if;
    end loop;
  end if;
  if chosen is null and flag."rollout_variant" is not null and target is not null
    and "better_supabase"."flag_bucket"(flag."key", target) < flag."rollout_percentage" * 100 then
    chosen := flag."rollout_variant";
    reason := 'SPLIT';
  end if;
  if chosen is null or not flag."variants" ? chosen then
    chosen := flag."default_variant";
    reason := 'DEFAULT';
  end if;
  return jsonb_build_object('value', flag."variants" -> chosen, 'variant', chosen, 'reason', reason);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
    coalesce((d ->> 'archived')::boolean, false),
    coalesce(d -> 'rules', '[]'::jsonb),
    coalesce((d ->> 'rollout_percentage')::numeric, 0),
    d ->> 'rollout_variant'
  )
  on conflict ("key") do update set
    "type" = case when d ? 'type' then excluded."type" else x."type" end,
    "description" = case when d ? 'description' then excluded."description" else x."description" end,
    "variants" = case when d ? 'variants' then excluded."variants" else x."variants" end,
    "default_variant" = case when d ? 'default_variant' then excluded."default_variant" else x."default_variant" end,
    "enabled" = case when d ? 'enabled' then excluded."enabled" else x."enabled" end,
    "archived" = case when d ? 'archived' then excluded."archived" else x."archived" end,
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
  perform better_supabase.audit_event(
    event_type => 'flag.saved',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  return (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_flag_override (
  key         text,
  variant     text,
  tenant      uuid DEFAULT NULL::uuid,
  member      uuid DEFAULT NULL::uuid,
  context     text DEFAULT NULL::text,
  context_key text DEFAULT NULL::text
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if num_nonnulls(tenant, member, context) <> 1 or (context is null) <> (context_key is null) then
    raise exception 'Pass one target: a tenant, a member, or a context with its key' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member
      and v."context" is not distinct from set_flag_override.context
      and v."context_key" is not distinct from set_flag_override.context_key;
    if not found then
      return false;
    end if;
    perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
    return true;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "context", "context_key", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.context, set_flag_override.context_key, set_flag_override.variant)
  on conflict on constraint flag_overrides_unique do update set "variant" = excluded."variant";
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
  return true;
end;
$function$;

ALTER TABLE "better_supabase"."flag_overrides"
  ADD CONSTRAINT "flag_overrides_context_check" CHECK ((context ~ '^[a-z][a-z0-9_]{0,62}$'::text));

ALTER TABLE "better_supabase"."flag_overrides"
  ADD CONSTRAINT "flag_overrides_context_key_check" CHECK (((length(context_key) >= 1) AND (length(context_key) <= 200)));

ALTER TABLE "better_supabase"."flag_overrides"
  ADD CONSTRAINT "flag_overrides_target" CHECK (((num_nonnulls(organization_id, user_id, context) = 1) AND ((context IS NULL) = (context_key IS NULL))));

ALTER TABLE "better_supabase"."flag_overrides"
  ADD CONSTRAINT "flag_overrides_unique" UNIQUE NULLS NOT DISTINCT (flag_key, organization_id, user_id, context, context_key);

REVOKE ALL ON FUNCTION "api"."flag_evaluation"(text, uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_evaluation"(text, uuid, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_flag_override"(text, text, uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_flag_override"(text, text, uuid, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."flag_evaluation"(text, uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_evaluation"(text, uuid, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_flag_override"(text, text, uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_flag_override"(text, text, uuid, uuid, text, text) TO "authenticated", "service_role";
