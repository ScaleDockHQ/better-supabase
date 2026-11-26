import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";
import {
  EVE_SERVICE_FUNCTIONS,
  eveContract,
  eveProjectionSql,
  eveTablesSql,
  EVE_TABLES,
} from "./eve.ts";
import { OPERATIONS } from "./permissions-model.ts";
import {
  WORLD_POSTGRES_DDL,
  WORLD_POSTGRES_VERSION,
} from "./workflow-sdk-world-ddl.generated.ts";

export const WORKFLOW_DELIVERY_MODES = [
  "poll",
  "pg_net",
  "vercel-queue",
] as const;

export type WorkflowDeliveryMode = (typeof WORKFLOW_DELIVERY_MODES)[number];

/** The Vault secret names the pg_net dispatcher reads. */
export const WORKFLOW_VAULT_SECRETS = {
  flowUrl: "workflow_flow_url",
  deliverySecret: "workflow_delivery_secret",
  deliveryHeaders: "workflow_delivery_headers",
  encryptionKey: "workflow_encryption_key",
  encryptionKeys: "workflow_encryption_keys",
} as const;

export const WORKFLOW_DELIVERY_QUEUE = "workflow_deliveries";

/**
 * The schema whose `add_job` stands in for Graphile Worker's (see
 * `workflow_purge_backstops`).
 */
export const WORKFLOW_GRAPHILE_SCHEMA = "workflow";

function deliveryModeOf(ctx: BlockSqlContext): WorkflowDeliveryMode {
  const mode = ctx.text("delivery", "poll");

  const found = WORKFLOW_DELIVERY_MODES.find((known) => known === mode);

  if (found === undefined) {
    throw new TypeError(
      `blocks["workflow-sdk"].options.delivery must be "poll", "pg_net" or "vercel-queue", got "${mode}"`,
    );
  }

  return found;
}

const IDENT = /^[a-z_][a-z0-9_]{0,40}$/;

function deliveryQueueOf(ctx: BlockSqlContext): string {
  const queue = ctx.text("queue", WORKFLOW_DELIVERY_QUEUE);

  if (!IDENT.test(queue)) {
    throw new TypeError(
      `blocks["workflow-sdk"].options.queue: "${queue}" is not a queue name`,
    );
  }

  return queue;
}

/** The tables the World's DDL and this module create in the `workflow` schema. */
function workflowTables(): string[] {
  const names = new Set<string>([
    "workflow_run_keys",
    "workflow_purge_backstops",
    ...EVE_TABLES,
  ]);

  for (const match of WORLD_POSTGRES_DDL.matchAll(
    /create table (?:if not exists )?workflow\.(\w+)/gu,
  )) {
    names.add(match[1]!);
  }

  return [...names].toSorted();
}

/**
 * The sequences behind the `serial` columns of the World's tables, as
 * `<table>_<column>_seq`, so the service role's grants name each one.
 */
function workflowSequences(): string[] {
  return [
    ...WORLD_POSTGRES_DDL.matchAll(
      /create table (?:if not exists )?workflow\.(\w+) \(([\s\S]*?)\n\);/gu,
    ),
  ]
    .flatMap(([, table = "", body = ""]) =>
      [...body.matchAll(/"(\w+)" (?:big|small)?serial\b/gu)].map(
        ([, column = ""]) => `${table}_${column}_seq`,
      ),
    )
    .toSorted();
}

/** Row level security and the service role's grants, one set per table. */
function workflowTableAccess(): string {
  return workflowTables()
    .map(
      (table) => `alter table workflow.${table} enable row level security;
revoke all on workflow.${table} from public, anon, authenticated;
grant all on workflow.${table} to service_role;`,
    )
    .join("\n");
}

const PRINCIPAL_KINDS = "'user', 'service_principal', 'system', 'external'";

