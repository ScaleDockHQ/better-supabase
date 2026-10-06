import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, schemaPreamble } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["bucket", "requireScan", "maxSize", "allowedMimeTypes"],
  tables: {
    attachments: {
      name: "attachments",
      columns: {
        id: "id",
        tenant: "organization_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        bucket: "bucket",
        path: "object_path",
        name: "name",
        mimeType: "mime_type",
        size: "size",
        status: "status",
        detail: "scan_detail",
        uploadedBy: "uploaded_by",
        createdAt: "created_at",
        uploadedAt: "uploaded_at",
        scannedAt: "scanned_at",
      },
    },
  },
};

const BUCKET = /^[a-z0-9][a-z0-9_-]{2,62}$/;

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const t = ctx.table("attachments");
  const c = (logical: string): string => ctx.col("attachments", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.attachments;
  const can = (tenant: string, action: keyof typeof permissions): string =>
    `coalesce(better_supabase.can('tenant', ${tenant}, ${ctx.permission(action, permissions[action])}), false)`;
  const { bucket, maxSize, mimeTypes } = bucketOptions(ctx);
  const requireScan = ctx.flag("requireScan", true);
  const mimeCheck =
    mimeTypes.length === 0
      ? ""
      : `,\n  check (${mimeTypes
          .map((type) =>
            type.endsWith("/*")
              ? `${c("mimeType")} like ${sqlString(`${type.slice(0, -1)}%`)}`
              : `${c("mimeType")} = ${sqlString(type)}`,
          )
          .join(" or ")})`;
  const readable = requireScan
    ? `a.${c("status")} = 'clean'`
    : `a.${c("status")} in ('pending', 'clean', 'failed')`;
  const bucketLiteral = sqlString(bucket);
  const uploaded = ctx.emit({
    type: "attachment.uploaded",
    payload: `jsonb_build_object('attachmentId', v_row.${c("id")}, 'organizationId', v_row.${c("tenant")}::text, 'subjectType', v_row.${c("subjectType")}, 'subjectId', v_row.${c("subjectId")}, 'uploadedBy', v_row.${c("uploadedBy")}, 'mimeType', v_row.${c("mimeType")}, 'size', v_row.${c("size")})`,
    subject: `'attachments/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
  });
  const scanned = ctx.emit({
    type: "attachment.scanned",
    payload: `jsonb_build_object('attachmentId', v_row.${c("id")}, 'organizationId', v_row.${c("tenant")}::text, 'status', v_row.${c("status")}, 'uploadedBy', v_row.${c("uploadedBy")})`,
    subject: `'attachments/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
  });
  const policy = (name: string): string => sqlIdent(`bs_attachments_${name}`);

  return `${schemaPreamble(ctx)}
-- Files linked to records. Each object lives at
-- {organization_id}/attachments/{id} in the ${bucket} bucket; the record is
-- created first, so the storage policies below only accept an upload a
-- pending record expects.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("subjectType")} text check (${c("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${c("subjectId")} text check (length(${c("subjectId")}) between 1 and 200),
  ${c("bucket")} text not null default ${bucketLiteral},
  ${c("path")} text generated always as (${c("tenant")}::text || '/attachments/' || ${c("id")}::text) stored,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 255),
  ${c("mimeType")} text not null check (${c("mimeType")} ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  ${c("size")} bigint not null check (${c("size")} between 0 and ${String(maxSize)}),
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'clean', 'infected', 'failed')),
  ${c("detail")} text,
  ${c("uploadedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("createdAt")} timestamptz not null default clock_timestamp(),
  ${c("uploadedAt")} timestamptz,
  ${c("scannedAt")} timestamptz,
  check ((${c("subjectType")} is null) = (${c("subjectId")} is null))${mimeCheck}
);
create unique index if not exists attachments_object_idx on ${t} (${c("bucket")}, ${c("path")});
create index if not exists attachments_subject_idx on ${t} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")});
create index if not exists attachments_uploaded_by_idx on ${t} (${c("uploadedBy")});
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
grant select, delete on ${t} to authenticated;
grant insert (${[c("tenant"), c("subjectType"), c("subjectId"), c("name"), c("mimeType"), c("size")].join(", ")}) on ${t} to authenticated;
grant all on ${t} to service_role;
drop policy if exists "attachments_read" on ${t};
create policy "attachments_read" on ${t} for select to authenticated
  using (${can(c("tenant"), "read")});
drop policy if exists "attachments_insert" on ${t};
create policy "attachments_insert" on ${t} for insert to authenticated
  with check (${c("uploadedBy")} = (select auth.uid()) and ${can(c("tenant"), "upload")});
drop policy if exists "attachments_delete" on ${t};
create policy "attachments_delete" on ${t} for delete to authenticated
  using (${c("uploadedBy")} = (select auth.uid()) or ${can(c("tenant"), "manage")});

-- Whether the caller may run action (insert, select or delete) on the
-- object at path: an upload needs the caller's pending record, a read a
-- ${requireScan ? "clean" : "not infected"} file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
create or replace function ${fn("attachment_object_allowed")}(path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${t} a
    where a.${c("bucket")} = ${bucketLiteral} and a.${c("path")} = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a.${c("status")} = 'pending' and a.${c("uploadedAt")} is null and a.${c("uploadedBy")} = auth.uid()
        when 'select' then (${readable} and ${can(`a.${c("tenant")}`, "read")})
          or a.${c("uploadedBy")} = auth.uid() or ${can(`a.${c("tenant")}`, "manage")}
        when 'delete' then a.${c("uploadedBy")} = auth.uid() or ${can(`a.${c("tenant")}`, "manage")}
        else false
      end
  )
$$;
revoke execute on function ${fn("attachment_object_allowed")}(text, text) from public, anon;
grant execute on function ${fn("attachment_object_allowed")}(text, text) to authenticated, service_role;

drop policy if exists ${policy("insert")} on storage.objects;
create policy ${policy("insert")} on storage.objects for insert to authenticated
  with check (bucket_id = ${bucketLiteral} and ${fn("attachment_object_allowed")}(name, 'insert'));
drop policy if exists ${policy("select")} on storage.objects;
create policy ${policy("select")} on storage.objects for select to authenticated
  using (bucket_id = ${bucketLiteral} and ${fn("attachment_object_allowed")}(name, 'select'));
drop policy if exists ${policy("delete")} on storage.objects;
create policy ${policy("delete")} on storage.objects for delete to authenticated
  using (bucket_id = ${bucketLiteral} and ${fn("attachment_object_allowed")}(name, 'delete'));

-- The caller's new record, for a signed upload URL to its object_path.
create or replace function ${fn("create_attachment")}(
  tenant ${id},
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into ${t} as x (${[c("tenant"), c("name"), c("mimeType"), c("size"), c("subjectType"), c("subjectId")].join(", ")})
  values (create_attachment.tenant, create_attachment.name, lower(create_attachment.mime_type), create_attachment.size, create_attachment.subject_type, create_attachment.subject_id)
  returning to_jsonb(x.*)
$$;

-- Marks the upload done once the object exists, taking its size and type
-- from Storage, and writes attachment.uploaded for the scan job.${requireScan ? "" : "\n-- Without requireScan the file is clean right away."}
create or replace function ${fn("confirm_attachment")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
  v_meta jsonb;
begin
  select * into v_row from ${t} a where a.${c("id")} = confirm_attachment.id for update;
  if v_row.${c("id")} is null or (v_row.${c("uploadedBy")} is distinct from auth.uid() and not (${SERVICE_CALLER})) then
    raise exception 'No pending attachment of yours has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row.${c("uploadedAt")} is not null then
    return to_jsonb(v_row);
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row.${c("bucket")} and o.name = v_row.${c("path")};
  if not found then
    raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
  end if;
  update ${t} a set
    ${c("uploadedAt")} = now(),
    ${c("size")} = coalesce((v_meta ->> 'size')::bigint, a.${c("size")}),
    ${c("mimeType")} = coalesce(lower(v_meta ->> 'mimetype'), a.${c("mimeType")})${requireScan ? "" : `,\n    ${c("status")} = 'clean'`}
  where a.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${uploaded || "null;"}
  return to_jsonb(v_row);
end;
$$;

-- Records a scan result (service role). A clean or infected file keeps its
-- status, so a replayed job changes nothing.
create or replace function ${fn("set_attachment_status")}(id uuid, status text, detail text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${t};
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_attachment_status.status not in ('clean', 'infected', 'failed') then
    raise exception 'status must be clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  update ${t} a set
    ${c("status")} = set_attachment_status.status,
    ${c("detail")} = set_attachment_status.detail,
    ${c("scannedAt")} = now()
  where a.${c("id")} = set_attachment_status.id
    and a.${c("uploadedAt")} is not null
    and a.${c("status")} in ('pending', 'failed')
  returning * into v_row;
  if v_row.${c("id")} is null then
    select * into v_row from ${t} a where a.${c("id")} = set_attachment_status.id;
    return case when v_row.${c("id")} is null then null else to_jsonb(v_row) end;
  end if;
  ${scanned || "null;"}
  return to_jsonb(v_row);
end;
$$;

create or replace function ${fn("list_attachments")}(tenant ${id}, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(a.*) order by a.${c("createdAt")}, a.${c("id")}), '[]'::jsonb)
  from ${t} a
  where a.${c("tenant")} = list_attachments.tenant
    and (list_attachments.subject_type is null or a.${c("subjectType")} = list_attachments.subject_type)
    and (list_attachments.subject_id is null or a.${c("subjectId")} = list_attachments.subject_id)
$$;

create or replace function ${fn("get_attachment")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(a.*) from ${t} a where a.${c("id")} = get_attachment.id
$$;

create or replace function ${fn("delete_attachment")}(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from ${t} a where a.${c("id")} = delete_attachment.id returning 1
  )
  select exists (select 1 from removed)
$$;

revoke execute on function ${fn("create_attachment")}(${id}, text, text, bigint, text, text) from public, anon;
revoke execute on function ${fn("confirm_attachment")}(uuid) from public, anon;
revoke execute on function ${fn("set_attachment_status")}(uuid, text, text) from public, anon, authenticated;
revoke execute on function ${fn("list_attachments")}(${id}, text, text) from public, anon;
revoke execute on function ${fn("get_attachment")}(uuid) from public, anon;
revoke execute on function ${fn("delete_attachment")}(uuid) from public, anon;
grant execute on function ${fn("create_attachment")}(${id}, text, text, bigint, text, text) to authenticated, service_role;
grant execute on function ${fn("confirm_attachment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("set_attachment_status")}(uuid, text, text) to service_role;
grant execute on function ${fn("list_attachments")}(${id}, text, text) to authenticated, service_role;
grant execute on function ${fn("get_attachment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("delete_attachment")}(uuid) to authenticated, service_role;`;
}

