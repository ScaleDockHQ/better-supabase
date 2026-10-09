import type { ModuleContext, ModuleEvents } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  schemaPreamble,
  SERVICE_CALLER,
  sha256Hex,
  updatedAt,
} from "../shared.ts";
import {
  qualifiedTable,
  subjectCascades,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { MODULE_PERMISSIONS, modulePermissionKey } from "./access-model.ts";

/** How a delivery to an endpoint proves it came from the sender. */
const INCOMING_VERIFY = [
  "none",
  "standard-webhooks",
  "hmac-sha256",
  "shared-secret",
] as const;

const headerFor = (mode: string, given: string, kept: string): string =>
  `case ${mode}
      when 'hmac-sha256' then coalesce(${given}, ${kept}, 'x-signature')
      when 'shared-secret' then coalesce(${given}, ${kept}, 'x-webhook-secret')
    end`;

const fail = (code: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${code}';`;

function secretStorage(ctx: ModuleContext): boolean {
  const storage = ctx.text("secretStorage", "vault");
  if (storage !== "vault" && storage !== "column") {
    throw new TypeError(
      `sql.modules.webhooks-in.options.secretStorage must be "vault" or "column", not "${storage}"`,
    );
  }
  return storage === "vault";
}

/** A Vault secret holding secret for endpoint, or null when secret is null. */
const vaultSecret = (secret: string, endpoint: string): string =>
  `case when ${secret} is null then null else vault.create_secret(${secret}, 'webhook-in:' || ${endpoint}::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end`;

const newSecret = (mode: string): string => `case ${mode}
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end`;

function webhooksInSql(ctx: ModuleContext): string {
  const renamed = Object.keys(ctx.config.columns["endpoints"] ?? {});
  if (renamed.length > 0) {
    throw new TypeError(
      `sql.modules.webhooks-in.columns.endpoints: the module owns its table, so ${renamed.join(", ")} can't be renamed`,
    );
  }
  const id = ctx.idType;
  const t = ctx.table("endpoints");
  const p = MODULE_PERMISSIONS["webhooks-in"];
  const key = (action: "create" | "update" | "delete") =>
    sqlString(modulePermissionKey(ctx, action, p[action]));
  const view = ctx.permission("view", p.view);
  const verify = INCOMING_VERIFY.map((mode) => `'${mode}'`).join(", ");
  const maxBody = ctx.number("maxBodyBytes", 1_048_576);
  const vault = secretStorage(ctx);
  const stored = (secret: string, endpoint: string) =>
    vault ? vaultSecret(secret, endpoint) : "null";
  const plain = (secret: string) => (vault ? "null" : secret);
  const cleanupTrigger = ctx.trigger("incoming_webhook_vault");
  const cleanup = vault
    ? `
-- Deleting an endpoint (or its tenant or subject) deletes its Vault secret.
create or replace function ${ctx.fn("drop_incoming_webhook_secret")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id in (old.secret_id, old.previous_secret_id);
  return null;
end;
$$;
revoke execute on function ${ctx.fn("drop_incoming_webhook_secret")}() from public, anon, authenticated;
drop trigger if exists ${cleanupTrigger} on ${t};
create trigger ${cleanupTrigger} after delete on ${t}
  for each row when (old.secret_id is not null or old.previous_secret_id is not null) execute function ${ctx.fn("drop_incoming_webhook_secret")}();`
    : `
drop trigger if exists ${cleanupTrigger} on ${t};`;
  const can = (tenant: string, action: "create" | "update" | "delete") =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${key(action)}), false))`;
  const hookEvent = (
    type: string,
    endpoint: string,
    tenant: string,
    category: "integration" | "security",
    extra = "",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${tenant}::text, 'endpointId', ${endpoint}${extra})`,
      subject: `'organizations/' || ${tenant}::text || '/incoming-webhooks/' || ${endpoint}::text`,
      tenant,
      audit: {
        category,
        targetType: "incoming_webhook",
        recordId: `${endpoint}::text`,
      },
    });
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
-- tenant. Only the token's hash is kept, and the signing secret is a Vault
-- secret (secret_id) unless options.secretStorage is "column".
create table if not exists ${t} (
  id uuid primary key default gen_random_uuid(),
  tenant ${id} not null,
  name text not null,
  token_hash text not null unique,
  verify text not null default 'none' check (verify in (${verify})),
  secret text,
  secret_id uuid,
  previous_secret text,
  previous_secret_id uuid,
  previous_secret_expires_at timestamptz,
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
alter table ${t} add column if not exists secret_id uuid;
alter table ${t} drop constraint if exists incoming_webhooks_verify_check;
alter table ${t} add constraint incoming_webhooks_verify_check check (verify in (${verify}));
alter table ${t} add column if not exists previous_secret text;
alter table ${t} add column if not exists previous_secret_id uuid;
alter table ${t} add column if not exists previous_secret_expires_at timestamptz;
create index if not exists incoming_webhooks_tenant_idx on ${t} (tenant);
create index if not exists incoming_webhooks_subject_idx on ${t} (tenant, subject_type, subject_id);
create index if not exists incoming_webhooks_created_by_idx on ${t} (created_by) where created_by is not null;
${updatedAt(t, "updated_at")}${cleanup}
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
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := ${newSecret("verify")};
  created ${t};
begin
  if not ${can("tenant", "create")} then
    ${fail("WEBHOOK_IN_FORBIDDEN", "Not allowed to manage incoming webhooks")}
  end if;
  if (subject_type is null) <> (subject_id is null) then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "Pass subject_type and subject_id together", "22023")}
  end if;
  if subject_type is not null and not (${subjectExists}) then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "No such subject in this tenant", "22023")}
  end if;
  insert into ${t} (id, tenant, name, token_hash, verify, secret, secret_id, signature_header, metadata, subject_type, subject_id, created_by)
  values (v_id, tenant, name, ${sha256Hex("token")}, verify, ${plain("secret")}, ${stored("secret", "v_id")},
    ${headerFor("verify", "signature_header", "null")},
    coalesce(metadata, '{}'), subject_type, subject_id, auth.uid())
  returning * into created;
  ${hookEvent("incoming_webhook.created", "created.id", "created.tenant", "integration", ", 'name', created.name")}
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
  v_secret text;
  updated ${t};
  previous ${t};
