import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, serviceGrant, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { tenantRefGuard } from "./credentials.ts";

export type BuilderAction =
  keyof (typeof MODULE_PERMISSIONS)["workflow-builder"];

/** The names and SQL fragments the workflow-builder module's functions share. */
export interface BuilderSql {
  readonly id: string;
  readonly fn: (value: string) => string;
  readonly d: string;
  readonly v: string;
  readonly t: string;
  readonly w: string;
  readonly c: string;
  readonly l: string;
  readonly n: string;
  readonly a: string;
  readonly f: string;
  readonly cd: (value: string) => string;
  readonly cv: (value: string) => string;
  readonly ct: (value: string) => string;
  readonly cw: (value: string) => string;
  readonly cc: (value: string) => string;
  readonly cl: (value: string) => string;
  readonly cn: (value: string) => string;
  readonly ca: (value: string) => string;
  readonly cf: (value: string) => string;
  readonly r: string;
  readonly cr: (value: string) => string;
  readonly permission: (action: BuilderAction) => string;
  readonly can: (tenant: string, action: BuilderAction) => string;
  readonly allowed: (tenant: string, action: BuilderAction) => string;
  readonly forbidden: (value: string) => string;
  readonly serviceOnly: (value: string) => string;
  readonly callable: (value: string) => string;
  readonly readable: (value: string) => string;
  readonly definitionReadable: (value: string) => string;
  readonly definitionJson: (value: string) => string;
  readonly versionJson: (alias: string, full: boolean) => string;
  readonly triggerJson: (value: string) => string;
  readonly credentialJson: (value: string) => string;
  readonly stepJson: (value: string) => string;
  readonly nodeRunJson: (value: string) => string;
  readonly alertJson: (value: string) => string;
  readonly alertEmit: string;
  readonly fire: string;
  readonly failedTrigger: string;
  readonly broadcast: ModuleContext["broadcast"];
}

