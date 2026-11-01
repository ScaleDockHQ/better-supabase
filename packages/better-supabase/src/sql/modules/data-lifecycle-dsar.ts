import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, fail, lockTable } from "../shared.ts";
import { lifecycleJson } from "./data-lifecycle-app.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The kinds of request GDPR Arts. 15 to 20 give a data subject. */
const DSAR_KINDS = [
  "access",
  "erasure",
  "rectification",
  "portability",
] as const;

/** Where a request stands. */
const DSAR_STATUSES = ["received", "verified", "fulfilled", "refused"] as const;

/** The request table. */
export const DSAR_TABLES: Readonly<Record<string, BlockSqlTableSpec>> = {
  requests: {
    name: "data_subject_requests",
    columns: {
      id: "id",
      tenant: "organization_id",
      kind: "kind",
      requester: "requester",
      subjectType: "subject_type",
      subjectId: "subject_id",
      details: "details",
      status: "status",
      receivedAt: "received_at",
      receivedBy: "received_by",
      dueAt: "due_at",
      extendedAt: "extended_at",
      extensionReason: "extension_reason",
      verifiedAt: "verified_at",
      verifiedBy: "verified_by",
      verificationMethod: "verification_method",
      exportId: "export_id",
      resolution: "resolution",
      closedAt: "closed_at",
      closedBy: "closed_by",
    },
    lifecycle: { tenant: "tenant", export: false },
    app: {},
  },
};

export const DSAR_CONTRACT: readonly BlockSqlContractFunction[] = [
  {
    name: "open_data_subject_request",
    args: ["{id}", "text", "text", "text", "text", "text"],
    returns: "jsonb",
  },
  {
    name: "verify_data_subject_request",
    args: ["uuid", "text"],
    returns: "jsonb",
  },
  {
    name: "extend_data_subject_request",
    args: ["uuid", "text"],
    returns: "jsonb",
  },
  {
    name: "fulfil_data_subject_request",
    args: ["uuid", "text"],
    returns: "jsonb",
  },
  {
    name: "refuse_data_subject_request",
    args: ["uuid", "text"],
    returns: "jsonb",
  },
  {
    name: "list_data_subject_requests",
    args: ["{id}", "text", "boolean"],
    returns: "jsonb",
  },
];

const kindList = DSAR_KINDS.map((kind) => sqlString(kind)).join(", ");
const statusList = DSAR_STATUSES.map((status) => sqlString(status)).join(", ");

/**
 * The GDPR data subject request workflow: the table and the functions that
 * open, verify, extend, fulfil and refuse a request. The due date is 30 days
 * after receipt, extended once by two further months (Art. 12(3)).
 */
