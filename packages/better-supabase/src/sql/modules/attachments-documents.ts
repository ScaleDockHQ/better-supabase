import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  ensureCheck,
  fail,
  lockTable,
  SERVICE_CALLER,
  raise,
  serviceGrant,
} from "../shared.ts";

/** The entity `import_upsert_batch` takes for attachment records. */
const ATTACHMENT_IMPORT_ENTITY = "attachment";

/** The field types a document type can declare. */
const DOCUMENT_FIELD_TYPES = [
  "text",
  "number",
  "amount",
  "date",
  "expiry",
  "boolean",
  "select",
] as const;

const KEY_PATTERN = "^[a-z][a-z0-9_]{0,62}$";
const SOURCE_PATTERN = /^[a-z0-9][a-z0-9_.:/-]{0,99}$/;

/** The storage states of an attachment record. */
const STORAGE_STATUSES = ["stored", "pending_upload", "missing"] as const;

/**
 * Whether the module renders document types and the metadata-first columns:
 * only on the table it creates, because an app's own table keeps its own
 * shape.
 */
export function documentsOn(ctx: BlockSqlContext): boolean {
  return (
    ctx.mode !== "custom" &&
    ctx.owns("attachments") &&
    ["documentType", "source", "externalId", "storage", "sourcePath"].every(
      (column) => ctx.has("attachments", column),
    )
  );
}

/** Whether the document types table and its functions render. */
export function typesOn(ctx: BlockSqlContext): boolean {
  return ctx.mode !== "custom";
}

/** Whether `import_attachment` is rendered. */
export function attachmentImportsOn(ctx: BlockSqlContext): boolean {
  return (
    documentsOn(ctx) &&
    ctx.installed("imports") &&
    ctx.of("imports").mode !== "custom"
  );
}

/** `options.sources`: the sources callers may name next to the import sources. */
function sourcesOf(ctx: BlockSqlContext): readonly string[] {
  const sources = ctx.list("sources", []);

  for (const source of sources) {
    if (!SOURCE_PATTERN.test(source)) {
      throw new TypeError(
        `blocks.attachments.options.sources: "${source}" must be 1 to 100 lowercase letters, digits, dots, colons, slashes, dashes or underscores`,
      );
    }
  }

  return sources;
}

/** What `contributes.imports` returns: the `attachment` target. */
export function attachmentImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (!attachmentImportsOn(own)) {
    return [];
  }

  return [
    {
      entity: ATTACHMENT_IMPORT_ENTITY,
      subjectType: ATTACHMENT_IMPORT_ENTITY,
      write: own.fn("import_attachment").replaceAll('"', ""),
    },
  ];
}

const textArray = (values: readonly string[]): string =>
  values.length === 0
    ? "array[]::text[]"
    : `array[${values.map((value) => sqlString(value)).join(", ")}]::text[]`;

/**
 * The document types table, the validators that check a type's field schema and
 * a record's metadata against it, and the functions that manage the types. It
 * renders before the attachments table, which references it.
 */
