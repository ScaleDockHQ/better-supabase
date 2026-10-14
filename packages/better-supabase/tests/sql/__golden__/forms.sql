-- ==== alone: schema supabase/schemas/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module forms@1 managed
-- Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, and handlers that turn a submission into a record.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."forms" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed', 'archived')),
  "current_version_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."forms" enable row level security;
revoke all on "better_supabase"."forms" from anon, authenticated;
grant select on "better_supabase"."forms" to authenticated;
grant all on "better_supabase"."forms" to service_role;
drop policy if exists "forms_read" on "better_supabase"."forms";
create policy "forms_read" on "better_supabase"."forms" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "better_supabase"."form_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "better_supabase"."forms" ("id") on delete cascade,
  "number" integer not null check ("number" > 0),
  "definition" jsonb not null,
  "schema" jsonb not null,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("form_id", "number")
);
alter table "better_supabase"."form_versions" enable row level security;
revoke all on "better_supabase"."form_versions" from anon, authenticated;
grant select on "better_supabase"."form_versions" to authenticated;
grant all on "better_supabase"."form_versions" to service_role;
drop policy if exists "form_versions_read" on "better_supabase"."form_versions";
create policy "form_versions_read" on "better_supabase"."form_versions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "better_supabase"."form_submissions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "better_supabase"."forms" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."form_versions" ("id") on delete cascade,
  "subject_type" text,
  "subject_id" text,
  "respondent_id" uuid,
  "answers" jsonb not null default '{}'::jsonb check (jsonb_typeof("answers") = 'object' and octet_length("answers"::text) <= 1048576),
  "status" text not null default 'submitted' check ("status" in ('draft', 'submitted', 'accepted', 'rejected')),
  "source" text not null default 'member' check ("source" in ('member', 'public', 'service')),
  "reviewed_by" uuid,
  "reviewed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "submitted_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create index if not exists "form_submissions_form_idx" on "better_supabase"."form_submissions" ("form_id", "created_at" desc);
create index if not exists "form_submissions_respondent_idx" on "better_supabase"."form_submissions" ("respondent_id") where "respondent_id" is not null;
create index if not exists "form_submissions_subject_idx" on "better_supabase"."form_submissions" ("subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."form_submissions" enable row level security;
revoke all on "better_supabase"."form_submissions" from anon, authenticated;
grant select on "better_supabase"."form_submissions" to authenticated;
grant all on "better_supabase"."form_submissions" to service_role;
drop policy if exists "form_submissions_read" on "better_supabase"."form_submissions";
create policy "form_submissions_read" on "better_supabase"."form_submissions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.review')) or "respondent_id" = (select auth.uid()));

-- The schema of one field's answer. Mirrors fieldSchema in
-- core/contracts/form-definition.ts.
create or replace function "better_supabase"."form_field_schema"(field jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text := field ->> 'type';
  -- required only asks for the key, so an empty answer needs its own floor.
  v_floor jsonb := case when field -> 'required' = 'true'::jsonb then '1'::jsonb end;
  v_values jsonb;
  v_out jsonb;
begin
  select coalesce(jsonb_agg(o.value -> 'value' order by o.ord), '[]'::jsonb) into v_values
    from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) with ordinality as o(value, ord);
  v_out := case v_type
    when 'text' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '500'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'textarea' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '10000'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'email' then jsonb_build_object('type', 'string', 'format', 'email', 'maxLength', 320)
    when 'url' then jsonb_build_object('type', 'string', 'format', 'uri', 'maxLength', 2000)
    when 'number' then jsonb_build_object('type', 'number') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'integer' then jsonb_build_object('type', 'integer') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'date' then '{"type": "string", "format": "date"}'::jsonb
    when 'bool' then '{"type": "boolean"}'::jsonb
    when 'consent' then '{"type": "boolean", "const": true}'::jsonb
    when 'option' then jsonb_build_object('type', 'string', 'enum', v_values)
    when 'multi' then jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string', 'enum', v_values), 'uniqueItems', true)
      || jsonb_strip_nulls(jsonb_build_object('minItems', coalesce(field -> 'min', v_floor), 'maxItems', field -> 'max'))
    else '{}'::jsonb
  end;
  return v_out || jsonb_strip_nulls(jsonb_build_object('title', field -> 'label', 'description', field -> 'help'));
end;
$$;
revoke execute on function "better_supabase"."form_field_schema"(jsonb) from public, anon, authenticated;

-- The schema a showIf condition holds under, as an if.
create or replace function "better_supabase"."form_condition_schema"(condition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'properties', jsonb_build_object(condition ->> 'field',
      case
        when condition ? 'equals' then jsonb_build_object('const', condition -> 'equals')
        when condition ? 'in' then jsonb_build_object('enum', condition -> 'in')
        else '{"not": {"enum": [null, "", []]}}'::jsonb
      end),
    'required', jsonb_build_array(condition ->> 'field'))
$$;
revoke execute on function "better_supabase"."form_condition_schema"(jsonb) from public, anon, authenticated;

-- The JSON Schema 2020-12 a version's answers validate against. Mirrors
-- formSchema in core/contracts/form-definition.ts: a required field with a
-- showIf (its own or its step's) is required only while the condition holds.
create or replace function "better_supabase"."form_schema"(definition jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_properties jsonb := '{}'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_conditional jsonb := '[]'::jsonb;
  v_conditions jsonb;
  v_step jsonb;
  v_field jsonb;
begin
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      v_properties := v_properties || jsonb_build_object(v_field ->> 'key', "better_supabase"."form_field_schema"(v_field));
      continue when coalesce((v_field ->> 'required')::boolean, false) is false;
      v_conditions := '[]'::jsonb;
      if v_step ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_step -> 'showIf'));
      end if;
      if v_field ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_field -> 'showIf'));
      end if;
      if jsonb_array_length(v_conditions) = 0 then
        v_required := v_required || jsonb_build_array(v_field ->> 'key');
      else
        v_conditional := v_conditional || jsonb_build_array(jsonb_build_object(
          'if', case when jsonb_array_length(v_conditions) = 1 then v_conditions -> 0 else jsonb_build_object('allOf', v_conditions) end,
          'then', jsonb_build_object('required', jsonb_build_array(v_field ->> 'key'))));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('$schema', 'https://json-schema.org/draft/2020-12/schema', 'type', 'object', 'properties', v_properties, 'additionalProperties', false)
    || case when jsonb_array_length(v_required) > 0 then jsonb_build_object('required', v_required) else '{}'::jsonb end
    || case when jsonb_array_length(v_conditional) > 0 then jsonb_build_object('allOf', v_conditional) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."form_schema"(jsonb) from public, anon, authenticated;

