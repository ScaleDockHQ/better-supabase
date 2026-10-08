import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, tenantIn } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { canIn, raise, serviceGrant, userGrant } from "./ai-chat-sql.ts";

const FILES = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  chat: "chat_id",
  project: "project_id",
  bucket: "bucket",
  path: "path",
  mediaType: "media_type",
  filename: "filename",
  size: "byte_size",
  sha256: "sha256",
  status: "status",
  source: "source",
  createdAt: "created_at",
  uploadedAt: "uploaded_at",
  expiresAt: "expires_at",
} as const;

const PROVIDER_FILES = {
  file: "file_id",
  provider: "provider",
  reference: "reference",
  expiresAt: "expires_at",
  createdAt: "created_at",
} as const;

const DOCUMENTS = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  chat: "chat_id",
  kind: "kind",
  title: "title",
  version: "current_version",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

const VERSIONS = {
  document: "document_id",
  version: "version",
  content: "content",
  storagePath: "storage_path",
  message: "created_by_message_id",
  createdBy: "created_by",
  createdAt: "created_at",
} as const;

const SUGGESTIONS = {
  id: "id",
  document: "document_id",
  version: "version",
  original: "original_text",
  suggested: "suggested_text",
  description: "description",
  createdBy: "created_by",
  createdAt: "created_at",
  resolvedAt: "resolved_at",
  accepted: "accepted",
} as const;