export function builderSql(ctx: ModuleContext): BuilderSql {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const d = ctx.table("definitions");
  const v = ctx.table("versions");
  const t = ctx.table("triggers");
  const w = ctx.table("webhookTokens");
  const c = ctx.table("credentials");
  const l = ctx.table("steps");
  const n = ctx.table("nodeRuns");
  const a = ctx.table("alerts");
  const f = ctx.table("alertFires");
  const cd = (column: string): string => ctx.col("definitions", column);
  const cv = (column: string): string => ctx.col("versions", column);
  const ct = (column: string): string => ctx.col("triggers", column);
  const cw = (column: string): string => ctx.col("webhookTokens", column);
  const cc = (column: string): string => ctx.col("credentials", column);
  const cl = (column: string): string => ctx.col("steps", column);
  const cn = (column: string): string => ctx.col("nodeRuns", column);
  const ca = (column: string): string => ctx.col("alerts", column);
  const cf = (column: string): string => ctx.col("alertFires", column);
  const workflows = ctx.of("workflows");
  const r = workflows.table("runs");
  const cr = (column: string): string => workflows.col("runs", column);
  const permissions = MODULE_PERMISSIONS["workflow-builder"];
  const permission = (action: BuilderAction): string =>
    ctx.permission(action, permissions[action]);
  const can = (tenant: string, action: BuilderAction): string =>
    ctx.can("tenant", tenant, permission(action));
  const allowed = (tenant: string, action: BuilderAction): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${can(tenant, action)}))`;
  const forbidden = (message: string): string =>
    `raise exception ${sqlString(message)} using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';`;
  const callable = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;
  const readable = (tenant: string): string =>
    tenantIn(tenant, permission("read"));
  const definitionReadable = (column: string): string =>
    `${column} in (select x.${cd("id")} from ${d} x)`;

  const definitionJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${cd("id")},
    'tenant', ${alias}.${cd("tenant")},
    'slug', ${alias}.${cd("slug")},
    'name', ${alias}.${cd("name")},
    'description', ${alias}.${cd("description")},
    'createdBy', ${alias}.${cd("createdBy")},
    'createdAt', ${alias}.${cd("createdAt")},
    'updatedAt', ${alias}.${cd("updatedAt")}
  )`;
  const versionJson = (
    alias: string,
    full: boolean,
  ): string => `jsonb_build_object(
    'id', ${alias}.${cv("id")},
    'definition', ${alias}.${cv("definition")},
    'version', ${alias}.${cv("version")},
    'status', ${alias}.${cv("status")},
    'createdBy', ${alias}.${cv("createdBy")},
    'createdAt', ${alias}.${cv("createdAt")},
    'publishedAt', ${alias}.${cv("publishedAt")}${
      full
        ? `,
    'graph', ${alias}.${cv("graph")},
    'compiled', ${alias}.${cv("compiled")}`
        : ""
    }
  )`;
  const triggerJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${ct("id")},
    'definition', ${alias}.${ct("definition")},
    'kind', ${alias}.${ct("kind")},
    'config', ${alias}.${ct("config")},
    'enabled', ${alias}.${ct("enabled")},
    'createdAt', ${alias}.${ct("createdAt")},
    'updatedAt', ${alias}.${ct("updatedAt")}
  )`;
  const credentialJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${cc("id")},
    'tenant', ${alias}.${cc("tenant")},
    'kind', ${alias}.${cc("kind")},
    'name', ${alias}.${cc("name")},
    'ref', ${alias}.${cc("ref")},
    'scopes', to_jsonb(${alias}.${cc("scopes")}),
    'createdBy', ${alias}.${cc("createdBy")},
    'createdAt', ${alias}.${cc("createdAt")}
  )`;
  const stepJson = (alias: string): string => `jsonb_build_object(
    'name', ${alias}.${cl("name")},
    'title', ${alias}.${cl("title")},
    'description', ${alias}.${cl("description")},
    'inputSchema', ${alias}.${cl("inputSchema")},
    'outputSchema', ${alias}.${cl("outputSchema")},
    'credentialKind', ${alias}.${cl("credentialKind")},
    'updatedAt', ${alias}.${cl("updatedAt")}
  )`;
  const nodeRunJson = (alias: string): string => `jsonb_build_object(
    'run', ${alias}.${cn("run")},
    'node', ${alias}.${cn("node")},
    'status', ${alias}.${cn("status")},
    'attempts', ${alias}.${cn("attempts")},
    'output', ${alias}.${cn("output")},
    'error', ${alias}.${cn("error")},
    'startedAt', ${alias}.${cn("startedAt")},
    'endedAt', ${alias}.${cn("endedAt")}
  )`;
  const alertJson = (alias: string): string => `jsonb_build_object(
    'id', ${alias}.${ca("id")},
    'definition', ${alias}.${ca("definition")},
    'onEvent', ${alias}.${ca("onEvent")},
    'threshold', extract(epoch from ${alias}.${ca("threshold")}),
    'channel', ${alias}.${ca("channel")},
    'createdBy', ${alias}.${ca("createdBy")},
    'createdAt', ${alias}.${ca("createdAt")}
  )`;
  const alertEmit = ctx.emit({
    type: "workflow.alert",
    payload: `jsonb_build_object('alertId', v_alert.${ca("id")}, 'definition', v_alert.${ca("definition")}, 'onEvent', v_alert.${ca("onEvent")}, 'channel', v_alert.${ca("channel")}, 'runId', v_run.${cr("id")}, 'status', v_run.${cr("status")}, 'error', v_run.${cr("error")})`,
    subject: `'workflow-runs/' || v_run.${cr("id")}`,
    tenant: `v_run.${cr("tenant")}`,
    key: `'workflow.alert:' || v_alert.${ca("id")} || ':' || v_run.${cr("id")}`,
  });
  const fire = `insert into ${f} (${cf("alert")}, ${cf("run")}) values (v_alert.${ca("id")}, v_run.${cr("id")})
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;${alertEmit === "" ? "" : `\n        ${alertEmit}`}
      end if;`;
  const failedTrigger = ctx.trigger("workflow_runs_alert");
  return {
    id,
    fn,
    d,
    v,
    t,
    w,
    c,
    l,
    n,
    a,
    f,
    cd,
    cv,
    ct,
    cw,
    cc,
    cl,
    cn,
    ca,
    cf,
    r,
    cr,
    permission,
    can,
    allowed,
    forbidden,
    serviceOnly: serviceGrant,
    callable,
    readable,
    definitionReadable,
    definitionJson,
    versionJson,
    triggerJson,
    credentialJson,
    stepJson,
    nodeRunJson,
    alertJson,
    alertEmit,
    fire,
    failedTrigger,
    broadcast: (topic, event, payload, options) =>
      ctx.broadcast(topic, event, payload, options),
  };
}

/** Triggers, credentials, the step library, node runs and alerts. */
export function builderRuntimeSql(s: BuilderSql): string {
  const {
    broadcast,
    id,
    fn,
    d,
    t,
    w,
    c,
    l,
    n,
    a,
    f,
    cd,
    ct,
    cw,
    cc,
    cl,
    cn,
    ca,
    cf,
    r,
    cr,
    allowed,
    forbidden,
    serviceOnly: serviceGrant,
    callable,
    triggerJson,
    credentialJson,
    stepJson,
    nodeRunJson,
    alertJson,
    fire,
    failedTrigger,
  } = s;
  return `-- Creates or updates a trigger: workflow.edit in the definition's tenant.