interface BucketOptions {
  readonly bucket: string;
  readonly maxSize: number;
  readonly mimeTypes: readonly string[];
}

function bucketOptions(ctx: ModuleContext): BucketOptions {
  const bucket = ctx.text("bucket", "attachments");
  if (!BUCKET.test(bucket)) {
    throw new TypeError(
      "sql.modules.attachments.options.bucket must be 3 to 63 lowercase letters, digits, dashes or underscores",
    );
  }
  const maxSize = ctx.number("maxSize", 50 * 1024 * 1024);
  if (!Number.isInteger(maxSize) || maxSize < 1) {
    throw new TypeError(
      "sql.modules.attachments.options.maxSize must be a whole number of bytes above zero",
    );
  }
  return { bucket, maxSize, mimeTypes: ctx.list("allowedMimeTypes", []) };
}

// An existing bucket keeps its settings.
function data(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const { bucket, maxSize, mimeTypes } = bucketOptions(ctx);
  const mimeArray =
    mimeTypes.length === 0
      ? "null"
      : `array[${mimeTypes.map(sqlString).join(", ")}]::text[]`;
  return `insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (${sqlString(bucket)}, ${sqlString(bucket)}, false, ${String(maxSize)}, ${mimeArray})
on conflict (id) do nothing;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "attachment_object_allowed",
      args: ["text", "text"],
      returns: "boolean",
    },
    {
      name: "create_attachment",
      args: ["{id}", "text", "text", "bigint", "text", "text"],
      returns: "jsonb",
    },
    { name: "confirm_attachment", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_attachment_status",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_attachments",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    { name: "get_attachment", args: ["uuid"], returns: "jsonb" },
    { name: "delete_attachment", args: ["uuid"], returns: "boolean" },
  ];
}

export const ATTACHMENTS: ModuleDefinition = {
  name: "attachments",
  title: "Attachments",
  description:
    "Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  data,
};