const NAMES: ModuleNames = {
  options: ["bucket", "maxSize", "allowedMimeTypes", "pendingTtl"],
  tables: {
    files: {
      name: "ai_files",
      columns: FILES,
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    providerFiles: { name: "ai_provider_files", columns: PROVIDER_FILES },
    documents: {
      name: "ai_documents",
      columns: DOCUMENTS,
      lifecycle: { user: "owner", tenant: "tenant" },
    },
    versions: {
      name: "ai_document_versions",
      columns: VERSIONS,
      lifecycle: { user: "createdBy" },
    },
    suggestions: {
      name: "ai_suggestions",
      columns: SUGGESTIONS,
      lifecycle: { user: "createdBy" },
    },
  },
};

/** A Storage bucket id: Supabase allows 1 to 100 characters. */
const BUCKET = /^[a-z0-9._-]{1,100}$/;
const MIME = /^[a-z0-9.+*-]+\/[a-z0-9.+*-]+$/;
/** 50 MB, the Supabase free-plan object limit. */
const DEFAULT_MAX_SIZE = 50 * 1024 * 1024;

interface BucketOptions {
  readonly bucket: string;
  readonly maxSize: number;
  readonly mimeTypes: readonly string[];
}

function bucketOptions(ctx: ModuleContext): BucketOptions {
  const bucket = ctx.text("bucket", "ai-files");
  if (!BUCKET.test(bucket)) {
    throw new TypeError(
      "sql.modules.ai-files.options.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores",
    );
  }
  const maxSize = ctx.number("maxSize", DEFAULT_MAX_SIZE);
  if (!Number.isInteger(maxSize) || maxSize <= 0) {
    throw new TypeError(
      "sql.modules.ai-files.options.maxSize must be a positive whole number of bytes",
    );
  }
  const mimeTypes = ctx.list("allowedMimeTypes", []);
  for (const type of mimeTypes) {
    if (!MIME.test(type)) {
      throw new TypeError(
        `sql.modules.ai-files.options.allowedMimeTypes: "${type}" is not a MIME type`,
      );
    }
  }
  return { bucket, maxSize, mimeTypes };
}

type Columns<T> = { readonly [K in keyof T]: string };

function columnsOf<T extends Readonly<Record<string, string>>>(
  ctx: ModuleContext,
  table: string,
  spec: T,
): Columns<T> {
  // SAFETY: the keys are spec's own keys, each mapped to its quoted name.
  return Object.fromEntries(
    Object.keys(spec).map((key) => [key, ctx.col(table, key)]),
  ) as Columns<T>;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const f = columnsOf(ctx, "files", FILES);
  const pf = columnsOf(ctx, "providerFiles", PROVIDER_FILES);
  const d = columnsOf(ctx, "documents", DOCUMENTS);
  const v = columnsOf(ctx, "versions", VERSIONS);
  const sg = columnsOf(ctx, "suggestions", SUGGESTIONS);
  const files = ctx.table("files");
  const providerFiles = ctx.table("providerFiles");
  const documents = ctx.table("documents");
  const versions = ctx.table("versions");
  const suggestions = ctx.table("suggestions");
  const permissions = MODULE_PERMISSIONS["ai-files"];
  const upload = ctx.permission("upload", permissions.upload);
  const manage = ctx.permission("manage", permissions.manage);
  const { bucket, maxSize, mimeTypes } = bucketOptions(ctx);
  const bucketLiteral = sqlString(bucket);
  const pendingTtl = ctx.text("pendingTtl", "1 day");
  const chatReadable = ctx.installed("ai-chat")
    ? (chat: string): string =>
        `(${chat} is not null and ${ctx.of("ai-chat").fn("ai_chat_can_read")}(${chat}))`
    : (): string => "false";
  const mimeCheck =
    mimeTypes.length === 0
      ? ""
      : `
  if not (lower(media_type) like any (array[${mimeTypes.map((type) => sqlString(type.replaceAll("*", "%"))).join(", ")}])) then
    ${raise("media type % is not allowed", "22023", "AI_FILE_TYPE", "media_type")}
  end if;`;
  const policy = (name: string): string => `bs_ai_files_${name}`;
  const fileJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${f.id}, 'organization_id', ${row}.${f.tenant}, 'owner_id', ${row}.${f.owner}, 'chat_id', ${row}.${f.chat}, 'project_id', ${row}.${f.project}, 'bucket', ${row}.${f.bucket}, 'path', ${row}.${f.path}, 'media_type', ${row}.${f.mediaType}, 'filename', ${row}.${f.filename}, 'byte_size', ${row}.${f.size}, 'sha256', ${row}.${f.sha256}, 'status', ${row}.${f.status}, 'source', ${row}.${f.source}, 'created_at', ${row}.${f.createdAt}, 'uploaded_at', ${row}.${f.uploadedAt}, 'expires_at', ${row}.${f.expiresAt})`;
  const documentJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${d.id}, 'organization_id', ${row}.${d.tenant}, 'owner_id', ${row}.${d.owner}, 'chat_id', ${row}.${d.chat}, 'kind', ${row}.${d.kind}, 'title', ${row}.${d.title}, 'current_version', ${row}.${d.version}, 'created_at', ${row}.${d.createdAt}, 'updated_at', ${row}.${d.updatedAt})`;
  const versionJson = (row: string): string =>
    `jsonb_build_object('document_id', ${row}.${v.document}, 'version', ${row}.${v.version}, 'content', ${row}.${v.content}, 'storage_path', ${row}.${v.storagePath}, 'created_by_message_id', ${row}.${v.message}, 'created_by', ${row}.${v.createdBy}, 'created_at', ${row}.${v.createdAt})`;
  const suggestionJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${sg.id}, 'document_id', ${row}.${sg.document}, 'version', ${row}.${sg.version}, 'original_text', ${row}.${sg.original}, 'suggested_text', ${row}.${sg.suggested}, 'description', ${row}.${sg.description}, 'created_by', ${row}.${sg.createdBy}, 'created_at', ${row}.${sg.createdAt}, 'resolved_at', ${row}.${sg.resolvedAt}, 'accepted', ${row}.${sg.accepted})`;
  // The owner, an ai_chat admin of the organization, or a reader of the chat
  // the file or document belongs to.
  const readable = (
    prefix: string,
    owner: string,
    tenant: string,
    chat: string,
  ): string =>
    `(${prefix}${owner} = (select auth.uid()) or ${prefix === "" ? tenantIn(tenant, manage) : canIn(`${prefix}${tenant}`, manage)} or ${chatReadable(`${prefix}${chat}`)})`;
  const ownFile = (row: string): string =>
    `(${SERVICE_CALLER} or ${row}.${f.owner} = auth.uid() or ${canIn(`${row}.${f.tenant}`, manage)})`;
  const ownDocument = (row: string): string =>
    `(${SERVICE_CALLER} or ${row}.${d.owner} = auth.uid() or ${canIn(`${row}.${d.tenant}`, manage)})`;
  const docNotFound = raise(
    "document % not found",
    "P0002",
    "AI_DOCUMENT_NOT_FOUND",
    "document_id",
  );

  return `${schemaPreamble(ctx)}
