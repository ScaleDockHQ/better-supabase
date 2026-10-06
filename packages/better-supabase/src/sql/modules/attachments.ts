import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, schemaPreamble } from "../shared.ts";
import {
  type Subject,
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: [
    "bucket",
    "requireScan",
    "maxSize",
    "allowedMimeTypes",
    "subjects",
    "path",
    "scanBuckets",
  ],
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
    scans: {
      name: "scanned_objects",
      columns: {
        bucket: "bucket",
        path: "object_path",
        status: "status",
        detail: "scan_detail",
        createdAt: "created_at",
        scannedAt: "scanned_at",
      },
    },
  },
};

const PATH_PARTS: Readonly<Record<string, string>> = {
  organization_id: "tenant",
  id: "id",
  subject_type: "subjectType",
  subject_id: "subjectId",
};

/**
 * `options.path`: the object path template, default
 * `{organization_id}/attachments/{id}`, as the generated column's expression.
 */
const pathTemplate = (ctx: ModuleContext): string =>
  ctx.text("path", "{organization_id}/attachments/{id}");

function pathExpression(ctx: ModuleContext): string {
  const template = pathTemplate(ctx);
  const where = "sql.modules.attachments.options.path";
  if (!template.includes("{id}")) {
    throw new TypeError(
      `${where} must contain {id}, so each file has its own path`,
    );
  }
  if (!template.startsWith("{organization_id}/")) {
    throw new TypeError(
      `${where} must start with {organization_id}/, so a tenant's files share a prefix`,
    );
  }
  const parts = template.split(/(\{[a-z_]+\})/).filter((part) => part !== "");
  return parts
    .map((part) => {
      const match = /^\{([a-z_]+)\}$/.exec(part);
      if (!match) {
        if (!/^[A-Za-z0-9/_.-]+$/.test(part)) {
          throw new TypeError(
            `${where}: "${part}" may hold letters, digits, /, _, . and - only`,
          );
        }
        return sqlString(part);
      }
      const logical = PATH_PARTS[match[1]!];
      if (!logical) {
        throw new TypeError(
          `${where}: {${match[1]}} is not a placeholder. Use ${Object.keys(
            PATH_PARTS,
          )
            .map((key) => `{${key}}`)
            .join(", ")}`,
        );
      }
      const column = ctx.col("attachments", logical);
      return logical === "subjectType" || logical === "subjectId"
        ? `coalesce(${column}, '-')`
        : `${column}::text`;
    })
    .join(" || ");
}

const isText = (value: unknown): value is string => typeof value === "string";

interface SubjectBucket {
  readonly type: string;
  readonly bucket: string;
  readonly mimeTypes: readonly string[];
}

/** The subjects with their own bucket or MIME types (`options.subjects.<type>.bucket`, `.allowedMimeTypes`). */
function subjectBuckets(
  subjects: readonly (readonly [string, Subject])[],
  fallback: string,
): readonly SubjectBucket[] {
  return subjects.map(([type, subject]) => {
    const bucket = subject.extra["bucket"] ?? fallback;
    if (!isText(bucket) || !BUCKET.test(bucket)) {
      throw new TypeError(
        `sql.modules.attachments.options.subjects.${type}.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores`,
      );
    }
    const mimeTypes = subject.extra["allowedMimeTypes"] ?? [];
    if (!Array.isArray(mimeTypes) || !mimeTypes.every(isText)) {
      throw new TypeError(
        `sql.modules.attachments.options.subjects.${type}.allowedMimeTypes must be a list of MIME types`,
      );
    }
    return { type, bucket, mimeTypes };
  });
}

const mimeMatch = (column: string, types: readonly string[]): string =>
  types
    .map((type) =>
      type.endsWith("/*")
        ? `${column} like ${sqlString(`${type.slice(0, -1)}%`)}`
        : `${column} = ${sqlString(type)}`,
    )
    .join(" or ");

