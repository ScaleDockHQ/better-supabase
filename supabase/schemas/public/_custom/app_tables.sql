-- Statements of the old app tables file that belong to no single table.
create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
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

create or replace function "better_supabase"."tasks_emit_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_changed text[];
begin
  if tg_op = 'INSERT' then
    v_row := to_jsonb(new);
    perform "better_supabase".emit_event('task.created', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'project_id', v_row -> 'project_id'), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  if tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    select coalesce(array_agg(n.key order by n.key), array[]::text[]) into v_changed
      from jsonb_each(v_row) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value and n.key <> 'updated_at';
    if cardinality(v_changed) > 0 then
      perform "better_supabase".emit_event('task.updated', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'project_id', v_row -> 'project_id', 'changed', to_jsonb(v_changed)), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
    end if;
  end if;
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    perform "better_supabase".emit_event('task.deleted', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'project_id', v_row -> 'project_id'), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  return null;
end;
$$;

revoke all on function "better_supabase"."tasks_emit_event"() from public, anon, authenticated;

create or replace function "better_supabase"."client_notes_seal"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text := 'tenant:' || (new."organization_id")::text;
  v_old_owner text;
  v_moved boolean := false;
  v_key text;
begin
  if tg_op = 'UPDATE' then
    v_old_owner := 'tenant:' || (old."organization_id")::text;
    v_moved := v_owner is distinct from v_old_owner;
  end if;
  if new."diagnosis" is not null and (case when tg_op = 'INSERT' then true else new."diagnosis" is distinct from old."diagnosis" end or left(new."diagnosis", 5) <> 'bsf1:') then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."diagnosis" := "better_supabase"."field_seal"(v_key, new."diagnosis");
  elsif new."diagnosis" is not null and v_moved then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."diagnosis" := "better_supabase"."field_seal"(v_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."diagnosis"));
  end if;
  if new."birth_date" is not null and (case when tg_op = 'INSERT' then true else new."birth_date" is distinct from old."birth_date" end or left(new."birth_date", 5) <> 'bsf1:') then
    new."birth_date" := ((new."birth_date")::date)::text;
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."birth_date" := "better_supabase"."field_seal"(v_key, new."birth_date");
  elsif new."birth_date" is not null and v_moved then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."birth_date" := "better_supabase"."field_seal"(v_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."birth_date"));
  end if;
  return new;
end;
$$;

revoke all on function "better_supabase"."client_notes_seal"() from public, anon, authenticated;

create or replace function "better_supabase"."client_notes_reveal"(ids uuid[])
returns table (id uuid, "diagnosis" text, "birth_date" date)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_read record;
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role reveal client_notes' using errcode = '42501', hint = 'APP_REVEAL_FORBIDDEN';
  end if;
  if coalesce(cardinality(client_notes_reveal.ids), 0) > 500 then
    raise exception 'reveal at most 500 rows of client_notes per call' using errcode = '22023', hint = 'APP_REVEAL_TOO_MANY';
  end if;
  for v_read in
    select t."organization_id" as tenant, jsonb_agg(t.id order by t.id) as ids
    from "public"."client_notes" t
    where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    group by 1
  loop
    perform better_supabase.audit_event(
    event_type => 'client_notes.viewed',
    category => 'read',
    target_type => 'client_notes',
    record_id => case when jsonb_array_length(v_read.ids) = 1 then v_read.ids ->> 0 end,
    summary => 'Revealed ' || jsonb_array_length(v_read.ids)::text || ' ' || 'client_notes' || ' record(s)',
    tenant => (v_read.tenant)::uuid,
    metadata => jsonb_build_object('ids', v_read.ids, 'columns', '["diagnosis","birth_date"]'::jsonb)
  );
  end loop;
  return query
    with r as materialized (
      select t.id, 'tenant:' || (t."organization_id")::text as bsb_owner, t."diagnosis", t."birth_date"
      from "public"."client_notes" t
      where t.id = any (client_notes_reveal.ids) and (v_service or ("organization_id" in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active())))
    ),
    k as materialized (
      select o.bsb_owner, "better_supabase"."field_key"(o.bsb_owner, false) as bsb_key
      from (select distinct r.bsb_owner from r) o
    )
    select r.id, ("better_supabase"."field_open"(k.bsb_key, r."diagnosis"))::text, ("better_supabase"."field_open"(k.bsb_key, r."birth_date"))::date
    from r join k on k.bsb_owner = r.bsb_owner;