-- Files for AI chats: uploads, generated images and audio, and what a
-- provider's file API returned for them. Objects live in the private
-- ${bucket} bucket at {organization_id}/{owner_id}/{id}/{filename}; the record is
-- reserved first, so the storage policies only accept the upload it expects.
create table if not exists ${files} (
  ${f.id} uuid primary key default gen_random_uuid(),
  ${f.tenant} ${id} not null,
  ${f.owner} uuid not null references auth.users (id) on delete cascade,
  ${f.chat} uuid,
  ${f.project} uuid,
  ${f.bucket} text not null,
  ${f.filename} text not null check (length(${f.filename}) >= 1 and length(${f.filename}) <= 255 and ${f.filename} !~ '[/\\\\]' and ${f.filename} not in ('.', '..')),
  ${f.path} text generated always as (${f.tenant}::text || '/' || ${f.owner}::text || '/' || ${f.id}::text || '/' || ${f.filename}) stored,
  ${f.mediaType} text not null check (${f.mediaType} ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  ${f.size} bigint not null check (${f.size} between 0 and ${String(maxSize)}),
  ${f.sha256} text check (${f.sha256} ~ '^[0-9a-f]{64}$'),
  ${f.status} text not null default 'pending' check (${f.status} in ('pending', 'ready', 'failed')),
  ${f.source} text not null default 'upload' check (${f.source} in ('upload', 'generated', 'provider')),
  ${f.createdAt} timestamptz not null default now(),
  ${f.uploadedAt} timestamptz,
  ${f.expiresAt} timestamptz
);
create unique index if not exists ai_files_object_idx on ${files} (${f.bucket}, ${f.path});
create index if not exists ai_files_owner_idx on ${files} (${f.owner});
create index if not exists ai_files_tenant_idx on ${files} (${f.tenant});
create index if not exists ai_files_chat_idx on ${files} (${f.chat}) where ${f.chat} is not null;
create index if not exists ai_files_pending_idx on ${files} (${f.createdAt}) where ${f.status} = 'pending';
alter table ${files} enable row level security;
revoke all on ${files} from anon, authenticated;
grant select on ${files} to authenticated;
grant all on ${files} to service_role;
drop policy if exists ai_files_read on ${files};
create policy ai_files_read on ${files} for select to authenticated
  using (${readable("", f.owner, f.tenant, f.chat)});

-- What a provider's file API returned for a file (an OpenAI file id, a
-- Gemini file URI), so the next call reuses it until it expires.
create table if not exists ${providerFiles} (
  ${pf.file} uuid not null references ${files} (${f.id}) on delete cascade,
  ${pf.provider} text not null check (length(${pf.provider}) between 1 and 100),
  ${pf.reference} text not null check (length(${pf.reference}) between 1 and 2000),
  ${pf.expiresAt} timestamptz,
  ${pf.createdAt} timestamptz not null default now(),
  primary key (${pf.file}, ${pf.provider})
);
create index if not exists ai_provider_files_expires_idx on ${providerFiles} (${pf.expiresAt}) where ${pf.expiresAt} is not null;
alter table ${providerFiles} enable row level security;
revoke all on ${providerFiles} from anon, authenticated;
grant all on ${providerFiles} to service_role;

-- Documents an assistant writes and the user edits beside the chat (text,
-- code, sheets, images), with every version kept.
create table if not exists ${documents} (
  ${d.id} uuid primary key default gen_random_uuid(),
  ${d.tenant} ${id} not null,
  ${d.owner} uuid not null references auth.users (id) on delete cascade,
  ${d.chat} uuid,
  ${d.kind} text not null check (${d.kind} in ('text', 'code', 'sheet', 'image')),
  ${d.title} text not null check (length(${d.title}) between 1 and 500),
  ${d.version} integer not null default 1 check (${d.version} >= 1),
  ${d.createdAt} timestamptz not null default now(),
  ${d.updatedAt} timestamptz not null default now()
);
create index if not exists ai_documents_owner_idx on ${documents} (${d.owner});
create index if not exists ai_documents_tenant_idx on ${documents} (${d.tenant});
create index if not exists ai_documents_chat_idx on ${documents} (${d.chat}) where ${d.chat} is not null;
alter table ${documents} enable row level security;
revoke all on ${documents} from anon, authenticated;
grant select on ${documents} to authenticated;
grant all on ${documents} to service_role;
drop policy if exists ai_documents_read on ${documents};
create policy ai_documents_read on ${documents} for select to authenticated
  using (${readable("", d.owner, d.tenant, d.chat)});

