-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:5ada12eab77b183b39b27a8c328b460f4b2e55ae0c3304e41f9687b9d4fc1b3b
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_user_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists status_history_read on "better_supabase"."status_history";
create policy status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (case "better_supabase"."status_history"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."status_history"."subject_id")::uuid)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."status_history"."subject_id")::uuid)
      else false
    end);
create table if not exists "better_supabase"."status_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "label" text not null,
  "outcome" text,
  "display" integer not null,
  "cleared_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists status_stages_read on "better_supabase"."status_stages";
create policy status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (case "better_supabase"."status_stages"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."status_stages"."subject_id")::uuid)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."status_stages"."subject_id")::uuid)
      else false
    end);
create table if not exists "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "paused_until" timestamptz,
  "pause_reason" text,
  "paused_by_user_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "better_supabase"."subject_lifecycles";
create policy subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (case "better_supabase"."subject_lifecycles"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."subject_lifecycles"."subject_id")::uuid)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."subject_lifecycles"."subject_id")::uuid)
      else false
    end);

-- The workflow-editor version a workflow machine's record follows.
alter table "better_supabase"."subject_lifecycles" add column if not exists "workflow_version_id" uuid references "better_supabase"."workflow_versions" ("id") on delete set null;
create index if not exists "subject_lifecycles_workflow_version_idx" on "better_supabase"."subject_lifecycles" ("workflow_version_id");