/** The functions only the service role calls, with their argument types. */
const SERVICE_FUNCTIONS: readonly (readonly [string, string])[] = [
  ["workflow_claim_run_key", "text, interval"],
  ["workflow_set_run_key", "text, text"],
  ["workflow_release_run_key", "text"],
  ["workflow_purge_runs", "interval, text[], integer, boolean"],
  ["workflow_purge_backstops", "integer"],
  ["workflow_open_hooks", "text, text, integer"],
  ...EVE_SERVICE_FUNCTIONS,
];

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const workflows = ctx.of("workflows");
  const record = workflows.fn("record_workflow_run");
  const runKey = workflows.permission("run", OPERATIONS["workflows.run"]);
  const claimJobs = ctx.of("queue").fn("claim_jobs");
  const id = ctx.idType;
  const queue = sqlString(deliveryQueueOf(ctx));
  const batch = Math.max(1, Math.trunc(ctx.number("batch", 20)));
  const timeout = Math.max(1000, Math.trunc(ctx.number("timeout", 30_000)));
  const lease = Math.ceil(timeout / 1000) + 30;
  const mirror = ctx.trigger("workflow_sdk_runs_mirror");

  return `${schemaPreamble(ctx)}
-- The Workflow SDK World's tables (@workflow/world-postgres ${WORLD_POSTGRES_VERSION}).
-- Only the service role reads them: the app reads runs from workflow_runs in
-- the workflows module.
${WORLD_POSTGRES_DDL}
-- One row per start idempotency key: startFor claims the key before it starts
-- a run, so two concurrent starts with one key start one run. run_id is null
-- while the start that claimed it is still running.
create table if not exists workflow.workflow_run_keys (
  key text primary key check (length(key) between 1 and 500),
  run_id character varying,
  claimed_at timestamptz not null default now()
);
create index if not exists workflow_run_keys_run_id_idx on workflow.workflow_run_keys (run_id);
-- The purge backstops of zero-retention runs. world-postgres adds one through
-- Graphile Worker's add_job in the transaction that finishes such a run; this
-- World runs no Graphile Worker, so it points GRAPHILE_WORKER_SCHEMA at
-- workflow, where add_job records the run here and workflow_purge_backstops
-- deletes its data once due if the purge after the commit did not.
create table if not exists workflow.workflow_purge_backstops (
  run_id character varying primary key,
  due_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index if not exists workflow_purge_backstops_due_at_idx on workflow.workflow_purge_backstops (due_at);
create or replace function workflow.add_job(
  identifier text,
  payload json default null,
  run_at timestamptz default null,
  max_attempts integer default null,
  job_key text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run text := payload ->> 'runId';
begin
  if identifier not like '%purge' or v_run is null then
    raise exception 'Only the purge backstops of @workflow/world-postgres go through workflow.add_job'
      using errcode = '0A000', hint = 'WORKFLOW_GRAPHILE_UNSUPPORTED', detail = 'task ' || coalesce(identifier, 'null');
  end if;
  insert into workflow.workflow_purge_backstops (run_id, due_at)
    values (v_run, coalesce(run_at, now()))
    on conflict (run_id) do nothing;
end;
$$;
revoke execute on function workflow.add_job(text, json, timestamptz, integer, text) from public, anon, authenticated;
grant execute on function workflow.add_job(text, json, timestamptz, integer, text) to service_role;
${eveTablesSql()}
revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
${workflowTableAccess()}
${workflowSequences()
  .map(
    (name) =>
      `grant usage, select on sequence workflow.${name} to service_role;`,
  )
  .join("\n")}
create index if not exists workflow_runs_attributes_idx on workflow.workflow_runs using gin (attributes jsonb_path_ops);

-- Copies each World run into workflow_runs: its tenant and actor come from
-- the bsb.tenant and bsb.actor attributes that startFor sets. A run with an
-- actor keeps its tenant only when the actor holds workflow.run there; a
-- run without one, or one with bsb.principal_kind (a runAs start, whose
-- actor is the user who triggered it), was started by the server, which is
-- trusted. bsb.subject
-- (type/id), bsb.principal_kind, bsb.principal, bsb.mode and bsb.trigger_node
-- fill the run's subject, principal, mode and trigger node.
create or replace function ${fn("workflow_sdk_mirror_run")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
  v_actor uuid;
  v_subject text;
  v_subject_type text;
  v_subject_id text;
  v_principal_kind text;
  v_mode text;
begin
  begin
    v_tenant := (new.attributes ->> 'bsb.tenant')::${id};
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bsb.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  v_principal_kind := new.attributes ->> 'bsb.principal_kind';
  if v_principal_kind is not null and v_principal_kind not in (${PRINCIPAL_KINDS}) then
    v_principal_kind := null;
  end if;
  if v_tenant is not null and v_actor is not null and v_principal_kind is null
    and not ${ctx.scope.canUser("v_actor", "v_tenant", runKey)} then
    v_tenant := null;
  end if;
  v_subject := new.attributes ->> 'bsb.subject';
  if v_subject is not null and position('/' in v_subject) between 2 and 101
    and length(v_subject) - position('/' in v_subject) between 1 and 200 then
    v_subject_type := left(v_subject, position('/' in v_subject) - 1);
    v_subject_id := substr(v_subject, position('/' in v_subject) + 1);
  end if;
  v_mode := case when new.attributes ->> 'bsb.mode' = 'test' then 'test' else 'live' end;
  perform ${record}(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bsb.tenant' - 'bsb.actor' - 'bsb.subject' - 'bsb.principal_kind' - 'bsb.principal' - 'bsb.mode' - 'bsb.trigger_node',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at,
    new.completed_at,
    v_subject_type,
    v_subject_id,
    v_principal_kind,
    case when v_principal_kind is null then null else nullif(left(new.attributes ->> 'bsb.principal', 200), '') end,
    v_mode,
    nullif(left(new.attributes ->> 'bsb.trigger_node', 100), '')
  );
  return null;
end;
$$;
revoke execute on function ${fn("workflow_sdk_mirror_run")}() from public, anon, authenticated;
drop trigger if exists ${mirror} on workflow.workflow_runs;
create trigger ${mirror} after insert or update of status, attributes, error on workflow.workflow_runs
  for each row execute function ${fn("workflow_sdk_mirror_run")}();

-- pg_net delivery: posts up to batch due messages to the flow route in the
-- Vault secret ${WORKFLOW_VAULT_SECRETS.flowUrl}, signed with ${WORKFLOW_VAULT_SECRETS.deliverySecret}
-- (x-bsb-signature: t=<unix>,v1=hex(hmac_sha256(t.job.body))). The body is
-- the stored message; the route completes or fails the job, so a delivery
-- whose response is lost runs again after the lease.
create or replace function ${fn("dispatch_workflow_deliveries")}(batch integer default ${String(batch)})
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_extra jsonb;
  v_job record;
  v_body jsonb;
  v_t text;
  v_job_header text;
  v_count integer := 0;
  -- pg_net is optional: http_post is looked up, not named, so plpgsql_check
  -- (supabase db lint) passes without the extension.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
begin
  if v_post is null then
    raise exception 'dispatch_workflow_deliveries needs pg_net: create extension pg_net, or deliver with the poll mode';
  end if;
  select ds.decrypted_secret into v_url from vault.decrypted_secrets ds where ds.name = ${sqlString(WORKFLOW_VAULT_SECRETS.flowUrl)};
  select ds.decrypted_secret into v_secret from vault.decrypted_secrets ds where ds.name = ${sqlString(WORKFLOW_VAULT_SECRETS.deliverySecret)};
  if v_url is null or v_secret is null then
    raise exception 'Set the Vault secrets ${WORKFLOW_VAULT_SECRETS.flowUrl} and ${WORKFLOW_VAULT_SECRETS.deliverySecret} before dispatching' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  -- Extra headers (a deployment protection bypass, for one) as a JSON object.
  select ds.decrypted_secret::jsonb into v_extra from vault.decrypted_secrets ds where ds.name = ${sqlString(WORKFLOW_VAULT_SECRETS.deliveryHeaders)};
  if v_extra is not null and pg_catalog.jsonb_typeof(v_extra) <> 'object' then
    raise exception 'The Vault secret ${WORKFLOW_VAULT_SECRETS.deliveryHeaders} must be a JSON object of header names and values' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from ${claimJobs}(${queue}, ${String(lease)}, greatest(coalesce(batch, ${String(batch)}), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := ${queue} || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, coalesce(v_extra, '{}'::jsonb) || jsonb_build_object(
        'content-type', 'application/json',
        'x-bsb-job', v_job_header,
        'x-bsb-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), ${String(timeout)};
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function ${fn("dispatch_workflow_deliveries")}(integer) from public, anon, authenticated;
grant execute on function ${fn("dispatch_workflow_deliveries")}(integer) to service_role;

-- Claims a start key: claimed is true when this caller may start the run,
-- either because the key is new or because the start that claimed it left no
-- run for stale_after. Otherwise run_id is the run of the earlier start (null
-- while that start is still running).
create or replace function ${fn("workflow_claim_run_key")}(run_key text, stale_after interval default '5 minutes')
returns table (claimed boolean, run_id text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
    insert into workflow.workflow_run_keys as k (key) values (run_key)
    on conflict (key) do update set claimed_at = now()
      where k.run_id is null and k.claimed_at < now() - coalesce(stale_after, interval '5 minutes')
    returning true, k.run_id::text;
  if not found then
    return query select false, k.run_id::text from workflow.workflow_run_keys k where k.key = run_key;
  end if;
end;
$$;

-- Records the run a claimed key started.
create or replace function ${fn("workflow_set_run_key")}(run_key text, run text)
returns void
language sql
security definer
set search_path = ''
as $$
  update workflow.workflow_run_keys set run_id = run, claimed_at = now() where key = run_key;
$$;

-- Frees a key whose start failed before it created a run.
create or replace function ${fn("workflow_release_run_key")}(run_key text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from workflow.workflow_run_keys where key = run_key and run_id is null;
$$;

-- Deletes up to batch terminal runs that ended more than older_than ago, with
-- their events, steps, waits, streams, snapshots and invocations; hooks whose
-- token is still reserved (token_retention_until) stay, so a token can't be
-- reused. The copies in workflow_runs follow purge_workflow_runs instead.
-- With skip_unprojected, a run of an eve session stays until the session's
-- copy in the blocks is current (the session was synced after its last change
-- and is no longer open).
drop function if exists ${fn("workflow_purge_runs")}(interval, text[], integer);
create or replace function ${fn("workflow_purge_runs")}(
  older_than interval default '30 days',
  statuses text[] default array['completed', 'failed', 'cancelled'],
  batch integer default 500,
  skip_unprojected boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_statuses text[] := coalesce(statuses, array['completed', 'failed', 'cancelled']);
  v_ids text[];
  v_count integer;
begin
  if exists (select 1 from unnest(v_statuses) s where s not in ('completed', 'failed', 'cancelled')) then
    raise exception 'workflow_purge_runs deletes only completed, failed or cancelled runs'
      using errcode = '22023', hint = 'WORKFLOW_PURGE_STATUS';
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.status::text = any (v_statuses)
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
      and not (coalesce(skip_unprojected, false) and exists (
        select 1 from workflow.eve_session_runs sr
        join workflow.eve_sessions es on es.session_id = sr.session_id
        where sr.run_id = r.id
          and (es.status = 'open' or es.synced_at is null or es.dirty_at > es.synced_at)
      ))
    order by coalesce(r.completed_at, r.updated_at)
    limit least(greatest(coalesce(batch, 500), 1), 10000)
    for update skip locked
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  delete from workflow.workflow_events where run_id = any (v_ids);
  delete from workflow.workflow_event_slots where run_id = any (v_ids);
  delete from workflow.workflow_steps where run_id = any (v_ids);
  delete from workflow.workflow_waits where run_id = any (v_ids);
  delete from workflow.workflow_stream_chunks where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  delete from workflow.workflow_invocations where run_id = any (v_ids);
  delete from workflow.workflow_hooks
    where run_id = any (v_ids) and (token_retention_until is null or token_retention_until < now());
  delete from workflow.workflow_run_keys where run_id = any (v_ids);
  delete from workflow.workflow_purge_backstops where run_id = any (v_ids);
  delete from workflow.eve_session_runs where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Runs up to batch due purge backstops: a run that ended with the $retention
-- attribute 0 and still has its data (expired_at is null) gets the purge
-- @workflow/world-postgres runs after the terminal write, in one transaction.
-- The run row is updated first, so late step and stream writes, which lock it
-- to read expired_at, wait for the purge. Returns how many runs it purged.
create or replace function ${fn("workflow_purge_backstops")}(batch integer default 100)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due text[];
  v_ids text[];
begin
  with due as (
    delete from workflow.workflow_purge_backstops b
    where b.run_id in (
      select d.run_id from workflow.workflow_purge_backstops d
      where d.due_at <= now()
      order by d.due_at
      limit least(greatest(coalesce(batch, 100), 1), 1000)
      for update skip locked
    )
    returning b.run_id
  )
  select coalesce(array_agg(due.run_id), '{}') into v_due from due;
  if cardinality(v_due) = 0 then
    return 0;
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.id = any (v_due)
      and r.status::text in ('completed', 'failed', 'cancelled')
      and r.attributes ->> '$retention' = '0'
      and r.expired_at is null
    for update
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  update workflow.workflow_runs set expired_at = now(),
    input_cbor = null, input = null, output_cbor = null, output = null,
    error_cbor = null, error = null, dynamic_workflow_code_cbor = null
    where id = any (v_ids);
  update workflow.workflow_steps set input_cbor = null, input = null,
    output_cbor = null, output = null, error_cbor = null, error = null
    where run_id = any (v_ids);
  update workflow.workflow_events set payload_cbor = null, payload = null, resume_payload_digest = null
    where run_id = any (v_ids);
  update workflow.workflow_hooks set metadata_cbor = null, metadata = null, resume_context = null
    where run_id = any (v_ids);
  update workflow.workflow_stream_chunks set data = ''::bytea where run_id = any (v_ids);
  update workflow.workflow_invocations set payload = null, result = null, fingerprint = null, expired_at = now()
    where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  return cardinality(v_ids);
end;
$$;

-- The hooks of pending and running runs, newest first: what a run waits on.
-- The token is left out; the app that created a hook knows it.
create or replace function ${fn("workflow_open_hooks")}(
  tenant text default null,
  workflow_name text default null,
  max integer default 50
)
returns table (
  hook_id text,
  run_id text,
  workflow text,
  tenant_id text,
  actor_id text,
  metadata jsonb,
  metadata_cbor bytea,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.metadata_cbor, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$$;
${eveProjectionSql(ctx)}
${SERVICE_FUNCTIONS.map(
  ([name, args]) =>
    `revoke execute on function ${fn(name)}(${args}) from public, anon, authenticated;
