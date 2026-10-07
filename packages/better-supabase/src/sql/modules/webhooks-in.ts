import type { ModuleContext } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, updatedAt } from "../shared.ts";
import {
  qualifiedTable,
  subjectCascades,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

/** How a delivery to an endpoint proves it came from the sender. */
const INCOMING_VERIFY = ["none", "standard-webhooks", "hmac-sha256"] as const;

const fail = (code: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${code}';`;

function webhooksInSql(ctx: ModuleContext): string {
  const id = ctx.idType;
  const t = ctx.table("endpoints");
  const p = MODULE_PERMISSIONS["webhooks-in"];
  const manage = ctx.permission("manage", p.manage);
  const view = ctx.permission("view", p.view);
  const verify = INCOMING_VERIFY.map((mode) => `'${mode}'`).join(", ");
  const maxBody = ctx.number("maxBodyBytes", 1_048_576);
  const can = (tenant: string) =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${manage}), false))`;
  const subjects = subjectsOption(ctx);
  const readable = subjectReadable(subjects, {
    type: "subject_type",
    id: "subject_id",
    tenant: "tenant",
  });
  // The create function runs as its owner, so it checks that the subject
  // exists in the tenant and its permission; the read policy applies the
  // subject table's own policies as the caller.
  const subjectExists =
    subjects.length === 0
      ? "true"
      : `case subject_type\n${subjects
          .map(([type, subject]) => {
            const permission = subject.permission
              ? ` and (${SERVICE_CALLER} or coalesce(better_supabase.member_can(auth.uid(), tenant, ${sqlString(subject.permission)}), false))`
              : "";
            return `      when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, "subject_id")} and s.${sqlIdent(subject.tenant === false ? "organization_id" : (subject.tenant ?? "organization_id"))} = tenant)${permission}`;
          })
          .join("\n")}\n      else false\n    end`;
  const cascades = subjectCascades(
    ctx,
    subjects,
    `delete from ${t} e where e.subject_type = v_type and e.subject_id = v_id;`,
  );
  return `${schemaPreamble(ctx)}
-- Trigger URLs a tenant hands to another system: /hooks/<token> stores each
-- delivery in the webhook inbox (source webhook-in), with the endpoint's
-- tenant. Only the token's hash is kept.
create table if not exists ${t} (
  id uuid primary key default gen_random_uuid(),
  tenant ${id} not null,
  name text not null,
  token_hash text not null unique,
  verify text not null default 'none' check (verify in (${verify})),
  secret text,
  signature_header text,
  enabled boolean not null default true,
  max_body_bytes integer not null default ${String(maxBody)} check (max_body_bytes > 0),
  receive_count bigint not null default 0,
  last_received_at timestamptz,
  last_status integer,
  metadata jsonb not null default '{}',
  subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$'),
  subject_id text check (length(subject_id) between 1 and 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table ${t} add column if not exists subject_type text check (subject_type ~ '^[a-z][a-z0-9_]{0,62}$');
alter table ${t} add column if not exists subject_id text check (length(subject_id) between 1 and 200);
create index if not exists incoming_webhooks_tenant_idx on ${t} (tenant);
create index if not exists incoming_webhooks_subject_idx on ${t} (tenant, subject_type, subject_id);
${updatedAt(t, "updated_at")}
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
-- The secret stays with the service: members read every other column.
grant select (id, tenant, name, verify, signature_header, enabled, max_body_bytes, receive_count, last_received_at, last_status, metadata, subject_type, subject_id, created_by, created_at, updated_at) on ${t} to authenticated;
grant all on ${t} to service_role;

create or replace function ${ctx.fn("incoming_webhook_tenant_ids")}()
returns setof ${id}
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with(${view});
end;
$$;
revoke execute on function ${ctx.fn("incoming_webhook_tenant_ids")}() from public, anon;
grant execute on function ${ctx.fn("incoming_webhook_tenant_ids")}() to authenticated, service_role;
-- Whether the caller may read an endpoint's subject: its row is visible to
-- them (the subject table's own policies apply) and they hold its permission.
create or replace function ${ctx.fn("incoming_webhook_subject_readable")}(subject_type text, subject_id text, tenant ${id})
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select subject_type is null or ${readable}
$$;
revoke execute on function ${ctx.fn("incoming_webhook_subject_readable")}(text, text, ${id}) from public, anon;
grant execute on function ${ctx.fn("incoming_webhook_subject_readable")}(text, text, ${id}) to authenticated, service_role;

drop policy if exists bs_incoming_webhooks_read on ${t};
create policy bs_incoming_webhooks_read on ${t} for select to authenticated
  using (
    tenant in (select ${ctx.fn("incoming_webhook_tenant_ids")}())
    and ${ctx.fn("incoming_webhook_subject_readable")}(subject_type, subject_id, tenant)
  );

-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function ${ctx.fn("list_incoming_webhooks")}(tenant ${id}, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'tenant', e.tenant, 'name', e.name, 'verify', e.verify,
    'signature_header', e.signature_header, 'enabled', e.enabled,
    'max_body_bytes', e.max_body_bytes, 'receive_count', e.receive_count,
    'last_received_at', e.last_received_at, 'last_status', e.last_status,
    'metadata', e.metadata, 'subject_type', e.subject_type, 'subject_id', e.subject_id,
    'created_by', e.created_by, 'created_at', e.created_at
  ) order by e.created_at), '[]'::jsonb)
  from ${t} e
  where e.tenant = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e.subject_type = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e.subject_id = list_incoming_webhooks.subject_id)