export function documentTypesSql(
  ctx: BlockSqlContext,
  parts: { readonly manage: string; readonly read: string },
): string {
  const types = ctx.table("documentTypes");
  const d = (logical: string): string => ctx.col("documentTypes", logical);
  const id = ctx.idType;

  const fieldTypes = DOCUMENT_FIELD_TYPES.map((type) => sqlString(type)).join(
    ", ",
  );

  return `
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types ${DOCUMENT_FIELD_TYPES.join(", ")}.
create table if not exists ${types} (
  ${d("id")} uuid primary key default gen_random_uuid(),
  ${d("tenant")} ${id} not null,
  ${d("key")} text not null check (${d("key")} ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  ${d("name")} text not null check (length(btrim(${d("name")})) between 1 and 200),
  ${d("fields")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${d("fields")}) = 'object'),
  ${d("createdAt")} timestamptz not null default now(),
  ${d("updatedAt")} timestamptz not null default now(),
  unique (${d("tenant")}, ${d("key")})
);${ctx.owns("documentTypes") ? "" : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("documentTypes").name}_key`)} on ${types} (${d("tenant")}, ${d("key")});`}
${lockTable(types, { read: true })}
${renderPolicy(makePolicy({ table: types, name: sqlIdent(`${ctx.tableName("documentTypes").name}_read`), command: "select", roles: ["authenticated"], using: ctx.scope.check(d("tenant"), parts.read) }), { drop: true, target: types })}

-- The reason a document type's field schema is invalid, or null.
create or replace function ${ctx.fn("attachment_schema_error")}(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '${KEY_PATTERN}' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in (${fieldTypes}) then
      return v_key || ' needs one of the types ${DOCUMENT_FIELD_TYPES.join(", ")}';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function ${ctx.fn("attachment_fields_error")}(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function ${ctx.fn("attachment_schema_error")}(jsonb) from public, anon;
revoke execute on function ${ctx.fn("attachment_fields_error")}(jsonb, jsonb) from public, anon;
grant execute on function ${ctx.fn("attachment_schema_error")}(jsonb) to authenticated, service_role;
grant execute on function ${ctx.fn("attachment_fields_error")}(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function ${ctx.fn("define_attachment_document_type")}(tenant ${id}, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${types};
  v_error text;
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("define_attachment_document_type.tenant", parts.manage)}) then
    ${fail("ATTACHMENT_FORBIDDEN", "not allowed to manage document types")}
  end if;
  v_error := ${ctx.fn("attachment_schema_error")}(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    ${raise("%", "22023", "ATTACHMENT_DOCUMENT_SCHEMA_INVALID", "v_error")}
  end if;
  insert into ${types} as t (${d("tenant")}, ${d("key")}, ${d("name")}, ${d("fields")})
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict (${d("tenant")}, ${d("key")}) do update
    set ${d("name")} = excluded.${d("name")}, ${d("fields")} = excluded.${d("fields")}, ${d("updatedAt")} = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function ${ctx.fn("list_attachment_document_types")}(tenant ${id})
returns jsonb
language sql
${ctx.readVolatility()}
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.${d("key")}), '[]'::jsonb)
  from ${types} t
  where t.${d("tenant")} = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function ${ctx.fn("delete_attachment_document_type")}(tenant ${id}, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (${SERVICE_CALLER} or ${ctx.scope.can("delete_attachment_document_type.tenant", parts.manage)}) then
    ${fail("ATTACHMENT_FORBIDDEN", "not allowed to manage document types")}
  end if;
  delete from ${types} t
  where t.${d("tenant")} = delete_attachment_document_type.tenant and t.${d("key")} = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  ${fail("ATTACHMENT_DOCUMENT_TYPE_IN_USE", "attachments still use this document type", "23503")}
end;
$$;
revoke execute on function ${ctx.fn("define_attachment_document_type")}(${id}, text, text, jsonb) from public, anon;
revoke execute on function ${ctx.fn("list_attachment_document_types")}(${id}) from public, anon;
revoke execute on function ${ctx.fn("delete_attachment_document_type")}(${id}, text) from public, anon;
grant execute on function ${ctx.fn("define_attachment_document_type")}(${id}, text, text, jsonb) to authenticated, service_role;
grant execute on function ${ctx.fn("list_attachment_document_types")}(${id}) to authenticated, service_role;
grant execute on function ${ctx.fn("delete_attachment_document_type")}(${id}, text) to authenticated, service_role;
`;
}

/**
 * The columns the attachments table gains: its document type, where the record
 * came from (`source` and `external_id`, unique per organization), the storage
 * status and the path in the source system.
 */
export function documentColumnsSql(
  ctx: BlockSqlContext,
  t: string,
  c: (logical: string) => string,
): string {
  const types = ctx.table("documentTypes");

  const statuses = STORAGE_STATUSES.map((status) => sqlString(status)).join(
    ", ",
  );

  return `-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table ${t} add column if not exists ${c("documentType")} uuid references ${types} (${ctx.col("documentTypes", "id")}) on delete restrict;
alter table ${t} add column if not exists ${c("source")} text check (length(${c("source")}) between 1 and 200);
alter table ${t} add column if not exists ${c("externalId")} text check (length(${c("externalId")}) between 1 and 500);
alter table ${t} add column if not exists ${c("storage")} text not null default 'pending_upload' check (${c("storage")} in (${statuses}));
alter table ${t} add column if not exists ${c("sourcePath")} text check (length(${c("sourcePath")}) between 1 and 2000);
${ensureCheck(t, "bsb_attachments_external", `(${c("source")} is null) = (${c("externalId")} is null)`)}
create unique index if not exists ${ctx.naming.rename("attachments_external_idx")} on ${t} (${c("tenant")}, ${c("source")}, ${c("externalId")}) where ${c("source")} is not null;
create index if not exists ${ctx.naming.rename("attachments_document_type_idx")} on ${t} (${c("documentType")}) where ${c("documentType")} is not null;
do $$
begin
  update ${t} set ${c("storage")} = 'stored' where ${c("uploadedAt")} is not null and ${c("storage")} = 'pending_upload';
end;
$$;
`;
}