export function dsarSql(ctx: BlockSqlContext): string {
  const id = ctx.idType;
  const t = ctx.table("requests");
  const c = (logical: string): string => ctx.col("requests", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("data-lifecycle");
  const exportPermission = ctx.permission("export", permissions.export);

  const json = (row: string, whole?: string): string =>
    lifecycleJson(ctx, "requests", row, whole);

  const allowed = (tenant: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, exportPermission)})`;

  const event = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('requestId', v_row.${c("id")}, 'organizationId', v_row.${c("tenant")}::text, 'kind', v_row.${c("kind")}::text, 'status', v_row.${c("status")}::text, 'dueAt', v_row.${c("dueAt")})`,
      subject: `'data-subject-requests/' || v_row.${c("id")}::text`,
      tenant: `v_row.${c("tenant")}`,
      audit: {
        category: "data",
        targetType: "data_subject_request",
        recordId: `v_row.${c("id")}::text`,
      },
    });

  const forbidden = fail(
    "DSAR_FORBIDDEN",
    "You may not handle data subject requests here",
  );

  const missing = fail("DSAR_NOT_FOUND", "request not found", "P0002");

  const closed = fail(
    "DSAR_CLOSED",
    "the request is already fulfilled or refused",
    "55000",
  );

  return `
-- One row per data subject request (GDPR Arts. 15 to 20). due_at is 30 days
-- after receipt; extended_at records the single extension of two months.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("kind")} text not null check (${c("kind")} in (${kindList})),
  ${c("requester")} text not null check (length(${c("requester")}) between 1 and 320),
  ${c("subjectType")} text,
  ${c("subjectId")} text,
  ${c("details")} text check (${c("details")} is null or length(${c("details")}) <= 5000),
  ${c("status")} text not null default 'received' check (${c("status")} in (${statusList})),
  ${c("receivedAt")} timestamptz not null default now(),
  ${c("receivedBy")} uuid,
  ${c("dueAt")} timestamptz not null,
  ${c("extendedAt")} timestamptz,
  ${c("extensionReason")} text,
  ${c("verifiedAt")} timestamptz,
  ${c("verifiedBy")} uuid,
  ${c("verificationMethod")} text,
  ${c("exportId")} uuid,
  ${c("resolution")} text,
  ${c("closedAt")} timestamptz,
  ${c("closedBy")} uuid,
  check ((${c("subjectType")} is null) = (${c("subjectId")} is null))
);
create index if not exists ${ctx.naming.rename("data_subject_requests_open_idx")} on ${t} (${c("tenant")}, ${c("dueAt")}) where ${c("closedAt")} is null;
${lockTable(t)}

-- Opens a request: kind is access, erasure, rectification or portability;
-- requester says who asked (an email address or a name). A request about a
-- record names it with subject_type and subject_id, which an access or
-- portability request needs to be fulfilled through the record export.
create or replace function ${fn("open_data_subject_request")}(tenant ${id}, kind text, requester text, subject_type text default null, subject_id text default null, details text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
begin
  if not ${allowed("open_data_subject_request.tenant")} then
    ${forbidden}
  end if;
  if open_data_subject_request.kind is null or open_data_subject_request.kind not in (${kindList}) then
    ${fail("DSAR_INVALID", "kind must be access, erasure, rectification or portability", "22023")}
  end if;
  if open_data_subject_request.requester is null or length(trim(open_data_subject_request.requester)) = 0 then
    ${fail("DSAR_INVALID", "requester is required", "22023")}
  end if;
  if (open_data_subject_request.subject_type is null) <> (open_data_subject_request.subject_id is null) then
    ${fail("DSAR_INVALID", "subject_type and subject_id go together", "22023")}
  end if;
  insert into ${t} (${c("tenant")}, ${c("kind")}, ${c("requester")}, ${c("subjectType")}, ${c("subjectId")}, ${c("details")}, ${c("receivedBy")}, ${c("dueAt")})
  values (open_data_subject_request.tenant, open_data_subject_request.kind, trim(open_data_subject_request.requester), open_data_subject_request.subject_type, open_data_subject_request.subject_id, open_data_subject_request.details, auth.uid(), now() + interval '30 days')
  returning * into v_row;
  ${event("data_subject_request.received")}
  return ${json("v_row")};
end;
$$;

-- Records that the requester's identity was checked (Art. 12(6)); method says
-- how, for example "signed in" or "ID document".
create or replace function ${fn("verify_data_subject_request")}(id uuid, method text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${c("id")} = verify_data_subject_request.id for update;
  if v_row.${c("id")} is null then
    ${missing}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`)} then
    ${forbidden}
  end if;
  if v_row.${c("closedAt")} is not null then
    ${closed}
  end if;
  if verify_data_subject_request.method is null or length(trim(verify_data_subject_request.method)) = 0 then
    ${fail("DSAR_INVALID", "method is required", "22023")}
  end if;
  update ${t} x set ${c("status")} = 'verified', ${c("verifiedAt")} = now(), ${c("verifiedBy")} = auth.uid(), ${c("verificationMethod")} = trim(verify_data_subject_request.method)
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${event("data_subject_request.verified")}
  return ${json("v_row")};
end;
$$;

-- Extends the due date by two months, once, when the request is complex or
-- there are many of them (Art. 12(3)). The reason is kept for the requester.
create or replace function ${fn("extend_data_subject_request")}(id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${c("id")} = extend_data_subject_request.id for update;
  if v_row.${c("id")} is null then
    ${missing}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`)} then
    ${forbidden}
  end if;
  if v_row.${c("closedAt")} is not null then
    ${closed}
  end if;
  if v_row.${c("extendedAt")} is not null then
    ${fail("DSAR_EXTENDED", "the due date was already extended once", "55000")}
  end if;
  if extend_data_subject_request.reason is null or length(trim(extend_data_subject_request.reason)) = 0 then
    ${fail("DSAR_INVALID", "reason is required", "22023")}
  end if;
  update ${t} x set ${c("dueAt")} = x.${c("receivedAt")} + interval '3 months', ${c("extendedAt")} = now(), ${c("extensionReason")} = trim(extend_data_subject_request.reason)
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${event("data_subject_request.extended")}
  return ${json("v_row")};
end;
$$;

-- Fulfils a verified request. Access and portability start the NDJSON export
-- of the named record (request_subject_export) and keep its id; the export job
-- writes the files. Erasure refuses while a legal hold covers every kind of
-- record and otherwise records that the app deleted or anonymized the data;
-- rectification records what changed. resolution is required for both.
create or replace function ${fn("fulfil_data_subject_request")}(id uuid, resolution text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
  v_export jsonb;
  v_export_id uuid;
begin
  select * into v_row from ${t} x where x.${c("id")} = fulfil_data_subject_request.id for update;
  if v_row.${c("id")} is null then
    ${missing}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`)} then
    ${forbidden}
  end if;
  if v_row.${c("closedAt")} is not null then
    ${closed}
  end if;
  if v_row.${c("verifiedAt")} is null then
    ${fail("DSAR_UNVERIFIED", "verify the requester's identity first", "55000")}
  end if;
  if v_row.${c("kind")} in ('access', 'portability') then
    if v_row.${c("subjectType")} is null then
      ${fail("DSAR_INVALID", "an access or portability request names the record to export", "22023")}
    end if;
    v_export := ${fn("request_subject_export")}(v_row.${c("subjectType")}, v_row.${c("subjectId")}, 'ndjson');
    v_export_id := (v_export ->> 'id')::uuid;
  else
    if fulfil_data_subject_request.resolution is null or length(trim(fulfil_data_subject_request.resolution)) = 0 then
      ${fail("DSAR_INVALID", "resolution is required", "22023")}
    end if;
    if v_row.${c("kind")} = 'erasure' and ${fn("is_held")}('data_subject_request', v_row.${c("tenant")}::text) then
      ${fail("DSAR_HELD", "a legal hold stops the erasure; refuse the request with its reason", "55000")}
    end if;
  end if;
  update ${t} x set ${c("status")} = 'fulfilled', ${c("closedAt")} = now(), ${c("closedBy")} = auth.uid(), ${c("exportId")} = v_export_id, ${c("resolution")} = nullif(trim(fulfil_data_subject_request.resolution), '')
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${event("data_subject_request.fulfilled")}
  return ${json("v_row")};