grant execute on function ${fn(name)}(${args}) to service_role;`,
).join("\n")}`;
}

const RETENTION = /^\d{1,4} (?:day|days|hour|hours)$/u;

function retentionOf(ctx: BlockSqlContext): string | undefined {
  const retention = ctx.text("retention", "");

  if (retention === "") {
    return undefined;
  }

  if (!RETENTION.test(retention)) {
    throw new TypeError(
      `blocks["workflow-sdk"].options.retention must look like "30 days" or "12 hours", got "${retention}"`,
    );
  }

  return retention;
}

function cronJob(
  name: string,
  schedule: string,
  command: string,
  notice: string,
): string {
  return `do $$
begin
  if pg_catalog.to_regnamespace('cron') is not null then
    perform cron.schedule(${sqlString(name)}, ${sqlString(schedule)}, ${sqlString(command)});
  else
    raise notice ${sqlString(notice)};
  end if;
end;
$$;`;
}

function data(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  // world-postgres 5.1 stores timestamptz; 5.0 tables hold UTC timestamps. A
  // schema diff can't convert the rows, so the data file does.
  const parts: string[] = [
    `do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;`,
  ];

  const delivery = deliveryModeOf(ctx);

  if (delivery === "pg_net") {
    const schedule = ctx.text("schedule", "1 seconds");
    const dispatch = ctx.fn("dispatch_workflow_deliveries");

    parts.push(
      `-- Delivers workflow messages through pg_net every ${schedule} when pg_cron is installed.
${cronJob(
  "better-supabase-workflow-deliveries",
  schedule,
  `select ${dispatch}()`,
  `pg_cron is not installed: call ${dispatch}() on a schedule to deliver workflow messages`,
)}`,
    );
  }

  // In poll mode the World runs the backstops while it polls; the other modes
  // have no process that polls.
  if (delivery !== "poll") {
    const backstops = ctx.fn("workflow_purge_backstops");

    parts.push(
      `-- Runs the purge backstops of zero-retention runs every minute.
${cronJob(
  "better-supabase-workflow-backstops",
  "* * * * *",
  `select ${backstops}()`,
  `pg_cron is not installed: call ${backstops}() on a schedule to purge zero-retention runs whose purge did not complete`,
)}`,
    );
  }

  const retention = retentionOf(ctx);

  if (retention !== undefined) {
    const purge = ctx.fn("workflow_purge_runs");

    parts.push(
      `-- Deletes the World's runs that ended more than ${retention} ago, every hour.
${cronJob(
  "better-supabase-workflow-purge",
  "17 * * * *",
  `select ${purge}(interval ${sqlString(retention)})`,
  `pg_cron is not installed: run better-supabase workflows prune on a schedule to delete old workflow runs`,
)}`,
    );
  }

  return parts.join("\n\n");
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "dispatch_workflow_deliveries",
      args: ["integer"],
      returns: "integer",
    },
    {
      name: "workflow_claim_run_key",
      args: ["text", "interval"],
      returns: "record",
    },
    { name: "workflow_set_run_key", args: ["text", "text"], returns: "void" },
    { name: "workflow_release_run_key", args: ["text"], returns: "void" },
    {
      name: "workflow_purge_runs",
      args: ["interval", "text[]", "integer", "boolean"],
      returns: "integer",
    },
    { name: "workflow_purge_backstops", args: ["integer"], returns: "integer" },
    {
      name: "workflow_open_hooks",
      args: ["text", "text", "integer"],
      returns: "record",
    },
    ...eveContract(),
  ];
}