end;
$$;

revoke execute on function "better_supabase"."client_notes_reveal"(uuid[]) from public, anon;

grant execute on function "better_supabase"."client_notes_reveal"(uuid[]) to authenticated, service_role;

create or replace function "public"."client_notes_reveal"(ids uuid[])
returns table (id uuid, "diagnosis" text, "birth_date" date)
language sql
security invoker
set search_path = ''
as $$
  select * from "better_supabase"."client_notes_reveal"(ids);
$$;

revoke execute on function "public"."client_notes_reveal"(uuid[]) from public, anon;

grant execute on function "public"."client_notes_reveal"(uuid[]) to authenticated, service_role;

create or replace function public."app_table_set"(tenant uuid, subject_type text, subject_id text, args jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_values jsonb := coalesce(app_table_set.args -> 'values', '{}'::jsonb);
  v_count integer := 0;
begin
  if jsonb_typeof(v_values) <> 'object' or v_values = '{}'::jsonb then
    raise exception 'pass the columns to set as args.values' using errcode = '22023', hint = 'APP_TABLE_SET_EMPTY';
  end if;
  case app_table_set.subject_type
    when 'project' then
      if exists (select 1 from jsonb_object_keys(v_values) k where not (k = any ('{name,budget_minor,currency,lead_id,label_id}'::text[]))) then
        raise exception 'only these columns of projects can be set: name, budget_minor, currency, lead_id, label_id' using errcode = '22023', hint = 'APP_TABLE_SET_COLUMN';
      end if;
      update public."projects" t set
          "name" = case when v_values ? 'name' then r."name" else t."name" end,
          "budget_minor" = case when v_values ? 'budget_minor' then r."budget_minor" else t."budget_minor" end,
          "currency" = case when v_values ? 'currency' then r."currency" else t."currency" end,
          "lead_id" = case when v_values ? 'lead_id' then r."lead_id" else t."lead_id" end,
          "label_id" = case when v_values ? 'label_id' then r."label_id" else t."label_id" end
        from jsonb_populate_record(null::public."projects", v_values) r
        where t.id = app_table_set.subject_id::uuid
        and t."organization_id" = app_table_set.tenant;
      get diagnostics v_count = row_count;
    when 'task' then
      if exists (select 1 from jsonb_object_keys(v_values) k where not (k = any ('{title,status,starts_on,due_on,assignee_id,project_id}'::text[]))) then
        raise exception 'only these columns of tasks can be set: title, status, starts_on, due_on, assignee_id, project_id' using errcode = '22023', hint = 'APP_TABLE_SET_COLUMN';
      end if;
      update public."tasks" t set
          "title" = case when v_values ? 'title' then r."title" else t."title" end,
          "status" = case when v_values ? 'status' then r."status" else t."status" end,
          "starts_on" = case when v_values ? 'starts_on' then r."starts_on" else t."starts_on" end,
          "due_on" = case when v_values ? 'due_on' then r."due_on" else t."due_on" end,
          "assignee_id" = case when v_values ? 'assignee_id' then r."assignee_id" else t."assignee_id" end,
          "project_id" = case when v_values ? 'project_id' then r."project_id" else t."project_id" end
        from jsonb_populate_record(null::public."tasks", v_values) r
        where t.id = app_table_set.subject_id::uuid
        and t."organization_id" = app_table_set.tenant;
      get diagnostics v_count = row_count;
    else
      raise exception 'not an app table subject type' using errcode = '22023', hint = 'APP_TABLE_SET_SUBJECT';
  end case;
  if v_count = 0 then
    raise exception 'row not found or not writable' using errcode = 'P0002', hint = 'APP_TABLE_SET_NOT_FOUND';
  end if;
end;
$$;

revoke execute on function public."app_table_set"(uuid, text, text, jsonb) from public, anon;

grant execute on function public."app_table_set"(uuid, text, text, jsonb) to authenticated, service_role;