end;
$$;

-- Refuses a request with its reason (Art. 12(4)): the requester gets it with
-- the right to complain to the supervisory authority.
create or replace function ${fn("refuse_data_subject_request")}(id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
begin
  select * into v_row from ${t} x where x.${c("id")} = refuse_data_subject_request.id for update;
  if v_row.${c("id")} is null then
    ${missing}
  end if;
  if not ${allowed(`v_row.${c("tenant")}`)} then
    ${forbidden}
  end if;
  if v_row.${c("closedAt")} is not null then
    ${closed}
  end if;
  if refuse_data_subject_request.reason is null or length(trim(refuse_data_subject_request.reason)) = 0 then
    ${fail("DSAR_INVALID", "reason is required", "22023")}
  end if;
  update ${t} x set ${c("status")} = 'refused', ${c("closedAt")} = now(), ${c("closedBy")} = auth.uid(), ${c("resolution")} = trim(refuse_data_subject_request.reason)
  where x.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${event("data_subject_request.refused")}
  return ${json("v_row")};
end;
$$;

-- The organization's requests, the nearest due date first. status filters by
-- status; open_only leaves out fulfilled and refused ones. overdue is true for
-- an open request past its due date.
create or replace function ${fn("list_data_subject_requests")}(tenant ${id}, status text default null, open_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("list_data_subject_requests.tenant")} then
    ${forbidden}
  end if;
  return coalesce((
    select jsonb_agg(${json("x", "x.*")} || jsonb_build_object('overdue', x.${c("closedAt")} is null and x.${c("dueAt")} < now()) order by x.${c("dueAt")}, x.${c("id")})
    from ${t} x
    where x.${c("tenant")} = list_data_subject_requests.tenant
      and (list_data_subject_requests.status is null or x.${c("status")} = list_data_subject_requests.status)
      and (not list_data_subject_requests.open_only or x.${c("closedAt")} is null)
  ), '[]'::jsonb);
end;
$$;

revoke execute on function ${fn("open_data_subject_request")}(${id}, text, text, text, text, text) from public, anon;
revoke execute on function ${fn("verify_data_subject_request")}(uuid, text) from public, anon;
revoke execute on function ${fn("extend_data_subject_request")}(uuid, text) from public, anon;
revoke execute on function ${fn("fulfil_data_subject_request")}(uuid, text) from public, anon;
revoke execute on function ${fn("refuse_data_subject_request")}(uuid, text) from public, anon;
revoke execute on function ${fn("list_data_subject_requests")}(${id}, text, boolean) from public, anon;
grant execute on function ${fn("open_data_subject_request")}(${id}, text, text, text, text, text) to authenticated, service_role;
grant execute on function ${fn("verify_data_subject_request")}(uuid, text) to authenticated, service_role;
grant execute on function ${fn("extend_data_subject_request")}(uuid, text) to authenticated, service_role;
grant execute on function ${fn("fulfil_data_subject_request")}(uuid, text) to authenticated, service_role;
grant execute on function ${fn("refuse_data_subject_request")}(uuid, text) to authenticated, service_role;
grant execute on function ${fn("list_data_subject_requests")}(${id}, text, boolean) to authenticated, service_role;
`;
}