begin
  select * into previous from ${t} e where e.id = endpoint for update;
  if previous.id is null or not ${can("previous.tenant", "update")} then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := ${newSecret("previous.verify")};
  end if;
  update ${t} e set token_hash = ${sha256Hex("token")},
    secret = case when rotate_secret then ${plain("v_secret")} else e.secret end,
    secret_id = case when rotate_secret then ${stored("v_secret", "e.id")} else e.secret_id end,
    previous_secret = case when rotate_secret then null else e.previous_secret end,
    previous_secret_id = case when rotate_secret then null else e.previous_secret_id end,
    previous_secret_expires_at = case when rotate_secret then null else e.previous_secret_expires_at end
  where e.id = endpoint
  returning * into updated;${
    vault
      ? `
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous.secret_id, previous.previous_secret_id);
  end if;`
      : ""
  }
  ${hookEvent("incoming_webhook.token_rotated", "updated.id", "updated.tenant", "security", ", 'secretRotated', rotate_secret")}
  return jsonb_build_object('id', updated.id, 'token', token, 'secret', v_secret);
end;
$$;

create or replace function ${ctx.fn("rotate_incoming_webhook_secret")}(endpoint uuid, grace interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous ${t};
  updated ${t};
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  select * into previous from ${t} e where e.id = endpoint for update;
  if previous.id is null or not ${can("previous.tenant", "update")} then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := ${newSecret("previous.verify")};
  if v_secret is null then
    ${fail("WEBHOOK_IN_NO_SECRET", "This endpoint verifies no secret", "22023")}
  end if;
  update ${t} e set
    secret = ${plain("v_secret")},
    secret_id = ${stored("v_secret", "e.id")},
    previous_secret = case when v_keep then e.secret end,
    previous_secret_id = case when v_keep then e.secret_id end,
    previous_secret_expires_at = case when v_keep then now() + grace end
  where e.id = endpoint
  returning * into updated;${
    vault
      ? `
  delete from vault.secrets vs
  where vs.id = previous.previous_secret_id or (not v_keep and vs.id = previous.secret_id);`
      : ""
  }
  ${hookEvent("incoming_webhook.secret_rotated", "updated.id", "updated.tenant", "security")}
  return jsonb_build_object('id', updated.id, 'secret', v_secret, 'previousSecretExpiresAt', updated.previous_secret_expires_at);
end;
$$;

create or replace function ${ctx.fn("update_incoming_webhook")}(
  endpoint uuid,
  name text default null,
  metadata jsonb default null,
  verify text default null,
  signature_header text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous ${t};
  updated ${t};
  v_verify text;
  v_secret text;
begin
  select * into previous from ${t} e where e.id = endpoint for update;
  if previous.id is null or not ${can("previous.tenant", "update")} then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    ${fail("WEBHOOK_IN_NAME_REQUIRED", "An endpoint needs a name", "22023")}
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    ${fail("WEBHOOK_IN_METADATA_INVALID", "metadata must be a JSON object", "22023")}
  end if;
  v_verify := coalesce(verify, previous.verify);
  if v_verify not in (${verify}) then
    ${fail("WEBHOOK_IN_VERIFY_UNKNOWN", "Unknown verification mode", "22023")}
  end if;
  if v_verify <> previous.verify then
    v_secret := ${newSecret("v_verify")};
  end if;
  update ${t} e set
    name = coalesce(update_incoming_webhook.name, e.name),
    metadata = coalesce(update_incoming_webhook.metadata, e.metadata),
    verify = v_verify,
    secret = case when v_verify = previous.verify then e.secret else ${plain("v_secret")} end,
    secret_id = case when v_verify = previous.verify then e.secret_id else ${stored("v_secret", "e.id")} end,
    previous_secret = case when v_verify = previous.verify then e.previous_secret end,
    previous_secret_id = case when v_verify = previous.verify then e.previous_secret_id end,
    previous_secret_expires_at = case when v_verify = previous.verify then e.previous_secret_expires_at end,
    signature_header = ${headerFor("v_verify", "update_incoming_webhook.signature_header", "case when v_verify = previous.verify then e.signature_header end")}
  where e.id = endpoint
  returning * into updated;${
    vault
      ? `
  if v_verify <> previous.verify then
    delete from vault.secrets vs where vs.id in (previous.secret_id, previous.previous_secret_id);
  end if;`
      : ""
  }
  ${hookEvent("incoming_webhook.updated", "updated.id", "updated.tenant", "integration", ", 'name', updated.name, 'verify', updated.verify")}
  return jsonb_build_object('id', updated.id, 'tenant', updated.tenant, 'name', updated.name,
    'verify', updated.verify, 'secret', v_secret, 'signatureHeader', updated.signature_header,
    'metadata', updated.metadata);
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
  if tenant is null or not ${can("tenant", "update")} then
    return false;
  end if;
  update ${t} e set enabled = set_incoming_webhook_enabled.enabled where e.id = endpoint;
  ${hookEvent("incoming_webhook.enabled_set", "endpoint", "tenant", "integration", ", 'enabled', set_incoming_webhook_enabled.enabled")}
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
  if tenant is null or not ${can("tenant", "delete")} then
    return false;
  end if;
  delete from ${t} e where e.id = endpoint;
  ${hookEvent("incoming_webhook.deleted", "endpoint", "tenant", "integration")}
  return true;
end;
$$;

-- The endpoint behind a token, with its secret, for the receiving route.
drop function if exists ${ctx.fn("incoming_webhook_by_token")}(text);
create or replace function ${ctx.fn("incoming_webhook_by_token")}(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id, e.tenant::text, e.enabled, e.verify, ${vault ? "coalesce(ds.decrypted_secret, e.secret)" : "e.secret"}, e.signature_header, e.max_body_bytes,
    case when e.previous_secret_expires_at > now() then ${vault ? "coalesce(dp.decrypted_secret, e.previous_secret)" : "e.previous_secret"} end
  from ${t} e${vault ? "\n  left join vault.decrypted_secrets ds on ds.id = e.secret_id\n  left join vault.decrypted_secrets dp on dp.id = e.previous_secret_id" : ""}
  where e.token_hash = ${sha256Hex("incoming_webhook_by_token.token")}
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
revoke execute on function ${ctx.fn("rotate_incoming_webhook_secret")}(uuid, interval) from public, anon;
grant execute on function ${ctx.fn("rotate_incoming_webhook_secret")}(uuid, interval) to authenticated, service_role;
revoke execute on function ${ctx.fn("update_incoming_webhook")}(uuid, text, jsonb, text, text) from public, anon;
grant execute on function ${ctx.fn("update_incoming_webhook")}(uuid, text, jsonb, text, text) to authenticated, service_role;
revoke execute on function ${ctx.fn("set_incoming_webhook_enabled")}(uuid, boolean) from public, anon;
grant execute on function ${ctx.fn("set_incoming_webhook_enabled")}(uuid, boolean) to authenticated, service_role;
revoke execute on function ${ctx.fn("delete_incoming_webhook")}(uuid) from public, anon;
grant execute on function ${ctx.fn("delete_incoming_webhook")}(uuid) to authenticated, service_role;
revoke execute on function ${ctx.fn("incoming_webhook_by_token")}(text) from public, anon, authenticated;
grant execute on function ${ctx.fn("incoming_webhook_by_token")}(text) to service_role;
revoke execute on function ${ctx.fn("record_incoming_webhook")}(uuid, integer) from public, anon, authenticated;
grant execute on function ${ctx.fn("record_incoming_webhook")}(uuid, integer) to service_role;`;
}

const EVENTS: ModuleEvents = {
  "incoming_webhook.created": {
    subject: "organizations",
    payload: ["organizationId", "endpointId", "name"],
  },
  "incoming_webhook.token_rotated": {
    subject: "organizations",
    payload: ["organizationId", "endpointId", "secretRotated"],
  },
  "incoming_webhook.secret_rotated": {
    subject: "organizations",
    payload: ["organizationId", "endpointId"],
  },
  "incoming_webhook.updated": {
    subject: "organizations",
    payload: ["organizationId", "endpointId", "name", "verify"],
  },
  "incoming_webhook.enabled_set": {
    subject: "organizations",
    payload: ["organizationId", "endpointId", "enabled"],
  },
  "incoming_webhook.deleted": {
    subject: "organizations",
    payload: ["organizationId", "endpointId"],
  },
};

export const WEBHOOKS_IN: ModuleDefinition = {
  internal: [
    "incoming_webhook_tenant_ids",
    "incoming_webhook_subject_readable",
  ],
  name: "webhooks-in",
  title: "Incoming webhook endpoints",
  description:
    "Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.",
  requires: ["access", "updated-at", "webhook-inbox"],
  target: "schema",
  names: {
    events: EVENTS,
    tables: {
      endpoints: {
        name: "incoming_webhooks",
        columns: {
          tenant: "tenant",
          tokenHash: "token_hash",
          secret: "secret",
          secretId: "secret_id",
          previousSecret: "previous_secret",
          previousSecretId: "previous_secret_id",
        },
        lifecycle: {
          tenant: "tenant",
          omit: [
            "tokenHash",
            "secret",
            "secretId",
            "previousSecret",
            "previousSecretId",
          ],
        },
      },
    },
    options: ["maxBodyBytes", "secretStorage", "subjects"],
  },
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        'Signing secrets move to Vault (secret_id) unless options.secretStorage is "column"; existing plaintext secrets are copied to Vault and cleared.',
      sql: (ctx) => {
        if (!secretStorage(ctx)) return "";
        const t = ctx.table("endpoints");
        return `alter table ${t} add column if not exists secret_id uuid;
update ${t} e set secret_id = ${vaultSecret("e.secret", "e.id")}, secret = null
where e.secret is not null and e.secret_id is null;`;
      },
    },
    {
      from: 2,
      description:
        "rotate_incoming_webhook_secret replaces the signing secret and keeps the old one verifying for a grace period; incoming_webhook_by_token returns it as previous_secret, and update_incoming_webhook is new.",
      sql: () => "",
    },
  ],
  contract: () => [
    {
      name: "create_incoming_webhook",
      args: ["{id}", "text", "text", "jsonb", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "rotate_incoming_webhook_secret",
      args: ["uuid", "interval"],
      returns: "jsonb",
    },
    {
      name: "update_incoming_webhook",
      args: ["uuid", "text", "jsonb", "text", "text"],
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