create table if not exists ${versions} (
  ${v.document} uuid not null references ${documents} (${d.id}) on delete cascade,
  ${v.version} integer not null check (${v.version} >= 1),
  ${v.content} text,
  ${v.storagePath} text,
  ${v.message} text,
  ${v.createdBy} uuid references auth.users (id) on delete set null,
  ${v.createdAt} timestamptz not null default now(),
  primary key (${v.document}, ${v.version}),
  check (${v.content} is not null or ${v.storagePath} is not null)
);
create index if not exists ai_document_versions_created_by_idx on ${versions} (${v.createdBy}) where ${v.createdBy} is not null;
alter table ${versions} enable row level security;
revoke all on ${versions} from anon, authenticated;
grant select on ${versions} to authenticated;
grant all on ${versions} to service_role;
drop policy if exists ai_document_versions_read on ${versions};
create policy ai_document_versions_read on ${versions} for select to authenticated
  using (exists (select 1 from ${documents} doc where doc.${d.id} = ${v.document}));

create table if not exists ${suggestions} (
  ${sg.id} uuid primary key default gen_random_uuid(),
  ${sg.document} uuid not null references ${documents} (${d.id}) on delete cascade,
  ${sg.version} integer not null,
  ${sg.original} text not null,
  ${sg.suggested} text not null,
  ${sg.description} text,
  ${sg.createdBy} uuid references auth.users (id) on delete set null,
  ${sg.createdAt} timestamptz not null default now(),
  ${sg.resolvedAt} timestamptz,
  ${sg.accepted} boolean
);
create index if not exists ai_suggestions_document_idx on ${suggestions} (${sg.document});
create index if not exists ai_suggestions_created_by_idx on ${suggestions} (${sg.createdBy}) where ${sg.createdBy} is not null;
alter table ${suggestions} enable row level security;
revoke all on ${suggestions} from anon, authenticated;
grant select on ${suggestions} to authenticated;
grant all on ${suggestions} to service_role;
drop policy if exists ai_suggestions_read on ${suggestions};
create policy ai_suggestions_read on ${suggestions} for select to authenticated
  using (exists (select 1 from ${documents} doc where doc.${d.id} = ${sg.document}));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read the owner, an ai_chat admin or a reader of the file's chat, a delete
-- the owner or an admin. It reads the table as its owner, so the storage
-- policies don't depend on the table's own policies.
create or replace function ${fn("ai_file_object_allowed")}(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${files} a
    where a.${f.bucket} = ai_file_object_allowed.bucket and a.${f.path} = ai_file_object_allowed.path
      and case ai_file_object_allowed.action
        when 'insert' then a.${f.status} = 'pending' and a.${f.owner} = auth.uid()
        when 'select' then a.${f.owner} = auth.uid() or ${canIn(`a.${f.tenant}`, manage)} or ${chatReadable(`a.${f.chat}`)}
        when 'delete' then a.${f.owner} = auth.uid() or ${canIn(`a.${f.tenant}`, manage)}
        else false
      end
  )
$$;
${userGrant(`${fn("ai_file_object_allowed")}(text, text, text)`)}

drop policy if exists ${policy("insert")} on storage.objects;
drop policy if exists ${policy("select")} on storage.objects;
drop policy if exists ${policy("delete")} on storage.objects;
create policy ${policy("insert")} on storage.objects for insert to authenticated
  with check (bucket_id = ${bucketLiteral} and ${fn("ai_file_object_allowed")}(bucket_id, name, 'insert'));
create policy ${policy("select")} on storage.objects for select to authenticated
  using (bucket_id = ${bucketLiteral} and ${fn("ai_file_object_allowed")}(bucket_id, name, 'select'));
create policy ${policy("delete")} on storage.objects for delete to authenticated
  using (bucket_id = ${bucketLiteral} and ${fn("ai_file_object_allowed")}(bucket_id, name, 'delete'));