-- A workflow version's graph as a machine: { initial, order, transitions }.
-- Stages are the nodes with a string config.stage, in graph order; a path
-- from one stage to the next through nodes without a stage is a transition,
-- as are the stages a stage's config.returnsTo lists. initial is the trigger's
-- own stage, else the nearest stage after a trigger, else the first stage.
-- Null when the version doesn't exist.
create or replace function "better_supabase"."lifecycle_graph"(version_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive g as (
    select (select v."graph" from "better_supabase"."workflow_versions" v where v."id" = lifecycle_graph.version_id) as graph
  ),
  nodes as (
    select n.value ->> 'id' as id, n.value ->> 'kind' as kind,
      case when jsonb_typeof(n.value -> 'config' -> 'stage') = 'string' then n.value -> 'config' ->> 'stage' end as stage,
      case when jsonb_typeof(n.value -> 'config' -> 'returnsTo') = 'array' then n.value -> 'config' -> 'returnsTo' else '[]'::jsonb end as back,
      n.ord
    from g, jsonb_array_elements(case when jsonb_typeof(g.graph -> 'nodes') = 'array' then g.graph -> 'nodes' else '[]'::jsonb end) with ordinality n (value, ord)
  ),
  edges as (
    select e.value ->> 'source' as source, e.value ->> 'target' as target
    from g, jsonb_array_elements(case when jsonb_typeof(g.graph -> 'edges') = 'array' then g.graph -> 'edges' else '[]'::jsonb end) e (value)
  ),
  walk (origin, node, depth) as (
    select o.id, e.target, 1
    from nodes o join edges e on e.source = o.id
    where o.stage is not null or o.kind = 'trigger'
    union
    select w.origin, e.target, w.depth + 1
    from walk w
    join nodes m on m.id = w.node and m.stage is null
    join edges e on e.source = w.node
    where w.depth < 100
  ),
  reached as (
    select o.kind as origin_kind, o.stage as from_stage, t.stage as to_stage, min(w.depth) as depth, min(t.ord) as ord
    from walk w
    join nodes o on o.id = w.origin
    join nodes t on t.id = w.node
    where t.stage is not null
    group by o.kind, o.stage, t.stage
  ),
  stages as (
    select n.stage, min(n.ord) as ord from nodes n where n.stage is not null group by n.stage
  ),
  moves as (
    select r.from_stage, r.to_stage from reached r
    where r.from_stage is not null and r.from_stage <> r.to_stage
    union
    select n.stage, b.value #>> '{}'
    from nodes n, jsonb_array_elements(n.back) b (value)
    where n.stage is not null and jsonb_typeof(b.value) = 'string'
      and b.value #>> '{}' <> n.stage
      and exists (select 1 from stages s where s.stage = b.value #>> '{}')
  )
  select jsonb_build_object(
    'initial', coalesce(
      (select n.stage from nodes n where n.kind = 'trigger' and n.stage is not null order by n.ord limit 1),
      (select r.to_stage from reached r where r.origin_kind = 'trigger' and r.from_stage is null order by r.depth, r.ord limit 1),
      (select s.stage from stages s order by s.ord limit 1)),
    'order', coalesce((select jsonb_agg(s.stage order by s.ord) from stages s), '[]'::jsonb),
    'transitions', coalesce((select jsonb_object_agg(m.from_stage, m.targets)
      from (select x.from_stage, jsonb_agg(distinct x.to_stage order by x.to_stage) as targets from moves x group by x.from_stage) m), '{}'::jsonb))
  from g
  where g.graph is not null
$$;
revoke execute on function "better_supabase"."lifecycle_graph"(uuid) from public, anon;
grant execute on function "better_supabase"."lifecycle_graph"(uuid) to authenticated, service_role;


create or replace function better_supabase.bsb_transition_work_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state"::text when 'triage' then new."state"::text = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state"::text = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state"::text = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state"::text = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state"::text = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state"::text = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, old."state"::text, new."state"::text, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$$;
drop trigger if exists bsb_transition_work_item on "better_supabase"."work_items";
create trigger bsb_transition_work_item before insert or update of "state" on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_transition_work_item();

create or replace function better_supabase.bsb_transition_change_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_op jsonb;
  v_flag text;
  v_flags text[];
  v_until timestamptz;
  v_paused boolean;
  v_version uuid;
  v_number integer;
  v_graph jsonb;
begin
  if tg_op = 'INSERT' then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    v_graph := "better_supabase"."lifecycle_graph"(v_version);
    if new."status" is null then
      new."status" := v_graph ->> 'initial';
    end if;
    if new."status" is null or not ((v_graph -> 'order') ? new."status"::text) then
      raise exception 'that status is not a stage of the machine''s workflow' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
    return new;
  end if;
  if new."status" is not distinct from old."status" then
    v_op := nullif(current_setting('better_supabase.lifecycle_op', true), '')::jsonb;
    if v_op is not null and v_op ->> 'machine' = 'change_request' and v_op ->> 'id' = new."id"::text then
      case v_op ->> 'op'
        when 'pause' then
          if (v_op ->> 'until') is not null and (v_op ->> 'until')::timestamptz <= now() then
            raise exception 'a pause must end in the future' using errcode = '22023', hint = 'STATE_PAUSE_INVALID';
          end if;
          insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "paused_at", "paused_until", "pause_reason", "paused_by_user_id")
          values (new."organization_id", 'change_request', new."id"::text, 1, now(), (v_op ->> 'until')::timestamptz, nullif(v_op ->> 'reason', ''), auth.uid())
          on conflict ("subject_type", "subject_id") do update set
            "paused_at" = excluded."paused_at",
            "paused_until" = excluded."paused_until",
            "pause_reason" = excluded."pause_reason",
            "paused_by_user_id" = excluded."paused_by_user_id",
            "updated_at" = now();
          perform set_config('better_supabase.lifecycle_changed', '1', true);
          perform "better_supabase".emit_event('status.paused', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'until', v_op ->> 'until', 'reason', nullif(v_op ->> 'reason', '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
        when 'resume' then
          update "better_supabase"."subject_lifecycles" set "paused_at" = null, "paused_until" = null, "pause_reason" = null, "paused_by_user_id" = null, "updated_at" = now()
          where "subject_type" = 'change_request' and "subject_id" = new."id"::text and "paused_at" is not null;
          if found then
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        when 'flag' then
          v_flag := v_op ->> 'flag';
          if v_flag is null or not (v_flag = any ('{}'::text[])) then
            raise exception 'the machine has no such flag' using errcode = '22023', hint = 'STATE_FLAG_UNKNOWN';
          end if;
          select coalesce("flags", '{}') into v_flags from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text for update;
          v_flags := coalesce(v_flags, '{}');
          if coalesce((v_op ->> 'enabled')::boolean, false) is distinct from (v_flag = any (v_flags)) then
            v_flags := case when coalesce((v_op ->> 'enabled')::boolean, false)
              then v_flags || v_flag else array_remove(v_flags, v_flag) end;
            insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "flags")
            values (new."organization_id", 'change_request', new."id"::text, 1, v_flags)
            on conflict ("subject_type", "subject_id") do update set
              "flags" = excluded."flags",
              "updated_at" = now();
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.flagged', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'flag', v_flag, 'enabled', coalesce((v_op ->> 'enabled')::boolean, false)), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        else
          raise exception 'unknown lifecycle change' using errcode = '22023', hint = 'STATE_LIFECYCLE_INVALID';
      end case;
    end if;
    return new;
  end if;
  select "workflow_version_id" into v_version from "better_supabase"."subject_lifecycles"
  where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if v_version is null then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
  end if;
  v_graph := "better_supabase"."lifecycle_graph"(v_version);
  if not coalesce((v_graph -> 'transitions' -> old."status"::text) ? new."status"::text, false) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  select "paused_until", "paused_at" is not null into v_until, v_paused from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if coalesce(v_paused, false) then
    if v_until is null or v_until > now() then
      raise exception 'the record is paused; resume it first' using errcode = '55000', hint = 'STATE_PAUSED';
    end if;
    update "better_supabase"."subject_lifecycles" set "paused_at" = null, "paused_until" = null, "pause_reason" = null, "paused_by_user_id" = null, "updated_at" = now()
    where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
    perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."organization_id", 'change_request', new."id"::text, old."status"::text, new."status"::text, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'from', old."status"::text, 'to', new."status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$$;
drop trigger if exists bsb_transition_change_request on "public"."change_requests";
create trigger bsb_transition_change_request before insert or update of "status" on "public"."change_requests"
for each row execute function better_supabase.bsb_transition_change_request();

drop function if exists "better_supabase"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  case transition.subject_type
    when 'work_item' then
      update "better_supabase"."work_items" s set "state" = better_supabase.as_column_type(transition.to_status, (null::"better_supabase"."work_items")."state")
      where s."id" = (transition.subject_id)::uuid;
    when 'change_request' then
      update "public"."change_requests" s set "status" = better_supabase.as_column_type(transition.to_status, (null::"public"."change_requests")."status")
      where s."id" = (transition.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "better_supabase"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  case pause_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    when 'change_request' then
      update "public"."change_requests" s set "status" = s."status"
      where s."id" = (pause_lifecycle.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "better_supabase"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  case resume_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    when 'change_request' then
      update "public"."change_requests" s set "status" = s."status"
      where s."id" = (resume_lifecycle.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "better_supabase"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "better_supabase"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  case set_lifecycle_flag.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    when 'change_request' then
      update "public"."change_requests" s set "status" = s."status"
      where s."id" = (set_lifecycle_flag.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
  v_life "better_supabase"."subject_lifecycles"%rowtype;
  v_order text[];
begin
  case status_state.subject_type
    when 'work_item' then
      select s."state"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."work_items" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position('{triage,backlog,unstarted,started,completed}'::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'work_item', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb('{triage,backlog,unstarted,started,completed}'::text[]), 'step', v_step, 'steps', 5, 'progress', case when v_step is null then null when 5 = 1 then 1 else round((v_step - 1)::numeric / 4, 4) end,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    when 'change_request' then
      select s."status"::text, s."organization_id"::text into v_status, v_tenant
      from "public"."change_requests" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      select * into v_life from "better_supabase"."subject_lifecycles" x
      where x."subject_type" = 'change_request' and x."subject_id" = status_state.subject_id;
      v_paused := v_life."paused_at" is not null and (v_life."paused_until" is null or v_life."paused_until" > now());
      v_order := coalesce(array(select jsonb_array_elements_text("better_supabase"."lifecycle_graph"(v_life."workflow_version_id") -> 'order')), '{}'::text[]);
      v_step := array_position(v_order, v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'change_request', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(v_order), 'step', v_step, 'steps', nullif(cardinality(v_order), 0), 'progress', case when v_step is null then null when cardinality(v_order) = 1 then 1 else round((v_step - 1)::numeric / (cardinality(v_order) - 1), 4) end,
        'version', v_life."version", 'flags', to_jsonb(coalesce(v_life."flags", '{}')),
        'paused', v_paused, 'pausedAt', case when v_paused then v_life."paused_at" end,
        'pausedUntil', case when v_paused then v_life."paused_until" end,
        'pauseReason', case when v_paused then v_life."pause_reason" end, 'workflow', 'change-requests', 'workflowVersionId', v_life."workflow_version_id");
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."status_state"(text, text) from public, anon;
grant execute on function "better_supabase"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "better_supabase"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case list_status_history.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'work_item'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'change_request' then
      if not exists (select 1 from "public"."change_requests" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'change_request'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "better_supabase"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case list_status_stages.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    when 'change_request' then
      if not exists (select 1 from "public"."change_requests" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (case "better_supabase"."status_history"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."status_history"."subject_id")::uuid)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."status_history"."subject_id")::uuid)
      else false
    end)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (case "better_supabase"."status_stages"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."status_stages"."subject_id")::uuid)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."status_stages"."subject_id")::uuid)
      else false
    end)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (case "better_supabase"."subject_lifecycles"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."subject_lifecycles"."subject_id")::uuid)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."subject_lifecycles"."subject_id")::uuid)
      else false
    end)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.state-machine.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."lifecycle_graph"(uuid);

drop function if exists "api"."transition"(text, text, text, text);

create or replace function "api"."as_column_type"(value text, target anyelement)
returns anyelement
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."as_column_type"($1, $2) $$;
revoke execute on function "api"."as_column_type"(text, anyelement) from public;
grant execute on function "api"."as_column_type"(text, anyelement) to anon, authenticated, service_role;

create or replace function "api"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."transition"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "api"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pause_lifecycle"($1, $2, $3, $4) $$;
revoke execute on function "api"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "api"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

create or replace function "api"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resume_lifecycle"($1, $2) $$;
revoke execute on function "api"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "api"."resume_lifecycle"(text, text) to authenticated, service_role;

create or replace function "api"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_lifecycle_flag"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "api"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."status_state"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."status_state"($1, $2) $$;
revoke execute on function "api"."status_state"(text, text) from public, anon;
grant execute on function "api"."status_state"(text, text) to authenticated, service_role;

create or replace function "api"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_status_history"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_status_stages"($1, $2) $$;
revoke execute on function "api"."list_status_stages"(text, text) from public, anon;
grant execute on function "api"."list_status_stages"(text, text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
