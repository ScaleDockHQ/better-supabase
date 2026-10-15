import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  sha256Hex,
  tenantIn,
  userGrant,
} from "../shared.ts";
import { subjectReadable, subjectsOption } from "../subjects.ts";
import { OPERATIONS } from "./access-model.ts";

const SUBJECT_PAYLOAD = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: ModuleEvents = {
  "signature.requested": {
    subject: "signature-requests",
    payload: [...SUBJECT_PAYLOAD, "id", "versionId"],
  },
  "signature.signed": {
    subject: "signature-requests",
    payload: [...SUBJECT_PAYLOAD, "id", "signatureId", "signer", "method"],
  },
  "signature.completed": {
    subject: "signature-requests",
    payload: [...SUBJECT_PAYLOAD, "id", "versionId"],
  },
  "signature.declined": {
    subject: "signature-requests",
    payload: [...SUBJECT_PAYLOAD, "id", "signer"],
  },
  "signature.cancelled": {
    subject: "signature-requests",
    payload: [...SUBJECT_PAYLOAD, "id"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_signature_request",
    "after_signature_request",
    "before_signature_sign",
    "after_signature_sign",
  ],
  options: ["subjects"],
  tables: {
    requests: {
      name: "signature_requests",
      lifecycle: { tenant: "tenant", user: "requestedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        version: "version_id",
        contentHash: "content_hash",
        signers: "signers",
        order: "sign_order",
        status: "status",
        approval: "approval_request_id",
        message: "message",
        requestedBy: "requested_by",
        createdAt: "created_at",
        completedAt: "completed_at",
      },
    },
    signatures: {
      name: "signatures",
      lifecycle: { tenant: "tenant", user: "signer", export: true },
      columns: {
        id: "id",
        request: "request_id",
        tenant: "tenant_id",
        signer: "signer",
        method: "method",
        typedName: "typed_name",
        image: "image_attachment_id",
        signedHash: "signed_hash",
        ip: "ip",
        userAgent: "user_agent",
        signedAt: "signed_at",
      },
    },
  },
};

/** How many people one request can ask to sign. */
const MAX_SIGNERS = 20;

/** The hash `versions` stores for a version's content. */
const versionHash = (content: string, storagePath: string): string =>
  sha256Hex(`coalesce(${content}::text, '') || coalesce(${storagePath}, '')`);

/**
 * The hash a signature stores: the request, the signed version's content
 * hash, the signer, how they signed and when, so `verify` can recompute it.
 */
const signedHash = (parts: {
  readonly request: string;
  readonly contentHash: string;
  readonly signer: string;
  readonly method: string;
  readonly typedName: string;
  readonly image: string;
  readonly signedAt: string;
}): string =>
  sha256Hex(
    `${parts.request}::text || ':' || ${parts.contentHash} || ':' || ${parts.signer}::text || ':' || ${parts.method} || ':' || coalesce(${parts.typedName}, '') || ':' || coalesce(${parts.image}::text, '') || ':' || to_char(${parts.signedAt} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`,
  );

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const versionsModule = ctx.of("versions");
  if (versionsModule.mode === "custom") {
    throw new TypeError(
      "blocks.signatures needs the versions table; versions can't be in custom mode",
    );
  }
  const requests = ctx.table("requests");
  const signatures = ctx.table("signatures");
  const r = (column: string): string => ctx.col("requests", column);
  const s = (column: string): string => ctx.col("signatures", column);
  const vt = versionsModule.table("versions");
  const v = (column: string): string => versionsModule.col("versions", column);
  const fn = (name: string): string => ctx.fn(name);
  const read = ctx.permission("read", OPERATIONS["signatures.read"]);
  const request = ctx.permission("request", OPERATIONS["signatures.request"]);
  const manage = ctx.permission("manage", OPERATIONS["signatures.manage"]);
  const subjects = subjectsOption(ctx);
  const members = ctx.of("tenant");
  const approvals =
    ctx.installed("approvals") && ctx.of("approvals").mode !== "custom"
      ? ctx.of("approvals")
      : undefined;
  const attachments =
    ctx.installed("attachments") && ctx.of("attachments").mode !== "custom"
      ? ctx.of("attachments")
      : undefined;
  const notFound = fail(
    "SIGNATURE_REQUEST_NOT_FOUND",
    "signature request not found",
    "P0002",
  );
  const forbidden = (message: string): string =>
    fail("SIGNATURE_FORBIDDEN", message);
  const requestJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'versionId', ${row}.${r("version")}, 'contentHash', ${row}.${r("contentHash")}, 'signers', to_jsonb(${row}.${r("signers")}), 'order', ${row}.${r("order")}, 'status', ${row}.${r("status")}, 'approvalRequestId', ${row}.${r("approval")}, 'message', ${row}.${r("message")}, 'requestedBy', ${row}.${r("requestedBy")}, 'createdAt', ${row}.${r("createdAt")}, 'completedAt', ${row}.${r("completedAt")})`;
  const signatureJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'requestId', ${row}.${s("request")}, 'signer', ${row}.${s("signer")}, 'method', ${row}.${s("method")}, 'typedName', ${row}.${s("typedName")}, 'imageAttachmentId', ${row}.${s("image")}, 'signedHash', ${row}.${s("signedHash")}, 'ip', ${row}.${s("ip")}, 'userAgent', ${row}.${s("userAgent")}, 'signedAt', ${row}.${s("signedAt")})`;
  const requestRecord = (
    type: string,
    row: string,
    extra: string,
    audit: string | false,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}, 'subjectType', ${row}.${r("subjectType")}, 'subjectId', ${row}.${r("subjectId")}, 'id', ${row}.${r("id")}${extra})`,
      subject: `'signature-requests/' || ${row}.${r("id")}::text`,
      tenant: `${row}.${r("tenant")}`,
      audit:
        audit === false
          ? false
          : {
              category: "data",
              targetType: "signature_request",
              recordId: `${row}.${r("id")}::text`,
              summary: audit,
            },
    });
  const readableRequest = (row: string): string =>
    `(${ctx.can("tenant", `${row}.${r("tenant")}`, read)} and ${subjectReadable(
      subjects,
      {
        type: `${row}.${r("subjectType")}`,
        id: `${row}.${r("subjectId")}`,
        tenant: `${row}.${r("tenant")}`,
      },
    )})`;
  const imageCheck =
    attachments === undefined
      ? `if sign_signature.method = 'drawn' then
    ${fail("SIGNATURE_METHOD_INVALID", "a drawn signature needs the attachments module for its image", "22023")}
  end if;`
      : `if sign_signature.image_attachment_id is not null and not exists (
    select 1 from ${attachments.table("attachments")} a
    where a.${attachments.col("attachments", "id")} = sign_signature.image_attachment_id
      and a.${attachments.col("attachments", "tenant")} = v_req.${r("tenant")}
  ) then
    ${fail("SIGNATURE_IMAGE_NOT_FOUND", "the signature image isn't an attachment in this organization", "22023")}
  end if;`;
  const approvalCheck =
    approvals === undefined
      ? `if create_signature_request.approval_request_id is not null then
    ${fail("SIGNATURE_APPROVAL_UNSUPPORTED", "linking an approval request needs the approvals module", "22023")}
  end if;`
      : `if create_signature_request.approval_request_id is not null and not exists (
    select 1 from ${approvals.table("requests")} a
    where a.${approvals.col("requests", "id")} = create_signature_request.approval_request_id
      and a.${approvals.col("requests", "tenant")} = create_signature_request.tenant
      and a.${approvals.col("requests", "subjectType")} = create_signature_request.subject_type
      and a.${approvals.col("requests", "subjectId")} = create_signature_request.subject_id
  ) then
    ${fail("SIGNATURE_APPROVAL_NOT_FOUND", "the approval request isn't for this record", "22023")}
  end if;`;
  const approvalStep =
    approvals === undefined
      ? ""
      : `
  -- A signer who approves the linked request's current step decides it.
  if v_req.${r("approval")} is not null and ${approvals.fn("approval_eligible")}(v_req.${r("approval")}) then
    perform ${approvals.fn("decide_approval")}(v_req.${r("approval")}, 'approved', 'Signed electronically');
  end if;`;
  const tables = ctx.manages
    ? `create table if not exists ${requests} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("subjectType")} text not null,
  ${r("subjectId")} text not null,
  ${r("version")} uuid not null${versionsModule.manages ? ` references ${vt} (${v("id")}) on delete restrict` : ""},
  ${r("contentHash")} text not null,
  ${r("signers")} uuid[] not null check (cardinality(${r("signers")}) between 1 and ${String(MAX_SIGNERS)} and array_position(${r("signers")}, null) is null),
  ${r("order")} text not null default 'parallel' check (${r("order")} in ('parallel', 'sequential')),
  ${r("status")} text not null default 'pending' check (${r("status")} in ('pending', 'completed', 'declined', 'cancelled')),
  ${r("approval")} uuid,
  ${r("message")} text check (${r("message")} is null or length(${r("message")}) <= 2000),
  ${r("requestedBy")} uuid,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("completedAt")} timestamptz
);
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_subject_idx`)} on ${requests} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")});
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_version_idx`)} on ${requests} (${r("version")});
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_signers_idx`)} on ${requests} using gin (${r("signers")});
${lockTable(requests, { read: true })}
drop policy if exists "signature_requests_read" on ${requests};
create policy "signature_requests_read" on ${requests} for select to authenticated
  using (${tenantIn(r("tenant"), read)} or (select auth.uid()) = any (${r("signers")}));

create table if not exists ${signatures} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("request")} uuid not null references ${requests} (${r("id")}) on delete cascade,
  ${s("tenant")} ${ctx.idType} not null,
  ${s("signer")} uuid not null,
  ${s("method")} text not null check (${s("method")} in ('drawn', 'typed', 'click')),
  ${s("typedName")} text check (${s("typedName")} is null or length(${s("typedName")}) between 1 and 200),
  ${s("image")} uuid,
  ${s("signedHash")} text not null,
  ${s("ip")} text check (${s("ip")} is null or length(${s("ip")}) <= 64),
  ${s("userAgent")} text check (${s("userAgent")} is null or length(${s("userAgent")}) <= 512),
  ${s("signedAt")} timestamptz not null,
  check (${s("method")} <> 'typed' or ${s("typedName")} is not null),
  check (${s("method")} <> 'drawn' or ${s("image")} is not null),
  unique (${s("request")}, ${s("signer")})
);
${lockTable(signatures, { read: true })}
drop policy if exists "signatures_read" on ${signatures};
create policy "signatures_read" on ${signatures} for select to authenticated
  using (${tenantIn(s("tenant"), read)} or ${s("signer")} = (select auth.uid()));
`
    : "";
  const hash = (row: string): string =>
    signedHash({
      request: `${row}.${s("request")}`,
      contentHash: "v_req_hash",
      signer: `${row}.${s("signer")}`,
      method: `${row}.${s("method")}`,
      typedName: `${row}.${s("typedName")}`,
      image: `${row}.${s("image")}`,
      signedAt: `${row}.${s("signedAt")}`,
    });
  return `${schemaPreamble(ctx)}
${tables}
-- Asks members to sign one version of a record. The version is frozen, so
-- retention and delete_version keep it; without one, the record's columns
-- are snapshotted first.
create or replace function ${fn("create_signature_request")}(tenant ${ctx.idType}, subject_type text, subject_id text, signers uuid[], version_id uuid default null, sign_order text default 'parallel', approval_request_id uuid default null, message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row ${requests}%rowtype;
begin
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "create_signature_request.tenant", request)} and ${subjectReadable(
    subjects,
    {
      type: "create_signature_request.subject_type",
      id: "create_signature_request.subject_id",
      tenant: "create_signature_request.tenant",
    },
  )})) then
    ${forbidden("not allowed to request signatures on this record")}
  end if;
  if create_signature_request.sign_order not in ('parallel', 'sequential') then
    ${fail("SIGNATURE_ORDER_INVALID", "sign_order must be parallel or sequential", "22023")}
  end if;
  if coalesce(cardinality(create_signature_request.signers), 0) not between 1 and ${String(MAX_SIGNERS)}
    or array_position(create_signature_request.signers, null) is not null
    or (select count(distinct x) from unnest(create_signature_request.signers) x) <> cardinality(create_signature_request.signers) then
    ${fail("SIGNATURE_SIGNERS_INVALID", `name between 1 and ${String(MAX_SIGNERS)} different signers`, "22023")}
  end if;
  if exists (
    select 1 from unnest(create_signature_request.signers) x
    where not exists (
      select 1 from ${members.table("memberships")} m
      where m.${members.col("memberships", "tenant")} = create_signature_request.tenant and m.${members.col("memberships", "user")} = x
    )
  ) then
    ${fail("SIGNATURE_SIGNERS_INVALID", "every signer must be a member of the organization", "22023")}
  end if;
  ${approvalCheck}
  if v_version is null then
    v_version := (${versionsModule.fn("snapshot_version")}(create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id) ->> 'id')::uuid;
  end if;
  select x.${v("contentHash")} into v_hash
    from ${vt} x
    where x.${v("id")} = v_version
      and x.${v("tenant")} = create_signature_request.tenant
      and x.${v("subjectType")} = create_signature_request.subject_type
      and x.${v("subjectId")} = create_signature_request.subject_id;
  if v_hash is null then
    ${fail("SIGNATURE_VERSION_NOT_FOUND", "the version isn't a version of this record", "22023")}
  end if;
  ${ctx.hook("before_signature_request", [
    [ctx.idType, "create_signature_request.tenant"],
    ["text", "create_signature_request.subject_type"],
    ["text", "create_signature_request.subject_id"],
    ["uuid", "v_version"],
  ])}
  update ${vt} x set ${v("frozen")} = true where x.${v("id")} = v_version and not x.${v("frozen")};
  insert into ${requests} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("version")}, ${r("contentHash")}, ${r("signers")}, ${r("order")}, ${r("approval")}, ${r("message")}, ${r("requestedBy")})
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), auth.uid())
  returning * into v_row;
  ${requestRecord("signature.requested", "v_row", `, 'versionId', v_row.${r("version")}`, `'requested signatures on ' || v_row.${r("subjectType")} || ' ' || v_row.${r("subjectId")}`)}
  ${ctx.hook("after_signature_request", [["uuid", `v_row.${r("id")}`]])}
  return ${requestJson("v_row")};
end;
$$;
${userGrant(`${fn("create_signature_request")}(${ctx.idType}, text, text, uuid[], uuid, text, uuid, text)`)}

-- Recomputes the signed version's hash from its content and each signature's
-- hash, and reports whether the record has a newer version since.
create or replace function ${fn("signature_verification")}(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_req_hash text;
  v_current text;
  v_latest uuid;
  v_latest_hash text;
  v_items jsonb;
  v_signed boolean;
begin
  select * into v_req from ${requests} x where x.${r("id")} = signature_verification.request_id;
  if not found then
    return null;
  end if;
  v_req_hash := v_req.${r("contentHash")};
  select ${versionHash(`x.${v("content")}`, `x.${v("storagePath")}`)} into v_current
    from ${vt} x where x.${v("id")} = v_req.${r("version")};
  select x.${v("id")}, x.${v("contentHash")} into v_latest, v_latest_hash
    from ${vt} x
    where x.${v("subjectType")} = v_req.${r("subjectType")} and x.${v("subjectId")} = v_req.${r("subjectId")}
    order by x.${v("number")} desc
    limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id', g.${s("id")}, 'signer', g.${s("signer")}, 'valid', g.${s("signedHash")} = ${hash("g")}) order by g.${s("signedAt")}), '[]'::jsonb)
    into v_items
    from ${signatures} g where g.${s("request")} = v_req.${r("id")};
  select coalesce(bool_and((i ->> 'valid')::boolean), true) into v_signed from jsonb_array_elements(v_items) i;
  return jsonb_build_object(
    'valid', v_current is not distinct from v_req_hash and v_signed,
    'contentMatches', v_current is not distinct from v_req_hash,
    'changedSince', v_latest_hash is distinct from v_req_hash,
    'latestVersionId', v_latest,
    'signatures', v_items
  );
end;
$$;
revoke execute on function ${fn("signature_verification")}(uuid) from public, anon, authenticated;

create or replace function ${fn("sign_signature")}(request_id uuid, method text, typed_name text default null, image_attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req ${requests}%rowtype;
  v_row ${signatures}%rowtype;
  v_typed text := nullif(trim(sign_signature.typed_name), '');
  v_current text;
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_count integer;
begin
  if v_me is null then
    ${forbidden("sign in to sign")}
  end if;
  if sign_signature.method not in ('drawn', 'typed', 'click') then
    ${fail("SIGNATURE_METHOD_INVALID", "method must be drawn, typed or click", "22023")}
  end if;
  if sign_signature.method = 'typed' and v_typed is null then
    ${fail("SIGNATURE_METHOD_INVALID", "a typed signature needs the typed name", "22023")}
  end if;
  if sign_signature.method = 'drawn' and sign_signature.image_attachment_id is null then
    ${fail("SIGNATURE_METHOD_INVALID", "a drawn signature needs its image attachment", "22023")}
  end if;
  select * into v_req from ${requests} x where x.${r("id")} = sign_signature.request_id for update;
  if not found then
    ${notFound}
  end if;
  if not (v_me = any (v_req.${r("signers")})) then
    ${forbidden("not a signer on this request")}
  end if;
  if v_req.${r("status")} <> 'pending' then
    ${fail("SIGNATURE_REQUEST_CLOSED", "this request is no longer pending", "22023")}
  end if;
  if exists (select 1 from ${signatures} g where g.${s("request")} = v_req.${r("id")} and g.${s("signer")} = v_me) then
    ${fail("SIGNATURE_ALREADY_SIGNED", "you already signed this request", "23505")}
  end if;
  select count(*) into v_count from ${signatures} g where g.${s("request")} = v_req.${r("id")};
  if v_req.${r("order")} = 'sequential' and array_position(v_req.${r("signers")}, v_me) <> v_count + 1 then
    ${fail("SIGNATURE_OUT_OF_ORDER", "an earlier signer hasn't signed yet", "55000")}
  end if;
  ${imageCheck}
  select ${versionHash(`x.${v("content")}`, `x.${v("storagePath")}`)} into v_current
    from ${vt} x where x.${v("id")} = v_req.${r("version")};
  if v_current is distinct from v_req.${r("contentHash")} then
    ${fail("SIGNATURE_CONTENT_CHANGED", "the version to sign changed after the request was made", "55000")}
  end if;
  ${ctx.hook("before_signature_sign", [
    ["uuid", `v_req.${r("id")}`],
    ["uuid", "v_me"],
    ["text", "sign_signature.method"],
  ])}
  insert into ${signatures} (${s("request")}, ${s("tenant")}, ${s("signer")}, ${s("method")}, ${s("typedName")}, ${s("image")}, ${s("signedHash")}, ${s("ip")}, ${s("userAgent")}, ${s("signedAt")})
  values (v_req.${r("id")}, v_req.${r("tenant")}, v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    ${signedHash({
      request: `v_req.${r("id")}`,
      contentHash: `v_req.${r("contentHash")}`,
      signer: "v_me",
      method: "sign_signature.method",
      typedName: "v_typed",
      image: "sign_signature.image_attachment_id",
      signedAt: "v_at",
    })},
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  ${requestRecord("signature.signed", "v_req", `, 'signatureId', v_row.${s("id")}, 'signer', v_me, 'method', v_row.${s("method")}`, `'signed ' || v_req.${r("subjectType")} || ' ' || v_req.${r("subjectId")}`)}${approvalStep}
  if v_count + 1 >= cardinality(v_req.${r("signers")}) then
    update ${requests} x set ${r("status")} = 'completed', ${r("completedAt")} = v_at
      where x.${r("id")} = v_req.${r("id")}
      returning * into v_req;
    ${requestRecord("signature.completed", "v_req", `, 'versionId', v_req.${r("version")}`, false)}
  end if;
  ${ctx.hook("after_signature_sign", [
    ["uuid", `v_row.${s("id")}`],
    ["text", `v_req.${r("status")}`],
  ])}
  return ${signatureJson("v_row")} || jsonb_build_object('requestStatus', v_req.${r("status")});
end;
$$;
${userGrant(`${fn("sign_signature")}(uuid, text, text, uuid)`)}

-- A signer refuses; the request closes for everyone.
create or replace function ${fn("decline_signature_request")}(request_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} x where x.${r("id")} = decline_signature_request.request_id for update;
  if not found then
    ${notFound}
  end if;
  if v_me is null or not (v_me = any (v_req.${r("signers")})) then
    ${forbidden("not a signer on this request")}
  end if;
  if v_req.${r("status")} <> 'pending' then
    ${fail("SIGNATURE_REQUEST_CLOSED", "this request is no longer pending", "22023")}
  end if;
  update ${requests} x set ${r("status")} = 'declined', ${r("completedAt")} = now()
    where x.${r("id")} = v_req.${r("id")}
    returning * into v_req;
  ${requestRecord("signature.declined", "v_req", ", 'signer', v_me", `'declined to sign' || coalesce(': ' || left(decline_signature_request.reason, 200), '')`)}
  return ${requestJson("v_req")};
end;
$$;
${userGrant(`${fn("decline_signature_request")}(uuid, text)`)}

-- The requester, or a holder of the manage permission, withdraws a request.
create or replace function ${fn("cancel_signature_request")}(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
begin
  select * into v_req from ${requests} x where x.${r("id")} = cancel_signature_request.request_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or v_req.${r("requestedBy")} = auth.uid() or ${ctx.can("tenant", `v_req.${r("tenant")}`, manage)}) then
    ${forbidden("not allowed to cancel this request")}
  end if;
  if v_req.${r("status")} <> 'pending' then
    ${fail("SIGNATURE_REQUEST_CLOSED", "this request is no longer pending", "22023")}
  end if;
  update ${requests} x set ${r("status")} = 'cancelled', ${r("completedAt")} = now()
    where x.${r("id")} = v_req.${r("id")}
    returning * into v_req;
  ${requestRecord("signature.cancelled", "v_req", "", "'cancelled a signature request'")}
  return ${requestJson("v_req")};
end;
$$;
${userGrant(`${fn("cancel_signature_request")}(uuid)`)}

create or replace function ${fn("get_signature_request")}(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req ${requests}%rowtype;
  v_items jsonb;
begin
  select * into v_req from ${requests} x where x.${r("id")} = get_signature_request.request_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or auth.uid() = any (v_req.${r("signers")}) or ${readableRequest("v_req")}) then
    ${forbidden("not allowed to read this request")}
  end if;
  select coalesce(jsonb_agg(${signatureJson("g")} order by g.${s("signedAt")}), '[]'::jsonb) into v_items
    from ${signatures} g where g.${s("request")} = v_req.${r("id")};
  return ${requestJson("v_req")} || jsonb_build_object('signatures', v_items, 'verification', ${fn("signature_verification")}(v_req.${r("id")}));
end;
$$;
${userGrant(`${fn("get_signature_request")}(uuid)`)}

-- A record's requests, or with mine the requests the caller is asked to sign.
create or replace function ${fn("list_signature_requests")}(tenant ${ctx.idType}, subject_type text default null, subject_id text default null, status text default null, mine boolean default false, page_size integer default 50, before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or list_signature_requests.mine or ${ctx.can("tenant", "list_signature_requests.tenant", read)}) then
    ${forbidden("not allowed to list signature requests")}
  end if;
  select coalesce(jsonb_agg(${requestJson("q")} order by q.${r("createdAt")} desc), '[]'::jsonb) into v_rows
  from (
    select * from ${requests} x
    where x.${r("tenant")} = list_signature_requests.tenant
      and (list_signature_requests.subject_type is null or x.${r("subjectType")} = list_signature_requests.subject_type)
      and (list_signature_requests.subject_id is null or x.${r("subjectId")} = list_signature_requests.subject_id)
      and (list_signature_requests.status is null or x.${r("status")} = list_signature_requests.status)
      and (list_signature_requests.before is null or x.${r("createdAt")} < list_signature_requests.before)
      and (not list_signature_requests.mine or auth.uid() = any (x.${r("signers")}))
      and (${SERVICE_CALLER} or auth.uid() = any (x.${r("signers")}) or ${readableRequest("x")})
    order by x.${r("createdAt")} desc
    limit ${pageSize("list_signature_requests.page_size", 50, 200)}
  ) q;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_signature_requests")}(${ctx.idType}, text, text, text, boolean, integer, timestamptz)`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_signature_request",
      args: ["{id}", "text", "text", "uuid[]", "uuid", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "sign_signature",
      args: ["uuid", "text", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "get_signature_request", args: ["uuid"], returns: "jsonb" },
  ];
}

export const SIGNATURES: ModuleDefinition = {
  name: "signatures",
  title: "Signatures",
  description:
    "Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.",
  requires: ["tenant", "access", "versions"],
  integrates: ["approvals", "attachments", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