/**
 * The trigger that keeps storage_status in step with the upload and validates
 * what a write names: the subject type against the registry, the source against
 * `options.sources` and the import sources, the external id against the
 * organization's index and the metadata against the document type.
 */
export function documentGuardSql(
  ctx: BlockSqlContext,
  t: string,
  c: (logical: string) => string,
  registered: readonly string[],
): string {
  const types = ctx.table("documentTypes");
  const sources = sourcesOf(ctx);
  const subjects = ctx.installed("subjects");
  const imports = ctx.installed("imports");
  const metadata = ctx.has("attachments", "metadata");
  const fn = ctx.fn("attachment_document_guard");

  const importSource = imports
    ? `
      or exists (
        select 1 from ${ctx.of("imports").table("runs")} r
        where r.${ctx.of("imports").col("runs", "tenant")} = new.${c("tenant")} and r.${ctx.of("imports").col("runs", "source")} = new.${c("source")}
      )`
    : "";

  return `
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new.${c("storage")} in ('stored', 'pending_upload') or new.${c("uploadedAt")} is not null then
    new.${c("storage")} := case when new.${c("uploadedAt")} is not null then 'stored' else
      case when new.${c("storage")} = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
${
  subjects
    ? `  if new.${c("subjectType")} is not null and (tg_op = 'INSERT' or new.${c("subjectType")} is distinct from old.${c("subjectType")}) then
    v_types := ${ctx.of("subjects").fn("subject_types")}();
    if cardinality(v_types) > 0 and new.${c("subjectType")} <> all (v_types) and new.${c("subjectType")} <> all (${textArray(registered)}) then
      ${fail("ATTACHMENT_SUBJECT_UNKNOWN", "the subject type is not a registered subject type", "22023")}
    end if;
  end if;
`
    : ""
}  if new.${c("source")} is not null and (tg_op = 'INSERT' or new.${c("source")} is distinct from old.${c("source")} or new.${c("externalId")} is distinct from old.${c("externalId")}) then
    if not (new.${c("source")} = any (${textArray(sources)})${importSource}) then
      ${fail("ATTACHMENT_SOURCE_UNKNOWN", "the source is not in options.sources and has no import run", "22023")}
    end if;
    if new.${c("tenant")} is not null and exists (
      select 1 from ${t} x
      where x.${c("tenant")} = new.${c("tenant")} and x.${c("source")} = new.${c("source")} and x.${c("externalId")} = new.${c("externalId")} and x.${c("id")} <> new.${c("id")}
    ) then
      ${fail("ATTACHMENT_EXTERNAL_ID_TAKEN", "an attachment of this source already has this external id", "23505")}
    end if;
  end if;
${
  metadata
    ? `  if new.${c("documentType")} is not null and (tg_op = 'INSERT' or new.${c("documentType")} is distinct from old.${c("documentType")} or new.${c("metadata")} is distinct from old.${c("metadata")}) then
    select y.${ctx.col("documentTypes", "fields")} into v_fields from ${types} y
    where y.${ctx.col("documentTypes", "id")} = new.${c("documentType")} and y.${ctx.col("documentTypes", "tenant")} = new.${c("tenant")};
    if not found then
      ${fail("ATTACHMENT_DOCUMENT_TYPE_UNKNOWN", "the document type doesn't exist in this organization", "22023")}
    end if;
    v_error := ${ctx.fn("attachment_fields_error")}(v_fields, new.${c("metadata")});
    if v_error is not null then
      ${raise("%", "22023", "ATTACHMENT_FIELD_INVALID", "v_error")}
    end if;
  end if;
`
    : ""
}  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists bsb_attachments_documents on ${t};
create trigger bsb_attachments_documents
  before insert or update on ${t}
  for each row execute function ${fn}();
`;
}

