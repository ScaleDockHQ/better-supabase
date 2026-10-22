import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import {
  WORLD_POSTGRES_DDL,
  WORLD_POSTGRES_VERSION,
} from "./workflow-sdk-world-ddl.generated.ts";

export const WORKFLOW_DELIVERY_MODES = ["poll", "pg_net"] as const;

export type WorkflowDeliveryMode = (typeof WORKFLOW_DELIVERY_MODES)[number];

/** The Vault secret names the pg_net dispatcher reads. */
export const WORKFLOW_VAULT_SECRETS = {
  flowUrl: "workflow_flow_url",
  deliverySecret: "workflow_delivery_secret",
  encryptionKey: "workflow_encryption_key",
} as const;

export const WORKFLOW_DELIVERY_QUEUE = "workflow_deliveries";

function deliveryModeOf(ctx: BlockSqlContext): WorkflowDeliveryMode {
  const mode = ctx.text("delivery", "poll");

  if (mode !== "poll" && mode !== "pg_net") {
    throw new TypeError(
      `blocks.workflow-sdk-world.options.delivery must be "poll" or "pg_net", got "${mode}"`,
    );
  }

  return mode;
}

const IDENT = /^[a-z_][a-z0-9_]{0,40}$/;

function deliveryQueueOf(ctx: BlockSqlContext): string {
  const queue = ctx.text("queue", WORKFLOW_DELIVERY_QUEUE);

  if (!IDENT.test(queue)) {
    throw new TypeError(
      `blocks.workflow-sdk-world.options.queue: "${queue}" is not a queue name`,
    );
  }

  return queue;
}

const PRINCIPAL_KINDS = "'user', 'service_principal', 'system', 'external'";

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const fn = (name: string): string => ctx.fn(name);
  const workflows = ctx.of("workflows");
  const record = workflows.fn("record_workflow_run");
  const runKey = workflows.permission("run", OPERATIONS["workflows.run"]);
  const claimJobs = ctx.of("jobs").fn("claim_jobs");
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
revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
do $$
declare
  t record;
begin
  for t in select c.relname from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'workflow' and c.relkind = 'r'
  loop
    execute format('alter table workflow.%I enable row level security', t.relname);
    execute format('revoke all on workflow.%I from public, anon, authenticated', t.relname);
    execute format('grant all on workflow.%I to service_role', t.relname);
  end loop;
end;
$$;
grant usage, select on all sequences in schema workflow to service_role;
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
    new.started_at at time zone 'UTC',
    new.completed_at at time zone 'UTC',
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
  for v_job in select * from ${claimJobs}(${queue}, ${String(lease)}, greatest(coalesce(batch, ${String(batch)}), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := ${queue} || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, jsonb_build_object(
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
grant execute on function ${fn("dispatch_workflow_deliveries")}(integer) to service_role;`;
}

function data(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom" || deliveryModeOf(ctx) !== "pg_net") {
    return "";
  }

  const schedule = ctx.text("schedule", "1 seconds");

  return `-- Delivers workflow messages through pg_net every ${schedule} when pg_cron is installed.
do $$
begin
  if pg_catalog.to_regnamespace('cron') is not null then
    perform cron.schedule('better-supabase-workflow-deliveries', ${sqlString(schedule)}, ${sqlString(`select ${ctx.fn("dispatch_workflow_deliveries")}()`)});
  else
    raise notice 'pg_cron is not installed: call ${ctx.fn("dispatch_workflow_deliveries").replaceAll("'", "")}() on a schedule to deliver workflow messages';
  end if;
end;
$$;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "dispatch_workflow_deliveries",
      args: ["integer"],
      returns: "integer",
    },
  ];
}

export const WORKFLOW_SDK_WORLD: BlockSqlDefinition = {
  name: "workflow-sdk-world",
  scopes: ["tenant"],
  title: "Workflow SDK World",
  description: `The tables of the Workflow SDK World (@workflow/world-postgres ${WORLD_POSTGRES_VERSION}) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, and a pg_net dispatcher for the delivery queue on a pg_cron schedule.`,
  requires: ["workflows", "jobs", "access"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "The run trigger fills subject, principal, mode and trigger node from the bsb.subject, bsb.principal_kind, bsb.principal, bsb.mode and bsb.trigger_node attributes, and a runAs start keeps bsb.actor as the user who triggered it.",
      sql: () => "",
    },
  ],
  names: {
    tables: {},
    options: ["delivery", "queue", "batch", "timeout", "schedule"],
  },
  contract,
  build,
  data,
};