-- Reserves a file for the caller, who then uploads to its path (a signed
-- upload URL, or TUS for large files). The size and type are checked here
-- and again by the bucket.
create or replace function ${fn("reserve_ai_file")}(
  tenant ${id},
  filename text,
  media_type text,
  byte_size bigint,
  chat_id uuid default null,
  project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${files}%rowtype;
begin
  if auth.uid() is null or not ${canIn("reserve_ai_file.tenant", upload)} then
    ${raise("you may not upload files here", "42501", "AI_FILE_FORBIDDEN")}
  end if;
  if byte_size < 0 or byte_size > ${String(maxSize)} then
    ${raise("files are limited to % bytes", "22023", "AI_FILE_TOO_LARGE", String(maxSize))}
  end if;${mimeCheck}
  insert into ${files} (${f.tenant}, ${f.owner}, ${f.chat}, ${f.project}, ${f.bucket}, ${f.filename}, ${f.mediaType}, ${f.size})
  values (reserve_ai_file.tenant, auth.uid(), reserve_ai_file.chat_id, reserve_ai_file.project_id, ${bucketLiteral}, reserve_ai_file.filename, lower(reserve_ai_file.media_type), reserve_ai_file.byte_size)
  returning * into v_row;
  return ${fileJson("v_row")};
end;
$$;
${userGrant(`${fn("reserve_ai_file")}(${id}, text, text, bigint, uuid, uuid)`)}

-- Marks an upload done once its object exists, taking the stored size.
create or replace function ${fn("confirm_ai_file")}(file_id uuid, sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${files}%rowtype;
  v_size bigint;
begin
  select * into v_row from ${files} x where x.${f.id} = confirm_ai_file.file_id for update;
  if not found or not (${SERVICE_CALLER} or v_row.${f.owner} = auth.uid()) then
    ${raise("file % not found", "P0002", "AI_FILE_NOT_FOUND", "file_id")}
  end if;
  if v_row.${f.status} <> 'pending' then
    return ${fileJson("v_row")};
  end if;
  select (o.metadata ->> 'size')::bigint into v_size
  from storage.objects o where o.bucket_id = v_row.${f.bucket} and o.name = v_row.${f.path};
  if not found then
    ${raise("file % has no uploaded object yet", "P0001", "AI_FILE_NOT_UPLOADED", "file_id")}
  end if;
  update ${files} x set
    ${f.status} = 'ready',
    ${f.uploadedAt} = now(),
    ${f.size} = coalesce(v_size, x.${f.size}),
    ${f.sha256} = coalesce(lower(confirm_ai_file.sha256), x.${f.sha256})
  where x.${f.id} = v_row.${f.id}
  returning * into v_row;
  return ${fileJson("v_row")};
end;
$$;
${userGrant(`${fn("confirm_ai_file")}(uuid, text)`)}

-- A file the caller may read, by id or by object path; null otherwise.
create or replace function ${fn("get_ai_file")}(file_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fileJson("x")} from ${files} x where x.${f.id} = get_ai_file.file_id
$$;
${userGrant(`${fn("get_ai_file")}(uuid)`)}

create or replace function ${fn("get_ai_file_by_path")}(bucket text, path text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fileJson("x")} from ${files} x
  where x.${f.bucket} = get_ai_file_by_path.bucket and x.${f.path} = get_ai_file_by_path.path
$$;
${userGrant(`${fn("get_ai_file_by_path")}(text, text)`)}

-- The files of a chat the caller can read, oldest first.
create or replace function ${fn("list_ai_files")}(chat_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${fileJson("x")} order by x.${f.createdAt}), '[]'::jsonb)
  from ${files} x where x.${f.chat} = list_ai_files.chat_id
$$;
${userGrant(`${fn("list_ai_files")}(uuid)`)}

-- Deletes the record; returns { bucket, path } for the Storage API to
-- remove the object, or null when the caller may not delete it.
create or replace function ${fn("delete_ai_file")}(file_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${files}%rowtype;
begin
  select * into v_row from ${files} x where x.${f.id} = delete_ai_file.file_id;
  if not found or not ${ownFile("v_row")} then
    return null;
  end if;
  delete from ${files} x where x.${f.id} = v_row.${f.id};
  return jsonb_build_object('bucket', v_row.${f.bucket}, 'path', v_row.${f.path});
end;
$$;
${userGrant(`${fn("delete_ai_file")}(uuid)`)}

-- A ready file the server writes itself (a generated image, speech, a file
-- a provider returned), owned by owner; the caller uploads to its path.
create or replace function ${fn("store_ai_file")}(
  tenant ${id},
  owner uuid,
  filename text,
  media_type text,
  byte_size bigint,
  chat_id uuid default null,
  source text default 'generated',
  sha256 text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row ${files}%rowtype;
begin
  insert into ${files} (${f.tenant}, ${f.owner}, ${f.chat}, ${f.bucket}, ${f.filename}, ${f.mediaType}, ${f.size}, ${f.status}, ${f.source}, ${f.sha256}, ${f.uploadedAt})
  values (store_ai_file.tenant, store_ai_file.owner, store_ai_file.chat_id, ${bucketLiteral}, store_ai_file.filename, lower(store_ai_file.media_type), store_ai_file.byte_size, 'ready', coalesce(store_ai_file.source, 'generated'), lower(store_ai_file.sha256), now())
  returning * into v_row;
  return ${fileJson("v_row")};
end;
$$;
${serviceGrant(`${fn("store_ai_file")}(${id}, uuid, text, text, bigint, uuid, text, text)`)}

create or replace function ${fn("set_ai_provider_file")}(file_id uuid, provider text, reference text, expires_at timestamptz default null)
returns boolean
language sql
set search_path = ''
as $$
  insert into ${providerFiles} (${pf.file}, ${pf.provider}, ${pf.reference}, ${pf.expiresAt})
  values (set_ai_provider_file.file_id, set_ai_provider_file.provider, set_ai_provider_file.reference, set_ai_provider_file.expires_at)
  on conflict (${pf.file}, ${pf.provider}) do update
    set ${pf.reference} = excluded.${pf.reference}, ${pf.expiresAt} = excluded.${pf.expiresAt}, ${pf.createdAt} = now()
  returning true
$$;
${serviceGrant(`${fn("set_ai_provider_file")}(uuid, text, text, timestamptz)`)}

-- The provider's reference while it is still valid, or null.
create or replace function ${fn("get_ai_provider_file")}(file_id uuid, provider text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('file_id', p.${pf.file}, 'provider', p.${pf.provider}, 'reference', p.${pf.reference}, 'expires_at', p.${pf.expiresAt})
  from ${providerFiles} p
  where p.${pf.file} = get_ai_provider_file.file_id and p.${pf.provider} = get_ai_provider_file.provider
    and (p.${pf.expiresAt} is null or p.${pf.expiresAt} > now())
$$;
${serviceGrant(`${fn("get_ai_provider_file")}(uuid, text)`)}

-- Provider references that expire within horizon, for a refresh job.
create or replace function ${fn("expiring_ai_provider_files")}(horizon interval default '1 day', batch integer default 100)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('file_id', p.${pf.file}, 'provider', p.${pf.provider}, 'reference', p.${pf.reference}, 'expires_at', p.${pf.expiresAt})), '[]'::jsonb)
  from (
    select * from ${providerFiles}
    where ${pf.expiresAt} is not null and ${pf.expiresAt} <= now() + coalesce(horizon, interval '1 day')
    order by ${pf.expiresAt}
    limit greatest(coalesce(batch, 100), 1)
  ) p
$$;
${serviceGrant(`${fn("expiring_ai_provider_files")}(interval, integer)`)}

-- Deletes pending uploads older than older_than, expired files and, with
-- ai-chat installed, the files of deleted chats. Returns the { bucket, path }
-- objects for the Storage API to remove.
create or replace function ${fn("purge_ai_files")}(older_than interval default ${sqlString(pendingTtl)}, batch integer default 500)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_removed jsonb;
begin
  with doomed as (
    select x.${f.id} from ${files} x
    where (x.${f.status} = 'pending' and x.${f.createdAt} <= now() - coalesce(older_than, interval ${sqlString(pendingTtl)}))
      or x.${f.expiresAt} <= now()${
        ctx.installed("ai-chat")
          ? `
      or (x.${f.chat} is not null and not exists (select 1 from ${ctx.of("ai-chat").table("chats")} ch where ch.${ctx.of("ai-chat").col("chats", "id")} = x.${f.chat}))`
          : ""
      }
    limit greatest(coalesce(batch, 500), 1)
  ),
  gone as (
    delete from ${files} x using doomed where x.${f.id} = doomed.${f.id}
    returning x.${f.bucket} as bucket, x.${f.path} as path
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', gone.bucket, 'path', gone.path)), '[]'::jsonb) into v_removed from gone;
  return v_removed;
end;
$$;
${serviceGrant(`${fn("purge_ai_files")}(interval, integer)`)}

-- A document with its first version. The caller needs upload rights in the
-- organization; the service role writes for an owner.
create or replace function ${fn("create_ai_document")}(
  tenant ${id},
  kind text,
  title text,
  content text default null,
  chat_id uuid default null,
  message_id text default null,
  owner uuid default null,
  storage_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := case when ${SERVICE_CALLER} then create_ai_document.owner else auth.uid() end;
  v_row ${documents}%rowtype;
begin
  if v_owner is null or not (${SERVICE_CALLER} or ${canIn("create_ai_document.tenant", upload)}) then
    ${raise("you may not create documents here", "42501", "AI_DOCUMENT_FORBIDDEN")}
  end if;
  insert into ${documents} (${d.tenant}, ${d.owner}, ${d.chat}, ${d.kind}, ${d.title})
  values (create_ai_document.tenant, v_owner, create_ai_document.chat_id, create_ai_document.kind, create_ai_document.title)
  returning * into v_row;
  insert into ${versions} (${v.document}, ${v.version}, ${v.content}, ${v.storagePath}, ${v.message}, ${v.createdBy})
  values (v_row.${d.id}, 1, create_ai_document.content, create_ai_document.storage_path, create_ai_document.message_id, v_owner);
  return ${documentJson("v_row")};
end;
$$;
${userGrant(`${fn("create_ai_document")}(${id}, text, text, text, uuid, text, uuid, text)`)}

-- A new version of the document. expected_version guards against two
-- writers: when it is set and not the current version, nothing changes.
create or replace function ${fn("update_ai_document")}(
  document_id uuid,
  content text default null,
  title text default null,
  message_id text default null,
  expected_version integer default null,
  storage_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${documents}%rowtype;
begin
  select * into v_row from ${documents} x where x.${d.id} = update_ai_document.document_id for update;
  if not found or not ${ownDocument("v_row")} then
    ${docNotFound}
  end if;
  if expected_version is not null and expected_version <> v_row.${d.version} then
    ${raise("document % is at version %", "40001", "AI_DOCUMENT_CONFLICT", "document_id", `v_row.${d.version}`)}
  end if;
  insert into ${versions} (${v.document}, ${v.version}, ${v.content}, ${v.storagePath}, ${v.message}, ${v.createdBy})
  values (v_row.${d.id}, v_row.${d.version} + 1, update_ai_document.content, update_ai_document.storage_path, update_ai_document.message_id, auth.uid());
  update ${documents} x set
    ${d.version} = v_row.${d.version} + 1,
    ${d.title} = coalesce(update_ai_document.title, x.${d.title}),
    ${d.updatedAt} = now()
  where x.${d.id} = v_row.${d.id}
  returning * into v_row;
  return ${documentJson("v_row")};
end;
$$;
${userGrant(`${fn("update_ai_document")}(uuid, text, text, text, integer, text)`)}

-- Writes version as the newest version again.
create or replace function ${fn("rollback_ai_document")}(document_id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${documents}%rowtype;
  v_old ${versions}%rowtype;
begin
  select * into v_row from ${documents} x where x.${d.id} = rollback_ai_document.document_id for update;
  if not found or not ${ownDocument("v_row")} then
    ${docNotFound}
  end if;
  select * into v_old from ${versions} x where x.${v.document} = v_row.${d.id} and x.${v.version} = rollback_ai_document.version;
  if not found then
    ${raise("document % has no version %", "P0002", "AI_DOCUMENT_VERSION_NOT_FOUND", "document_id", "rollback_ai_document.version")}
  end if;
  insert into ${versions} (${v.document}, ${v.version}, ${v.content}, ${v.storagePath}, ${v.message}, ${v.createdBy})
  values (v_row.${d.id}, v_row.${d.version} + 1, v_old.${v.content}, v_old.${v.storagePath}, null, auth.uid());
  update ${documents} x set ${d.version} = v_row.${d.version} + 1, ${d.updatedAt} = now()
  where x.${d.id} = v_row.${d.id}
  returning * into v_row;
  return ${documentJson("v_row")};
end;
$$;
${userGrant(`${fn("rollback_ai_document")}(uuid, integer)`)}

create or replace function ${fn("get_ai_document")}(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${documentJson("x")} || jsonb_build_object('content', vv.${v.content}, 'storage_path', vv.${v.storagePath})
  from ${documents} x
  join ${versions} vv on vv.${v.document} = x.${d.id} and vv.${v.version} = x.${d.version}
  where x.${d.id} = get_ai_document.document_id
$$;
${userGrant(`${fn("get_ai_document")}(uuid)`)}

-- Every version of a document the caller can read, newest first.
create or replace function ${fn("list_ai_document_versions")}(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${versionJson("x")} order by x.${v.version} desc), '[]'::jsonb)
  from ${versions} x where x.${v.document} = list_ai_document_versions.document_id
$$;
${userGrant(`${fn("list_ai_document_versions")}(uuid)`)}

-- A suggested edit on the current version; the assistant or a reader of the
-- document writes it, the owner resolves it.
create or replace function ${fn("suggest_ai_document_edit")}(document_id uuid, original_text text, suggested_text text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc ${documents}%rowtype;
  v_row ${suggestions}%rowtype;
begin
  select * into v_doc from ${documents} x where x.${d.id} = suggest_ai_document_edit.document_id;
  if not found or not (${SERVICE_CALLER} or ${readable("v_doc.", d.owner, d.tenant, d.chat)}) then
    ${docNotFound}
  end if;
  insert into ${suggestions} (${sg.document}, ${sg.version}, ${sg.original}, ${sg.suggested}, ${sg.description}, ${sg.createdBy})
  values (v_doc.${d.id}, v_doc.${d.version}, suggest_ai_document_edit.original_text, suggest_ai_document_edit.suggested_text, suggest_ai_document_edit.description, auth.uid())
  returning * into v_row;
  return ${suggestionJson("v_row")};
end;
$$;
${userGrant(`${fn("suggest_ai_document_edit")}(uuid, text, text, text)`)}

create or replace function ${fn("list_ai_suggestions")}(document_id uuid, open_only boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${suggestionJson("x")} order by x.${sg.createdAt}), '[]'::jsonb)
  from ${suggestions} x
  where x.${sg.document} = list_ai_suggestions.document_id
    and (not coalesce(open_only, true) or x.${sg.resolvedAt} is null)
$$;
${userGrant(`${fn("list_ai_suggestions")}(uuid, boolean)`)}

-- Accepts or rejects a suggestion; accepting doesn't edit the document, the
-- client writes the new version with update_ai_document.
create or replace function ${fn("resolve_ai_suggestion")}(suggestion_id uuid, accepted boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${suggestions}%rowtype;
  v_doc ${documents}%rowtype;
begin
  select * into v_row from ${suggestions} x where x.${sg.id} = resolve_ai_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from ${documents} x where x.${d.id} = v_row.${sg.document};
  end if;
  if v_doc.${d.id} is null or not ${ownDocument("v_doc")} then
    ${raise("suggestion % not found", "P0002", "AI_SUGGESTION_NOT_FOUND", "suggestion_id")}
  end if;
  update ${suggestions} x set ${sg.resolvedAt} = now(), ${sg.accepted} = resolve_ai_suggestion.accepted
  where x.${sg.id} = v_row.${sg.id}
  returning * into v_row;
  return ${suggestionJson("v_row")};
end;
$$;
${userGrant(`${fn("resolve_ai_suggestion")}(uuid, boolean)`)}

-- Deletes a document and its versions; true when the caller could.
create or replace function ${fn("delete_ai_document")}(document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${documents}%rowtype;
begin
  select * into v_row from ${documents} x where x.${d.id} = delete_ai_document.document_id;
  if not found or not ${ownDocument("v_row")} then
    return false;
  end if;
  delete from ${documents} x where x.${d.id} = v_row.${d.id};
  return true;
end;
$$;
${userGrant(`${fn("delete_ai_document")}(uuid)`)}`;
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
      name: "reserve_ai_file",
      args: ["{id}", "text", "text", "bigint", "uuid", "uuid"],
      returns: "jsonb",
    },
    { name: "confirm_ai_file", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_ai_file", args: ["uuid"], returns: "jsonb" },
    { name: "get_ai_file_by_path", args: ["text", "text"], returns: "jsonb" },
    { name: "list_ai_files", args: ["uuid"], returns: "jsonb" },
    { name: "delete_ai_file", args: ["uuid"], returns: "jsonb" },
    {
      name: "store_ai_file",
      args: ["{id}", "uuid", "text", "text", "bigint", "uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "set_ai_provider_file",
      args: ["uuid", "text", "text", "timestamptz"],
      returns: "boolean",
    },
    { name: "get_ai_provider_file", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "expiring_ai_provider_files",
      args: ["interval", "integer"],
      returns: "jsonb",
    },
    { name: "purge_ai_files", args: ["interval", "integer"], returns: "jsonb" },
    {
      name: "create_ai_document",
      args: ["{id}", "text", "text", "text", "uuid", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "update_ai_document",
      args: ["uuid", "text", "text", "text", "integer", "text"],
      returns: "jsonb",
    },
    {
      name: "rollback_ai_document",
      args: ["uuid", "integer"],
      returns: "jsonb",
    },
    { name: "get_ai_document", args: ["uuid"], returns: "jsonb" },
    { name: "list_ai_document_versions", args: ["uuid"], returns: "jsonb" },
    {
      name: "suggest_ai_document_edit",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_ai_suggestions",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "resolve_ai_suggestion",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "delete_ai_document", args: ["uuid"], returns: "boolean" },
  ];
}

export const AI_FILES: ModuleDefinition = {
  internal: ["ai_file_object_allowed"],
  name: "ai-files",
  title: "AI files",
  description:
    "Files and documents for AI chats: a private bucket whose policies only accept an upload a reserved record expects, provider file references with expiry, versioned documents with suggested edits, and a purge that hands back the objects to remove.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
  data,
};