export const WORKFLOW_SDK_WORLD: BlockSqlDefinition = {
  name: "workflow-sdk",
  scopes: ["tenant"],
  title: "Workflow SDK World",
  description: `The tables of the Workflow SDK World (@workflow/world-postgres ${WORLD_POSTGRES_VERSION}) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on, a purge of ended runs, the purge backstops of zero-retention runs and the eve projection tables with the jobs that copy eve sessions into the blocks.`,
  requires: ["workflows", "queue", "permissions"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 10,
  upgrades: [
    {
      from: 1,
      description:
        "The run trigger fills subject, principal, mode and trigger node from the bsb.subject, bsb.principal_kind, bsb.principal, bsb.mode and bsb.trigger_node attributes, and a runAs start keeps bsb.actor as the user who triggered it.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "workflow.workflow_run_keys holds start idempotency keys (workflow_claim_run_key, workflow_set_run_key, workflow_release_run_key); workflow_open_hooks lists the hooks open runs wait on; workflow_purge_runs deletes ended runs, hourly when the retention option is set.",
      sql: () => "",
    },
    {
      from: 3,
      description:
        "The World tables follow @workflow/world-postgres 5.1: timestamps become timestamptz (read as UTC), hooks gain claims_token, runs gain start_hook_cbor and job_prefix, and workflow_start_hook_admissions is new. workflow_open_hooks returns metadata_cbor, which the World decodes.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "The World tables follow @workflow/world-postgres 5.2: workflow_job_lock_holders is new (migration 0030), closed to the API roles like the other World tables.",
      sql: () => "",
    },
    {
      from: 5,
      description:
        "The World tables follow @workflow/world-postgres 5.4: workflow_run_delivery_leases is new (migration 0031) and workflow_runs gains wake_pending (migration 0032). Runs that exist before the upgrade start with wake_pending set, so startup recovery lets their next completed delivery decide, and new runs start clear.",
      // Upstream adds the column with a default of true so existing rows are
      // set, then changes the default; the module's file adds it with the
      // final default, which would clear existing rows.
      sql: () => `alter table workflow.workflow_runs add column if not exists "wake_pending" boolean not null default true;
alter table workflow.workflow_runs alter column "wake_pending" set default false;`,
    },
    {
      from: 6,
      description:
        "The eve projection: workflow.eve_sessions and workflow.eve_session_runs, triggers that wake a debounced eve_session_sync job when an eve run or one of its events changes, the eve_session_* functions syncSession uses, and workflow_purge_runs takes skip_unprojected.",
      sql: () => "",
    },
    {
      from: 7,
      description:
        'dispatch_workflow_deliveries adds the headers in the Vault secret workflow_delivery_headers (a JSON object) to each delivery, and the delivery option accepts "vercel-queue", which sends messages through Vercel Queues and creates no cron job.',
      sql: () => "",
    },
    {
      from: 8,
      description:
        "Follows @workflow/world-postgres 5.4.1, whose terminal write of a zero-retention run adds a purge backstop through Graphile Worker's add_job: workflow.add_job records it in workflow.workflow_purge_backstops, workflow_purge_backstops deletes the data of due runs whose purge did not complete (the World runs it while it polls; the pg_net and vercel-queue modes schedule it every minute under pg_cron), and workflow_purge_runs deletes a purged run's backstop.",
      sql: () => "",
    },
    {
      from: 9,
      description:
        "Follows @workflow/world-postgres 5.5: workflow.workflow_rate_limits is new (migration 0033), closed to the API roles like the other World tables. The World does not reserve rate limit slots (it mints spec 8 runs), so the table stays empty until it does.",
      sql: () => "",
    },
  ],
  names: {
    tables: {},
    options: ["delivery", "queue", "batch", "timeout", "schedule", "retention"],
  },
  contract,
  build,
  data,
};
