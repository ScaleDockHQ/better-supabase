SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."declared_defaults" (
  "kind"     text    NOT NULL,
  "subject"  text    NOT NULL,
  "key"      text    NOT NULL,
  "position" integer NOT NULL DEFAULT 0,
  "value"    jsonb   NOT NULL,
  CONSTRAINT "declared_defaults_pkey" PRIMARY KEY (kind, subject, key)
);

ALTER TABLE "better_supabase"."declared_defaults"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."approval_policy"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(
    better_supabase.declared_defaults_of('approval_floor', approval_policy.subject_type || ':' || approval_policy.action) -> 0,
    better_supabase.declared_defaults_of('approval_floor', approval_policy.subject_type || ':*') -> 0,
    better_supabase.declared_defaults_of('approval_floor', '*:' || approval_policy.action) -> 0,
    better_supabase.declared_defaults_of('approval_floor', '*:*') -> 0,
    coalesce(case approval_policy.subject_type || ':' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    when 'customer:discount' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'customer:refund' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'customer:export' then '{"steps":[{"approvers":{"manager":true},"required":1}],"selfApproval":false,"expiresIn":null,"run":null,"mode":"confirm"}'::jsonb
    when 'case:close' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'drive_node:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'drive_node:release' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":2}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'eve_tool_call:add_note' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'workflow_run:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    else null::jsonb
  end, case '*:' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    else null::jsonb
  end)
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.declared_defaults_of (
  kind    text,
  subject text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_agg(d.value order by d.position, d.key)
  from better_supabase.declared_defaults d
  where d.kind = declared_defaults_of.kind and d.subject = declared_defaults_of.subject
$function$;

CREATE OR REPLACE FUNCTION better_supabase.default_option_set (
  tenant       uuid,
  subject_type text,
  field        text,
  scope_id     text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_brand text;
  v_declared jsonb;
begin
  select x."id" into v_id from "better_supabase"."option_sets" x
  where x."tenant_id" = default_option_set.tenant
    and x."subject_type" = default_option_set.subject_type
    and x."field" = default_option_set.field
    and x."scope_id" is not distinct from default_option_set.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."created_at", x."id"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
      if default_option_set.subject_type = 'work_item' and default_option_set.field = 'priority' then
      insert into "better_supabase"."option_sets" ("tenant_id", "subject_type", "field", "scope_id", "key", "name", "is_default")
      values (default_option_set.tenant, default_option_set.subject_type, default_option_set.field, default_option_set.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        select x."id" into v_id from "better_supabase"."option_sets" x
        where x."tenant_id" = default_option_set.tenant
          and x."subject_type" = default_option_set.subject_type
          and x."field" = default_option_set.field
          and x."scope_id" is not distinct from default_option_set.scope_id
          and x."archived_at" is null
        order by x."is_default" desc, x."created_at", x."id"
        limit 1;
        if v_id is null then
          raise exception 'the default option set of this field is archived' using errcode = '55000', hint = 'OPTION_SET_UNAVAILABLE';
        end if;
        return v_id;
      end if;
      v_declared := better_supabase.declared_defaults_of('option_set_item', default_option_set.subject_type || '.' || default_option_set.field);
      if v_declared is not null then
        insert into "better_supabase"."option_set_items" ("tenant_id", "option_set_id", "key", "system_key", "label", "color", "icon", "rank", "level")
        select default_option_set.tenant, v_id, x.key, x.key, x.label, x.color, x.icon, substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', ((x.ord / 62) % 62)::integer + 1, 1) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (x.ord % 62)::integer + 1, 1) || 'V', x.level
        from rows from (jsonb_to_recordset(v_declared) as (key text, label text, level integer, color text, icon text)) with ordinality as x(key, label, level, color, icon, ord);
      else
      insert into "better_supabase"."option_set_items" ("tenant_id", "option_set_id", "key", "system_key", "label", "color", "icon", "rank", "level")
      select default_option_set.tenant, v_id, x.key, x.key, x.label, x.color, x.icon, x.rank, x.level
      from (values
          ('none', 'None', 0, null::text, null::text, 'A'),
          ('low', 'Low', 1, null::text, null::text, 'K'),
          ('medium', 'Medium', 2, null::text, null::text, 'U'),
          ('high', 'High', 3, null::text, null::text, 'e'),
          ('urgent', 'Urgent', 4, null::text, null::text, 'o')
      ) x(key, label, level, color, icon, rank);
      end if;
    else
      raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
    end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.default_pipeline (
  tenant       uuid,
  subject_type text,
  scope_id     text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_declared jsonb;
begin
  select x."id" into v_id from "better_supabase"."pipelines" x
  where x."tenant_id" = default_pipeline.tenant
    and x."subject_type" = default_pipeline.subject_type
    and x."scope_id" is not distinct from default_pipeline.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."rank" collate "C"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
  case default_pipeline.subject_type
    when 'deal' then
      begin
        perform "better_supabase"."seed_pipelines_defaults"(default_pipeline.tenant, 'b2b-sales');
      exception when unique_violation then
        null;
      end;
      select x."id" into v_id from "better_supabase"."pipelines" x
      where x."tenant_id" = default_pipeline.tenant
        and x."subject_type" = default_pipeline.subject_type
        and x."scope_id" is null
        and x."archived_at" is null
      order by x."is_default" desc, x."rank" collate "C"
      limit 1;
    when 'work_item' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      v_declared := better_supabase.declared_defaults_of('pipeline_stage', 'work_item');
      if v_declared is not null then
        insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank", "color", "icon")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank, x.color, x.icon
      from (select d.key, d.name, d.category, case d.category when 'triage' then 'open' when 'backlog' then 'open' when 'unstarted' then 'open' when 'started' then 'open' when 'completed' then 'success' when 'canceled' then 'failure' else 'open' end as outcome, d.probability, substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', ((d.ord / 62) % 62)::integer + 1, 1) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (d.ord % 62)::integer + 1, 1) || 'V' as rank, d.color, d.icon
      from rows from (jsonb_to_recordset(v_declared) as (key text, name text, category text, probability smallint, color text, icon text)) with ordinality as d(key, name, category, probability, color, icon, ord)
      ) x(key, name, category, outcome, probability, rank, color, icon);
      else
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('triage', 'Triage', 'triage', 'open', null::smallint, '7'),
          ('backlog', 'Backlog', 'backlog', 'open', null::smallint, 'E'),
          ('todo', 'Todo', 'unstarted', 'open', null::smallint, 'L'),
          ('in_progress', 'In progress', 'started', 'open', null::smallint, 'S'),
          ('in_review', 'In review', 'started', 'open', null::smallint, 'Z'),
          ('done', 'Done', 'completed', 'success', null::smallint, 'g'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
      end if;
    when 'maintenance_request' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      v_declared := better_supabase.declared_defaults_of('pipeline_stage', 'maintenance_request');
      if v_declared is not null then
        insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank", "color", "icon")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank, x.color, x.icon
      from (select d.key, d.name, d.category, case d.category when 'triage' then 'open' when 'backlog' then 'open' when 'unstarted' then 'open' when 'started' then 'open' when 'completed' then 'success' when 'canceled' then 'failure' else 'open' end as outcome, d.probability, substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', ((d.ord / 62) % 62)::integer + 1, 1) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (d.ord % 62)::integer + 1, 1) || 'V' as rank, d.color, d.icon
      from rows from (jsonb_to_recordset(v_declared) as (key text, name text, category text, probability smallint, color text, icon text)) with ordinality as d(key, name, category, probability, color, icon, ord)
      ) x(key, name, category, outcome, probability, rank, color, icon);
      else
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('triage', 'Triage', 'triage', 'open', null::smallint, '7'),
          ('backlog', 'Backlog', 'backlog', 'open', null::smallint, 'E'),
          ('todo', 'Todo', 'unstarted', 'open', null::smallint, 'L'),
          ('in_progress', 'In progress', 'started', 'open', null::smallint, 'S'),
          ('in_review', 'In review', 'started', 'open', null::smallint, 'Z'),
          ('done', 'Done', 'completed', 'success', null::smallint, 'g'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
      end if;
    when 'application' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      v_declared := better_supabase.declared_defaults_of('pipeline_stage', 'application');
      if v_declared is not null then
        insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank", "color", "icon")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank, x.color, x.icon
      from (select d.key, d.name, d.category, case d.category when 'active' then 'open' when 'hired' then 'success' when 'rejected' then 'failure' when 'withdrawn' then 'failure' else 'open' end as outcome, d.probability, substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', ((d.ord / 62) % 62)::integer + 1, 1) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (d.ord % 62)::integer + 1, 1) || 'V' as rank, d.color, d.icon
      from rows from (jsonb_to_recordset(v_declared) as (key text, name text, category text, probability smallint, color text, icon text)) with ordinality as d(key, name, category, probability, color, icon, ord)
      ) x(key, name, category, outcome, probability, rank, color, icon);
      else
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('applied', 'Applied', 'active', 'open', null::smallint, '7'),
          ('screening', 'Screening', 'active', 'open', null::smallint, 'E'),
          ('interview', 'Interview', 'active', 'open', null::smallint, 'L'),
          ('offer', 'Offer', 'active', 'open', null::smallint, 'S'),
          ('hired', 'Hired', 'hired', 'success', null::smallint, 'Z'),
          ('rejected', 'Rejected', 'rejected', 'failure', null::smallint, 'g'),
          ('withdrawn', 'Withdrawn', 'withdrawn', 'failure', null::smallint, 'n')
      ) x(key, name, category, outcome, probability, rank);
      end if;
    when 'case' then
      insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
      values (default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        return "better_supabase"."default_pipeline"(default_pipeline.tenant, default_pipeline.subject_type, default_pipeline.scope_id);
      end if;
      v_declared := better_supabase.declared_defaults_of('pipeline_stage', 'case');
      if v_declared is not null then
        insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank", "color", "icon")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank, x.color, x.icon
      from (select d.key, d.name, d.category, case d.category when 'open' then 'open' when 'closed' then 'success' when 'canceled' then 'failure' else 'open' end as outcome, d.probability, substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', ((d.ord / 62) % 62)::integer + 1, 1) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (d.ord % 62)::integer + 1, 1) || 'V' as rank, d.color, d.icon
      from rows from (jsonb_to_recordset(v_declared) as (key text, name text, category text, probability smallint, color text, icon text)) with ordinality as d(key, name, category, probability, color, icon, ord)
      ) x(key, name, category, outcome, probability, rank, color, icon);
      else
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "system_key", "name", "category", "outcome", "probability", "rank")
      select default_pipeline.tenant, v_id, x.key, x.key, x.name, x.category, x.outcome, x.probability, x.rank
      from (values
          ('reported', 'Reported', 'open', 'open', null::smallint, '8'),
          ('investigating', 'Investigating', 'open', 'open', null::smallint, 'G'),
          ('acting', 'Acting', 'open', 'open', null::smallint, 'O'),
          ('verifying', 'Verifying', 'open', 'open', null::smallint, 'W'),
          ('closed', 'Closed', 'closed', 'success', null::smallint, 'e'),
          ('canceled', 'Canceled', 'canceled', 'failure', null::smallint, 'm')
      ) x(key, name, category, outcome, probability, rank);
      end if;
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_approval_policy (
  tenant uuid,
  policy jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"case","action":"close","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"drive_node","action":"release","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    ) or exists (
      select 1 from better_supabase.declared_defaults f
      where f.kind = 'approval_floor'
        and (v_type = '*' or split_part(f.subject, ':', 1) in (v_type, '*'))
        and (v_action = '*' or split_part(f.subject, ':', 2) in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager', 'decider'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'decider' and v_who -> 'decider' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  if exists (
    select 1 from jsonb_array_elements(v_steps) d(s)
    where d.s -> 'approvers' -> 'decider' = 'true'::jsonb or d.s -> 'escalateTo' -> 'decider' = 'true'::jsonb
  ) then
    raise exception 'decider is only valid for subject types a block decides' using errcode = '22023', hint = 'APPROVAL_POLICY_DECIDER_UNAVAILABLE';
  end if;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) || '{"all": true}'::jsonb else s - 'all' end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), case when coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description" else better_supabase.column_default('"better_supabase"."approval_policies"', 'description', (null::"better_supabase"."approval_policies")."description") end)
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('approval_policy.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.created',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'created approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  else
    perform "better_supabase".emit_event('approval_policy.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.updated',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'updated approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.seed_pipelines_defaults (
  p_tenant  uuid,
  p_variant text DEFAULT NULL::text,
  p_locale  text DEFAULT 'en'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if (p_variant is null or p_variant = 'b2b-sales') then
    insert into "better_supabase"."pipelines" ("tenant_id", "subject_type", "scope_id", "key", "name", "is_default")
    select p_tenant, 'deal', null, 'default', 'Default', (not exists (select 1 from "better_supabase"."pipelines" d where d."tenant_id" = p_tenant and d."subject_type" = 'deal' and d."scope_id" is null and d."is_default" and d."archived_at" is null))
    where not exists (select 1 from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" is not distinct from 'deal' and x."scope_id" is not distinct from null and x."key" is not distinct from 'default');
  end if;
  if (p_variant is null or p_variant = 'b2b-sales') then
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'qualified', 'Qualified', ('open'), ('open'), '8', 'qualified', 20
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'qualified') and not (better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null);
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'discovery', 'Discovery', ('open'), ('open'), 'G', 'discovery', 35
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'discovery') and not (better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null);
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'proposal', 'Proposal', ('open'), ('open'), 'O', 'proposal', 55
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'proposal') and not (better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null);
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'negotiation', 'Negotiation', ('open'), ('open'), 'W', 'negotiation', 75
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'negotiation') and not (better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null);
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'closed_won', 'Closed won', ('won'), ('success'), 'e', 'closed_won', 100
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'closed_won') and not (better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null);
    insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability")
    select p_tenant, (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1), 'closed_lost', 'Closed lost', ('lost'), ('failure'), 'm', 'closed_lost', 0
    where not exists (select 1 from "better_supabase"."pipeline_stages" x where x."tenant_id" = p_tenant and x."pipeline_id" is not distinct from (select x."id" from "better_supabase"."pipelines" x where x."tenant_id" = p_tenant and x."subject_type" = 'deal' and x."scope_id" is null and x."key" = 'default' limit 1) and x."system_key" is not distinct from 'closed_lost') and not (better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null);
    if better_supabase.declared_defaults_of('pipeline_stage', 'deal') is not null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "rank", "system_key", "probability", "color", "icon")
      select p_tenant, (select pl."id" from "better_supabase"."pipelines" pl where pl."tenant_id" = p_tenant and pl."subject_type" = 'deal' and pl."scope_id" is null and pl."key" = 'default' limit 1), x.key, x.name, x.category, x.outcome, x.rank, x.key, x.probability, x.color, x.icon
      from (select d.key, d.name, d.category, case d.category when 'open' then 'open' when 'won' then 'success' when 'lost' then 'failure' else 'open' end as outcome, d.probability, substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', ((d.ord / 62) % 62)::integer + 1, 1) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (d.ord % 62)::integer + 1, 1) || 'V' as rank, d.color, d.icon
        from rows from (jsonb_to_recordset(better_supabase.declared_defaults_of('pipeline_stage', 'deal')) as (key text, name text, category text, probability smallint, color text, icon text)) with ordinality as d(key, name, category, probability, color, icon, ord)
        ) x(key, name, category, outcome, probability, rank, color, icon)
      where not exists (select 1 from "better_supabase"."pipeline_stages" e where e."tenant_id" = p_tenant and e."pipeline_id" = (select pl."id" from "better_supabase"."pipelines" pl where pl."tenant_id" = p_tenant and pl."subject_type" = 'deal' and pl."scope_id" is null and pl."key" = 'default' limit 1) and e."system_key" is not distinct from x.key);
    end if;
  end if;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."declared_defaults_of"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."declared_defaults_of"(text, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."declared_defaults" TO "service_role";