$$;
revoke execute on function ${ctx.fn("list_incoming_webhooks")}(${id}, text, text) from public, anon;
grant execute on function ${ctx.fn("list_incoming_webhooks")}(${id}, text, text) to authenticated, service_role;
${cascades}
drop function if exists ${ctx.fn("create_incoming_webhook")}(${id}, text, text, jsonb, text);
-- Creates an endpoint and returns it with its token (and the signing secret
-- for standard-webhooks and hmac-sha256), shown once.
create or replace function ${ctx.fn("create_incoming_webhook")}(
  tenant ${id},
  name text,
  verify text default 'none',
  metadata jsonb default '{}',
  signature_header text default null,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created ${t};
begin
  if not ${can("tenant")} then
    ${fail("WEBHOOK_IN_FORBIDDEN", "Not allowed to manage incoming webhooks")}
  end if;
  if (subject_type is null) <> (subject_id is null) then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "Pass subject_type and subject_id together", "22023")}
  end if;
  if subject_type is not null and not (${subjectExists}) then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "No such subject in this tenant", "22023")}
  end if;
  insert into ${t} (tenant, name, token_hash, verify, secret, signature_header, metadata, subject_type, subject_id, created_by)
  values (tenant, name, encode(extensions.digest(token, 'sha256'), 'hex'), verify, secret,
    case when verify = 'hmac-sha256' then coalesce(signature_header, 'x-signature') end,
    coalesce(metadata, '{}'), subject_type, subject_id, auth.uid())
  returning * into created;
  return jsonb_build_object('id', created.id, 'tenant', created.tenant, 'name', created.name,
    'verify', created.verify, 'token', token, 'secret', secret, 'signatureHeader', created.signature_header,
    'subjectType', created.subject_type, 'subjectId', created.subject_id);
end;
$$;