create or replace function ${fn("save_workflow_trigger")}(
  definition uuid,
  kind text,
  config jsonb default '{}'::jsonb,
  enabled boolean default true,
  trigger uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${id};
  v_row ${t}%rowtype;
begin
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ${allowed("v_tenant", "edit")} then
    ${forbidden("You may not edit this workflow")}
  end if;
  if trigger is null then
    insert into ${t} (${ct("definition")}, ${ct("kind")}, ${ct("config")}, ${ct("enabled")})
    values (definition, kind, coalesce(config, '{}'::jsonb), coalesce(enabled, true))
    returning * into v_row;
  else
    update ${t} x set
      ${ct("kind")} = kind,
      ${ct("config")} = coalesce(config, '{}'::jsonb),
      ${ct("enabled")} = coalesce(enabled, true),
      ${ct("updatedAt")} = now()
    where x.${ct("id")} = trigger and x.${ct("definition")} = definition
    returning * into v_row;
    if not found then
      raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
    if kind <> 'webhook' then
      delete from ${w} x where x.${cw("trigger")} = trigger;
    end if;
  end if;
  return ${triggerJson("v_row")};
end;
$$;
${callable(`${fn("save_workflow_trigger")}(uuid, text, jsonb, boolean, uuid)`)}

create or replace function ${fn("workflow_triggers_list")}(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${triggerJson("x")} order by x.${ct("createdAt")}), '[]'::jsonb)
  from ${t} x where x.${ct("definition")} = workflow_triggers_list.definition;
$$;
${callable(`${fn("workflow_triggers_list")}(uuid)`)}

