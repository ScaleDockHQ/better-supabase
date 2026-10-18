SET local check_function_bodies = off;

DROP INDEX "better_supabase"."saved_views_default_idx";

DROP INDEX "better_supabase"."saved_views_list_idx";

DROP INDEX "better_supabase"."saved_views_owner_idx";

CREATE OR REPLACE FUNCTION better_supabase.form_resolve (
  tenant     uuid,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_errors text[];
  v_problem text;
  v_steps jsonb := '[]'::jsonb;
  v_fields jsonb;
  v_step jsonb;
  v_field jsonb;
  v_custom jsonb;
  v_options jsonb;
  v_step_keys text[] := '{}';
  v_keys text[] := '{}';
begin
  v_errors := extensions.jsonschema_validation_errors('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["steps"],"additionalProperties":false,"properties":{"steps":{"type":"array","minItems":1,"maxItems":50,"items":{"type":"object","required":["key","fields"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"title":{"type":"string","maxLength":200},"description":{"type":"string","maxLength":2000},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"fields":{"type":"array","minItems":1,"maxItems":200,"items":{"type":"object","required":["key"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"label":{"type":"string","minLength":1,"maxLength":200},"type":{"enum":["text","textarea","email","url","number","integer","date","bool","consent","option","multi","json"]},"required":{"type":"boolean"},"help":{"type":"string","maxLength":1000},"placeholder":{"type":"string","maxLength":200},"options":{"type":"array","minItems":1,"maxItems":500,"items":{"type":"object","required":["value","label"],"additionalProperties":false,"properties":{"value":{"type":"string","minLength":1,"maxLength":200},"label":{"type":"string","minLength":1,"maxLength":200}}}},"min":{"type":"number"},"max":{"type":"number"},"minLength":{"type":"integer","minimum":0},"maxLength":{"type":"integer","minimum":1},"pattern":{"type":"string","maxLength":500},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"customField":{"type":"string","pattern":"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"}}}}}}}}}'::json, definition::json);
  if cardinality(v_errors) > 0 then
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
  end if;
  <<steps>>
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    if (v_step ->> 'key') = any (v_step_keys) then
      v_problem := format('step %s is listed twice', v_step ->> 'key');
      exit;
    end if;
    v_step_keys := v_step_keys || (v_step ->> 'key');
    if v_step ? 'showIf' and not ((v_step -> 'showIf' ->> 'field') = any (v_keys)) then
      v_problem := format('step %s: showIf names %s, which isn''t an earlier field', v_step ->> 'key', v_step -> 'showIf' ->> 'field');
      exit;
    end if;
    v_fields := '[]'::jsonb;
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      if (v_field ->> 'key') = any (v_keys) then
        v_problem := format('field %s is listed twice', v_field ->> 'key');
        exit steps;
      end if;
      if v_field ? 'showIf' and not ((v_field -> 'showIf' ->> 'field') = any (v_keys)) then
        v_problem := format('field %s: showIf names %s, which isn''t an earlier field', v_field ->> 'key', v_field -> 'showIf' ->> 'field');
        exit steps;
      end if;
      v_keys := v_keys || (v_field ->> 'key');
      v_custom := null;
      if v_field ? 'customField' then
        select jsonb_strip_nulls(jsonb_build_object('label', d."label", 'type', d."type", 'required', d."required"))
          into v_custom
          from "better_supabase"."field_definitions" d
          where d."id" = (v_field ->> 'customField')::uuid and d."tenant_id" = form_resolve.tenant;
        if v_custom is null then
          v_problem := format('field %s: customField %s is not a field definition in this organization', v_field ->> 'key', v_field ->> 'customField');
        exit steps;
        end if;
        if v_custom ->> 'type' = 'option' and not v_field ? 'options' and to_regclass('"better_supabase"."field_options"') is not null then
          execute format('select jsonb_agg(jsonb_build_object(''value'', o."value", ''label'', o."label") order by o."value") from %s o where o."definition_id" = $1', to_regclass('"better_supabase"."field_options"'))
            into v_options using (v_field ->> 'customField')::uuid;
          v_custom := v_custom || jsonb_strip_nulls(jsonb_build_object('options', v_options));
        end if;
        v_field := v_custom || v_field;
      end if;
      if not (v_field ? 'label' and v_field ? 'type') then
        v_problem := format('field %s needs a label and a type, or a customField', v_field ->> 'key');
        exit steps;
      end if;
      if (v_field ->> 'type') in ('option', 'multi') and coalesce(jsonb_array_length(v_field -> 'options'), 0) = 0 then
        v_problem := format('field %s needs options', v_field ->> 'key');
        exit steps;
      end if;
      if v_field ? 'pattern' then
        begin
          perform '' ~ (v_field ->> 'pattern');
        exception when invalid_regular_expression then
          v_problem := format('field %s: pattern is not a valid regular expression', v_field ->> 'key');
        end;
        exit steps when v_problem is not null;
      end if;
      v_fields := v_fields || jsonb_build_array(v_field);
    end loop;
    v_steps := v_steps || jsonb_build_array(jsonb_set(v_step, '{fields}', v_fields));
  end loop;
  if v_problem is not null then
    v_errors := array[v_problem];
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
  end if;
  return jsonb_build_object('steps', v_steps);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_view (
  tenant  uuid,
  list    text,
  name    text,
  kind    text,
  scope   text,
  team    text,
  state   jsonb,
  view_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid := save_view.view_id;
  v_row "better_supabase"."shared_views";
  v_last text;
  v_rank text;
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_view.scope is null or save_view.scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.kind is null or save_view.kind not in ('table', 'board', 'calendar', 'timeline', 'gantt') then
    raise exception 'unknown view kind' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.state is null or jsonb_typeof(save_view.state) <> 'object' then
    raise exception 'state must be an object' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'views.read'), false)) then
    raise exception 'not allowed to save views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'user' and auth.uid() is null then
    raise exception 'a personal view needs a signed-in user' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'views.share'), false)) then
    raise exception 'not allowed to share views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'team' then
    if save_view.team is null then
      raise exception 'a team view needs a team' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
    end if;
    if not (v_service or save_view.team in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t)) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
    end if;
  end if;
  if v_id is not null then
    select * into v_row from "better_supabase"."shared_views" where "id" = v_id and "tenant_id" = save_view.tenant for update;
    if not found then
      raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
    end if;
    if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and v_row."owner_id" = auth.uid())
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'views.share'), false))) then
      raise exception 'not allowed to change this view' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_view_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_view.tenant, save_view.list, save_view.scope, save_view.state;
    end if;
  end;
  if v_id is null then
    select max(v."rank" collate "C") into v_last from "better_supabase"."shared_views" v
      where v."tenant_id" = save_view.tenant and v."list" = save_view.list;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."shared_views" ("tenant_id", "list", "scope", "owner_id", "team_id", "name", "kind", "state", "rank")
    values (save_view.tenant, save_view.list, save_view.scope, auth.uid(),
      case when save_view.scope = 'team' then save_view.team end,
      save_view.name, save_view.kind, save_view.state, v_rank)
    returning "id" into v_id;
  else
    update "better_supabase"."shared_views" set
      "list" = save_view.list,
      "scope" = save_view.scope,
      "team_id" = case when save_view.scope = 'team' then save_view.team end,
      "owner_id" = coalesce("owner_id", auth.uid()),
      "name" = save_view.name,
      "kind" = save_view.kind,
      "state" = save_view.state,
      "is_default" = case when "scope" = save_view.scope then "is_default" else false end,
      "updated_at" = now()
    where "id" = v_id
    returning "rank" into v_rank;
  end if;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_view_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'rank', v_rank);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_user_state (
  subject_type text,
  subject_id   text,
  starred      boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  insert into "better_supabase"."subject_user_state" ("subject_type", "subject_id", "user_id", "starred_at", "last_opened_at")
  values (set_user_state.subject_type, set_user_state.subject_id, auth.uid(), case when set_user_state.starred then now() else null end, now())
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "starred_at" = excluded."starred_at", "last_opened_at" = now();
  return true;
end;
$function$;

CREATE UNIQUE INDEX shared_views_default_idx ON better_supabase.shared_views USING btree (tenant_id, list, scope, COALESCE(
CASE scope
    WHEN 'user'::text THEN (owner_id)::text
    WHEN 'team'::text THEN team_id
    ELSE NULL::text
END, ''::text))
  WHERE is_default;

CREATE INDEX shared_views_list_idx ON better_supabase.shared_views USING btree (tenant_id, list);

CREATE INDEX shared_views_owner_idx ON better_supabase.shared_views USING btree (owner_id)
  WHERE (owner_id IS NOT NULL);