/** `options.scanBuckets`: buckets whose new objects get a pending scan row. */
function scanBucketsOf(ctx: ModuleContext): readonly string[] {
  const buckets = ctx.list("scanBuckets", []);
  for (const bucket of buckets) {
    if (!BUCKET.test(bucket)) {
      throw new TypeError(
        `sql.modules.attachments.options.scanBuckets: "${bucket}" is not a bucket id`,
      );
    }
  }
  return buckets;
}

/** A Storage bucket id: Supabase allows 1 to 100 characters. */
const BUCKET = /^[a-z0-9][a-z0-9_.-]{0,99}$/;

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
  const subjects = subjectsOption(ctx, ["bucket", "allowedMimeTypes"]);
  const perSubject = subjectBuckets(subjects, bucket);
  const buckets = [
    ...new Set([bucket, ...perSubject.map((entry) => entry.bucket)]),
  ];
  const bucketList = buckets.map(sqlString).join(", ");
  const bucketFor = perSubject.some((entry) => entry.bucket !== bucket)
    ? `case create_attachment.subject_type ${perSubject
        .filter((entry) => entry.bucket !== bucket)
        .map(
          (entry) =>
            `when ${sqlString(entry.type)} then ${sqlString(entry.bucket)}`,
        )
        .join(" ")} else ${sqlString(bucket)} end`
    : sqlString(bucket);
  const mimeRules = [
    ...(mimeTypes.length === 0 ? [] : [mimeMatch(c("mimeType"), mimeTypes)]),
    ...perSubject
      .filter((entry) => entry.mimeTypes.length > 0)
      .map(
        (entry) =>
          `${c("subjectType")} is distinct from ${sqlString(entry.type)} or ${mimeMatch(c("mimeType"), entry.mimeTypes)}`,
      ),
  ];
  const mimeCheck =
    mimeRules.length === 0
      ? ""
      : `\nalter table ${t} add constraint bs_attachments_mime_type check (${mimeRules
          .map((rule) => `(${rule})`)
          .join(" and ")});`;
  const subjectReadableSql = subjectReadable(subjects, {
    type: "subject_type",
    id: "subject_id",
    tenant: "tenant",
  });
  const cascades = subjectCascades(
    ctx,
    subjects,
    `delete from ${t} x where x.${c("subjectType")} = v_type and x.${c("subjectId")} = v_id;`,
  );
  const scans = ctx.table("scans");
  const sc = (logical: string): string => ctx.col("scans", logical);
  const scanBuckets = scanBucketsOf(ctx);
  const objectUploaded = ctx.emit({
    type: "object.uploaded",
    payload: `jsonb_build_object('bucket', new.bucket_id, 'path', new.name)`,
    subject: `'objects/' || new.bucket_id || '/' || new.name`,
    tenant: "null",
  });
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
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the ${bucket} bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("subjectType")} text check (${c("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${c("subjectId")} text check (length(${c("subjectId")}) between 1 and 200),
  ${c("bucket")} text not null default ${bucketLiteral},
  ${c("path")} text generated always as (${pathExpression(ctx)}) stored,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 255),
  ${c("mimeType")} text not null check (${c("mimeType")} ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  ${c("size")} bigint not null,
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'clean', 'infected', 'failed')),
  ${c("detail")} text,
  ${c("uploadedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("createdAt")} timestamptz not null default clock_timestamp(),
  ${c("uploadedAt")} timestamptz,
  ${c("scannedAt")} timestamptz,
  check ((${c("subjectType")} is null) = (${c("subjectId")} is null))
);
-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- options.path: the column comment records the template the expression was
-- built from, so a changed template rewrites the column (Postgres 17+).
do $$
declare
  v_current text := coalesce(
    col_description(${sqlString(ctx.tableName("attachments").schema + "." + ctx.tableName("attachments").name)}::regclass,
      (select attnum from pg_attribute where attrelid = ${sqlString(ctx.tableName("attachments").schema + "." + ctx.tableName("attachments").name)}::regclass and attname = ${sqlString(c("path").replaceAll('"', ""))})::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from ${sqlString(`better-supabase path: ${pathTemplate(ctx)}`)} then
    if current_setting('server_version_num')::integer < 170000 then
      raise exception 'sql.modules.attachments.options.path changed, which needs Postgres 17 to rewrite object_path; recreate the column in a migration instead';
    end if;
    execute ${sqlString(`alter table ${t} alter column ${c("path")} set expression as (${pathExpression(ctx)})`)};
  end if;
end;
$$;
comment on column ${t}.${c("path")} is ${sqlString(`better-supabase path: ${pathTemplate(ctx)}`)};
alter table ${t} alter column ${c("bucket")} set default ${bucketLiteral};
alter table ${t} drop constraint if exists bs_attachments_bucket;
alter table ${t} add constraint bs_attachments_bucket check (${c("bucket")} in (${bucketList})) not valid;
alter table ${t} drop constraint if exists bs_attachments_size;
alter table ${t} add constraint bs_attachments_size check (${c("size")} between 0 and ${String(maxSize)});
alter table ${t} drop constraint if exists bs_attachments_mime_type;${mimeCheck}
create unique index if not exists attachments_object_idx on ${t} (${c("bucket")}, ${c("path")});
create index if not exists attachments_subject_idx on ${t} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")});
create index if not exists attachments_uploaded_by_idx on ${t} (${c("uploadedBy")});
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
grant select, delete on ${t} to authenticated;
grant insert (${[c("tenant"), c("bucket"), c("subjectType"), c("subjectId"), c("name"), c("mimeType"), c("size")].join(", ")}) on ${t} to authenticated;
grant all on ${t} to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with options.subjects, an unlisted type fails.
create or replace function ${fn("attachment_subject_readable")}(subject_type text, subject_id text, tenant ${id})
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select ${subjects.length === 0 ? "true" : `subject_type is null or ${subjectReadableSql}`}
$$;
revoke execute on function ${fn("attachment_subject_readable")}(text, text, ${id}) from public, anon;
grant execute on function ${fn("attachment_subject_readable")}(text, text, ${id}) to authenticated, service_role;

drop policy if exists "attachments_read" on ${t};
create policy "attachments_read" on ${t} for select to authenticated
  using (${can(c("tenant"), "read")} and ${fn("attachment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")}));
drop policy if exists "attachments_insert" on ${t};
create policy "attachments_insert" on ${t} for insert to authenticated
  with check (
    ${c("uploadedBy")} = (select auth.uid())
    and ${can(c("tenant"), "upload")}
    and ${fn("attachment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")})
  );
drop policy if exists "attachments_delete" on ${t};
create policy "attachments_delete" on ${t} for delete to authenticated
  using (${c("uploadedBy")} = (select auth.uid()) or ${can(c("tenant"), "manage")});

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a ${requireScan ? "clean" : "not infected"} file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists ${policy("insert")} on storage.objects;
drop policy if exists ${policy("select")} on storage.objects;
drop policy if exists ${policy("delete")} on storage.objects;
drop function if exists ${fn("attachment_object_allowed")}(text, text);
create or replace function ${fn("attachment_object_allowed")}(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${t} a
    where a.${c("bucket")} = attachment_object_allowed.bucket and a.${c("path")} = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a.${c("status")} = 'pending' and a.${c("uploadedAt")} is null and a.${c("uploadedBy")} = auth.uid()
        when 'select' then (${readable} and ${can(`a.${c("tenant")}`, "read")})
          or a.${c("uploadedBy")} = auth.uid() or ${can(`a.${c("tenant")}`, "manage")}
        when 'delete' then a.${c("uploadedBy")} = auth.uid() or ${can(`a.${c("tenant")}`, "manage")}
        else false
      end
  )
$$;
revoke execute on function ${fn("attachment_object_allowed")}(text, text, text) from public, anon;
grant execute on function ${fn("attachment_object_allowed")}(text, text, text) to authenticated, service_role;

-- Whether the caller sees the object's record through the table's own read
-- policy, which checks the subject. It runs as the caller (security invoker):
-- attachment_object_allowed runs as its owner, so it can't apply the subject
-- table's policies itself.
create or replace function ${fn("attachment_object_visible")}(bucket text, path text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from ${t} a
    where a.${c("bucket")} = attachment_object_visible.bucket and a.${c("path")} = attachment_object_visible.path
  )
$$;
revoke execute on function ${fn("attachment_object_visible")}(text, text) from public, anon;
grant execute on function ${fn("attachment_object_visible")}(text, text) to authenticated, service_role;

create policy ${policy("insert")} on storage.objects for insert to authenticated
  with check (bucket_id in (${bucketList}) and ${fn("attachment_object_allowed")}(bucket_id, name, 'insert'));
create policy ${policy("select")} on storage.objects for select to authenticated
  using (bucket_id in (${bucketList}) and ${fn("attachment_object_allowed")}(bucket_id, name, 'select')${
    subjects.length === 0
      ? ""
      : ` and ${fn("attachment_object_visible")}(bucket_id, name)`
  });
create policy ${policy("delete")} on storage.objects for delete to authenticated
  using (bucket_id in (${bucketList}) and ${fn("attachment_object_allowed")}(bucket_id, name, 'delete'));

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
  insert into ${t} as x (${[c("tenant"), c("bucket"), c("name"), c("mimeType"), c("size"), c("subjectType"), c("subjectId")].join(", ")})
  values (create_attachment.tenant, ${bucketFor}, create_attachment.name, lower(create_attachment.mime_type), create_attachment.size, create_attachment.subject_type, create_attachment.subject_id)
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
  insert into ${scans} (${sc("bucket")}, ${sc("path")}, ${sc("status")}, ${sc("detail")}, ${sc("scannedAt")})
  values (v_row.${c("bucket")}, v_row.${c("path")}, v_row.${c("status")}, v_row.${c("detail")}, now())
  on conflict (${sc("bucket")}, ${sc("path")}) do update
    set ${sc("status")} = excluded.${sc("status")}, ${sc("detail")} = excluded.${sc("detail")}, ${sc("scannedAt")} = excluded.${sc("scannedAt")};
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

-- The scan gate for any bucket: one row per scanned object, object_clean()
-- for storage policies, and set_object_scan() for the scanner. With
-- options.scanBuckets, a new object in those buckets gets a pending row and
-- writes object.uploaded for the scan job.
create table if not exists ${scans} (
  ${sc("bucket")} text not null,
  ${sc("path")} text not null,
  ${sc("status")} text not null default 'pending' check (${sc("status")} in ('pending', 'clean', 'infected', 'failed')),
  ${sc("detail")} text,
  ${sc("createdAt")} timestamptz not null default now(),
  ${sc("scannedAt")} timestamptz,
  primary key (${sc("bucket")}, ${sc("path")})
);
alter table ${scans} enable row level security;
revoke all on ${scans} from anon, authenticated;
grant all on ${scans} to service_role;

-- For storage policies: whether the object was scanned and found clean.
--   using (bucket_id = 'files' and better_supabase.object_clean(bucket_id, name) and ...)
create or replace function ${fn("object_clean")}(bucket text, path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${scans} s
    where s.${sc("bucket")} = object_clean.bucket and s.${sc("path")} = object_clean.path and s.${sc("status")} = 'clean'
  )
$$;

-- The scan row of an object, or null (service role).
create or replace function ${fn("object_scan")}(bucket text, path text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(s.*) from ${scans} s
  where s.${sc("bucket")} = object_scan.bucket and s.${sc("path")} = object_scan.path
$$;

-- Records a scan result for any object (service role). A clean or infected
-- object keeps its status, so a replayed job changes nothing.
create or replace function ${fn("set_object_scan")}(bucket text, path text, status text, detail text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${scans};
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_object_scan.status not in ('pending', 'clean', 'infected', 'failed') then
    raise exception 'status must be pending, clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  insert into ${scans} as s (${sc("bucket")}, ${sc("path")}, ${sc("status")}, ${sc("detail")}, ${sc("scannedAt")})
  values (set_object_scan.bucket, set_object_scan.path, set_object_scan.status, set_object_scan.detail,
    case when set_object_scan.status = 'pending' then null else now() end)
  on conflict (${sc("bucket")}, ${sc("path")}) do update
    set ${sc("status")} = excluded.${sc("status")}, ${sc("detail")} = excluded.${sc("detail")}, ${sc("scannedAt")} = excluded.${sc("scannedAt")}
    where s.${sc("status")} in ('pending', 'failed')
  returning * into v_row;
  if v_row.${sc("bucket")} is null then
    select * into v_row from ${scans} s where s.${sc("bucket")} = set_object_scan.bucket and s.${sc("path")} = set_object_scan.path;
  end if;
  return to_jsonb(v_row);
end;
$$;
${
  scanBuckets.length === 0
    ? `drop trigger if exists bs_object_scan_pending on storage.objects;`
    : `
create or replace function ${fn("object_scan_pending")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into ${scans} (${sc("bucket")}, ${sc("path")}) values (new.bucket_id, new.name)
  on conflict (${sc("bucket")}, ${sc("path")}) do update
    set ${sc("status")} = 'pending', ${sc("detail")} = null, ${sc("scannedAt")} = null, ${sc("createdAt")} = now();
  ${objectUploaded || "null;"}
  return null;
end;
$$;
revoke execute on function ${fn("object_scan_pending")}() from public, anon, authenticated;
drop trigger if exists bs_object_scan_pending on storage.objects;
create trigger bs_object_scan_pending
  after insert or update of version on storage.objects
  for each row when (new.bucket_id in (${scanBuckets.map(sqlString).join(", ")}))
  execute function ${fn("object_scan_pending")}();`
}
${cascades}
revoke execute on function ${fn("object_clean")}(text, text) from public, anon;
revoke execute on function ${fn("object_scan")}(text, text) from public, anon, authenticated;
revoke execute on function ${fn("set_object_scan")}(text, text, text, text) from public, anon, authenticated;
grant execute on function ${fn("object_clean")}(text, text) to authenticated, service_role;
grant execute on function ${fn("object_scan")}(text, text) to service_role;
grant execute on function ${fn("set_object_scan")}(text, text, text, text) to service_role;
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
      "sql.modules.attachments.options.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores",
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
  const subjects = subjectBuckets(
    subjectsOption(ctx, ["bucket", "allowedMimeTypes"]),
    bucket,
  );
  const rows = new Map<string, readonly string[]>([[bucket, mimeTypes]]);
  for (const entry of subjects) {
    if (!rows.has(entry.bucket)) rows.set(entry.bucket, entry.mimeTypes);
  }
  const values = [...rows].map(([id, types]) => {
    const mimeArray =
      types.length === 0
        ? "null"
        : `array[${types.map(sqlString).join(", ")}]::text[]`;
    return `(${sqlString(id)}, ${sqlString(id)}, false, ${String(maxSize)}, ${mimeArray})`;
  });
  return `insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ${values.join(",\n  ")}
on conflict (id) do nothing;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "attachment_object_allowed",
      args: ["text", "text", "text"],
      returns: "boolean",
    },
    { name: "object_clean", args: ["text", "text"], returns: "boolean" },
    {
      name: "set_object_scan",
      args: ["text", "text", "text", "text"],
      returns: "jsonb",
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