/**
 * `claim_attachment_upload` and `mark_attachment_missing`: the later steps of a
 * record an import registered before its file existed.
 */
export function metadataFirstSql(
  ctx: BlockSqlContext,
  t: string,
  c: (logical: string) => string,
  parts: {
    readonly mayUpload: string;
    readonly mayManage: string;
    readonly json: (row: string) => string;
  },
): string {
  const fn = (name: string): string => ctx.fn(name);

  return `
-- The caller takes the upload of a record whose file hasn't arrived (pending
-- upload or missing): they become its uploader, upload to its object_path and
-- call confirm_attachment. The service role leaves the uploader as it is.
create or replace function ${fn("claim_attachment_upload")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
begin
  select * into v_row from ${t} a where a.${c("id")} = claim_attachment_upload.id for update;
  if v_row.${c("id")} is null then
    ${fail("ATTACHMENT_NOT_FOUND", "No attachment has this id", "P0002")}
  end if;
  if not (${parts.mayUpload} or ${parts.mayManage} or (${SERVICE_CALLER})) then
    ${fail("ATTACHMENT_FORBIDDEN", "not allowed to upload this attachment")}
  end if;
  if v_row.${c("uploadedAt")} is not null or v_row.${c("storage")} = 'stored' then
    ${fail("ATTACHMENT_NOT_CLAIMABLE", "the file is already stored", "55000")}
  end if;
  update ${t} a set
    ${c("storage")} = 'pending_upload',
    ${c("uploadedBy")} = case when (${SERVICE_CALLER}) then a.${c("uploadedBy")} else auth.uid() end
  where a.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  return ${parts.json("v_row")};
end;
$$;

-- Marks a record whose file will not arrive.
create or replace function ${fn("mark_attachment_missing")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
begin
  select * into v_row from ${t} a where a.${c("id")} = mark_attachment_missing.id for update;
  if v_row.${c("id")} is null then
    ${fail("ATTACHMENT_NOT_FOUND", "No attachment has this id", "P0002")}
  end if;
  if not (${parts.mayManage} or (${SERVICE_CALLER})) then
    ${fail("ATTACHMENT_FORBIDDEN", "not allowed to manage this attachment")}
  end if;
  if v_row.${c("uploadedAt")} is not null or v_row.${c("storage")} = 'stored' then
    ${fail("ATTACHMENT_NOT_CLAIMABLE", "the file is already stored", "55000")}
  end if;
  update ${t} a set ${c("storage")} = 'missing' where a.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  return ${parts.json("v_row")};
end;
$$;
revoke execute on function ${fn("claim_attachment_upload")}(uuid) from public, anon;
revoke execute on function ${fn("mark_attachment_missing")}(uuid) from public, anon;
grant execute on function ${fn("claim_attachment_upload")}(uuid) to authenticated, service_role;
grant execute on function ${fn("mark_attachment_missing")}(uuid) to authenticated, service_role;
`;
}

/**
 * `import_attachment(run, item, subject_id)`: the import target of the
 * `attachment` entity. `item.data` is `{ name, mimeType?, size?, subject: {
 * entity, key } | subjectType and subjectId, documentType?, metadata?,
 * sourcePath?, status? }`; the item key is the external id and the run's source
 * is the source. A re-import updates the record and leaves a stored file
 * alone.
 */
