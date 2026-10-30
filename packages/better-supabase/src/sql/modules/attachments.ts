import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";
import type { Subject } from "../subjects.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { readIfAny } from "../read-if-any.ts";
import {
  addExtraColumns,
  ensureCheck,
  extraFieldsArg,
  fail,
  lockTable,
  revokeTable,
  schemaPreamble,
  SERVICE_CALLER,
  withExtraFields,
} from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import {
  subjectAccess,
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import {
  attachmentInsertDefaults,
  columnOrNull,
  namedRowJson,
  scanColumns,
  statusFrom,
} from "./attachments-app.ts";
import {
  BUCKET,
  bucketInsert,
  bucketOptions,
  publicBucketsOf,
} from "./attachments-bucket.ts";
import {
  ATTACHMENTS_CONTRIBUTES,
  attachmentsContract,
} from "./attachments-contract.ts";
import { NAMES, RESERVED } from "./attachments-names.ts";
import {
  attachmentsOfflineSql,
  attachmentsOnlineSql,
} from "./attachments-offline.ts";
import { pathExpression, pathTemplate } from "./attachments-path.ts";
import {
  attachmentsTopicOf,
  attachmentsTopicSql,
} from "./attachments-topic.ts";
import { attachmentVersionsSql, versionPaths } from "./attachments-versions.ts";
import { authorLookup } from "./authors.ts";
import { moduleOperations } from "./permissions-model.ts";

const isText = (value: unknown): value is string => typeof value === "string";

interface SubjectBucket {
  readonly type: string;
  readonly bucket: string;
  readonly mimeTypes: readonly string[];
}

/**
 * The subjects with their own bucket or MIME types (`on.<type>.bucket`,
 * `.allowedMimeTypes`).
 */
function subjectBuckets(
  subjects: readonly (readonly [string, Subject])[],
  fallback: string,
): readonly SubjectBucket[] {
  return subjects.map(([type, subject]) => {
    const bucket = subject.extra["bucket"] ?? fallback;

    if (!isText(bucket) || !BUCKET.test(bucket)) {
      throw new TypeError(
        `blocks.attachments.on.${type}.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores`,
      );
    }

    const mimeTypes = subject.extra["allowedMimeTypes"] ?? [];

    if (!Array.isArray(mimeTypes) || !mimeTypes.every(isText)) {
      throw new TypeError(
        `blocks.attachments.on.${type}.allowedMimeTypes must be a list of MIME types`,
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
function scanBucketsOf(ctx: BlockSqlContext): readonly string[] {
  const buckets = ctx.list("scanBuckets", []);

  for (const bucket of buckets) {
    if (!BUCKET.test(bucket)) {
      throw new TypeError(
        `blocks.attachments.options.scanBuckets: "${bucket}" is not a bucket id`,
      );
    }
  }

  return buckets;
}

/** The argument types of `create_attachment`, before `fields`. */
const CREATE_ARGS = (id: string): string =>
  `${id}, text, text, bigint, text, text, jsonb, integer, integer, integer`;

/** A Storage bucket id: Supabase allows 1 to 100 characters. */
function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const t = ctx.table("attachments");
  const metadata = ctx.has("attachments", "metadata");
  const c = (logical: string): string => ctx.col("attachments", logical);
  const fn = (name: string): string => ctx.fn(name);
  const versions = ctx.table("versions");
  const vc = (logical: string): string => ctx.col("versions", logical);
  const { current, atCurrent } = versionPaths(c);
  const pathKey = sqlString(c("path").replaceAll('"', ""));

  // The row as JSON, with object_path set to the current version's path.
  const rowJson = (row: string): string =>
    ctx.owns("attachments")
      ? `(to_jsonb(${row}) || jsonb_build_object(${pathKey}, ${current(row)}))`
      : namedRowJson(ctx, "attachments", row, { path: current(row) });

  const has = (logical: string): boolean => ctx.has("attachments", logical);
  const sizes = ["width", "height", "pages"].filter(has);

  const or = (logical: string, row: string): string =>
    columnOrNull(ctx, "attachments", row, logical);

  const permissions = moduleOperations("attachments");
  const { bucket, maxSize, mimeTypes } = bucketOptions(ctx);
  const offline = ctx.flag("offline", false);
  const requireScan = ctx.flag("requireScan", !offline);

  const subjects = subjectsOption(
    ctx,
    ["bucket", "allowedMimeTypes", "permissions", "scope"],
    { tenantless: true },
  );

  // Subject types without a tenant: their files have no organization_id, and
  // the subject's own policies decide who reads and uploads them.
  const tenantless = subjects
    .filter(([, subject]) => subject.tenant === false)
    .map(([type]) => type);

  // The column comment records what the expression was built from, so a
  // changed template, or files without a tenant, rewrite the column.
  const qualifiedTable = `${ctx.tableName("attachments").schema}.${ctx.tableName("attachments").name}`;
  const pathColumn = c("path").replaceAll('"', "");
  const pathComment = `better-supabase path: ${pathTemplate(ctx)}${tenantless.length > 0 ? " (tenantless)" : ""}`;

  const access = subjectAccess(ctx, {
    subjects,
    actions: ["read", "upload", "manage"],
    permission: (action) => ctx.permission(action, permissions[action]),
    provider: layout.accessProvider,
    guest: { read: "read", upload: "upload" },
  });

  const orTenantless = (tenant: string, check: string): string =>
    tenantless.length === 0 ? check : `(${tenant} is null or ${check})`;

  // row is the alias of the attachments row, or "" for the policies.
  const at = (row: string, logical: string): string =>
    row === "" ? c(logical) : `${row}.${c(logical)}`;

  const inTenant = (row: string, action: keyof typeof permissions): string =>
    orTenantless(
      at(row, "tenant"),
      access.canOn(
        at(row, "tenant"),
        at(row, "subjectType"),
        at(row, "subjectId"),
        action,
      ),
    );

  // The policy form of inTenant: the tenant_ids_with set runs once per
  // statement instead of can() once per row.
  const memberIn = (action: keyof typeof permissions): string =>
    orTenantless(
      c("tenant"),
      access.memberOn(c("tenant"), c("subjectType"), c("subjectId"), action),
    );

  const canManage = (row: string): string =>
    access.canOn(
      at(row, "tenant"),
      at(row, "subjectType"),
      at(row, "subjectId"),
      "manage",
    );

  const perSubject = subjectBuckets(subjects, bucket);

  const buckets = [
    ...new Set([bucket, ...perSubject.map((entry) => entry.bucket)]),
  ];

  const bucketList = buckets.map(sqlString).join(", ");
  publicBucketsOf(ctx, buckets);
  const extras = ctx.extraColumns("attachments", RESERVED);

  const json = (row: string): string =>
    withExtraFields(rowJson(row), row, extras);

  const authors = authorLookup(ctx, {
    name: "attachment_authors",
    table: t,
    id: c("id"),
    user: c("uploadedBy"),
    visible: orTenantless(
      at("y", "tenant"),
      access.memberOn(
        at("y", "tenant"),
        at("y", "subjectType"),
        at("y", "subjectId"),
        "read",
      ),
    ),
    what: "The name and avatar of each attachment's uploader, keyed by\n-- attachment id, for the attachments of ids the caller may read.",
  });

  const listJson = (row: string): string => {
    const base = withExtraFields(rowJson(row), row, extras);

    return authors === undefined
      ? base
      : authors.attach(base, "m.authors", row);
  };

  const bucketFor = perSubject.some((entry) => entry.bucket !== bucket)
    ? `case create_attachment.subject_type ${perSubject
        .filter((entry) => entry.bucket !== bucket)
        .map(
          (entry) =>
            `when ${sqlString(entry.type)} then ${sqlString(entry.bucket)}`,
        )
        .join(" ")} else ${sqlString(bucket)} end`
    : sqlString(bucket);

  // Inserts only the extra columns attrs names, so the others keep their
  // default, under the caller's column grants and policies.
  const insertColumns = [
    c("tenant"),
    c("bucket"),
    c("name"),
    c("mimeType"),
    c("size"),
    c("subjectType"),
    c("subjectId"),
    ...(metadata ? [c("metadata")] : []),
    ...sizes.map(c),
  ];

  const createWithExtras = `
declare
  v_row ${t};
  v_columns text;
begin
  v_row := jsonb_populate_record(null::${t}, (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each(coalesce(create_attachment.fields, '{}'::jsonb)) as e (field_key, field_value)
    where e.field_key = any (array[${extras.map((extra) => sqlString(extra.name)).join(", ")}])
  ));
  v_row.${c("tenant")} := create_attachment.tenant;
  v_row.${c("bucket")} := ${bucketFor};
  v_row.${c("name")} := create_attachment.name;
  v_row.${c("mimeType")} := lower(create_attachment.mime_type);
  v_row.${c("size")} := create_attachment.size;
  v_row.${c("subjectType")} := create_attachment.subject_type;
  v_row.${c("subjectId")} := create_attachment.subject_id;${metadata ? `\n  v_row.${c("metadata")} := coalesce(create_attachment.metadata, '{}');` : ""}
${sizes.map((logical) => `  v_row.${c(logical)} := create_attachment.${logical};\n`).join("")}  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array[${insertColumns.map((column) => sqlString(column)).join(", ")}]
    || array(select quote_ident(k) from jsonb_object_keys(coalesce(create_attachment.fields, '{}'::jsonb)) as k
      where k = any (array[${extras.map((extra) => sqlString(extra.name)).join(", ")}]))) as column_name;
  execute format('insert into ${t.replaceAll("'", "''")} as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return ${json("v_row")};
end;`;

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
      ? `alter table ${t} drop constraint if exists bsb_attachments_mime_type;`
      : ensureCheck(
          t,
          "bsb_attachments_mime_type",
          mimeRules.map((rule) => `(${rule})`).join(" and "),
        );

  const subjectReadableSql = subjectReadable(
    ctx,
    subjects,
    {
      type: "attachment_subject_readable.subject_type",
      id: "attachment_subject_readable.subject_id",
      tenant: "attachment_subject_readable.tenant",
    },
    { guest: true },
  );

  const cascades = subjectCascades(
    ctx,
    subjects,
    `delete from ${t} x where x.${c("subjectType")} = v_type and x.${c("subjectId")} = v_id;`,
  );

  const scans = ctx.table("scans");
  const sc = (logical: string): string => ctx.col("scans", logical);
  const scanBuckets = scanBucketsOf(ctx);

  const {
    detail: scanDetail,
    set: scanSet,
    pending: scanPending,
    json: scanJson,
  } = scanColumns(ctx);

  const insertDefaults = attachmentInsertDefaults(ctx);

  const objectUploaded = ctx.record({
    type: "object.uploaded",
    payload: `jsonb_build_object('bucket', new.bucket_id, 'path', new.name)`,
    subject: `'objects/' || new.bucket_id || '/' || new.name`,
    tenant: "null",
    audit: false,
  });

  const readable = (row: string, col: (logical: string) => string): string =>
    requireScan
      ? `${row}.${col("status")} = 'clean'`
      : `${row}.${col("status")} in ('pending', 'clean', 'failed')`;

  const bucketLiteral = sqlString(bucket);

  const uploaded = ctx.record({
    type: "attachment.uploaded",
    payload: `jsonb_build_object('attachmentId', v_row.${c("id")}, 'organizationId', v_row.${c("tenant")}::text, 'subjectType', v_row.${c("subjectType")}, 'subjectId', v_row.${c("subjectId")}, 'uploadedBy', v_row.${c("uploadedBy")}, 'mimeType', v_row.${c("mimeType")}, 'size', v_row.${c("size")}, 'version', v_row.${c("version")})`,
    subject: `'attachments/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    audit: {
      category: "data",
      targetType: "attachment",
      recordId: `v_row.${c("id")}::text`,
    },
  });

  const scanned = ctx.record({
    type: "attachment.scanned",
    payload: `jsonb_build_object('attachmentId', v_row.${c("id")}, 'organizationId', v_row.${c("tenant")}::text, 'status', v_row.${c("status")}, 'uploadedBy', v_row.${c("uploadedBy")})`,
    subject: `'attachments/' || v_row.${c("id")}::text`,
    tenant: `v_row.${c("tenant")}`,
    key: `'attachment.scanned:' || v_row.${c("id")}::text || ':' || v_row.${c("status")}`,
    audit: false,
  });

  // Who may change a file's versions: its uploader with attachments.upload,
  // attachments.manage, or the service role.
  const versioned = attachmentVersionsSql(ctx, {
    id,
    tenantless: tenantless.length > 0,
    json,
    mayVersion: `(coalesce(v_row.${c("uploadedBy")} = auth.uid(), false) and ${inTenant("v_row", "upload")}) or ${canManage("v_row")} or (${SERVICE_CALLER})`,
  });

  const policy = (name: string): string => sqlIdent(`bsb_attachments_${name}`);

  const offlineSql = offline
    ? attachmentsOfflineSql(ctx, {
        t,
        c,
        versions,
        vc,
        current,
        atCurrent,
        buckets,
        requireScan,
        uploaded,
      })
    : undefined;

  return `${schemaPreamble(ctx)}
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the ${bucket} bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("subjectType")} text check (${c("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${c("subjectId")} text check (length(${c("subjectId")}) between 1 and 200),
  ${c("bucket")} text not null default ${bucketLiteral},
  ${c("path")} text,
  ${c("name")} text not null check (length(${c("name")}) between 1 and 255),
  ${c("mimeType")} text not null check (${c("mimeType")} ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  ${c("size")} bigint not null,
  ${c("status")} text not null default 'pending' check (${c("status")} in ('pending', 'clean', 'infected', 'failed')),${has("detail") ? `\n  ${c("detail")} text,` : ""}
  ${c("uploadedBy")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("createdAt")} timestamptz not null default clock_timestamp(),
  ${c("uploadedAt")} timestamptz,${has("scannedAt") ? `\n  ${c("scannedAt")} timestamptz,` : ""}
  check ((${c("subjectType")} is null) = (${c("subjectId")} is null))
);
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table ${t} add column if not exists ${c("version")} integer not null default 1 check (${c("version")} >= 1);${sizes
    .map(
      (logical) =>
        `\nalter table ${t} add column if not exists ${c(logical)} integer check (${c(logical)} > 0);`,
    )
    .join("")}${
    metadata
      ? `
-- App data about the file (a caption, the source, a page count), set on create.
alter table ${t} add column if not exists ${c("metadata")} jsonb not null default '{}' check (jsonb_typeof(${c("metadata")}) = 'object');`
      : ""
  }
-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.${
    ctx.owns("attachments")
      ? `
-- ${c("path")} is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = ${sqlString(qualifiedTable)}::regclass
      and attname = ${sqlString(pathColumn)} and attgenerated <> ''
  ) then
    alter table ${t} alter column ${c("path")} drop expression;
  end if;
end;
$$;
create or replace function ${fn("attachment_object_path")}()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select ${pathExpression(ctx, tenantless.length > 0)} into new.${c("path")} from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function ${fn("attachment_object_path")}() from public, anon, authenticated;
drop trigger if exists bsb_attachments_object_path on ${t};
create trigger bsb_attachments_object_path
  before insert or update on ${t}
  for each row execute function ${fn("attachment_object_path")}();
-- options.path: the column comment records the template the path was built
-- from, so a changed template rewrites every row's path.
do $$
declare
  v_current text := coalesce(
    col_description(${sqlString(qualifiedTable)}::regclass,
      (select attnum from pg_attribute where attrelid = ${sqlString(qualifiedTable)}::regclass and attname = ${sqlString(pathColumn)})::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from ${sqlString(pathComment)} then
    update ${t} set ${c("path")} = null;
  end if;
end;
$$;`
      : ""
  }
${
  tenantless.length === 0
    ? ""
    : `alter table ${t} alter column ${c("tenant")} drop not null;
${ensureCheck(t, "bsb_attachments_tenant", `${c("tenant")} is not null or coalesce(${c("subjectType")} in (${tenantless.map(sqlString).join(", ")}), false)`)}
`
}${ctx.owns("attachments") ? `comment on column ${t}.${c("path")} is ${sqlString(pathComment)};\n` : ""}alter table ${t} alter column ${c("bucket")} set default ${bucketLiteral};
${ensureCheck(t, "bsb_attachments_bucket", `${c("bucket")} in (${bucketList})`, { notValid: true })}
${ensureCheck(t, "bsb_attachments_size", `${c("size")} between 0 and ${String(maxSize)}`)}
${mimeCheck}
create unique index if not exists ${ctx.naming.rename("attachments_object_idx")} on ${t} (${c("bucket")}, ${c("path")});
create index if not exists ${ctx.naming.rename("attachments_subject_idx")} on ${t} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")});
create index if not exists ${ctx.naming.rename("attachments_uploaded_by_idx")} on ${t} (${c("uploadedBy")});${addExtraColumns(t, extras)}
alter table ${t} enable row level security;
${revokeTable(t)}
grant select, delete on ${t} to authenticated;
grant insert (${[...(offline ? [c("id")] : []), c("tenant"), c("bucket"), c("subjectType"), c("subjectId"), c("name"), c("mimeType"), c("size"), ...(metadata ? [c("metadata")] : []), ...sizes.map(c), ...extras.map((extra) => extra.ident)].join(", ")}) on ${t} to authenticated;
grant all on ${t} to service_role;
${insertDefaults}-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
-- plpgsql, so a subject table a later module creates (messages) binds late.
create or replace function ${fn("attachment_subject_readable")}(subject_type text, subject_id text, tenant ${id})
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return ${subjects.length === 0 ? "true" : `attachment_subject_readable.subject_type is null or ${subjectReadableSql}`};
end;
$$;
revoke execute on function ${fn("attachment_subject_readable")}(text, text, ${id}) from public, anon;
grant execute on function ${fn("attachment_subject_readable")}(text, text, ${id}) to authenticated, service_role;

${renderPolicy(makePolicy({ table: t, name: sqlIdent(`${ctx.tableName("attachments").name}_read`), command: "select", roles: ["authenticated"], using: `${memberIn("read")} and ${fn("attachment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")})` }), { drop: true, target: t })}
${renderPolicy(
  makePolicy({
    table: t,
    name: sqlIdent(`${ctx.tableName("attachments").name}_insert`),
    command: "insert",
    roles: ["authenticated"],
    check: `${c("uploadedBy")} = (select auth.uid())
    and ${inTenant("", "upload")}
    and ${fn("attachment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")})`,
  }),
  { drop: true, target: t },
)}
${renderPolicy(makePolicy({ table: t, name: sqlIdent(`${ctx.tableName("attachments").name}_delete`), command: "delete", roles: ["authenticated"], using: `${c("uploadedBy")} = (select auth.uid()) or ${access.memberOn(c("tenant"), c("subjectType"), c("subjectId"), "manage")}` }), { drop: true, target: t })}
${attachmentsTopicSql(ctx, { t, c, read: ctx.permission("read", permissions.read) })}
${versioned.table}
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
    where a.${c("bucket")} = attachment_object_allowed.bucket and ${atCurrent("a", "attachment_object_allowed.path")}
      and case attachment_object_allowed.action
        when 'insert' then a.${c("status")} = 'pending' and a.${c("uploadedAt")} is null and a.${c("uploadedBy")} = auth.uid()
        when 'select' then (${readable("a", c)} and ${inTenant("a", "read")})
          or a.${c("uploadedBy")} = auth.uid() or ${canManage("a")}
        when 'delete' then a.${c("uploadedBy")} = auth.uid() or ${canManage("a")}
        else false
      end
  ) or exists (
    select 1 from ${versions} v
    join ${t} a on a.${c("id")} = v.${vc("attachment")}
    where v.${vc("bucket")} = attachment_object_allowed.bucket and v.${vc("path")} = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (${readable("v", vc)} and ${inTenant("a", "read")})
          or v.${vc("uploadedBy")} = auth.uid() or ${canManage("a")}
        when 'delete' then a.${c("uploadedBy")} = auth.uid() or ${canManage("a")}
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
    where a.${c("bucket")} = attachment_object_visible.bucket and ${atCurrent("a", "attachment_object_visible.path")}
  ) or exists (
    select 1 from ${versions} v
    where v.${vc("bucket")} = attachment_object_visible.bucket and v.${vc("path")} = attachment_object_visible.path
  )
$$;
revoke execute on function ${fn("attachment_object_visible")}(text, text) from public, anon;
grant execute on function ${fn("attachment_object_visible")}(text, text) to authenticated, service_role;
${offlineSql?.sql ?? attachmentsOnlineSql(ctx, t)}

${renderPolicy(makePolicy({ table: "storage.objects", name: policy("insert"), command: "insert", roles: ["authenticated"], check: `bucket_id in (${bucketList}) and ${fn("attachment_object_allowed")}(bucket_id, name, 'insert')` }), { target: "storage.objects" })}
${renderPolicy(
  makePolicy({
    table: "storage.objects",
    name: policy("select"),
    command: "select",
    roles: ["authenticated"],
    using: `bucket_id in (${bucketList}) and ${fn("attachment_object_allowed")}(bucket_id, name, 'select')${
      subjects.length === 0
        ? ""
        : ` and ${fn("attachment_object_visible")}(bucket_id, name)`
    }`,
  }),
  { target: "storage.objects" },
)}
${renderPolicy(makePolicy({ table: "storage.objects", name: policy("delete"), command: "delete", roles: ["authenticated"], using: `bucket_id in (${bucketList}) and ${offlineSql === undefined ? `${fn("attachment_object_allowed")}(bucket_id, name, 'delete')` : offlineSql.deleteCheck}` }), { target: "storage.objects" })}

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists ${fn("create_attachment")}(${id}, text, text, bigint, text, text);
drop function if exists ${fn("create_attachment")}(${id}, text, text, bigint, text, text, jsonb);
drop function if exists ${fn("create_attachment")}(${id}, text, text, bigint, text, text, jsonb, jsonb);
${extraFieldsArg(extras).drop(fn("create_attachment"), CREATE_ARGS(id))}
create or replace function ${fn("create_attachment")}(
  tenant ${id},
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null${extraFieldsArg(extras).param}
)
returns jsonb
language ${extras.length === 0 ? "sql" : "plpgsql"}
security invoker
set search_path = ''
as $$${
    extras.length === 0
      ? `
  insert into ${t} as x (${insertColumns.join(", ")})
  values (create_attachment.tenant, ${bucketFor}, create_attachment.name, lower(create_attachment.mime_type), create_attachment.size, create_attachment.subject_type, create_attachment.subject_id${metadata ? ", coalesce(create_attachment.metadata, '{}')" : ""}${sizes.map((logical) => `, create_attachment.${logical}`).join("")})
  returning ${rowJson("x")}`
      : createWithExtras
  }
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
    ${fail("ATTACHMENT_NOT_FOUND", "No pending attachment of yours has this id", "P0002")}
  end if;
  if v_row.${c("uploadedAt")} is not null then
    return ${json("v_row")};
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row.${c("bucket")} and o.name = ${current("v_row")};
  if not found then
    ${fail("ATTACHMENT_NOT_UPLOADED", "The file was not uploaded yet", "P0002")}
  end if;
  update ${t} a set
    ${c("uploadedAt")} = now(),
    ${c("size")} = coalesce((v_meta ->> 'size')::bigint, a.${c("size")}),
    ${c("mimeType")} = coalesce(lower(v_meta ->> 'mimetype'), a.${c("mimeType")})${requireScan ? "" : `,\n    ${c("status")} = 'clean'`}
  where a.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${uploaded}
  return ${json("v_row")};
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
    ${fail("ATTACHMENT_FORBIDDEN", "Only the service role records scan results")}
  end if;
  if set_attachment_status.status not in ('clean', 'infected', 'failed') then
    ${fail("ATTACHMENT_STATUS_UNKNOWN", "status must be clean, infected or failed", "22023")}
  end if;
  update ${t} a set
    ${[
      `${c("status")} = ${ctx.cast("attachments", "status", "set_attachment_status.status")}`,
      ...(has("detail")
        ? [`${c("detail")} = set_attachment_status.detail`]
        : []),
      ...(has("scannedAt") ? [`${c("scannedAt")} = now()`] : []),
    ].join(",\n    ")}
  where a.${c("id")} = set_attachment_status.id
    and a.${c("uploadedAt")} is not null
    and a.${c("status")} in ('pending', 'failed')
  returning * into v_row;
  if v_row.${c("id")} is null then
    select * into v_row from ${t} a where a.${c("id")} = set_attachment_status.id;
    return case when v_row.${c("id")} is null then null else ${json("v_row")} end;
  end if;
  insert into ${scans} (${sc("bucket")}, ${sc("path")}, ${sc("status")}${scanDetail ? `, ${sc("detail")}` : ""}, ${sc("scannedAt")})
  values (v_row.${c("bucket")}, ${current("v_row")}, ${statusFrom(ctx, "scans", "attachments", `v_row.${c("status")}`)}${scanDetail ? `, ${or("detail", "v_row")}` : ""}, now())
  on conflict (${sc("bucket")}, ${sc("path")}) do update
    set ${scanSet};
  ${scanned}
  return ${json("v_row")};
end;
$$;${authors?.sql ?? ""}

create or replace function ${fn("list_attachments")}(tenant ${id}, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
${ctx.readVolatility()}
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from ${t} y
    where y.${c("tenant")} is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y.${c("subjectType")} = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y.${c("subjectId")} = list_attachments.subject_id)
  )${
    authors === undefined
      ? ""
      : `,
  m as (select ${authors.call(`array(select p.${c("id")} from page p)`)} as authors)`
  }
  select coalesce(jsonb_agg(${listJson("a")} order by a.${c("createdAt")}, a.${c("id")}), '[]'::jsonb) into v_files
  from page a${authors === undefined ? "" : ", m"};${readIfAny(
    ctx.read(
      "list_attachments.subject_type",
      "list_attachments.subject_id",
      "list_attachments",
    ),
    "v_files",
    "list_attachments.subject_type is not null and list_attachments.subject_id is not null",
  )}
  return v_files;
end;
$$;

create or replace function ${fn("get_attachment")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${json("a")} from ${t} a where a.${c("id")} = get_attachment.id
$$;

${versioned.functions}

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
  ${sc("status")} text not null default 'pending' check (${sc("status")} in ('pending', 'clean', 'infected', 'failed')),${scanDetail ? `\n  ${sc("detail")} text,` : ""}${ctx.has("scans", "createdAt") ? `\n  ${sc("createdAt")} timestamptz not null default now(),` : ""}
  ${sc("scannedAt")} timestamptz,
  primary key (${sc("bucket")}, ${sc("path")})
);${ctx.owns("scans") ? "" : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("scans").name}_object_key`)} on ${scans} (${sc("bucket")}, ${sc("path")});`}
${lockTable(scans)}

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
  select ${ctx.owns("scans") ? "to_jsonb(s.*)" : scanJson("s")} from ${scans} s
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
    ${fail("ATTACHMENT_FORBIDDEN", "Only the service role records scan results")}
  end if;
  if set_object_scan.status not in ('pending', 'clean', 'infected', 'failed') then
    ${fail("ATTACHMENT_STATUS_UNKNOWN", "status must be pending, clean, infected or failed", "22023")}
  end if;
  insert into ${scans} as s (${sc("bucket")}, ${sc("path")}, ${sc("status")}${scanDetail ? `, ${sc("detail")}` : ""}, ${sc("scannedAt")})
  values (set_object_scan.bucket, set_object_scan.path, ${ctx.cast("scans", "status", "set_object_scan.status")}${scanDetail ? ", set_object_scan.detail" : ""},
    case when set_object_scan.status = 'pending' then null else now() end)
  on conflict (${sc("bucket")}, ${sc("path")}) do update
    set ${scanSet}
    where s.${sc("status")} in ('pending', 'failed')
  returning * into v_row;
  if v_row.${sc("bucket")} is null then
    select * into v_row from ${scans} s where s.${sc("bucket")} = set_object_scan.bucket and s.${sc("path")} = set_object_scan.path;
  end if;
  return ${scanJson("v_row")};
end;
$$;
${
  scanBuckets.length === 0
    ? `drop trigger if exists bsb_object_scan_pending on storage.objects;`
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
    set ${scanPending};
  ${objectUploaded}
  return null;
end;
$$;
revoke execute on function ${fn("object_scan_pending")}() from public, anon, authenticated;
drop trigger if exists bsb_object_scan_pending on storage.objects;
create trigger bsb_object_scan_pending
  after insert or update of version on storage.objects
  for each row when (new.bucket_id in (${scanBuckets.map(sqlString).join(", ")}))
  execute function ${fn("object_scan_pending")}();`
}
${cascades}${subjectMergeHandler(ctx, subjects, moveSubjectRows({ table: t, type: c("subjectType"), id: c("subjectId") }, "v_type"))}
revoke execute on function ${fn("object_clean")}(text, text) from public, anon;
revoke execute on function ${fn("object_scan")}(text, text) from public, anon, authenticated;
revoke execute on function ${fn("set_object_scan")}(text, text, text, text) from public, anon, authenticated;
grant execute on function ${fn("object_clean")}(text, text) to authenticated, service_role;
grant execute on function ${fn("object_scan")}(text, text) to service_role;
grant execute on function ${fn("set_object_scan")}(text, text, text, text) to service_role;
revoke execute on function ${fn("create_attachment")}(${CREATE_ARGS(id)}${extraFieldsArg(extras).type}) from public, anon;
revoke execute on function ${fn("confirm_attachment")}(uuid) from public, anon;
revoke execute on function ${fn("set_attachment_status")}(uuid, text, text) from public, anon, authenticated;
revoke execute on function ${fn("list_attachments")}(${id}, text, text) from public, anon;
revoke execute on function ${fn("get_attachment")}(uuid) from public, anon;
revoke execute on function ${fn("delete_attachment")}(uuid) from public, anon;
grant execute on function ${fn("create_attachment")}(${CREATE_ARGS(id)}${extraFieldsArg(extras).type}) to authenticated, service_role;
grant execute on function ${fn("confirm_attachment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("set_attachment_status")}(uuid, text, text) to service_role;
grant execute on function ${fn("list_attachments")}(${id}, text, text) to authenticated, service_role;
grant execute on function ${fn("get_attachment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("delete_attachment")}(uuid) to authenticated, service_role;`;
}

// An existing bucket keeps its size limit and MIME types.
function data(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const { bucket, maxSize, mimeTypes } = bucketOptions(ctx);

  const subjects = subjectBuckets(
    subjectsOption(
      ctx,
      ["bucket", "allowedMimeTypes", "permissions", "scope"],
      { tenantless: true },
    ),
    bucket,
  );

  const rows = new Map<string, readonly string[]>([[bucket, mimeTypes]]);

  for (const entry of subjects) {
    if (!rows.has(entry.bucket)) {
      rows.set(entry.bucket, entry.mimeTypes);
    }
  }

  return bucketInsert(ctx, rows, maxSize);
}

export const ATTACHMENTS: BlockSqlDefinition = {
  contributes: ATTACHMENTS_CONTRIBUTES,
  internal: [
    "attachment_authors",
    "attachment_subject_readable",
    "attachment_object_allowed",
    "attachment_object_visible",
    "attachment_object_queued",
    "object_clean",
  ],
  name: "attachments",
  scopes: ["tenant"],
  title: "Attachments",
  description:
    "Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.",
  requires: ["memberships", "permissions"],
  integrates: ["profiles"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 7,
  upgrades: [
    {
      from: 1,
      description:
        "Attachments keep metadata; create_attachment takes it as a seventh argument.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("create_attachment")}(${ctx.idType}, text, text, bigint, text, text);`,
    },
    {
      from: 2,
      description:
        "With profiles, list_attachments returns each file's uploader with a name and avatar.",
      sql: () => "",
    },
    {
      from: 3,
      description:
        "Files keep versions (replace_attachment, restore_attachment_version) and a width, height and page count; create_attachment takes them after metadata.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "options.publicBuckets makes chosen attachment buckets public, and the data file sets each bucket's public flag on every run.",
      sql: () => "",
    },
    {
      from: 5,
      description:
        "options.offline takes client ids, marks an upload done from a storage trigger and queues a deleted record's objects in attachment_cleanup; options.path takes {ext}.",
      sql: () => "",
    },
    {
      from: 6,
      description:
        "object_path is a plain column a trigger fills, so logical replication sends it, and attachments broadcast changed to <topic>:<tenant> (options.topic, default attachments) when a tenant's files change.",
      sql: () => "",
    },
  ],
  names: NAMES,
  topics: (ctx) => [`${attachmentsTopicOf(ctx)}:{tenant}`],
  contract: (ctx) =>
    attachmentsContract(
      ctx,
      extraFieldsArg(ctx.extraColumns("attachments", RESERVED)).contract,
    ),
  build,
  data,
};
