import type { IncomingWebhooksEvents } from "../../blocks/webhooks/events.ts";
import type { BlockSqlContext, BlockSqlEvents } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  schemaPreamble,
  SERVICE_CALLER,
  sha256Hex,
  updatedAt,
  fail,
  revokeTable,
  raise,
} from "../shared.ts";
import {
  qualifiedTable,
  subjectCascades,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { moduleOperations, modulePermissionKey } from "./permissions-model.ts";

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

function secretStorage(ctx: BlockSqlContext): boolean {
  const storage = ctx.text("secretStorage", "vault");

  if (storage !== "vault" && storage !== "column") {
    throw new TypeError(
      `blocks.webhooks-in.options.secretStorage must be "vault" or "column", not "${storage}"`,
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

const ENDPOINT_COLUMNS = {
  id: "id",
  tenant: "tenant",
  name: "name",
  tokenHash: "token_hash",
  verify: "verify",
  secret: "secret",
  secretId: "secret_id",
  previousSecret: "previous_secret",
  previousSecretId: "previous_secret_id",
  previousSecretExpiresAt: "previous_secret_expires_at",
  signatureHeader: "signature_header",
  enabled: "enabled",
  maxBodyBytes: "max_body_bytes",
  receiveCount: "receive_count",
  lastReceivedAt: "last_received_at",
  lastStatus: "last_status",
  metadata: "metadata",
  subjectType: "subject_type",
  subjectId: "subject_id",
  createdBy: "created_by",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

type EndpointColumn = keyof typeof ENDPOINT_COLUMNS;

/** The previous-secret columns a grace rotation needs, by secret storage. */
const graceColumns = (vault: boolean): readonly EndpointColumn[] => [
  vault ? "previousSecretId" : "previousSecret",
  "previousSecretExpiresAt",
];

function webhooksInSql(ctx: BlockSqlContext): string {
  const renamed = Object.keys(ctx.config.columns["endpoints"] ?? {});

  if (ctx.owns("endpoints") && renamed.length > 0) {
    throw new TypeError(
      `blocks.webhooks-in.columns.endpoints: the block creates this table, so ${renamed.join(", ")} can't be renamed; declare your own table in your schema, or map blocks.webhooks-in.tables.endpoints`,
    );
  }

  const id = ctx.idType;
  const t = ctx.table("endpoints");
  const c = (logical: EndpointColumn) => ctx.col("endpoints", logical);
  const has = (logical: EndpointColumn) => ctx.has("endpoints", logical);
  const e = (logical: EndpointColumn) => `e.${c(logical)}`;
  /** A column for an `assign` value, which `assign` drops when it's missing. */
  const cv = (logical: EndpointColumn) => (has(logical) ? c(logical) : "null");
  const ev = (logical: EndpointColumn) => `e.${cv(logical)}`;

  /** `alias.column` when the column exists, else `fallback`. */
  const read = (alias: string, logical: EndpointColumn, fallback = "null") =>
    has(logical) ? `${alias}.${c(logical)}` : fallback;

  /** `column = value` assignments for the columns that exist. */
  const assign = (
    pairs: readonly (readonly [EndpointColumn, string])[],
  ): string[] =>
    pairs
      .filter(([logical]) => has(logical))
      .map(([logical, value]) => `${c(logical)} = ${value}`);

  const p = moduleOperations("webhooks-in");

  const key = (action: "create" | "update" | "delete") =>
    sqlString(modulePermissionKey(ctx, action, p[action]));

  const view = ctx.permission("view", p.view);
  const verify = INCOMING_VERIFY.map((mode) => `'${mode}'`).join(", ");
  const maxBody = ctx.number("maxBodyBytes", 1_048_576);
  const vault = secretStorage(ctx);
  // The column the secret is kept in must exist; the other one is optional.
  c(vault ? "secretId" : "secret");
  const grace = graceColumns(vault).every(has);

  const stored = (secret: string, endpoint: string) =>
    vault ? vaultSecret(secret, endpoint) : "null";

  const plain = (secret: string) => (vault ? "null" : secret);

  const vaultIds = (row: string) =>
    [
      `${row}.${c("secretId")}`,
      ...(has("previousSecretId") ? [`${row}.${c("previousSecretId")}`] : []),
    ].join(", ");

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
  delete from vault.secrets vs where vs.id in (${vaultIds("old")});
  return null;
end;
$$;
revoke execute on function ${ctx.fn("drop_incoming_webhook_secret")}() from public, anon, authenticated;
drop trigger if exists ${cleanupTrigger} on ${t};
create trigger ${cleanupTrigger} after delete on ${t}
  for each row when (${vaultIds("old")
    .split(", ")
    .map((column) => `${column} is not null`)
    .join(
      " or ",
    )}) execute function ${ctx.fn("drop_incoming_webhook_secret")}();`
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

  // An endpoint names a subject only when the app asks for it, so the
  // registry applies to the types on lists.
  const subjects = subjectsOption(ctx, [], { fallback: false });
  const subjectColumns = has("subjectType") && has("subjectId");

  if (subjects.length > 0 && !subjectColumns) {
    throw new TypeError(
      "blocks.webhooks-in.on needs the subjectType and subjectId columns of the endpoints table",
    );
  }

  const readable = subjectReadable(ctx, subjects, {
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

  const cascades = subjectColumns
    ? subjectCascades(
        ctx,
        subjects,
        `delete from ${t} e where ${e("subjectType")} = v_type and ${e("subjectId")} = v_id;`,
      )
    : "";

  const table = ctx.owns("endpoints")
    ? `
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
  subject_type text check (subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'),
  subject_id text check (length(subject_id) between 1 and 200),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table ${t} add column if not exists subject_type text check (subject_type ~ '^[a-z][a-z0-9_-]{0,62}$');
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
${updatedAt(t, "updated_at")}`
    : `
-- Trigger URLs over the app's table ${t} (the app's table): the app owns its
-- columns, indexes, grants and policies. Only the token's hash is kept.`;

  const policies = ctx.owns("endpoints")
    ? `
alter table ${t} enable row level security;
${revokeTable(t)}
-- The secret stays with the service: members read every other column.
grant select (id, tenant, name, verify, signature_header, enabled, max_body_bytes, receive_count, last_received_at, last_status, metadata, subject_type, subject_id, created_by, created_at, updated_at) on ${t} to authenticated;
grant all on ${t} to service_role;
`
    : "\n";

  const readPolicy = ctx.owns("endpoints")
    ? `
${renderPolicy(
  makePolicy({
    table: t,
    name: "bsb_incoming_webhooks_read",
    command: "select",
    roles: ["authenticated"],
    using: `tenant in (select ${ctx.fn("incoming_webhook_tenant_ids")}())
    and ${ctx.fn("incoming_webhook_subject_readable")}(subject_type, subject_id, tenant)`,
  }),
  { drop: true, target: t },
)}
`
    : "\n";

  const listed: readonly (readonly [string, string])[] = [
    ["id", e("id")],
    ["tenant", e("tenant")],
    ["name", e("name")],
    ["verify", e("verify")],
    ["signature_header", read("e", "signatureHeader")],
    ["enabled", e("enabled")],
    ["max_body_bytes", read("e", "maxBodyBytes", String(maxBody))],
    ["receive_count", read("e", "receiveCount", "0")],
    ["last_received_at", read("e", "lastReceivedAt")],
    ["last_status", read("e", "lastStatus")],
    ["metadata", read("e", "metadata", "'{}'::jsonb")],
    ["subject_type", read("e", "subjectType")],
    ["subject_id", read("e", "subjectId")],
    ["created_by", read("e", "createdBy")],
    ["created_at", read("e", "createdAt")],
  ];

  const subjectFilter = subjectColumns
    ? `
    and (list_incoming_webhooks.subject_type is null or ${e("subjectType")} = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or ${e("subjectId")} = list_incoming_webhooks.subject_id)`
    : `
    and list_incoming_webhooks.subject_type is null and list_incoming_webhooks.subject_id is null`;

  const insertColumns = (
    [
      ["id", "v_id"],
      ["tenant", "tenant"],
      ["name", "name"],
      ["tokenHash", sha256Hex("token")],
      ["verify", "verify"],
      ["secret", plain("secret")],
      ["secretId", stored("secret", "v_id")],
      ["signatureHeader", headerFor("verify", "signature_header", "null")],
      ["metadata", "coalesce(metadata, '{}')"],
      ["subjectType", "subject_type"],
      ["subjectId", "subject_id"],
      ["createdBy", "auth.uid()"],
    ] as const satisfies readonly (readonly [EndpointColumn, string])[]
  ).filter(([logical]) => has(logical));

  const noSubjects = subjectColumns
    ? ""
    : `
  if subject_type is not null or subject_id is not null then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "This endpoints table has no subject columns", "22023")}
  end if;`;

  const noMetadata = has("metadata")
    ? ""
    : `
  if metadata is not null and metadata <> '{}'::jsonb then
    ${fail("WEBHOOK_IN_METADATA_INVALID", "This endpoints table has no metadata column", "22023")}
  end if;`;

  const clearGrace = (when: string, keep: string) =>
    assign([
      [
        "previousSecret",
        `case when ${when} then null else ${keep}.${cv("previousSecret")} end`,
      ],
      [
        "previousSecretId",
        `case when ${when} then null else ${keep}.${cv("previousSecretId")} end`,
      ],
      [
        "previousSecretExpiresAt",
        `case when ${when} then null else ${keep}.${cv("previousSecretExpiresAt")} end`,
      ],
    ]);

  const rotateSet = [
    `${c("tokenHash")} = ${sha256Hex("token")}`,
    ...assign([
      [
        "secret",
        `case when rotate_secret then ${plain("v_secret")} else ${ev("secret")} end`,
      ],
      [
        "secretId",
        `case when rotate_secret then ${stored("v_secret", ev("id"))} else ${ev("secretId")} end`,
      ],
    ]),
    ...clearGrace("rotate_secret", "e"),
  ];

  const keepColumn = (logical: EndpointColumn, when: string, from: string) =>
    has(logical) ? `case when ${when} then ${from} end` : "";

  const secretSet = [
    ...assign([
      ["secret", plain("v_secret")],
      ["secretId", stored("v_secret", ev("id"))],
    ]),
    ...(grace
      ? assign([
          [
            "previousSecret",
            keepColumn("secret", "v_keep", ev("secret")) || "null",
          ],
          [
            "previousSecretId",
            keepColumn("secretId", "v_keep", ev("secretId")) || "null",
          ],
          [
            "previousSecretExpiresAt",
            "case when v_keep then now() + grace end",
          ],
        ])
      : []),
  ];

  const same = `v_verify = previous.${c("verify")}`;

  const updateSet = [
    `${c("name")} = coalesce(update_incoming_webhook.name, ${ev("name")})`,
    ...assign([
      [
        "metadata",
        `coalesce(update_incoming_webhook.metadata, ${ev("metadata")})`,
      ],
    ]),
    `${c("verify")} = v_verify`,
    ...assign([
      [
        "secret",
        `case when ${same} then ${ev("secret")} else ${plain("v_secret")} end`,
      ],
      [
        "secretId",
        `case when ${same} then ${ev("secretId")} else ${stored("v_secret", ev("id"))} end`,
      ],
      ["previousSecret", `case when ${same} then ${ev("previousSecret")} end`],
      [
        "previousSecretId",
        `case when ${same} then ${ev("previousSecretId")} end`,
      ],
      [
        "previousSecretExpiresAt",
        `case when ${same} then ${ev("previousSecretExpiresAt")} end`,
      ],
      [
        "signatureHeader",
        headerFor(
          "v_verify",
          "update_incoming_webhook.signature_header",
          `case when ${same} then ${ev("signatureHeader")} end`,
        ),
      ],
    ]),
  ];

  const current = (alias: string) =>
    vault
      ? has("secret")
        ? `coalesce(ds.decrypted_secret, ${alias}.${c("secret")})`
        : "ds.decrypted_secret"
      : `${alias}.${c("secret")}`;

  const previousSecret = grace
    ? `case when ${e("previousSecretExpiresAt")} > now() then ${
        vault
          ? has("previousSecret")
            ? `coalesce(dp.decrypted_secret, ${e("previousSecret")})`
            : "dp.decrypted_secret"
          : e("previousSecret")
      } end`
    : "null::text";

  const vaultJoins = vault
    ? `\n  left join vault.decrypted_secrets ds on ds.id = ${e("secretId")}${
        grace && has("previousSecretId")
          ? `\n  left join vault.decrypted_secrets dp on dp.id = ${e("previousSecretId")}`
          : ""
      }`
    : "";

  const counters = assign([
    ["receiveCount", `${ev("receiveCount")} + 1`],
    ["lastReceivedAt", "now()"],
    ["lastStatus", "record_incoming_webhook.status"],
  ]);

  const record =
    counters.length > 0
      ? `language sql
security definer
set search_path = ''
as $$
  update ${t} e
  set ${counters.join(", ")}
  where ${e("id")} = endpoint
$$;`
      : `language sql
security definer
set search_path = ''
as $$
  select
$$;`;

  return `${schemaPreamble(ctx)}${table}${cleanup}${policies}
create or replace function ${ctx.fn("incoming_webhook_tenant_ids")}()
returns setof ${id}
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select ${ctx.scope.ids(view)};
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
${readPolicy}
-- A tenant's endpoints, or one subject's, without secrets; runs as the caller.
create or replace function ${ctx.fn("list_incoming_webhooks")}(tenant ${id}, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    ${listed.map(([name, value]) => `'${name}', ${value}`).join(",\n    ")}
  ) order by ${read("e", "createdAt", e("id"))}), '[]'::jsonb)
  from ${t} e
  where ${e("tenant")} = list_incoming_webhooks.tenant${subjectFilter}
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
  if verify not in (${verify}) then
    ${fail("WEBHOOK_IN_VERIFY_UNKNOWN", "Unknown verification mode", "22023")}
  end if;${noSubjects}${noMetadata}
  if (subject_type is null) <> (subject_id is null) then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "Pass subject_type and subject_id together", "22023")}
  end if;
  if subject_type is not null and not (${subjectExists}) then
    ${fail("WEBHOOK_IN_SUBJECT_INVALID", "No such subject in this tenant", "22023")}
  end if;
  insert into ${t} (${insertColumns.map(([logical]) => c(logical)).join(", ")})
  values (${insertColumns.map(([, value]) => value).join(",\n    ")})
  returning * into created;
  ${hookEvent("incoming_webhook.created", `created.${c("id")}`, `created.${c("tenant")}`, "integration", `, 'name', created.${c("name")}`)}
  return jsonb_build_object('id', created.${c("id")}, 'tenant', created.${c("tenant")}, 'name', created.${c("name")},
    'verify', created.${c("verify")}, 'token', token, 'secret', secret, 'signatureHeader', ${read("created", "signatureHeader")},
    'subjectType', ${read("created", "subjectType")}, 'subjectId', ${read("created", "subjectId")});
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
  select * into previous from ${t} e where ${e("id")} = endpoint for update;
  if previous.${c("id")} is null or not ${can(`previous.${c("tenant")}`, "update")} then
    ${raise("No incoming webhook %", "P0002", "WEBHOOK_IN_NOT_FOUND", "endpoint")}
  end if;
  if rotate_secret then
    v_secret := ${newSecret(`previous.${c("verify")}`)};
  end if;
  update ${t} e set ${rotateSet.join(",\n    ")}
  where ${e("id")} = endpoint
  returning * into updated;${
    vault
      ? `
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (${vaultIds("previous")});
  end if;`
      : ""
  }
  ${hookEvent("incoming_webhook.token_rotated", `updated.${c("id")}`, `updated.${c("tenant")}`, "security", ", 'secretRotated', rotate_secret")}
  return jsonb_build_object('id', updated.${c("id")}, 'token', token, 'secret', v_secret);
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
  select * into previous from ${t} e where ${e("id")} = endpoint for update;
  if previous.${c("id")} is null or not ${can(`previous.${c("tenant")}`, "update")} then
    ${raise("No incoming webhook %", "P0002", "WEBHOOK_IN_NOT_FOUND", "endpoint")}
  end if;
  v_secret := ${newSecret(`previous.${c("verify")}`)};
  if v_secret is null then
    ${fail("WEBHOOK_IN_NO_SECRET", "This endpoint verifies no secret", "22023")}
  end if;${
    grace
      ? ""
      : `
  if v_keep then
    ${fail("WEBHOOK_IN_NO_GRACE", "This endpoints table has no previous-secret columns, so a rotation can't keep the old secret", "22023")}
  end if;`
  }
  update ${t} e set
    ${secretSet.join(",\n    ")}
  where ${e("id")} = endpoint
  returning * into updated;${
    vault
      ? grace && has("previousSecretId")
        ? `
  delete from vault.secrets vs
  where vs.id = previous.${c("previousSecretId")} or (not v_keep and vs.id = previous.${c("secretId")});`
        : `
  delete from vault.secrets vs where vs.id = previous.${c("secretId")};`
      : ""
  }
  ${hookEvent("incoming_webhook.secret_rotated", `updated.${c("id")}`, `updated.${c("tenant")}`, "security")}
  return jsonb_build_object('id', updated.${c("id")}, 'secret', v_secret, 'previousSecretExpiresAt', ${read("updated", "previousSecretExpiresAt")});
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
  select * into previous from ${t} e where ${e("id")} = endpoint for update;
  if previous.${c("id")} is null or not ${can(`previous.${c("tenant")}`, "update")} then
    ${raise("No incoming webhook %", "P0002", "WEBHOOK_IN_NOT_FOUND", "endpoint")}
  end if;
  if name is not null and btrim(name) = '' then
    ${fail("WEBHOOK_IN_NAME_REQUIRED", "An endpoint needs a name", "22023")}
  end if;
  if metadata is not null and ${has("metadata") ? "jsonb_typeof(metadata) <> 'object'" : "true"} then
    ${fail("WEBHOOK_IN_METADATA_INVALID", "metadata must be a JSON object", "22023")}
  end if;
  v_verify := coalesce(verify, previous.${c("verify")});
  if v_verify not in (${verify}) then
    ${fail("WEBHOOK_IN_VERIFY_UNKNOWN", "Unknown verification mode", "22023")}
  end if;
  if v_verify <> previous.${c("verify")} then
    v_secret := ${newSecret("v_verify")};
  end if;
  update ${t} e set
    ${updateSet.join(",\n    ")}
  where ${e("id")} = endpoint
  returning * into updated;${
    vault
      ? `
  if v_verify <> previous.${c("verify")} then
    delete from vault.secrets vs where vs.id in (${vaultIds("previous")});
  end if;`
      : ""
  }
  ${hookEvent("incoming_webhook.updated", `updated.${c("id")}`, `updated.${c("tenant")}`, "integration", `, 'name', updated.${c("name")}, 'verify', updated.${c("verify")}`)}
  return jsonb_build_object('id', updated.${c("id")}, 'tenant', updated.${c("tenant")}, 'name', updated.${c("name")},
    'verify', updated.${c("verify")}, 'secret', v_secret, 'signatureHeader', ${read("updated", "signatureHeader")},
    'metadata', ${read("updated", "metadata", "'{}'::jsonb")});
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
  select ${e("tenant")} into tenant from ${t} e where ${e("id")} = endpoint;
  if tenant is null or not ${can("tenant", "update")} then
    return false;
  end if;
  update ${t} e set ${c("enabled")} = set_incoming_webhook_enabled.enabled where ${e("id")} = endpoint;
  ${hookEvent("incoming_webhook.enabled_changed", "endpoint", "tenant", "integration", ", 'enabled', set_incoming_webhook_enabled.enabled")}
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
  select ${e("tenant")} into tenant from ${t} e where ${e("id")} = endpoint;
  if tenant is null or not ${can("tenant", "delete")} then
    return false;
  end if;
  delete from ${t} e where ${e("id")} = endpoint;
  ${hookEvent("incoming_webhook.deleted", "endpoint", "tenant", "integration")}
  return true;
end;
$$;

-- The endpoint behind a token, with its secret and metadata, for the
-- receiving route.
drop function if exists ${ctx.fn("incoming_webhook_by_token")}(text);
create or replace function ${ctx.fn("incoming_webhook_by_token")}(token text)
returns table (id uuid, tenant text, enabled boolean, verify text, secret text, signature_header text, max_body_bytes integer, previous_secret text, metadata jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select ${e("id")}, ${e("tenant")}::text, ${e("enabled")}, ${e("verify")}, ${current("e")}, ${read("e", "signatureHeader")}, ${read("e", "maxBodyBytes", String(maxBody))},
    ${previousSecret}, ${read("e", "metadata", "'{}'::jsonb")}
  from ${t} e${vaultJoins}
  where ${e("tokenHash")} = ${sha256Hex("incoming_webhook_by_token.token")}
$$;

-- Counts a delivery and keeps its HTTP status.
create or replace function ${ctx.fn("record_incoming_webhook")}(endpoint uuid, status integer)
returns void
${record}

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

const EVENTS: BlockSqlEvents<IncomingWebhooksEvents> = {
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
  "incoming_webhook.enabled_changed": {
    subject: "organizations",
    payload: ["organizationId", "endpointId", "enabled"],
  },
  "incoming_webhook.deleted": {
    subject: "organizations",
    payload: ["organizationId", "endpointId"],
  },
};

export const WEBHOOKS_IN: BlockSqlDefinition = {
  internal: [
    "incoming_webhook_tenant_ids",
    "incoming_webhook_subject_readable",
  ],
  name: "webhooks-in",
  scopes: ["tenant"],
  title: "Incoming webhook endpoints",
  description:
    "Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.",
  requires: ["permissions", "updated-at", "webhook-inbox"],
  target: "schema",
  modes: ["managed"],
  names: {
    events: EVENTS,
    tables: {
      endpoints: {
        name: "incoming_webhooks",
        app: {
          unused: (ctx) =>
            secretStorage(ctx)
              ? ["secret", "previousSecret"]
              : ["secretId", "previousSecretId"],
        },
        columns: ENDPOINT_COLUMNS,
        optional: [
          "secret",
          "secretId",
          "previousSecret",
          "previousSecretId",
          "previousSecretExpiresAt",
          "signatureHeader",
          "maxBodyBytes",
          "receiveCount",
          "lastReceivedAt",
          "lastStatus",
          "metadata",
          "subjectType",
          "subjectId",
          "createdBy",
          "createdAt",
          "updatedAt",
        ],
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
    options: ["maxBodyBytes", "secretStorage"],
  },
  version: 4,
  upgrades: [
    {
      from: 1,
      description:
        'Signing secrets move to Vault (secret_id) unless options.secretStorage is "column"; existing plaintext secrets are copied to Vault and cleared.',
      sql: (ctx) => {
        if (!secretStorage(ctx)) {
          return "";
        }

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
    {
      from: 3,
      description:
        "Adopt mode over an app's endpoints table; incoming_webhook_by_token returns the endpoint's metadata for destinations.",
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