-- Checks a definition (its shape, then what the shape can't say, as
-- formDefinitionProblems does) and copies each customField's definition in.
create or replace function "better_supabase"."form_resolve"(tenant uuid, definition jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
        v_problem := format('field %s: customField needs the custom-fields module', v_field ->> 'key');
        exit steps;
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
$$;
revoke execute on function "better_supabase"."form_resolve"(uuid, jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."create_form"(tenant uuid, key text, title text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_form.tenant, 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if create_form.key is null or create_form.key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a form key is lowercase letters, digits, - and _, starting with a letter' using errcode = '22023', hint = 'FORM_KEY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."forms" x where x."tenant_id" = create_form.tenant and x."key" = create_form.key) then
    raise exception 'a form with this key exists' using errcode = '23505', hint = 'FORM_KEY_TAKEN';
  end if;
  insert into "better_supabase"."forms" ("tenant_id", "key", "title", "description", "created_by")
  values (create_form.tenant, create_form.key, create_form.title, create_form.description, auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_form"(uuid, text, text, text) to authenticated, service_role;

-- Changes the title, description or status. A form opens for submissions
-- once it has a published version.
create or replace function "better_supabase"."update_form"(form_id uuid, title text default null, description text default null, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."forms" x where x."id" = update_form.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if update_form.status is not null and update_form.status not in ('open', 'closed', 'archived') then
    raise exception 'status is open, closed or archived' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if update_form.status = 'open' and v_row."current_version_id" is null then
    raise exception 'publish a version before opening the form' using errcode = '55000', hint = 'FORM_NOT_PUBLISHED';
  end if;
  update "better_supabase"."forms" x set
    "title" = coalesce(update_form.title, x."title"),
    "description" = coalesce(update_form.description, x."description"),
    "status" = coalesce(update_form.status, x."status"),
    "updated_at" = now()
  where x."id" = update_form.form_id
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_form"(uuid, text, text, text) to authenticated, service_role;

-- Publishes a new version: checks the definition, copies custom fields in,
-- builds the version's JSON Schema and makes it current. A draft form opens.
create or replace function "better_supabase"."publish_form_version"(form_id uuid, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_resolved jsonb;
  v_number integer;
  v_row "better_supabase"."form_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_form from "better_supabase"."forms" x where x."id" = publish_form_version.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_form."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_publish"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using publish_form_version.form_id, publish_form_version.definition;
    end if;
  end;
  v_resolved := "better_supabase"."form_resolve"(v_form."tenant_id", publish_form_version.definition);
  select coalesce(max(x."number"), 0) + 1 into v_number from "better_supabase"."form_versions" x where x."form_id" = v_form."id";
  insert into "better_supabase"."form_versions" ("tenant_id", "form_id", "number", "definition", "schema", "created_by")
  values (v_form."tenant_id", v_form."id", v_number, v_resolved, "better_supabase"."form_schema"(v_resolved), auth.uid())
  returning * into v_row;
  update "better_supabase"."forms" x set
    "current_version_id" = v_row."id",
    "status" = case when x."status" = 'draft' then 'open' else x."status" end,
    "updated_at" = now()
  where x."id" = v_form."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."publish_form_version"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."publish_form_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_form"(form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
  v_version "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."forms" x where x."id" = get_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('version', case when v_version."id" is null then null else jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") end);
end;
$$;
revoke execute on function "better_supabase"."get_form"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_form_version"(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_versions" x where x."id" = get_form_version.version_id;
  if not found then
    raise exception 'form version not found' using errcode = 'P0002', hint = 'FORM_VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_version"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_forms"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."forms" x
  where x."tenant_id" = list_forms.tenant
    and (list_forms.status is null or x."status" = list_forms.status);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_forms"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_forms"(uuid, text) to authenticated, service_role;

-- Writes a submission against the form's current version, validating the
-- answers unless it is a draft. Only definer functions of this module call it.
create or replace function "better_supabase"."form_submission_save"(form_id uuid, answers jsonb, subject_type text, subject_id text, respondent uuid, source text, draft boolean, submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_schema jsonb;
  v_errors text[];
  v_row "better_supabase"."form_submissions"%rowtype;
  v_link jsonb;
begin
  select * into v_form from "better_supabase"."forms" x where x."id" = form_submission_save.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if v_form."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    raise exception 'answers must be an object' using errcode = '22023', hint = 'FORM_ANSWERS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_submission"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using form_submission_save.form_id, form_submission_save.answers;
    end if;
  end;
  if not form_submission_save.draft then
    select x."schema" into v_schema from "better_supabase"."form_versions" x where x."id" = v_form."current_version_id";
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      raise exception '%.answers does not match its JSON Schema: %', 'form_submissions', array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';
    end if;
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from "better_supabase"."form_submissions" x where x."id" = form_submission_save.submission_id for update;
    if not found or v_row."form_id" <> form_submission_save.form_id or v_row."respondent_id" is distinct from form_submission_save.respondent then
      raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'only a draft submission can change' using errcode = '55000', hint = 'FORM_SUBMISSION_LOCKED';
    end if;
    update "better_supabase"."form_submissions" x set
      "version_id" = v_form."current_version_id",
      "answers" = form_submission_save.answers,
      "status" = case when form_submission_save.draft then 'draft' else 'submitted' end,
      "submitted_at" = case when form_submission_save.draft then null else now() end,
      "subject_type" = coalesce(form_submission_save.subject_type, x."subject_type"),
      "subject_id" = coalesce(form_submission_save.subject_id, x."subject_id"),
      "updated_at" = now()
    where x."id" = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into "better_supabase"."form_submissions" ("tenant_id", "form_id", "version_id", "subject_type", "subject_id", "respondent_id", "answers", "status", "source", "submitted_at")
    values (v_form."tenant_id", v_form."id", v_form."current_version_id", form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end)
    returning * into v_row;
  end if;
  if not form_submission_save.draft then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_submission"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."form_submission_save"(uuid, jsonb, text, text, uuid, text, boolean, uuid) from public, anon, authenticated;

-- Submits answers as the caller, or saves them as a draft to finish later
-- (submission_id continues one). A subject links the submission to a record
-- the caller can read.
create or replace function "better_supabase"."submit_form"(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$$;
revoke execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."get_form_submission"(submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = get_form_submission.submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."respondent_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_submission"(uuid) to authenticated, service_role;

-- Newest first. Reviewers see every submission; others see their own.
create or replace function "better_supabase"."list_form_submissions"(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status" = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."review_form_submission"(submission_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = review_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to review submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    raise exception 'status is submitted, accepted or rejected' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "better_supabase"."form_submissions" x set
    "status" = review_form_submission.status,
    "reviewed_by" = auth.uid(),
    "reviewed_at" = now(),
    "updated_at" = now()
  where x."id" = review_form_submission.submission_id
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_form_submission"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_form_submission"(uuid, text) to authenticated, service_role;

-- Reviewers delete any submission; a respondent deletes their own draft.
create or replace function "better_supabase"."delete_form_submission"(submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)
    or (v_row."respondent_id" = auth.uid() and v_row."status" = 'draft')) then
    raise exception 'not allowed to delete this submission' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  delete from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_form_submission"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module-data forms
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('forms', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module forms@1 managed
-- Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, and handlers that turn a submission into a record.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."forms" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed', 'archived')),
  "current_version_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."forms" enable row level security;
revoke all on "better_supabase"."forms" from anon, authenticated;
grant select on "better_supabase"."forms" to authenticated;
grant all on "better_supabase"."forms" to service_role;
drop policy if exists "forms_read" on "better_supabase"."forms";
create policy "forms_read" on "better_supabase"."forms" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "better_supabase"."form_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "better_supabase"."forms" ("id") on delete cascade,
  "number" integer not null check ("number" > 0),
  "definition" jsonb not null,
  "schema" jsonb not null,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("form_id", "number")
);
alter table "better_supabase"."form_versions" enable row level security;
revoke all on "better_supabase"."form_versions" from anon, authenticated;
grant select on "better_supabase"."form_versions" to authenticated;
grant all on "better_supabase"."form_versions" to service_role;
drop policy if exists "form_versions_read" on "better_supabase"."form_versions";
create policy "form_versions_read" on "better_supabase"."form_versions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "better_supabase"."form_submissions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "better_supabase"."forms" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."form_versions" ("id") on delete cascade,
  "subject_type" text,
  "subject_id" text,
  "respondent_id" uuid,
  "answers" jsonb not null default '{}'::jsonb check (jsonb_typeof("answers") = 'object' and octet_length("answers"::text) <= 1048576),
  "status" text not null default 'submitted' check ("status" in ('draft', 'submitted', 'accepted', 'rejected')),
  "source" text not null default 'member' check ("source" in ('member', 'public', 'service')),
  "reviewed_by" uuid,
  "reviewed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "submitted_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create index if not exists "form_submissions_form_idx" on "better_supabase"."form_submissions" ("form_id", "created_at" desc);
create index if not exists "form_submissions_respondent_idx" on "better_supabase"."form_submissions" ("respondent_id") where "respondent_id" is not null;
create index if not exists "form_submissions_subject_idx" on "better_supabase"."form_submissions" ("subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."form_submissions" enable row level security;
revoke all on "better_supabase"."form_submissions" from anon, authenticated;
grant select on "better_supabase"."form_submissions" to authenticated;
grant all on "better_supabase"."form_submissions" to service_role;
drop policy if exists "form_submissions_read" on "better_supabase"."form_submissions";
create policy "form_submissions_read" on "better_supabase"."form_submissions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.review')) or "respondent_id" = (select auth.uid()));

-- The schema of one field's answer. Mirrors fieldSchema in
-- core/contracts/form-definition.ts.
create or replace function "better_supabase"."form_field_schema"(field jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text := field ->> 'type';
  -- required only asks for the key, so an empty answer needs its own floor.
  v_floor jsonb := case when field -> 'required' = 'true'::jsonb then '1'::jsonb end;
  v_values jsonb;
  v_out jsonb;
begin
  select coalesce(jsonb_agg(o.value -> 'value' order by o.ord), '[]'::jsonb) into v_values
    from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) with ordinality as o(value, ord);
  v_out := case v_type
    when 'text' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '500'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'textarea' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '10000'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'email' then jsonb_build_object('type', 'string', 'format', 'email', 'maxLength', 320)
    when 'url' then jsonb_build_object('type', 'string', 'format', 'uri', 'maxLength', 2000)
    when 'number' then jsonb_build_object('type', 'number') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'integer' then jsonb_build_object('type', 'integer') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'date' then '{"type": "string", "format": "date"}'::jsonb
    when 'bool' then '{"type": "boolean"}'::jsonb
    when 'consent' then '{"type": "boolean", "const": true}'::jsonb
    when 'option' then jsonb_build_object('type', 'string', 'enum', v_values)
    when 'multi' then jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string', 'enum', v_values), 'uniqueItems', true)
      || jsonb_strip_nulls(jsonb_build_object('minItems', coalesce(field -> 'min', v_floor), 'maxItems', field -> 'max'))
    else '{}'::jsonb
  end;
  return v_out || jsonb_strip_nulls(jsonb_build_object('title', field -> 'label', 'description', field -> 'help'));
end;
$$;
revoke execute on function "better_supabase"."form_field_schema"(jsonb) from public, anon, authenticated;

-- The schema a showIf condition holds under, as an if.
create or replace function "better_supabase"."form_condition_schema"(condition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'properties', jsonb_build_object(condition ->> 'field',
      case
        when condition ? 'equals' then jsonb_build_object('const', condition -> 'equals')
        when condition ? 'in' then jsonb_build_object('enum', condition -> 'in')
        else '{"not": {"enum": [null, "", []]}}'::jsonb
      end),
    'required', jsonb_build_array(condition ->> 'field'))
$$;
revoke execute on function "better_supabase"."form_condition_schema"(jsonb) from public, anon, authenticated;

-- The JSON Schema 2020-12 a version's answers validate against. Mirrors
-- formSchema in core/contracts/form-definition.ts: a required field with a
-- showIf (its own or its step's) is required only while the condition holds.
create or replace function "better_supabase"."form_schema"(definition jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_properties jsonb := '{}'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_conditional jsonb := '[]'::jsonb;
  v_conditions jsonb;
  v_step jsonb;
  v_field jsonb;
begin
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      v_properties := v_properties || jsonb_build_object(v_field ->> 'key', "better_supabase"."form_field_schema"(v_field));
      continue when coalesce((v_field ->> 'required')::boolean, false) is false;
      v_conditions := '[]'::jsonb;
      if v_step ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_step -> 'showIf'));
      end if;
      if v_field ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_field -> 'showIf'));
      end if;
      if jsonb_array_length(v_conditions) = 0 then
        v_required := v_required || jsonb_build_array(v_field ->> 'key');
      else
        v_conditional := v_conditional || jsonb_build_array(jsonb_build_object(
          'if', case when jsonb_array_length(v_conditions) = 1 then v_conditions -> 0 else jsonb_build_object('allOf', v_conditions) end,
          'then', jsonb_build_object('required', jsonb_build_array(v_field ->> 'key'))));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('$schema', 'https://json-schema.org/draft/2020-12/schema', 'type', 'object', 'properties', v_properties, 'additionalProperties', false)
    || case when jsonb_array_length(v_required) > 0 then jsonb_build_object('required', v_required) else '{}'::jsonb end
    || case when jsonb_array_length(v_conditional) > 0 then jsonb_build_object('allOf', v_conditional) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."form_schema"(jsonb) from public, anon, authenticated;

-- Checks a definition (its shape, then what the shape can't say, as
-- formDefinitionProblems does) and copies each customField's definition in.
create or replace function "better_supabase"."form_resolve"(tenant uuid, definition jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
          execute 'select jsonb_agg(jsonb_build_object(''value'', o."value", ''label'', o."label") order by o."value") from "better_supabase"."field_options" o where o."definition_id" = $1'
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
$$;
revoke execute on function "better_supabase"."form_resolve"(uuid, jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."create_form"(tenant uuid, key text, title text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_form.tenant, 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if create_form.key is null or create_form.key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a form key is lowercase letters, digits, - and _, starting with a letter' using errcode = '22023', hint = 'FORM_KEY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."forms" x where x."tenant_id" = create_form.tenant and x."key" = create_form.key) then
    raise exception 'a form with this key exists' using errcode = '23505', hint = 'FORM_KEY_TAKEN';
  end if;
  insert into "better_supabase"."forms" ("tenant_id", "key", "title", "description", "created_by")
  values (create_form.tenant, create_form.key, create_form.title, create_form.description, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('form.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key"), 'forms/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form.created',
    category => 'configuration',
    target_type => 'form',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_form"(uuid, text, text, text) to authenticated, service_role;

-- Changes the title, description or status. A form opens for submissions
-- once it has a published version.
create or replace function "better_supabase"."update_form"(form_id uuid, title text default null, description text default null, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."forms" x where x."id" = update_form.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if update_form.status is not null and update_form.status not in ('open', 'closed', 'archived') then
    raise exception 'status is open, closed or archived' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if update_form.status = 'open' and v_row."current_version_id" is null then
    raise exception 'publish a version before opening the form' using errcode = '55000', hint = 'FORM_NOT_PUBLISHED';
  end if;
  update "better_supabase"."forms" x set
    "title" = coalesce(update_form.title, x."title"),
    "description" = coalesce(update_form.description, x."description"),
    "status" = coalesce(update_form.status, x."status"),
    "updated_at" = now()
  where x."id" = update_form.form_id
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_form"(uuid, text, text, text) to authenticated, service_role;

-- Publishes a new version: checks the definition, copies custom fields in,
-- builds the version's JSON Schema and makes it current. A draft form opens.
create or replace function "better_supabase"."publish_form_version"(form_id uuid, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_resolved jsonb;
  v_number integer;
  v_row "better_supabase"."form_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_form from "better_supabase"."forms" x where x."id" = publish_form_version.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_form."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_publish"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using publish_form_version.form_id, publish_form_version.definition;
    end if;
  end;
  v_resolved := "better_supabase"."form_resolve"(v_form."tenant_id", publish_form_version.definition);
  select coalesce(max(x."number"), 0) + 1 into v_number from "better_supabase"."form_versions" x where x."form_id" = v_form."id";
  insert into "better_supabase"."form_versions" ("tenant_id", "form_id", "number", "definition", "schema", "created_by")
  values (v_form."tenant_id", v_form."id", v_number, v_resolved, "better_supabase"."form_schema"(v_resolved), auth.uid())
  returning * into v_row;
  update "better_supabase"."forms" x set
    "current_version_id" = v_row."id",
    "status" = case when x."status" = 'draft' then 'open' else x."status" end,
    "updated_at" = now()
  where x."id" = v_form."id";
  perform "better_supabase".emit_event('form_version.published', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number"), 'forms/' || v_row."form_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_version.published',
    category => 'configuration',
    target_type => 'form',
    record_id => v_row."form_id"::text,
    target_label => v_form."title",
    summary => 'published version ' || v_row."number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."publish_form_version"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."publish_form_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_form"(form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
  v_version "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."forms" x where x."id" = get_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('version', case when v_version."id" is null then null else jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") end);
end;
$$;
revoke execute on function "better_supabase"."get_form"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_form_version"(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_versions" x where x."id" = get_form_version.version_id;
  if not found then
    raise exception 'form version not found' using errcode = 'P0002', hint = 'FORM_VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_version"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_forms"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."forms" x
  where x."tenant_id" = list_forms.tenant
    and (list_forms.status is null or x."status" = list_forms.status);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_forms"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_forms"(uuid, text) to authenticated, service_role;

-- Writes a submission against the form's current version, validating the
-- answers unless it is a draft. Only definer functions of this module call it.
create or replace function "better_supabase"."form_submission_save"(form_id uuid, answers jsonb, subject_type text, subject_id text, respondent uuid, source text, draft boolean, submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_schema jsonb;
  v_errors text[];
  v_row "better_supabase"."form_submissions"%rowtype;
  v_link jsonb;
begin
  select * into v_form from "better_supabase"."forms" x where x."id" = form_submission_save.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if v_form."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    raise exception 'answers must be an object' using errcode = '22023', hint = 'FORM_ANSWERS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_submission"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using form_submission_save.form_id, form_submission_save.answers;
    end if;
  end;
  if not form_submission_save.draft then
    select x."schema" into v_schema from "better_supabase"."form_versions" x where x."id" = v_form."current_version_id";
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      raise exception '%.answers does not match its JSON Schema: %', 'form_submissions', array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';
    end if;
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from "better_supabase"."form_submissions" x where x."id" = form_submission_save.submission_id for update;
    if not found or v_row."form_id" <> form_submission_save.form_id or v_row."respondent_id" is distinct from form_submission_save.respondent then
      raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'only a draft submission can change' using errcode = '55000', hint = 'FORM_SUBMISSION_LOCKED';
    end if;
    update "better_supabase"."form_submissions" x set
      "version_id" = v_form."current_version_id",
      "answers" = form_submission_save.answers,
      "status" = case when form_submission_save.draft then 'draft' else 'submitted' end,
      "submitted_at" = case when form_submission_save.draft then null else now() end,
      "subject_type" = coalesce(form_submission_save.subject_type, x."subject_type"),
      "subject_id" = coalesce(form_submission_save.subject_id, x."subject_id"),
      "updated_at" = now()
    where x."id" = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into "better_supabase"."form_submissions" ("tenant_id", "form_id", "version_id", "subject_type", "subject_id", "respondent_id", "answers", "status", "source", "submitted_at")
    values (v_form."tenant_id", v_form."id", v_form."current_version_id", form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end)
    returning * into v_row;
  end if;
  if not form_submission_save.draft then
    perform "better_supabase".emit_event('form_submission.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'source', v_row."source"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_submission"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."form_submission_save"(uuid, jsonb, text, text, uuid, text, boolean, uuid) from public, anon, authenticated;

-- Submits answers as the caller, or saves them as a draft to finish later
-- (submission_id continues one). A subject links the submission to a record
-- the caller can read.
create or replace function "better_supabase"."submit_form"(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$$;
revoke execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) to authenticated, service_role;

-- The open form a public link (a share link to subject type 'form' with
-- role 'respond') points at, with its current version.
create or replace function "better_supabase"."get_public_form"(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_form_id uuid;
  v_row "better_supabase"."forms"%rowtype;
  v_version "better_supabase"."form_versions"%rowtype;
begin
  select x."id" into v_form_id
  from "better_supabase"."share_links" k
  join "better_supabase"."forms" x on x."id"::text = k."subject_id" and x."tenant_id" = k."tenant_id"
  where k."token_hash" = encode(extensions.digest(convert_to(get_public_form.token, 'utf8'), 'sha256'), 'hex')
    and k."subject_type" = 'form'
    and k."role" = 'respond'
    and k."revoked_at" is null
    and (k."expires_at" is null or k."expires_at" > now());
  if v_form_id is null then
    raise exception 'this form link isn''t valid' using errcode = 'P0002', hint = 'FORM_LINK_INVALID';
  end if;
  select * into v_row from "better_supabase"."forms" x where x."id" = v_form_id;
  if v_row."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  select * into v_version from "better_supabase"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'title', v_row."title", 'description', v_row."description", 'version', jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") - 'createdBy');
end;
$$;
revoke all on function "better_supabase"."get_public_form"(text) from public;
grant execute on function "better_supabase"."get_public_form"(text) to anon, authenticated, service_role;

-- Submits answers through a public link. Each caller (the user, else the
-- right-most x-forwarded-for hop) gets options.publicLimit submissions per
-- form when the rate-limit module is installed, and before_public_form_submission
-- receives the bot-check token to refuse it.
create or replace function "better_supabase"."submit_public_form"(token text, answers jsonb, bot_token text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form_id uuid;
  v_headers jsonb;
  v_caller text;
  v_allowed boolean;
  v_retry integer;
  v_result jsonb;
begin
  select x."id" into v_form_id
  from "better_supabase"."share_links" k
  join "better_supabase"."forms" x on x."id"::text = k."subject_id" and x."tenant_id" = k."tenant_id"
  where k."token_hash" = encode(extensions.digest(convert_to(submit_public_form.token, 'utf8'), 'sha256'), 'hex')
    and k."subject_type" = 'form'
    and k."role" = 'respond'
    and k."revoked_at" is null
    and (k."expires_at" is null or k."expires_at" > now());
  if v_form_id is null then
    raise exception 'this form link isn''t valid' using errcode = 'P0002', hint = 'FORM_LINK_INVALID';
  end if;
  v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  v_caller := coalesce(auth.uid()::text, 'ip:' || coalesce(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 'unknown'));
  select h.allowed, h.retry_after into v_allowed, v_retry
    from "better_supabase"."hit_rate_limit"('forms:' || v_form_id::text, v_caller, 20, 'PT1H'::interval) h;
  if not v_allowed then
    raise sqlstate 'PGRST' using
      message = json_build_object(
        'code', 'BS429',
        'message', 'Rate limit for this form exceeded: 20 submissions per PT1H',
        'details', format('Retry after %s seconds.', v_retry),
        'hint', null
      )::text,
      detail = json_build_object(
        'status', 429,
        'status_text', 'Too Many Requests',
        'headers', json_build_object('Retry-After', v_retry::text)
      )::text;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_public_form_submission"(uuid, jsonb, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::text)', v_hook::oid::regproc)
        using v_form_id, submit_public_form.answers, submit_public_form.bot_token;
    end if;
  end;
  v_result := "better_supabase"."form_submission_save"(v_form_id, submit_public_form.answers, null, null, auth.uid(), 'public', false, null);
  return jsonb_build_object('id', v_result -> 'id', 'status', v_result -> 'status', 'submittedAt', v_result -> 'submittedAt');
end;
$$;
revoke all on function "better_supabase"."submit_public_form"(text, jsonb, text) from public;
grant execute on function "better_supabase"."submit_public_form"(text, jsonb, text) to anon, authenticated, service_role;

create or replace function "better_supabase"."get_form_submission"(submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = get_form_submission.submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."respondent_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_submission"(uuid) to authenticated, service_role;

-- Newest first. Reviewers see every submission; others see their own.
create or replace function "better_supabase"."list_form_submissions"(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status" = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."review_form_submission"(submission_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = review_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to review submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    raise exception 'status is submitted, accepted or rejected' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "better_supabase"."form_submissions" x set
    "status" = review_form_submission.status,
    "reviewed_by" = auth.uid(),
    "reviewed_at" = now(),
    "updated_at" = now()
  where x."id" = review_form_submission.submission_id
  returning * into v_row;
  perform "better_supabase".emit_event('form_submission.reviewed', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id", 'status', v_row."status"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_submission.reviewed',
    category => 'data',
    target_type => 'form_submission',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_form_submission"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_form_submission"(uuid, text) to authenticated, service_role;

-- Reviewers delete any submission; a respondent deletes their own draft.
create or replace function "better_supabase"."delete_form_submission"(submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)
    or (v_row."respondent_id" = auth.uid() and v_row."status" = 'draft')) then
    raise exception 'not allowed to delete this submission' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  delete from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id;
  perform "better_supabase".emit_event('form_submission.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id"), 'form-submissions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/forms');
  perform better_supabase.audit_event(
    event_type => 'form_submission.deleted',
    category => 'data',
    target_type => 'form_submission',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', coalesce(v_row."subject_type", 'form'), 'subjectId', coalesce(v_row."subject_id", v_row."form_id"::text), 'id', v_row."id", 'formId', v_row."form_id")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_form_submission"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module-data forms
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('forms', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module forms@1 managed
-- Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, and handlers that turn a submission into a record.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create table if not exists "app_private"."forms" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed', 'archived')),
  "current_version_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "app_private"."forms" enable row level security;
revoke all on "app_private"."forms" from anon, authenticated;
grant select on "app_private"."forms" to authenticated;
grant all on "app_private"."forms" to service_role;
drop policy if exists "forms_read" on "app_private"."forms";
create policy "forms_read" on "app_private"."forms" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "app_private"."form_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "app_private"."forms" ("id") on delete cascade,
  "number" integer not null check ("number" > 0),
  "definition" jsonb not null,
  "schema" jsonb not null,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("form_id", "number")
);
alter table "app_private"."form_versions" enable row level security;
revoke all on "app_private"."form_versions" from anon, authenticated;
grant select on "app_private"."form_versions" to authenticated;
grant all on "app_private"."form_versions" to service_role;
drop policy if exists "form_versions_read" on "app_private"."form_versions";
create policy "form_versions_read" on "app_private"."form_versions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "app_private"."form_submissions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "app_private"."forms" ("id") on delete cascade,
  "version_id" uuid not null references "app_private"."form_versions" ("id") on delete cascade,
  "subject_type" text,
  "subject_id" text,
  "respondent_id" uuid,
  "answers" jsonb not null default '{}'::jsonb check (jsonb_typeof("answers") = 'object' and octet_length("answers"::text) <= 1048576),
  "status" text not null default 'submitted' check ("status" in ('draft', 'submitted', 'accepted', 'rejected')),
  "source" text not null default 'member' check ("source" in ('member', 'public', 'service')),
  "reviewed_by" uuid,
  "reviewed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "submitted_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create index if not exists "form_submissions_form_idx" on "app_private"."form_submissions" ("form_id", "created_at" desc);
create index if not exists "form_submissions_respondent_idx" on "app_private"."form_submissions" ("respondent_id") where "respondent_id" is not null;
create index if not exists "form_submissions_subject_idx" on "app_private"."form_submissions" ("subject_type", "subject_id") where "subject_type" is not null;
alter table "app_private"."form_submissions" enable row level security;
revoke all on "app_private"."form_submissions" from anon, authenticated;
grant select on "app_private"."form_submissions" to authenticated;
grant all on "app_private"."form_submissions" to service_role;
drop policy if exists "form_submissions_read" on "app_private"."form_submissions";
create policy "form_submissions_read" on "app_private"."form_submissions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.review')) or "respondent_id" = (select auth.uid()));

-- The schema of one field's answer. Mirrors fieldSchema in
-- core/contracts/form-definition.ts.
create or replace function "app_private"."form_field_schema"(field jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text := field ->> 'type';
  -- required only asks for the key, so an empty answer needs its own floor.
  v_floor jsonb := case when field -> 'required' = 'true'::jsonb then '1'::jsonb end;
  v_values jsonb;
  v_out jsonb;
begin
  select coalesce(jsonb_agg(o.value -> 'value' order by o.ord), '[]'::jsonb) into v_values
    from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) with ordinality as o(value, ord);
  v_out := case v_type
    when 'text' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '500'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'textarea' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '10000'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'email' then jsonb_build_object('type', 'string', 'format', 'email', 'maxLength', 320)
    when 'url' then jsonb_build_object('type', 'string', 'format', 'uri', 'maxLength', 2000)
    when 'number' then jsonb_build_object('type', 'number') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'integer' then jsonb_build_object('type', 'integer') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'date' then '{"type": "string", "format": "date"}'::jsonb
    when 'bool' then '{"type": "boolean"}'::jsonb
    when 'consent' then '{"type": "boolean", "const": true}'::jsonb
    when 'option' then jsonb_build_object('type', 'string', 'enum', v_values)
    when 'multi' then jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string', 'enum', v_values), 'uniqueItems', true)
      || jsonb_strip_nulls(jsonb_build_object('minItems', coalesce(field -> 'min', v_floor), 'maxItems', field -> 'max'))
    else '{}'::jsonb
  end;
  return v_out || jsonb_strip_nulls(jsonb_build_object('title', field -> 'label', 'description', field -> 'help'));
end;
$$;
revoke execute on function "app_private"."form_field_schema"(jsonb) from public, anon, authenticated;

-- The schema a showIf condition holds under, as an if.
create or replace function "app_private"."form_condition_schema"(condition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'properties', jsonb_build_object(condition ->> 'field',
      case
        when condition ? 'equals' then jsonb_build_object('const', condition -> 'equals')
        when condition ? 'in' then jsonb_build_object('enum', condition -> 'in')
        else '{"not": {"enum": [null, "", []]}}'::jsonb
      end),
    'required', jsonb_build_array(condition ->> 'field'))
$$;
revoke execute on function "app_private"."form_condition_schema"(jsonb) from public, anon, authenticated;

-- The JSON Schema 2020-12 a version's answers validate against. Mirrors
-- formSchema in core/contracts/form-definition.ts: a required field with a
-- showIf (its own or its step's) is required only while the condition holds.
create or replace function "app_private"."form_schema"(definition jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_properties jsonb := '{}'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_conditional jsonb := '[]'::jsonb;
  v_conditions jsonb;
  v_step jsonb;
  v_field jsonb;
begin
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      v_properties := v_properties || jsonb_build_object(v_field ->> 'key', "app_private"."form_field_schema"(v_field));
      continue when coalesce((v_field ->> 'required')::boolean, false) is false;
      v_conditions := '[]'::jsonb;
      if v_step ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("app_private"."form_condition_schema"(v_step -> 'showIf'));
      end if;
      if v_field ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("app_private"."form_condition_schema"(v_field -> 'showIf'));
      end if;
      if jsonb_array_length(v_conditions) = 0 then
        v_required := v_required || jsonb_build_array(v_field ->> 'key');
      else
        v_conditional := v_conditional || jsonb_build_array(jsonb_build_object(
          'if', case when jsonb_array_length(v_conditions) = 1 then v_conditions -> 0 else jsonb_build_object('allOf', v_conditions) end,
          'then', jsonb_build_object('required', jsonb_build_array(v_field ->> 'key'))));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('$schema', 'https://json-schema.org/draft/2020-12/schema', 'type', 'object', 'properties', v_properties, 'additionalProperties', false)
    || case when jsonb_array_length(v_required) > 0 then jsonb_build_object('required', v_required) else '{}'::jsonb end
    || case when jsonb_array_length(v_conditional) > 0 then jsonb_build_object('allOf', v_conditional) else '{}'::jsonb end;
end;
$$;
revoke execute on function "app_private"."form_schema"(jsonb) from public, anon, authenticated;

-- Checks a definition (its shape, then what the shape can't say, as
-- formDefinitionProblems does) and copies each customField's definition in.
create or replace function "app_private"."form_resolve"(tenant uuid, definition jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
        v_problem := format('field %s: customField needs the custom-fields module', v_field ->> 'key');
        exit steps;
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
$$;
revoke execute on function "app_private"."form_resolve"(uuid, jsonb) from public, anon, authenticated;

create or replace function "app_private"."create_form"(tenant uuid, key text, title text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_form.tenant, 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if create_form.key is null or create_form.key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a form key is lowercase letters, digits, - and _, starting with a letter' using errcode = '22023', hint = 'FORM_KEY_INVALID';
  end if;
  if exists (select 1 from "app_private"."forms" x where x."tenant_id" = create_form.tenant and x."key" = create_form.key) then
    raise exception 'a form with this key exists' using errcode = '23505', hint = 'FORM_KEY_TAKEN';
  end if;
  insert into "app_private"."forms" ("tenant_id", "key", "title", "description", "created_by")
  values (create_form.tenant, create_form.key, create_form.title, create_form.description, auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_form"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."create_form"(uuid, text, text, text) to authenticated, service_role;

-- Changes the title, description or status. A form opens for submissions
-- once it has a published version.
create or replace function "app_private"."update_form"(form_id uuid, title text default null, description text default null, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."forms" x where x."id" = update_form.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if update_form.status is not null and update_form.status not in ('open', 'closed', 'archived') then
    raise exception 'status is open, closed or archived' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if update_form.status = 'open' and v_row."current_version_id" is null then
    raise exception 'publish a version before opening the form' using errcode = '55000', hint = 'FORM_NOT_PUBLISHED';
  end if;
  update "app_private"."forms" x set
    "title" = coalesce(update_form.title, x."title"),
    "description" = coalesce(update_form.description, x."description"),
    "status" = coalesce(update_form.status, x."status"),
    "updated_at" = now()
  where x."id" = update_form.form_id
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_form"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."update_form"(uuid, text, text, text) to authenticated, service_role;

-- Publishes a new version: checks the definition, copies custom fields in,
-- builds the version's JSON Schema and makes it current. A draft form opens.
create or replace function "app_private"."publish_form_version"(form_id uuid, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "app_private"."forms"%rowtype;
  v_resolved jsonb;
  v_number integer;
  v_row "app_private"."form_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_form from "app_private"."forms" x where x."id" = publish_form_version.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_form."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_publish"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using publish_form_version.form_id, publish_form_version.definition;
    end if;
  end;
  v_resolved := "app_private"."form_resolve"(v_form."tenant_id", publish_form_version.definition);
  select coalesce(max(x."number"), 0) + 1 into v_number from "app_private"."form_versions" x where x."form_id" = v_form."id";
  insert into "app_private"."form_versions" ("tenant_id", "form_id", "number", "definition", "schema", "created_by")
  values (v_form."tenant_id", v_form."id", v_number, v_resolved, "app_private"."form_schema"(v_resolved), auth.uid())
  returning * into v_row;
  update "app_private"."forms" x set
    "current_version_id" = v_row."id",
    "status" = case when x."status" = 'draft' then 'open' else x."status" end,
    "updated_at" = now()
  where x."id" = v_form."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."publish_form_version"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."publish_form_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."get_form"(form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."forms"%rowtype;
  v_version "app_private"."form_versions"%rowtype;
begin
  select * into v_row from "app_private"."forms" x where x."id" = get_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select * into v_version from "app_private"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('version', case when v_version."id" is null then null else jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") end);
end;
$$;
revoke execute on function "app_private"."get_form"(uuid) from public, anon;
grant execute on function "app_private"."get_form"(uuid) to authenticated, service_role;

create or replace function "app_private"."get_form_version"(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."form_versions"%rowtype;
begin
  select * into v_row from "app_private"."form_versions" x where x."id" = get_form_version.version_id;
  if not found then
    raise exception 'form version not found' using errcode = 'P0002', hint = 'FORM_VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."get_form_version"(uuid) from public, anon;
grant execute on function "app_private"."get_form_version"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_forms"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb) into v_rows
  from "app_private"."forms" x
  where x."tenant_id" = list_forms.tenant
    and (list_forms.status is null or x."status" = list_forms.status);
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_forms"(uuid, text) from public, anon;
grant execute on function "app_private"."list_forms"(uuid, text) to authenticated, service_role;

-- Writes a submission against the form's current version, validating the
-- answers unless it is a draft. Only definer functions of this module call it.
create or replace function "app_private"."form_submission_save"(form_id uuid, answers jsonb, subject_type text, subject_id text, respondent uuid, source text, draft boolean, submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "app_private"."forms"%rowtype;
  v_schema jsonb;
  v_errors text[];
  v_row "app_private"."form_submissions"%rowtype;
  v_link jsonb;
begin
  select * into v_form from "app_private"."forms" x where x."id" = form_submission_save.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if v_form."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    raise exception 'answers must be an object' using errcode = '22023', hint = 'FORM_ANSWERS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_submission"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using form_submission_save.form_id, form_submission_save.answers;
    end if;
  end;
  if not form_submission_save.draft then
    select x."schema" into v_schema from "app_private"."form_versions" x where x."id" = v_form."current_version_id";
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      raise exception '%.answers does not match its JSON Schema: %', 'form_submissions', array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';
    end if;
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from "app_private"."form_submissions" x where x."id" = form_submission_save.submission_id for update;
    if not found or v_row."form_id" <> form_submission_save.form_id or v_row."respondent_id" is distinct from form_submission_save.respondent then
      raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'only a draft submission can change' using errcode = '55000', hint = 'FORM_SUBMISSION_LOCKED';
    end if;
    update "app_private"."form_submissions" x set
      "version_id" = v_form."current_version_id",
      "answers" = form_submission_save.answers,
      "status" = case when form_submission_save.draft then 'draft' else 'submitted' end,
      "submitted_at" = case when form_submission_save.draft then null else now() end,
      "subject_type" = coalesce(form_submission_save.subject_type, x."subject_type"),
      "subject_id" = coalesce(form_submission_save.subject_id, x."subject_id"),
      "updated_at" = now()
    where x."id" = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into "app_private"."form_submissions" ("tenant_id", "form_id", "version_id", "subject_type", "subject_id", "respondent_id", "answers", "status", "source", "submitted_at")
    values (v_form."tenant_id", v_form."id", v_form."current_version_id", form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end)
    returning * into v_row;
  end if;
  if not form_submission_save.draft then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_submission"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."form_submission_save"(uuid, jsonb, text, text, uuid, text, boolean, uuid) from public, anon, authenticated;

-- Submits answers as the caller, or saves them as a draft to finish later
-- (submission_id continues one). A subject links the submission to a record
-- the caller can read.
create or replace function "app_private"."submit_form"(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "app_private"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "app_private"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$$;
revoke execute on function "app_private"."submit_form"(uuid, jsonb, text, text, uuid, boolean) from public, anon;
grant execute on function "app_private"."submit_form"(uuid, jsonb, text, text, uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."get_form_submission"(submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."form_submissions"%rowtype;
begin
  select * into v_row from "app_private"."form_submissions" x where x."id" = get_form_submission.submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."respondent_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."get_form_submission"(uuid) from public, anon;
grant execute on function "app_private"."get_form_submission"(uuid) to authenticated, service_role;

-- Newest first. Reviewers see every submission; others see their own.
create or replace function "app_private"."list_form_submissions"(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "app_private"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "app_private"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status" = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_form_submissions"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "app_private"."list_form_submissions"(uuid, text, integer, timestamptz) to authenticated, service_role;

create or replace function "app_private"."review_form_submission"(submission_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."form_submissions" x where x."id" = review_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to review submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    raise exception 'status is submitted, accepted or rejected' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "app_private"."form_submissions" x set
    "status" = review_form_submission.status,
    "reviewed_by" = auth.uid(),
    "reviewed_at" = now(),
    "updated_at" = now()
  where x."id" = review_form_submission.submission_id
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."review_form_submission"(uuid, text) from public, anon;
grant execute on function "app_private"."review_form_submission"(uuid, text) to authenticated, service_role;

-- Reviewers delete any submission; a respondent deletes their own draft.
create or replace function "app_private"."delete_form_submission"(submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."form_submissions" x where x."id" = delete_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)
    or (v_row."respondent_id" = auth.uid() and v_row."status" = 'draft')) then
    raise exception 'not allowed to delete this submission' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  delete from "app_private"."form_submissions" x where x."id" = delete_form_submission.submission_id;
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_form_submission"(uuid) from public, anon;
grant execute on function "app_private"."delete_form_submission"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module-data forms
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('forms', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module forms@1 managed
-- Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, and handlers that turn a submission into a record.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."forms" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "title" text not null check (length("title") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed', 'archived')),
  "current_version_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."forms" enable row level security;
revoke all on "better_supabase"."forms" from anon, authenticated;
grant select on "better_supabase"."forms" to authenticated;
grant all on "better_supabase"."forms" to service_role;
drop policy if exists "forms_read" on "better_supabase"."forms";
create policy "forms_read" on "better_supabase"."forms" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "better_supabase"."form_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "better_supabase"."forms" ("id") on delete cascade,
  "number" integer not null check ("number" > 0),
  "definition" jsonb not null,
  "schema" jsonb not null,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("form_id", "number")
);
alter table "better_supabase"."form_versions" enable row level security;
revoke all on "better_supabase"."form_versions" from anon, authenticated;
grant select on "better_supabase"."form_versions" to authenticated;
grant all on "better_supabase"."form_versions" to service_role;
drop policy if exists "form_versions_read" on "better_supabase"."form_versions";
create policy "form_versions_read" on "better_supabase"."form_versions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.read')));

create table if not exists "better_supabase"."form_submissions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "form_id" uuid not null references "better_supabase"."forms" ("id") on delete cascade,
  "version_id" uuid not null references "better_supabase"."form_versions" ("id") on delete cascade,
  "subject_type" text,
  "subject_id" text,
  "respondent_id" uuid,
  "answers" jsonb not null default '{}'::jsonb check (jsonb_typeof("answers") = 'object' and octet_length("answers"::text) <= 1048576),
  "status" text not null default 'submitted' check ("status" in ('draft', 'submitted', 'accepted', 'rejected')),
  "source" text not null default 'member' check ("source" in ('member', 'public', 'service')),
  "reviewed_by" uuid,
  "reviewed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "submitted_at" timestamptz,
  "updated_at" timestamptz not null default now(),
  check (("subject_type" is null) = ("subject_id" is null))
);
create index if not exists "form_submissions_form_idx" on "better_supabase"."form_submissions" ("form_id", "created_at" desc);
create index if not exists "form_submissions_respondent_idx" on "better_supabase"."form_submissions" ("respondent_id") where "respondent_id" is not null;
create index if not exists "form_submissions_subject_idx" on "better_supabase"."form_submissions" ("subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."form_submissions" enable row level security;
revoke all on "better_supabase"."form_submissions" from anon, authenticated;
grant select on "better_supabase"."form_submissions" to authenticated;
grant all on "better_supabase"."form_submissions" to service_role;
drop policy if exists "form_submissions_read" on "better_supabase"."form_submissions";
create policy "form_submissions_read" on "better_supabase"."form_submissions" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('forms.review')) or "respondent_id" = (select auth.uid()));

-- The schema of one field's answer. Mirrors fieldSchema in
-- core/contracts/form-definition.ts.
create or replace function "better_supabase"."form_field_schema"(field jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text := field ->> 'type';
  -- required only asks for the key, so an empty answer needs its own floor.
  v_floor jsonb := case when field -> 'required' = 'true'::jsonb then '1'::jsonb end;
  v_values jsonb;
  v_out jsonb;
begin
  select coalesce(jsonb_agg(o.value -> 'value' order by o.ord), '[]'::jsonb) into v_values
    from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) with ordinality as o(value, ord);
  v_out := case v_type
    when 'text' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '500'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'textarea' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '10000'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'email' then jsonb_build_object('type', 'string', 'format', 'email', 'maxLength', 320)
    when 'url' then jsonb_build_object('type', 'string', 'format', 'uri', 'maxLength', 2000)
    when 'number' then jsonb_build_object('type', 'number') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'integer' then jsonb_build_object('type', 'integer') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'date' then '{"type": "string", "format": "date"}'::jsonb
    when 'bool' then '{"type": "boolean"}'::jsonb
    when 'consent' then '{"type": "boolean", "const": true}'::jsonb
    when 'option' then jsonb_build_object('type', 'string', 'enum', v_values)
    when 'multi' then jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string', 'enum', v_values), 'uniqueItems', true)
      || jsonb_strip_nulls(jsonb_build_object('minItems', coalesce(field -> 'min', v_floor), 'maxItems', field -> 'max'))
    else '{}'::jsonb
  end;
  return v_out || jsonb_strip_nulls(jsonb_build_object('title', field -> 'label', 'description', field -> 'help'));
end;
$$;
revoke execute on function "better_supabase"."form_field_schema"(jsonb) from public, anon, authenticated;

-- The schema a showIf condition holds under, as an if.
create or replace function "better_supabase"."form_condition_schema"(condition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'properties', jsonb_build_object(condition ->> 'field',
      case
        when condition ? 'equals' then jsonb_build_object('const', condition -> 'equals')
        when condition ? 'in' then jsonb_build_object('enum', condition -> 'in')
        else '{"not": {"enum": [null, "", []]}}'::jsonb
      end),
    'required', jsonb_build_array(condition ->> 'field'))
$$;
revoke execute on function "better_supabase"."form_condition_schema"(jsonb) from public, anon, authenticated;

-- The JSON Schema 2020-12 a version's answers validate against. Mirrors
-- formSchema in core/contracts/form-definition.ts: a required field with a
-- showIf (its own or its step's) is required only while the condition holds.
create or replace function "better_supabase"."form_schema"(definition jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_properties jsonb := '{}'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_conditional jsonb := '[]'::jsonb;
  v_conditions jsonb;
  v_step jsonb;
  v_field jsonb;
begin
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      v_properties := v_properties || jsonb_build_object(v_field ->> 'key', "better_supabase"."form_field_schema"(v_field));
      continue when coalesce((v_field ->> 'required')::boolean, false) is false;
      v_conditions := '[]'::jsonb;
      if v_step ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_step -> 'showIf'));
      end if;
      if v_field ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_field -> 'showIf'));
      end if;
      if jsonb_array_length(v_conditions) = 0 then
        v_required := v_required || jsonb_build_array(v_field ->> 'key');
      else
        v_conditional := v_conditional || jsonb_build_array(jsonb_build_object(
          'if', case when jsonb_array_length(v_conditions) = 1 then v_conditions -> 0 else jsonb_build_object('allOf', v_conditions) end,
          'then', jsonb_build_object('required', jsonb_build_array(v_field ->> 'key'))));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('$schema', 'https://json-schema.org/draft/2020-12/schema', 'type', 'object', 'properties', v_properties, 'additionalProperties', false)
    || case when jsonb_array_length(v_required) > 0 then jsonb_build_object('required', v_required) else '{}'::jsonb end
    || case when jsonb_array_length(v_conditional) > 0 then jsonb_build_object('allOf', v_conditional) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."form_schema"(jsonb) from public, anon, authenticated;

-- Checks a definition (its shape, then what the shape can't say, as
-- formDefinitionProblems does) and copies each customField's definition in.
create or replace function "better_supabase"."form_resolve"(tenant uuid, definition jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
        v_problem := format('field %s: customField needs the custom-fields module', v_field ->> 'key');
        exit steps;
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
$$;
revoke execute on function "better_supabase"."form_resolve"(uuid, jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."create_form"(tenant uuid, key text, title text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_form.tenant, 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if create_form.key is null or create_form.key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a form key is lowercase letters, digits, - and _, starting with a letter' using errcode = '22023', hint = 'FORM_KEY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."forms" x where x."tenant_id" = create_form.tenant and x."key" = create_form.key) then
    raise exception 'a form with this key exists' using errcode = '23505', hint = 'FORM_KEY_TAKEN';
  end if;
  insert into "better_supabase"."forms" ("tenant_id", "key", "title", "description", "created_by")
  values (create_form.tenant, create_form.key, create_form.title, create_form.description, auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_form"(uuid, text, text, text) to authenticated, service_role;

-- Changes the title, description or status. A form opens for submissions
-- once it has a published version.
create or replace function "better_supabase"."update_form"(form_id uuid, title text default null, description text default null, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."forms" x where x."id" = update_form.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if update_form.status is not null and update_form.status not in ('open', 'closed', 'archived') then
    raise exception 'status is open, closed or archived' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if update_form.status = 'open' and v_row."current_version_id" is null then
    raise exception 'publish a version before opening the form' using errcode = '55000', hint = 'FORM_NOT_PUBLISHED';
  end if;
  update "better_supabase"."forms" x set
    "title" = coalesce(update_form.title, x."title"),
    "description" = coalesce(update_form.description, x."description"),
    "status" = coalesce(update_form.status, x."status"),
    "updated_at" = now()
  where x."id" = update_form.form_id
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_form"(uuid, text, text, text) to authenticated, service_role;

-- Publishes a new version: checks the definition, copies custom fields in,
-- builds the version's JSON Schema and makes it current. A draft form opens.
create or replace function "better_supabase"."publish_form_version"(form_id uuid, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_resolved jsonb;
  v_number integer;
  v_row "better_supabase"."form_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_form from "better_supabase"."forms" x where x."id" = publish_form_version.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_form."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_publish"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using publish_form_version.form_id, publish_form_version.definition;
    end if;
  end;
  v_resolved := "better_supabase"."form_resolve"(v_form."tenant_id", publish_form_version.definition);
  select coalesce(max(x."number"), 0) + 1 into v_number from "better_supabase"."form_versions" x where x."form_id" = v_form."id";
  insert into "better_supabase"."form_versions" ("tenant_id", "form_id", "number", "definition", "schema", "created_by")
  values (v_form."tenant_id", v_form."id", v_number, v_resolved, "better_supabase"."form_schema"(v_resolved), auth.uid())
  returning * into v_row;
  update "better_supabase"."forms" x set
    "current_version_id" = v_row."id",
    "status" = case when x."status" = 'draft' then 'open' else x."status" end,
    "updated_at" = now()
  where x."id" = v_form."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."publish_form_version"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."publish_form_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_form"(form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
  v_version "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."forms" x where x."id" = get_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('version', case when v_version."id" is null then null else jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") end);
end;
$$;
revoke execute on function "better_supabase"."get_form"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_form_version"(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_versions" x where x."id" = get_form_version.version_id;
  if not found then
    raise exception 'form version not found' using errcode = 'P0002', hint = 'FORM_VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_version"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_forms"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."forms" x
  where x."tenant_id" = list_forms.tenant
    and (list_forms.status is null or x."status" = list_forms.status);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_forms"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_forms"(uuid, text) to authenticated, service_role;

-- Writes a submission against the form's current version, validating the
-- answers unless it is a draft. Only definer functions of this module call it.
create or replace function "better_supabase"."form_submission_save"(form_id uuid, answers jsonb, subject_type text, subject_id text, respondent uuid, source text, draft boolean, submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_schema jsonb;
  v_errors text[];
  v_row "better_supabase"."form_submissions"%rowtype;
  v_link jsonb;
begin
  select * into v_form from "better_supabase"."forms" x where x."id" = form_submission_save.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if v_form."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    raise exception 'answers must be an object' using errcode = '22023', hint = 'FORM_ANSWERS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_submission"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using form_submission_save.form_id, form_submission_save.answers;
    end if;
  end;
  if not form_submission_save.draft then
    select x."schema" into v_schema from "better_supabase"."form_versions" x where x."id" = v_form."current_version_id";
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      raise exception '%.answers does not match its JSON Schema: %', 'form_submissions', array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';
    end if;
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from "better_supabase"."form_submissions" x where x."id" = form_submission_save.submission_id for update;
    if not found or v_row."form_id" <> form_submission_save.form_id or v_row."respondent_id" is distinct from form_submission_save.respondent then
      raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'only a draft submission can change' using errcode = '55000', hint = 'FORM_SUBMISSION_LOCKED';
    end if;
    update "better_supabase"."form_submissions" x set
      "version_id" = v_form."current_version_id",
      "answers" = form_submission_save.answers,
      "status" = case when form_submission_save.draft then 'draft' else 'submitted' end,
      "submitted_at" = case when form_submission_save.draft then null else now() end,
      "subject_type" = coalesce(form_submission_save.subject_type, x."subject_type"),
      "subject_id" = coalesce(form_submission_save.subject_id, x."subject_id"),
      "updated_at" = now()
    where x."id" = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into "better_supabase"."form_submissions" ("tenant_id", "form_id", "version_id", "subject_type", "subject_id", "respondent_id", "answers", "status", "source", "submitted_at")
    values (v_form."tenant_id", v_form."id", v_form."current_version_id", form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end)
    returning * into v_row;
  end if;
  if not form_submission_save.draft then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_submission"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."form_submission_save"(uuid, jsonb, text, text, uuid, text, boolean, uuid) from public, anon, authenticated;

-- Submits answers as the caller, or saves them as a draft to finish later
-- (submission_id continues one). A subject links the submission to a record
-- the caller can read.
create or replace function "better_supabase"."submit_form"(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$$;
revoke execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."get_form_submission"(submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = get_form_submission.submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."respondent_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_submission"(uuid) to authenticated, service_role;

-- Newest first. Reviewers see every submission; others see their own.
create or replace function "better_supabase"."list_form_submissions"(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status" = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."review_form_submission"(submission_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = review_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to review submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    raise exception 'status is submitted, accepted or rejected' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "better_supabase"."form_submissions" x set
    "status" = review_form_submission.status,
    "reviewed_by" = auth.uid(),
    "reviewed_at" = now(),
    "updated_at" = now()
  where x."id" = review_form_submission.submission_id
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_form_submission"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_form_submission"(uuid, text) to authenticated, service_role;

-- Reviewers delete any submission; a respondent deletes their own draft.
create or replace function "better_supabase"."delete_form_submission"(submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)
    or (v_row."respondent_id" = auth.uid() and v_row."status" = 'draft')) then
    raise exception 'not allowed to delete this submission' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  delete from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_form_submission"(uuid) to authenticated, service_role;

-- sql.modules.forms.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."create_form"(tenant uuid, key text, title text, description text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_form"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_form"(uuid, text, text, text) from public, anon;
grant execute on function "api"."create_form"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."update_form"(form_id uuid, title text default null, description text default null, status text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_form"($1, $2, $3, $4) $$;
revoke execute on function "api"."update_form"(uuid, text, text, text) from public, anon;
grant execute on function "api"."update_form"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."publish_form_version"(form_id uuid, definition jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_form_version"($1, $2) $$;
revoke execute on function "api"."publish_form_version"(uuid, jsonb) from public, anon;
grant execute on function "api"."publish_form_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."get_form"(form_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_form"($1) $$;
revoke execute on function "api"."get_form"(uuid) from public, anon;
grant execute on function "api"."get_form"(uuid) to authenticated, service_role;

create or replace function "api"."get_form_version"(version_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_form_version"($1) $$;
revoke execute on function "api"."get_form_version"(uuid) from public, anon;
grant execute on function "api"."get_form_version"(uuid) to authenticated, service_role;

create or replace function "api"."list_forms"(tenant uuid, status text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_forms"($1, $2) $$;
revoke execute on function "api"."list_forms"(uuid, text) from public, anon;
grant execute on function "api"."list_forms"(uuid, text) to authenticated, service_role;

create or replace function "api"."submit_form"(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_form"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."submit_form"(uuid, jsonb, text, text, uuid, boolean) from public, anon;
grant execute on function "api"."submit_form"(uuid, jsonb, text, text, uuid, boolean) to authenticated, service_role;

create or replace function "api"."get_form_submission"(submission_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_form_submission"($1) $$;
revoke execute on function "api"."get_form_submission"(uuid) from public, anon;
grant execute on function "api"."get_form_submission"(uuid) to authenticated, service_role;

create or replace function "api"."list_form_submissions"(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_form_submissions"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_form_submissions"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "api"."list_form_submissions"(uuid, text, integer, timestamptz) to authenticated, service_role;

create or replace function "api"."review_form_submission"(submission_id uuid, status text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."review_form_submission"($1, $2) $$;
revoke execute on function "api"."review_form_submission"(uuid, text) from public, anon;
grant execute on function "api"."review_form_submission"(uuid, text) to authenticated, service_role;

create or replace function "api"."delete_form_submission"(submission_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_form_submission"($1) $$;
revoke execute on function "api"."delete_form_submission"(uuid) from public, anon;
grant execute on function "api"."delete_form_submission"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module-data forms
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('forms', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module forms@1 adopt
-- Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, and handlers that turn a submission into a record.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- The schema of one field's answer. Mirrors fieldSchema in
-- core/contracts/form-definition.ts.
create or replace function "better_supabase"."form_field_schema"(field jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text := field ->> 'type';
  -- required only asks for the key, so an empty answer needs its own floor.
  v_floor jsonb := case when field -> 'required' = 'true'::jsonb then '1'::jsonb end;
  v_values jsonb;
  v_out jsonb;
begin
  select coalesce(jsonb_agg(o.value -> 'value' order by o.ord), '[]'::jsonb) into v_values
    from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) with ordinality as o(value, ord);
  v_out := case v_type
    when 'text' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '500'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'textarea' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '10000'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'email' then jsonb_build_object('type', 'string', 'format', 'email', 'maxLength', 320)
    when 'url' then jsonb_build_object('type', 'string', 'format', 'uri', 'maxLength', 2000)
    when 'number' then jsonb_build_object('type', 'number') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'integer' then jsonb_build_object('type', 'integer') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'date' then '{"type": "string", "format": "date"}'::jsonb
    when 'bool' then '{"type": "boolean"}'::jsonb
    when 'consent' then '{"type": "boolean", "const": true}'::jsonb
    when 'option' then jsonb_build_object('type', 'string', 'enum', v_values)
    when 'multi' then jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string', 'enum', v_values), 'uniqueItems', true)
      || jsonb_strip_nulls(jsonb_build_object('minItems', coalesce(field -> 'min', v_floor), 'maxItems', field -> 'max'))
    else '{}'::jsonb
  end;
  return v_out || jsonb_strip_nulls(jsonb_build_object('title', field -> 'label', 'description', field -> 'help'));
end;
$$;
revoke execute on function "better_supabase"."form_field_schema"(jsonb) from public, anon, authenticated;

-- The schema a showIf condition holds under, as an if.
create or replace function "better_supabase"."form_condition_schema"(condition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'properties', jsonb_build_object(condition ->> 'field',
      case
        when condition ? 'equals' then jsonb_build_object('const', condition -> 'equals')
        when condition ? 'in' then jsonb_build_object('enum', condition -> 'in')
        else '{"not": {"enum": [null, "", []]}}'::jsonb
      end),
    'required', jsonb_build_array(condition ->> 'field'))
$$;
revoke execute on function "better_supabase"."form_condition_schema"(jsonb) from public, anon, authenticated;

-- The JSON Schema 2020-12 a version's answers validate against. Mirrors
-- formSchema in core/contracts/form-definition.ts: a required field with a
-- showIf (its own or its step's) is required only while the condition holds.
create or replace function "better_supabase"."form_schema"(definition jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_properties jsonb := '{}'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_conditional jsonb := '[]'::jsonb;
  v_conditions jsonb;
  v_step jsonb;
  v_field jsonb;
begin
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      v_properties := v_properties || jsonb_build_object(v_field ->> 'key', "better_supabase"."form_field_schema"(v_field));
      continue when coalesce((v_field ->> 'required')::boolean, false) is false;
      v_conditions := '[]'::jsonb;
      if v_step ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_step -> 'showIf'));
      end if;
      if v_field ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array("better_supabase"."form_condition_schema"(v_field -> 'showIf'));
      end if;
      if jsonb_array_length(v_conditions) = 0 then
        v_required := v_required || jsonb_build_array(v_field ->> 'key');
      else
        v_conditional := v_conditional || jsonb_build_array(jsonb_build_object(
          'if', case when jsonb_array_length(v_conditions) = 1 then v_conditions -> 0 else jsonb_build_object('allOf', v_conditions) end,
          'then', jsonb_build_object('required', jsonb_build_array(v_field ->> 'key'))));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('$schema', 'https://json-schema.org/draft/2020-12/schema', 'type', 'object', 'properties', v_properties, 'additionalProperties', false)
    || case when jsonb_array_length(v_required) > 0 then jsonb_build_object('required', v_required) else '{}'::jsonb end
    || case when jsonb_array_length(v_conditional) > 0 then jsonb_build_object('allOf', v_conditional) else '{}'::jsonb end;
end;
$$;
revoke execute on function "better_supabase"."form_schema"(jsonb) from public, anon, authenticated;

-- Checks a definition (its shape, then what the shape can't say, as
-- formDefinitionProblems does) and copies each customField's definition in.
create or replace function "better_supabase"."form_resolve"(tenant uuid, definition jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
        v_problem := format('field %s: customField needs the custom-fields module', v_field ->> 'key');
        exit steps;
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
$$;
revoke execute on function "better_supabase"."form_resolve"(uuid, jsonb) from public, anon, authenticated;

create or replace function "better_supabase"."create_form"(tenant uuid, key text, title text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_form.tenant, 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if create_form.key is null or create_form.key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a form key is lowercase letters, digits, - and _, starting with a letter' using errcode = '22023', hint = 'FORM_KEY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."forms" x where x."tenant_id" = create_form.tenant and x."key" = create_form.key) then
    raise exception 'a form with this key exists' using errcode = '23505', hint = 'FORM_KEY_TAKEN';
  end if;
  insert into "better_supabase"."forms" ("tenant_id", "key", "title", "description", "created_by")
  values (create_form.tenant, create_form.key, create_form.title, create_form.description, auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_form"(uuid, text, text, text) to authenticated, service_role;

-- Changes the title, description or status. A form opens for submissions
-- once it has a published version.
create or replace function "better_supabase"."update_form"(form_id uuid, title text default null, description text default null, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."forms" x where x."id" = update_form.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if update_form.status is not null and update_form.status not in ('open', 'closed', 'archived') then
    raise exception 'status is open, closed or archived' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if update_form.status = 'open' and v_row."current_version_id" is null then
    raise exception 'publish a version before opening the form' using errcode = '55000', hint = 'FORM_NOT_PUBLISHED';
  end if;
  update "better_supabase"."forms" x set
    "title" = coalesce(update_form.title, x."title"),
    "description" = coalesce(update_form.description, x."description"),
    "status" = coalesce(update_form.status, x."status"),
    "updated_at" = now()
  where x."id" = update_form.form_id
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_form"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."update_form"(uuid, text, text, text) to authenticated, service_role;

-- Publishes a new version: checks the definition, copies custom fields in,
-- builds the version's JSON Schema and makes it current. A draft form opens.
create or replace function "better_supabase"."publish_form_version"(form_id uuid, definition jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_resolved jsonb;
  v_number integer;
  v_row "better_supabase"."form_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_form from "better_supabase"."forms" x where x."id" = publish_form_version.form_id for update;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_form."tenant_id", 'forms.manage'), false)) then
    raise exception 'not allowed to manage forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_publish"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using publish_form_version.form_id, publish_form_version.definition;
    end if;
  end;
  v_resolved := "better_supabase"."form_resolve"(v_form."tenant_id", publish_form_version.definition);
  select coalesce(max(x."number"), 0) + 1 into v_number from "better_supabase"."form_versions" x where x."form_id" = v_form."id";
  insert into "better_supabase"."form_versions" ("tenant_id", "form_id", "number", "definition", "schema", "created_by")
  values (v_form."tenant_id", v_form."id", v_number, v_resolved, "better_supabase"."form_schema"(v_resolved), auth.uid())
  returning * into v_row;
  update "better_supabase"."forms" x set
    "current_version_id" = v_row."id",
    "status" = case when x."status" = 'draft' then 'open' else x."status" end,
    "updated_at" = now()
  where x."id" = v_form."id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_publish"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."publish_form_version"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."publish_form_version"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."get_form"(form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."forms"%rowtype;
  v_version "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."forms" x where x."id" = get_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select * into v_version from "better_supabase"."form_versions" x where x."id" = v_row."current_version_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'status', v_row."status", 'currentVersionId', v_row."current_version_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('version', case when v_version."id" is null then null else jsonb_build_object('id', v_version."id", 'formId', v_version."form_id", 'number', v_version."number", 'definition', v_version."definition", 'schema', v_version."schema", 'createdBy', v_version."created_by", 'createdAt', v_version."created_at") end);
end;
$$;
revoke execute on function "better_supabase"."get_form"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_form_version"(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_versions" x where x."id" = get_form_version.version_id;
  if not found then
    raise exception 'form version not found' using errcode = 'P0002', hint = 'FORM_VERSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)) then
    raise exception 'not allowed to read this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'formId', v_row."form_id", 'number', v_row."number", 'definition', v_row."definition", 'schema', v_row."schema", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_version"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_version"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_forms"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."forms" x
  where x."tenant_id" = list_forms.tenant
    and (list_forms.status is null or x."status" = list_forms.status);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_forms"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_forms"(uuid, text) to authenticated, service_role;

-- Writes a submission against the form's current version, validating the
-- answers unless it is a draft. Only definer functions of this module call it.
create or replace function "better_supabase"."form_submission_save"(form_id uuid, answers jsonb, subject_type text, subject_id text, respondent uuid, source text, draft boolean, submission_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form "better_supabase"."forms"%rowtype;
  v_schema jsonb;
  v_errors text[];
  v_row "better_supabase"."form_submissions"%rowtype;
  v_link jsonb;
begin
  select * into v_form from "better_supabase"."forms" x where x."id" = form_submission_save.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if v_form."status" <> 'open' then
    raise exception 'this form isn''t taking submissions' using errcode = '55000', hint = 'FORM_CLOSED';
  end if;
  if jsonb_typeof(form_submission_save.answers) is distinct from 'object' then
    raise exception 'answers must be an object' using errcode = '22023', hint = 'FORM_ANSWERS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_form_submission"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using form_submission_save.form_id, form_submission_save.answers;
    end if;
  end;
  if not form_submission_save.draft then
    select x."schema" into v_schema from "better_supabase"."form_versions" x where x."id" = v_form."current_version_id";
    v_errors := extensions.jsonschema_validation_errors(v_schema::json, form_submission_save.answers::json);
    if cardinality(v_errors) > 0 then
      raise exception '%.answers does not match its JSON Schema: %', 'form_submissions', array_to_string(v_errors, '; ')
      using errcode = '23514', column = 'answers', detail = to_jsonb(v_errors)::text, hint = 'JSON_SCHEMA_INVALID';
    end if;
  end if;
  if form_submission_save.submission_id is not null then
    select * into v_row from "better_supabase"."form_submissions" x where x."id" = form_submission_save.submission_id for update;
    if not found or v_row."form_id" <> form_submission_save.form_id or v_row."respondent_id" is distinct from form_submission_save.respondent then
      raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
    end if;
    if v_row."status" <> 'draft' then
      raise exception 'only a draft submission can change' using errcode = '55000', hint = 'FORM_SUBMISSION_LOCKED';
    end if;
    update "better_supabase"."form_submissions" x set
      "version_id" = v_form."current_version_id",
      "answers" = form_submission_save.answers,
      "status" = case when form_submission_save.draft then 'draft' else 'submitted' end,
      "submitted_at" = case when form_submission_save.draft then null else now() end,
      "subject_type" = coalesce(form_submission_save.subject_type, x."subject_type"),
      "subject_id" = coalesce(form_submission_save.subject_id, x."subject_id"),
      "updated_at" = now()
    where x."id" = form_submission_save.submission_id
    returning * into v_row;
  else
    insert into "better_supabase"."form_submissions" ("tenant_id", "form_id", "version_id", "subject_type", "subject_id", "respondent_id", "answers", "status", "source", "submitted_at")
    values (v_form."tenant_id", v_form."id", v_form."current_version_id", form_submission_save.subject_type, form_submission_save.subject_id, form_submission_save.respondent, form_submission_save.answers,
      case when form_submission_save.draft then 'draft' else 'submitted' end, form_submission_save.source,
      case when form_submission_save.draft then null else now() end)
    returning * into v_row;
  end if;
  if not form_submission_save.draft then
    null;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_form_submission"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."form_submission_save"(uuid, jsonb, text, text, uuid, text, boolean, uuid) from public, anon, authenticated;

-- Submits answers as the caller, or saves them as a draft to finish later
-- (submission_id continues one). A subject links the submission to a record
-- the caller can read.
create or replace function "better_supabase"."submit_form"(form_id uuid, answers jsonb, subject_type text default null, subject_id text default null, submission_id uuid default null, draft boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$$;
revoke execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."submit_form"(uuid, jsonb, text, text, uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."get_form_submission"(submission_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = get_form_submission.submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."respondent_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."get_form_submission"(uuid) to authenticated, service_role;

-- Newest first. Reviewers see every submission; others see their own.
create or replace function "better_supabase"."list_form_submissions"(form_id uuid, status text default null, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status" = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."list_form_submissions"(uuid, text, integer, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."review_form_submission"(submission_id uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = review_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)) then
    raise exception 'not allowed to review submissions' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if review_form_submission.status is null or review_form_submission.status not in ('submitted', 'accepted', 'rejected') then
    raise exception 'status is submitted, accepted or rejected' using errcode = '22023', hint = 'FORM_STATUS_INVALID';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft isn''t submitted yet' using errcode = '55000', hint = 'FORM_SUBMISSION_DRAFT';
  end if;
  update "better_supabase"."form_submissions" x set
    "status" = review_form_submission.status,
    "reviewed_by" = auth.uid(),
    "reviewed_at" = now(),
    "updated_at" = now()
  where x."id" = review_form_submission.submission_id
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'formId', v_row."form_id", 'versionId', v_row."version_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'respondentId', v_row."respondent_id", 'answers', v_row."answers", 'status', v_row."status", 'source', v_row."source", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at", 'createdAt', v_row."created_at", 'submittedAt', v_row."submitted_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."review_form_submission"(uuid, text) from public, anon;
grant execute on function "better_supabase"."review_form_submission"(uuid, text) to authenticated, service_role;

-- Reviewers delete any submission; a respondent deletes their own draft.
create or replace function "better_supabase"."delete_form_submission"(submission_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."form_submissions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id for update;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002', hint = 'FORM_SUBMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.review'), false)
    or (v_row."respondent_id" = auth.uid() and v_row."status" = 'draft')) then
    raise exception 'not allowed to delete this submission' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  delete from "better_supabase"."form_submissions" x where x."id" = delete_form_submission.submission_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_form_submission"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_form_submission"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_86_forms.sql
-- better-supabase module: forms
-- @bs-module-data forms
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('forms', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
