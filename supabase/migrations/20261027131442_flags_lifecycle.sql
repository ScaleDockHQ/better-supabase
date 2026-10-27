SET local check_function_bodies = off;

DROP FUNCTION "api"."save_flag"(text, jsonb);

DROP FUNCTION "better_supabase"."save_flag"(text, jsonb);

CREATE TABLE "better_supabase"."flag_revisions" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "flag_key"   text                     NOT NULL,
  "revision"   integer                  NOT NULL,
  "definition" jsonb                    NOT NULL,
  "message"    text,
  "changed_by" uuid,
  "changed_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "flag_revisions_definition_check" CHECK ((jsonb_typeof(definition) = 'object'::text)),
  CONSTRAINT "flag_revisions_message_check" CHECK ((length(message) <= 500)),
  CONSTRAINT "flag_revisions_pkey" PRIMARY KEY (id),
  CONSTRAINT "flag_revisions_revision_check" CHECK ((revision > 0)),
  CONSTRAINT "flag_revisions_unique" UNIQUE (flag_key, revision)
);

ALTER TABLE "better_supabase"."flag_revisions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."flag_segments" (
  "name"        text                     NOT NULL,
  "description" text,
  "rules"       jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "flag_segments_name_check" CHECK ((name ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "flag_segments_pkey" PRIMARY KEY (name),
  CONSTRAINT "flag_segments_rules_check" CHECK ((jsonb_typeof(rules) = 'object'::text))
);

ALTER TABLE "better_supabase"."flag_segments"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."flags"
  ADD COLUMN "rollout_schedule" jsonb;

ALTER TABLE "better_supabase"."flags"
  ADD COLUMN "created_at" timestamp WITH time zone NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION api.delete_flag_segment (
  name text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_flag_segment"($1) $function$;

CREATE OR REPLACE FUNCTION api.flag_condition_matches (
  condition      jsonb,
  tenant         text,
  member         text,
  role           text,
  plans          text[],
  context_values jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_condition_matches"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.flag_history (
  key text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_history"($1) $function$;

CREATE OR REPLACE FUNCTION api.flag_rollout_percentage (
  percentage numeric,
  schedule   jsonb,
  at         timestamp with time zone DEFAULT now()
)
  RETURNS numeric
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."flag_rollout_percentage"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_flag_segments()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_flag_segments"() $function$;

CREATE OR REPLACE FUNCTION api.restore_flag (
  key      text,
  revision integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_flag"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_flag (
  key        text,
  definition jsonb,
  message    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_flag"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_flag_segment (
  name        text,
  description text,
  rules       jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_flag_segment"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_flag_segment (
  name text
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flag_segments" g where g."name" = delete_flag_segment.name;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_condition_matches (
  condition      jsonb,
  tenant         text,
  member         text,
  role           text,
  plans          text[],
  context_values jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select (not condition ? 'tenants' or condition -> 'tenants' ? coalesce(tenant, ''))
    and (not condition ? 'users' or condition -> 'users' ? coalesce(member, ''))
    and (not condition ? 'roles' or condition -> 'roles' ? coalesce(role, ''))
    and (not condition ? 'plans' or condition -> 'plans' ?| coalesce(plans, '{}'))
    and (not condition ? 'contexts' or not exists (
      select 1 from jsonb_each(condition -> 'contexts') c(name, keys)
      where not (c.keys ? coalesce(context_values ->> c.name, ''))
    ))
$function$;

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
    'rollout_variants', x."rollout_variants",
    'rollout_schedule', x."rollout_schedule",
    'segments', case when x."rules" @? '$[*].segments' then (
      select coalesce(jsonb_object_agg(g."name", g."rules"), '{}'::jsonb)
      from "better_supabase"."flag_segments" g
      where g."name" in (select jsonb_array_elements_text(e.value -> 'segments') from jsonb_array_elements(x."rules") e where jsonb_typeof(e.value -> 'segments') = 'array')
    ) else '{}'::jsonb end,
    'created_at', x."created_at",
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
  segment_rules jsonb := '{}'::jsonb;
  conditions jsonb;
begin
  select * into flag from "better_supabase"."flags" x where x."key" = flag_evaluation.key;
  if flag."key" is null then
    return null;
  end if;
  if not flag."enabled" or flag."archived" then
    return jsonb_build_object('value', flag."variants" -> flag."default_variant", 'variant', flag."default_variant", 'reason', 'DISABLED');
  end if;
  if flag."rules" @? '$[*].segments' then
    select coalesce(jsonb_object_agg(g."name", g."rules"), '{}'::jsonb) into segment_rules
    from "better_supabase"."flag_segments" g
    where g."name" in (select jsonb_array_elements_text(e.value -> 'segments') from jsonb_array_elements(flag."rules") e where jsonb_typeof(e.value -> 'segments') = 'array');
  end if;
  -- The rules and the segments they name, for the lookups below.
  conditions := flag."rules" || coalesce((select jsonb_agg(v) from jsonb_each(segment_rules) as e(k, v)), '[]'::jsonb);
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
    if tenant is not null and conditions @? '$[*].roles' then
      role := better_supabase.organization_member_role(tenant, member);
    end if;
    if tenant is not null and conditions @? '$[*].plans' then
      tenant_plans := better_supabase.tenant_entitlements(tenant);
    end if;
    for rule in select * from jsonb_array_elements(flag."rules") loop
      if "better_supabase"."flag_condition_matches"(rule, tenant::text, member::text, role, tenant_plans, context_values)
        and (not rule ? 'segments' or exists (
          select 1 from jsonb_array_elements_text(case when jsonb_typeof(rule -> 'segments') = 'array' then rule -> 'segments' else '[]'::jsonb end) n(name)
          where segment_rules ? n.name
            and "better_supabase"."flag_condition_matches"(segment_rules -> n.name, tenant::text, member::text, role, tenant_plans, context_values)
        ))
      then
        chosen := rule ->> 'variant';
        reason := 'TARGETING_MATCH';
        exit;
      end if;
    end loop;
  end if;
  if chosen is null and jsonb_array_length(flag."rollout_variants") > 0 and target is not null
    and "better_supabase"."flag_bucket"(flag."key", target) < "better_supabase"."flag_rollout_percentage"(flag."rollout_percentage", flag."rollout_schedule", now()) * 100 then
    -- A second bucket, so growing the rollout never moves a target between
    -- variants.
    select w.split ->> 'variant' into chosen
    from (
      select e.split, e.i, sum(coalesce((e.split ->> 'weight')::numeric, 0) * 100) over (order by e.i) as edge
      from jsonb_array_elements(flag."rollout_variants") with ordinality as e(split, i)
    ) w
    where "better_supabase"."flag_bucket"(flag."key" || '/split', target) < w.edge
    order by w.i
    limit 1;
    reason := 'SPLIT';
  end if;
  if chosen is null or not flag."variants" ? chosen then
    chosen := flag."default_variant";
    reason := 'DEFAULT';
  end if;
  return jsonb_build_object('value', flag."variants" -> chosen, 'variant', chosen, 'reason', reason);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_history (
  key text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('revision', h."revision", 'definition', h."definition", 'message', h."message", 'changed_by', h."changed_by", 'changed_at', h."changed_at") order by h."revision" desc)
    from "better_supabase"."flag_revisions" h where h."flag_key" = flag_history.key
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.flag_rollout_percentage (
  percentage numeric,
  schedule   jsonb,
  at         timestamp with time zone DEFAULT now()
)
  RETURNS numeric
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  start timestamptz;
  elapsed numeric;
  step jsonb;
begin
  if schedule is null or jsonb_typeof(schedule) <> 'object' then
    return percentage;
  end if;
  begin
    start := (schedule ->> 'startAt')::timestamptz;
  exception when others then
    return 0;
  end;
  if start is null or at < start then
    return 0;
  end if;
  elapsed := extract(epoch from at - start);
  for step in select * from jsonb_array_elements(case when jsonb_typeof(schedule -> 'steps') = 'array' then schedule -> 'steps' else '[]'::jsonb end) loop
    if elapsed < coalesce((step ->> 'durationSeconds')::numeric, 0) then
      return coalesce((step ->> 'percentage')::numeric, 0);
    end if;
    elapsed := elapsed - coalesce((step ->> 'durationSeconds')::numeric, 0);
  end loop;
  return coalesce((schedule ->> 'finalPercentage')::numeric, (schedule -> 'steps' -> -1 ->> 'percentage')::numeric, 0);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_flag_segments()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('name', g."name", 'description', g."description", 'rules', g."rules") order by g."name")
    from "better_supabase"."flag_segments" g
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_flag (
  key      text,
  revision integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  stored jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  select h."definition" into stored from "better_supabase"."flag_revisions" h
  where h."flag_key" = restore_flag.key and h."revision" = restore_flag.revision;
  if stored is null then
    return null;
  end if;
  return "better_supabase"."save_flag"(restore_flag.key, stored - 'key' - 'created_at' - 'updated_at', 'Restored revision ' || restore_flag.revision);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
  key        text,
  definition jsonb,
  message    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
  saved jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if d ? 'rollout_variants' and jsonb_typeof(d -> 'rollout_variants') = 'array' and exists (
    select 1 from jsonb_array_elements(d -> 'rollout_variants') e
    where jsonb_typeof(e.value) <> 'object' or not (coalesce(d -> 'variants', (select x."variants" from "better_supabase"."flags" x where x."key" = save_flag.key), '{"on": true, "off": false}'::jsonb) ? (e.value ->> 'variant'))
      or coalesce((e.value ->> 'weight')::numeric, -1) not between 0 and 100
  ) then
    raise exception 'Each rollout variant needs a known variant and a weight from 0 to 100' using errcode = '22023', hint = 'FLAGS_ROLLOUT_VARIANTS';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variants", "rollout_schedule")
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
    coalesce(d -> 'rollout_variants', '[]'::jsonb),
    nullif(d -> 'rollout_schedule', 'null'::jsonb)
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
    "rollout_variants" = case when d ? 'rollout_variants' then excluded."rollout_variants" else x."rollout_variants" end,
    "rollout_schedule" = case when d ? 'rollout_schedule' then excluded."rollout_schedule" else x."rollout_schedule" end,
    "updated_at" = now();
  saved := (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
  insert into "better_supabase"."flag_revisions" ("flag_key", "revision", "definition", "message", "changed_by")
  values (
    save_flag.key,
    coalesce((select max(h."revision") from "better_supabase"."flag_revisions" h where h."flag_key" = save_flag.key), 0) + 1,
    saved - 'overrides' - 'segments',
    save_flag.message,
    (select u.id from auth.users u where u.id = auth.uid())
  );
  perform "better_supabase".emit_event('flag.saved', jsonb_build_object('key', save_flag.key), 'flags/' || save_flag.key, null, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.saved',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  return saved;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag_segment (
  name        text,
  description text,
  rules       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flag_segments" as g ("name", "description", "rules")
  values (save_flag_segment.name, save_flag_segment.description, coalesce(save_flag_segment.rules, '{}'::jsonb))
  on conflict ("name") do update set
    "description" = excluded."description",
    "rules" = excluded."rules",
    "updated_at" = now();
  return jsonb_build_object('name', save_flag_segment.name, 'description', save_flag_segment.description, 'rules', coalesce(save_flag_segment.rules, '{}'::jsonb));
end;
$function$;

ALTER TABLE "better_supabase"."flag_revisions"
  ADD CONSTRAINT "flag_revisions_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."flags"
  ADD CONSTRAINT "flags_rollout_schedule_check" CHECK (((rollout_schedule IS NULL) OR (jsonb_typeof(rollout_schedule) = 'object'::text)));

CREATE INDEX flag_revisions_changed_by_idx ON better_supabase.flag_revisions USING btree (changed_by);

REVOKE ALL ON FUNCTION "api"."delete_flag_segment"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_flag_segment"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."flag_condition_matches"(jsonb, text, text, text, text[], jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_condition_matches"(jsonb, text, text, text, text[], jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."flag_history"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_history"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."flag_rollout_percentage"(numeric, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."flag_rollout_percentage"(numeric, jsonb, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_flag_segments"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_flag_segments"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_flag"(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_flag"(text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_flag"(text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_flag"(text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_flag_segment"(text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_flag_segment"(text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_flag_segment"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_flag_segment"(text) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_condition_matches"(jsonb, text, text, text, text[], jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."flag_history"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_history"(text) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "better_supabase"."flag_rollout_percentage"(numeric, jsonb, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_flag_segments"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_flag_segments"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_flag"(text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_flag"(text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_flag"(text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_flag"(text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_flag_segment"(text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_flag_segment"(text, text, jsonb) TO "authenticated", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."flag_revisions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."flag_segments" TO "service_role";