export function importAttachmentSql(
  ctx: BlockSqlContext,
  t: string,
  c: (logical: string) => string,
): string {
  const types = ctx.table("documentTypes");
  const imports = ctx.of("imports");
  const records = imports.table("records");
  const runs = imports.table("runs");
  const x = (column: string): string => imports.col("records", column);
  const r = (column: string): string => imports.col("runs", column);

  return `
-- The import target of the attachment entity (ADR 0157): the record is
-- registered now, and claim_attachment_upload or mark_attachment_missing
-- settles it later. The item key is the external id in the run's source.
create or replace function ${ctx.fn("import_attachment")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType} := (import_attachment.item ->> 'tenant')::${ctx.idType};
  v_scope text := coalesce(import_attachment.item ->> 'scope', '');
  v_key text := import_attachment.item ->> 'key';
  v_data jsonb := import_attachment.item -> 'data';
  v_reference jsonb := v_data -> 'subject';
  v_type text := nullif(v_data ->> 'subjectType', '');
  v_subject text := nullif(v_data ->> 'subjectId', '');
  v_source text;
  v_status text := coalesce(v_data ->> 'status', 'pending_upload');
  v_document uuid;
  v_size bigint;
  v_id uuid;
  v_metadata jsonb := coalesce(v_data -> 'metadata', '{}'::jsonb);
begin
  select u.${r("source")} into v_source from ${runs} u where u.${r("id")} = import_attachment.run;
  if v_status not in ('pending_upload', 'missing') then
    ${fail("IMPORT_ITEM_INVALID", "an imported attachment is pending_upload or missing", "22023")}
  end if;
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    ${fail("IMPORT_ITEM_INVALID", "metadata must be an object", "22023")}
  end if;
  if v_data ->> 'name' is null then
    ${fail("IMPORT_ITEM_INVALID", "an attachment needs a name", "22023")}
  end if;
  begin
    v_size := coalesce((v_data ->> 'size')::bigint, 0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    ${fail("IMPORT_ITEM_INVALID", "size must be a whole number of bytes", "22023")}
  end;
  if v_reference is not null then
    if jsonb_typeof(v_reference) is distinct from 'object' then
      ${fail("IMPORT_ITEM_INVALID", "subject is { entity, key }", "22023")}
    end if;
    select x.${x("subjectType")}, x.${x("subjectId")} into v_type, v_subject
    from ${records} x
    where x.${x("tenant")} = v_tenant and x.${x("source")} = v_source and x.${x("scope")} = v_scope
      and x.${x("entity")} = v_reference ->> 'entity' and x.${x("externalKey")} = v_reference ->> 'key'
      and x.${x("role")} = 'primary';
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the record isn't in the import record map; import it first", "22023")}
    end if;
  end if;
  if (v_type is null) <> (v_subject is null) then
    ${fail("IMPORT_ITEM_INVALID", "an attachment names a subject with both subjectType and subjectId, or none", "22023")}
  end if;
  if v_data ->> 'documentType' is not null then
    select y.${ctx.col("documentTypes", "id")} into v_document from ${types} y
    where y.${ctx.col("documentTypes", "tenant")} = v_tenant and y.${ctx.col("documentTypes", "key")} = v_data ->> 'documentType';
    if not found then
      ${fail("ATTACHMENT_DOCUMENT_TYPE_UNKNOWN", "the document type doesn't exist in this organization", "22022")}
    end if;
  end if;

  select a.${c("id")} into v_id from ${t} a
  where a.${c("tenant")} = v_tenant and a.${c("source")} = v_source and a.${c("externalId")} = v_key;
  if found then
    update ${t} a set
      ${c("name")} = v_data ->> 'name',
      ${c("mimeType")} = case when a.${c("uploadedAt")} is null then lower(coalesce(v_data ->> 'mimeType', a.${c("mimeType")})) else a.${c("mimeType")} end,
      ${c("size")} = case when a.${c("uploadedAt")} is null then v_size else a.${c("size")} end,
      ${c("subjectType")} = v_type,
      ${c("subjectId")} = v_subject,
      ${c("documentType")} = v_document,
      ${c("metadata")} = v_metadata,
      ${c("sourcePath")} = v_data ->> 'sourcePath',
      ${c("storage")} = case when a.${c("uploadedAt")} is null then v_status else a.${c("storage")} end
    where a.${c("id")} = v_id;
  else
    insert into ${t} (${c("tenant")}, ${c("name")}, ${c("mimeType")}, ${c("size")}, ${c("subjectType")}, ${c("subjectId")}, ${c("documentType")}, ${c("metadata")}, ${c("source")}, ${c("externalId")}, ${c("sourcePath")}, ${c("storage")}, ${c("uploadedBy")})
    values (v_tenant, v_data ->> 'name', lower(coalesce(v_data ->> 'mimeType', 'application/octet-stream')), v_size, v_type, v_subject, v_document, v_metadata, v_source, v_key, v_data ->> 'sourcePath', v_status, null)
    returning ${c("id")} into v_id;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'subjectType', ${sqlString(ATTACHMENT_IMPORT_ENTITY)});
end;
$$;
${serviceGrant(`${ctx.fn("import_attachment")}(uuid, jsonb, text)`)}
`;
}