create or replace function ${fn("remove_workflow_trigger")}(trigger uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${t} x
  using ${d} y
  where x.${ct("id")} = trigger and y.${cd("id")} = x.${ct("definition")}
    and ${allowed(`y.${cd("tenant")}`, "edit")};
  return found;
end;
$$;
${callable(`${fn("remove_workflow_trigger")}(uuid)`)}

-- Issues a new token for a webhook trigger and returns it; only its SHA-256
-- is kept, so the old token stops working. workflow.edit in its tenant.
create or replace function ${fn("rotate_workflow_webhook_token")}(trigger uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${id};
  v_kind text;
  v_token text := 'wfh_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  select y.${cd("tenant")}, x.${ct("kind")} into v_tenant, v_kind
  from ${t} x join ${d} y on y.${cd("id")} = x.${ct("definition")}
  where x.${ct("id")} = trigger;
  if not found then
    raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ${allowed("v_tenant", "edit")} then
    ${forbidden("You may not edit this workflow")}
  end if;
  if v_kind <> 'webhook' then
    raise exception 'Only webhook triggers have tokens' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_KIND';
  end if;
  delete from ${w} x where x.${cw("trigger")} = trigger;
  insert into ${w} (${cw("tokenHash")}, ${cw("trigger")})
  values (extensions.digest(v_token, 'sha256'), trigger);
  return v_token;
end;
$$;
${callable(`${fn("rotate_workflow_webhook_token")}(uuid)`)}

-- The enabled webhook trigger a token belongs to, with its definition and
-- tenant (service role; the webhook route calls it).
create or replace function ${fn("workflow_webhook_target")}(token text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('trigger', ${triggerJson("x")}, 'tenant', y.${cd("tenant")})
  from ${w} k
  join ${t} x on x.${ct("id")} = k.${cw("trigger")}
  join ${d} y on y.${cd("id")} = x.${ct("definition")}
  where k.${cw("tokenHash")} = extensions.digest(workflow_webhook_target.token, 'sha256')
    and x.${ct("enabled")};
$$;
${serviceGrant(`${fn("workflow_webhook_target")}(text)`)}

-- The enabled event triggers listening for type (config.type) in tenant,
-- with their definitions (service role; the outbox consumer calls it).
create or replace function ${fn("workflow_event_targets")}(type text, tenant ${id} default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('trigger', ${triggerJson("x")}, 'tenant', y.${cd("tenant")}) order by x.${ct("createdAt")}), '[]'::jsonb)
  from ${t} x
  join ${d} y on y.${cd("id")} = x.${ct("definition")}
  where x.${ct("kind")} = 'event' and x.${ct("enabled")}
    and x.${ct("config")} ->> 'type' = workflow_event_targets.type
    and y.${cd("tenant")} is not distinct from workflow_event_targets.tenant;
$$;
${serviceGrant(`${fn("workflow_event_targets")}(text, ${id})`)}

-- Creates or replaces a credential reference: workflow.admin in tenant.
create or replace function ${fn("save_workflow_credential")}(
  tenant ${id},
  kind text,
  name text,
  ref jsonb,
  scopes text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${c}%rowtype;
begin
  if not ${allowed("tenant", "admin")} then
    ${forbidden("You may not manage workflow credentials here")}
  end if;
  ${tenantRefGuard("save_workflow_credential.ref", "save_workflow_credential.tenant")}
  insert into ${c} as x (${cc("tenant")}, ${cc("kind")}, ${cc("name")}, ${cc("ref")}, ${cc("scopes")}, ${cc("createdBy")})
  values (tenant, kind, name, ref, coalesce(scopes, '{}'), (select auth.uid()))
  on conflict on constraint workflow_credentials_tenant_name_key do update set
    ${cc("kind")} = excluded.${cc("kind")},
    ${cc("ref")} = excluded.${cc("ref")},
    ${cc("scopes")} = excluded.${cc("scopes")}
  returning * into v_row;
  return ${credentialJson("v_row")};
end;
$$;
${callable(`${fn("save_workflow_credential")}(${id}, text, text, jsonb, text[])`)}

create or replace function ${fn("workflow_credentials_list")}(tenant ${id} default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${credentialJson("x")} order by x.${cc("name")}), '[]'::jsonb)
  from ${c} x
  where workflow_credentials_list.tenant is null or x.${cc("tenant")} = workflow_credentials_list.tenant;
$$;
${callable(`${fn("workflow_credentials_list")}(${id})`)}

-- One credential row with its reference (service role; steps resolve it).
create or replace function ${fn("workflow_credential_get")}(credential uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${credentialJson("x")} from ${c} x where x.${cc("id")} = workflow_credential_get.credential;
$$;
${serviceGrant(`${fn("workflow_credential_get")}(uuid)`)}

-- Deletes a credential row and returns it, so the caller can revoke the
-- secret it names: workflow.admin in its tenant.
create or replace function ${fn("remove_workflow_credential")}(credential uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${c}%rowtype;
begin
  delete from ${c} x
  where x.${cc("id")} = credential and ${allowed(`x.${cc("tenant")}`, "admin")}
  returning * into v_row;
  if not found then
    return null;
  end if;
  return ${credentialJson("v_row")};
end;
$$;
${callable(`${fn("remove_workflow_credential")}(uuid)`)}

-- Replaces the step library with steps, keyed by name ({ name: { title,
-- description, inputSchema, outputSchema, credentialKind } }); returns how
-- many there are.
create or replace function ${fn("sync_workflow_steps")}(steps jsonb)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into ${l} (${cl("name")}, ${cl("title")}, ${cl("description")}, ${cl("inputSchema")}, ${cl("outputSchema")}, ${cl("credentialKind")})
  select e.key, coalesce(e.value ->> 'title', e.key), e.value ->> 'description',
    coalesce(e.value -> 'inputSchema', '{}'::jsonb), coalesce(e.value -> 'outputSchema', '{}'::jsonb), e.value ->> 'credentialKind'
  from jsonb_each(coalesce(steps, '{}'::jsonb)) e
  on conflict (${cl("name")}) do update set
    ${cl("title")} = excluded.${cl("title")},
    ${cl("description")} = excluded.${cl("description")},
    ${cl("inputSchema")} = excluded.${cl("inputSchema")},
    ${cl("outputSchema")} = excluded.${cl("outputSchema")},
    ${cl("credentialKind")} = excluded.${cl("credentialKind")},
    ${cl("updatedAt")} = now();
  delete from ${l} x
  where not exists (
    select 1 from jsonb_each(coalesce(steps, '{}'::jsonb)) e where e.key = x.${cl("name")}
  );
  select count(*) into v_count from ${l};
  return v_count;
end;
$$;
${serviceGrant(`${fn("sync_workflow_steps")}(jsonb)`)}

create or replace function ${fn("workflow_steps_list")}()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${stepJson("x")} order by x.${cl("name")}), '[]'::jsonb) from ${l} x;
$$;
${callable(`${fn("workflow_steps_list")}()`)}

-- Records a node's status for a run (by its id or its engine's id) and
-- pings the run's topic. attempt raises attempts; started_at keeps the
-- first start and ended_at is set by completed, failed and skipped.
create or replace function ${fn("record_workflow_node_run")}(
  run text,
  node text,
  status text,
  attempt integer default null,
  output jsonb default null,
  error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_run uuid;
  v_ended boolean := status in ('completed', 'failed', 'skipped');
begin
  select x.${cr("id")} into v_run from ${r} x
  where x.${cr("id")}::text = run or x.${cr("externalId")} = run
  order by x.${cr("id")}::text = run desc
  limit 1;
  if not found then
    return false;
  end if;
  insert into ${n} as x (${cn("run")}, ${cn("node")}, ${cn("status")}, ${cn("attempts")}, ${cn("output")}, ${cn("error")}, ${cn("startedAt")}, ${cn("endedAt")})
  values (v_run, node, status, coalesce(attempt, 0), output, left(error, 4000), now(), case when v_ended then now() end)
  on conflict (${cn("run")}, ${cn("node")}) do update set
    ${cn("status")} = excluded.${cn("status")},
    ${cn("attempts")} = greatest(x.${cn("attempts")}, excluded.${cn("attempts")}),
    ${cn("output")} = coalesce(excluded.${cn("output")}, x.${cn("output")}),
    ${cn("error")} = excluded.${cn("error")},
    ${cn("startedAt")} = coalesce(x.${cn("startedAt")}, excluded.${cn("startedAt")}),
    ${cn("endedAt")} = excluded.${cn("endedAt")};
  ${broadcast("'workflow-run:' || v_run::text", "'node'", "jsonb_build_object('id', v_run, 'node', node, 'status', status)")}
  return true;
end;
$$;
${serviceGrant(`${fn("record_workflow_node_run")}(text, text, text, integer, jsonb, text)`)}

-- The node statuses of a run the caller may read.
create or replace function ${fn("workflow_node_runs_list")}(run text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${nodeRunJson("x")} order by x.${cn("startedAt")} nulls last, x.${cn("node")}), '[]'::jsonb)
  from ${n} x
  join ${r} y on y.${cr("id")} = x.${cn("run")}
  where y.${cr("id")}::text = workflow_node_runs_list.run or y.${cr("externalId")} = workflow_node_runs_list.run;
$$;
${callable(`${fn("workflow_node_runs_list")}(text)`)}

-- Creates or updates an alert: workflow.admin in the definition's tenant.
-- threshold (slow alerts) is how long a run may stay unfinished.
create or replace function ${fn("save_workflow_alert")}(
  definition uuid,
  on_event text,
  channel jsonb default '{}'::jsonb,
  threshold interval default null,
  alert uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${id};
  v_row ${a}%rowtype;
begin
  select x.${cd("tenant")} into v_tenant from ${d} x where x.${cd("id")} = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not ${allowed("v_tenant", "admin")} then
    ${forbidden("You may not manage alerts for this workflow")}
  end if;
  if alert is null then
    insert into ${a} (${ca("definition")}, ${ca("onEvent")}, ${ca("threshold")}, ${ca("channel")}, ${ca("createdBy")})
    values (definition, on_event, threshold, coalesce(channel, '{}'::jsonb), (select auth.uid()))
    returning * into v_row;
  else
    update ${a} x set ${ca("onEvent")} = on_event, ${ca("threshold")} = threshold, ${ca("channel")} = coalesce(channel, '{}'::jsonb)
    where x.${ca("id")} = alert and x.${ca("definition")} = definition
    returning * into v_row;
    if not found then
      raise exception 'No such alert' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
  end if;
  return ${alertJson("v_row")};
end;
$$;
${callable(`${fn("save_workflow_alert")}(uuid, text, jsonb, interval, uuid)`)}

create or replace function ${fn("workflow_alerts_list")}(definition uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${alertJson("x")} order by x.${ca("createdAt")}), '[]'::jsonb)
  from ${a} x where x.${ca("definition")} = workflow_alerts_list.definition;
$$;
${callable(`${fn("workflow_alerts_list")}(uuid)`)}

create or replace function ${fn("remove_workflow_alert")}(alert uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${a} x
  using ${d} y
  where x.${ca("id")} = alert and y.${cd("id")} = x.${ca("definition")}
    and ${allowed(`y.${cd("tenant")}`, "admin")};
  return found;
end;
$$;
${callable(`${fn("remove_workflow_alert")}(uuid)`)}

-- Fires the failed alerts of a run's definition (the bs.definition
-- attribute) when the run fails.
create or replace function ${fn("workflow_runs_alert")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ${r}%rowtype := new;
  v_alert ${a}%rowtype;
  v_fired integer := 0;
begin
  if new.${cr("status")} <> 'failed' or (tg_op = 'UPDATE' and old.${cr("status")} = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from ${a} x
    where x.${ca("onEvent")} = 'failed' and x.${ca("definition")}::text = new.${cr("attributes")} ->> 'bs.definition'
  loop
    ${fire}
  end loop;
  return null;
end;
$$;
revoke execute on function ${fn("workflow_runs_alert")}() from public, anon, authenticated;
drop trigger if exists ${failedTrigger} on ${r};
create trigger ${failedTrigger} after insert or update of ${cr("status")} on ${r}
  for each row execute function ${fn("workflow_runs_alert")}();

-- Fires the slow alerts whose runs are still unfinished after their
-- threshold, at most batch per call; returns how many fired. Call it from
-- a cron route or a job.
create or replace function ${fn("check_workflow_alerts")}(batch integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pair record;
  v_alert ${a}%rowtype;
  v_run ${r}%rowtype;
  v_fired integer := 0;
begin
  for v_pair in
    select x.${ca("id")} as alert, y.${cr("id")} as run from ${a} x
    join ${r} y on y.${cr("attributes")} ->> 'bs.definition' = x.${ca("definition")}::text
    where x.${ca("onEvent")} = 'slow'
      and y.${cr("status")} in ('queued', 'running', 'waiting')
      and y.${cr("createdAt")} < now() - x.${ca("threshold")}
      and not exists (select 1 from ${f} z where z.${cf("alert")} = x.${ca("id")} and z.${cf("run")} = y.${cr("id")})
    limit greatest(coalesce(batch, 100), 1)
  loop
    select * into v_alert from ${a} x where x.${ca("id")} = v_pair.alert;
    select * into v_run from ${r} x where x.${cr("id")} = v_pair.run;
    ${fire}
  end loop;
  return v_fired;
end;
$$;
${serviceGrant(`${fn("check_workflow_alerts")}(integer)`)}`;
}