-- A new token (the old URL stops working); with rotate_secret, a new secret too.
create or replace function ${ctx.fn("rotate_incoming_webhook")}(endpoint uuid, rotate_secret boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  updated ${t};
begin
  select * into updated from ${t} e where e.id = endpoint for update;
  if updated.id is null or not ${can("updated.tenant")} then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  update ${t} e set token_hash = encode(extensions.digest(token, 'sha256'), 'hex'),
    secret = case when rotate_secret and e.verify = 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
      when rotate_secret and e.verify = 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
      else e.secret end
  where e.id = endpoint
  returning * into updated;
  return jsonb_build_object('id', updated.id, 'token', token,
    'secret', case when rotate_secret then updated.secret end);
end;
$$;

create or replace function ${ctx.fn("set_incoming_webhook_enabled")}(endpoint uuid, enabled boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant ${id};
begin
  select e.tenant into tenant from ${t} e where e.id = endpoint;
  if tenant is null or not ${can("tenant")} then
    return false;
  end if;
  update ${t} e set enabled = set_incoming_webhook_enabled.enabled where e.id = endpoint;
  return true;
end;
$$;

create or replace function ${ctx.fn("delete_incoming_webhook")}(endpoint uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant ${id};
begin
  select e.tenant into tenant from ${t} e where e.id = endpoint;
  if tenant is null or not ${can("tenant")} then
    return false;
  end if;
  delete from ${t} e where e.id = endpoint;
  return true;
end;
$$;

-- The endpoint behind a token, with its secret, for the receiving route.
create or replace function ${ctx.fn("incoming_webhook_by_token")}(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id, e.tenant::text, e.enabled, e.verify, e.secret, e.signature_header, e.max_body_bytes
  from ${t} e
  where e.token_hash = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function ${ctx.fn("record_incoming_webhook")}(endpoint uuid, status integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update ${t} e
  set receive_count = e.receive_count + 1, last_received_at = now(), last_status = record_incoming_webhook.status
  where e.id = endpoint
$$;

revoke execute on function ${ctx.fn("create_incoming_webhook")}(${id}, text, text, jsonb, text, text, text) from public, anon;
grant execute on function ${ctx.fn("create_incoming_webhook")}(${id}, text, text, jsonb, text, text, text) to authenticated, service_role;
revoke execute on function ${ctx.fn("rotate_incoming_webhook")}(uuid, boolean) from public, anon;
grant execute on function ${ctx.fn("rotate_incoming_webhook")}(uuid, boolean) to authenticated, service_role;
revoke execute on function ${ctx.fn("set_incoming_webhook_enabled")}(uuid, boolean) from public, anon;
grant execute on function ${ctx.fn("set_incoming_webhook_enabled")}(uuid, boolean) to authenticated, service_role;
revoke execute on function ${ctx.fn("delete_incoming_webhook")}(uuid) from public, anon;
grant execute on function ${ctx.fn("delete_incoming_webhook")}(uuid) to authenticated, service_role;
revoke execute on function ${ctx.fn("incoming_webhook_by_token")}(text) from public, anon, authenticated;
grant execute on function ${ctx.fn("incoming_webhook_by_token")}(text) to service_role;
revoke execute on function ${ctx.fn("record_incoming_webhook")}(uuid, integer) from public, anon, authenticated;
grant execute on function ${ctx.fn("record_incoming_webhook")}(uuid, integer) to service_role;`;
}

export const WEBHOOKS_IN: ModuleDefinition = {
  internal: [
    "incoming_webhook_tenant_ids",
    "incoming_webhook_subject_readable",
  ],
  name: "webhooks-in",
  title: "Incoming webhook endpoints",
  description:
    "Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.",
  requires: ["access", "webhook-inbox"],
  target: "schema",
  names: {
    tables: {
      endpoints: { name: "incoming_webhooks", columns: {} },
    },
    options: ["maxBodyBytes", "subjects"],
  },
  contract: () => [
    {
      name: "create_incoming_webhook",
      args: ["{id}", "text", "text", "jsonb", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_incoming_webhooks",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    { name: "incoming_webhook_by_token", args: ["text"], returns: "record" },
    {
      name: "record_incoming_webhook",
      args: ["uuid", "integer"],
      returns: "void",
    },
  ],
  build: webhooksInSql,
};
