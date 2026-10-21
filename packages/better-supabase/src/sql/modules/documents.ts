import type { DocumentsEvents } from "../../blocks/documents/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { subjectWritable } from "../subject-write.ts";
import {
  subjectCascades,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./access-model.ts";

const TOPIC = /^[a-z][a-z0-9_-]{0,30}$/;

const UUID_TEXT =
  "'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'";

const EVENTS: ModuleEvents<DocumentsEvents> = {
  "document.created": {
    subject: "documents",
    payload: ["organizationId", "subjectType", "subjectId", "id", "name"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_document_create", "after_document_create"],
  options: ["subjects", "topic", "maxUpdateBytes", "compactAfter"],
  tables: {
    documents: {
      name: "documents",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        name: "name",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    updates: {
      name: "document_updates",
      lifecycle: { tenant: "tenant", user: "actor" },
      columns: {
        seq: "seq",
        document: "document_id",
        tenant: "tenant_id",
        update: "payload",
        actor: "actor",
        createdAt: "created_at",
      },
    },
    snapshots: {
      name: "document_snapshots",
      lifecycle: { tenant: "tenant" },
      columns: {
        document: "document_id",
        tenant: "tenant_id",
        state: "state",
        seq: "seq",
        createdAt: "created_at",
      },
    },
  },
};

/** `options.topic`: the realtime topic prefix, `documents` by default. */
function documentsTopic(ctx: ModuleContext): string {
  const topic = ctx.text("topic", "documents");

  if (!TOPIC.test(topic)) {
    throw new TypeError(
      "blocks.documents.options.topic must be a lowercase name of at most 31 characters",
    );
  }

  return topic;
}

const b64 = (bytes: string): string =>
  `replace(encode(${bytes}, 'base64'), E'\\n', '')`;

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const documents = ctx.table("documents");
  const updates = ctx.table("updates");
  const snapshots = ctx.table("snapshots");
  const c = (column: string): string => ctx.col("documents", column);
  const u = (column: string): string => ctx.col("updates", column);
  const s = (column: string): string => ctx.col("snapshots", column);
  const fn = (name: string): string => ctx.fn(name);
  const read = ctx.permission("read", OPERATIONS["documents.read"]);
  const write = ctx.permission("write", OPERATIONS["documents.write"]);
  const manage = ctx.permission("manage", OPERATIONS["documents.manage"]);
  const subjects = subjectsOption(ctx);
  const topic = documentsTopic(ctx);
  const maxBytes = ctx.number("maxUpdateBytes", 1_048_576);
  const compactAfter = ctx.number("compactAfter", 200);

  if (!Number.isInteger(maxBytes) || maxBytes < 1) {
    throw new TypeError(
      "blocks.documents.options.maxUpdateBytes must be a positive whole number",
    );
  }

  if (!Number.isInteger(compactAfter) || compactAfter < 1) {
    throw new TypeError(
      "blocks.documents.options.compactAfter must be a positive whole number",
    );
  }

  const readable = (row: string): string =>
    subjectReadable(ctx, subjects, {
      type: `${row}.${c("subjectType")}`,
      id: `${row}.${c("subjectId")}`,
      tenant: `${row}.${c("tenant")}`,
    });

  const canRead = (row: string): string =>
    `(${ctx.can("tenant", `${row}.${c("tenant")}`, read)} and ${readable(row)})`;

  const canWrite = (row: string): string =>
    `(${ctx.can("tenant", `${row}.${c("tenant")}`, write)} and ${readable(row)} and ${subjectWritable(ctx, subjects, { type: `${row}.${c("subjectType")}`, tenant: `${row}.${c("tenant")}` })})`;

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'name', ${row}.${c("name")}, 'topic', ${sqlString(`${topic}:`)} || ${row}.${c("id")}::text, 'createdAt', ${row}.${c("createdAt")}, 'updatedAt', ${row}.${c("updatedAt")})`;

  const notFound = fail("DOCUMENT_NOT_FOUND", "document not found", "P0002");

  const versions =
    ctx.installed("versions") && ctx.of("versions").mode !== "custom"
      ? ctx.of("versions")
      : undefined;

  const v = (column: string): string =>
    versions === undefined ? column : versions.col("versions", column);

  const compactJob = ctx.enqueue(
    "documents.compact",
    `jsonb_build_object('documentId', v_doc.${c("id")})`,
    `'documents.compact:' || v_doc.${c("id")}::text`,
  );

  const tables = ctx.manages
    ? `create table if not exists ${documents} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("name")} text not null default 'body' check (${c("name")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${c("createdBy")} uuid,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  unique (${c("subjectType")}, ${c("subjectId")}, ${c("name")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("documents").name}_tenant_idx`)} on ${documents} (${c("tenant")}, ${c("updatedAt")} desc);
${lockTable(documents, { read: true })}
drop policy if exists "documents_read" on ${documents};
create policy "documents_read" on ${documents} for select to authenticated
  using (${ctx.scope.check(c("tenant"), read)});

create table if not exists ${updates} (
  ${u("seq")} bigint generated always as identity primary key,
  ${u("document")} uuid not null references ${documents} (${c("id")}) on delete cascade,
  ${u("tenant")} ${ctx.idType} not null,
  ${u("update")} bytea not null,
  ${u("actor")} uuid,
  ${u("createdAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${ctx.tableName("updates").name}_document_idx`)} on ${updates} (${u("document")}, ${u("seq")});
${lockTable(updates, { read: false })}

create table if not exists ${snapshots} (
  ${s("document")} uuid primary key references ${documents} (${c("id")}) on delete cascade,
  ${s("tenant")} ${ctx.idType} not null,
  ${s("state")} bytea not null,
  ${s("seq")} bigint not null,
  ${s("createdAt")} timestamptz not null default now()
);
${lockTable(snapshots, { read: false })}
`
    : "";

  const versionFunctions =
    versions === undefined
      ? ""
      : `
-- Saves the client's merged state as a version of subject 'document'.
create or replace function ${fn("save_document_version")}(document_id uuid, state text, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = save_document_version.document_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite("v_doc")}) then
    ${fail("DOCUMENT_FORBIDDEN", "not allowed to edit this document")}
  end if;
  return ${versions.fn("version_insert")}(v_doc.${c("tenant")}, 'document', v_doc.${c("id")}::text,
    jsonb_build_object('state', save_document_version.state, 'name', v_doc.${c("name")}),
    null, nullif(trim(save_document_version.label), ''), 'manual', false, auth.uid());
end;
$$;
${userGrant(`${fn("save_document_version")}(uuid, text, text)`)}

create or replace function ${fn("list_document_versions")}(document_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = list_document_versions.document_id;
  if not found or not (${SERVICE_CALLER} or ${canRead("v_doc")}) then
    ${notFound}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x.${v("id")}, 'number', x.${v("number")}, 'label', x.${v("label")}, 'createdBy', x.${v("createdBy")}, 'createdAt', x.${v("createdAt")}) order by x.${v("number")} desc), '[]'::jsonb)
    from ${versions.table("versions")} x
    where x.${v("subjectType")} = 'document' and x.${v("subjectId")} = v_doc.${c("id")}::text
  );
end;
$$;
${userGrant(`${fn("list_document_versions")}(uuid)`)}

-- A saved state, for a preview or for the client to restore from.
create or replace function ${fn("get_document_version")}(document_id uuid, version_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
  v_state text;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = get_document_version.document_id;
  if not found or not (${SERVICE_CALLER} or ${canRead("v_doc")}) then
    ${notFound}
  end if;
  select x.${v("content")} ->> 'state' into v_state from ${versions.table("versions")} x
  where x.${v("id")} = get_document_version.version_id
    and x.${v("subjectType")} = 'document' and x.${v("subjectId")} = v_doc.${c("id")}::text;
  if v_state is null then
    ${fail("DOCUMENT_VERSION_NOT_FOUND", "version not found", "P0002")}
  end if;
  return v_state;
end;
$$;
${userGrant(`${fn("get_document_version")}(uuid, uuid)`)}
`;

  return `${schemaPreamble(ctx)}
${tables}
-- Whether the caller may read (or, with write, edit) a document. The
-- realtime policies call it with the id from the topic.
create or replace function ${fn("document_access")}(document_id uuid, write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = document_access.document_id;
  if not found then
    return false;
  end if;
  if ${SERVICE_CALLER} then
    return true;
  end if;
  if document_access.write then
    return ${canWrite("v_doc")};
  end if;
  return ${canRead("v_doc")};
end;
$$;
${userGrant(`${fn("document_access")}(uuid, boolean)`)}

create or replace function ${fn("document_topic_access")}(topic text, write boolean)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when document_topic_access.topic like ${sqlString(`${topic}:%`)}
      and substr(document_topic_access.topic, ${String(topic.length + 2)}) ~ ${UUID_TEXT}
    then ${fn("document_access")}(substr(document_topic_access.topic, ${String(topic.length + 2)})::uuid, document_topic_access.write)
    else false
  end
$$;
${userGrant(`${fn("document_topic_access")}(text, boolean)`)}

-- The state to start from: the latest snapshot and the updates after it.
-- Creates the document on first open when the caller may edit it.
create or replace function ${fn("open_document")}(tenant ${ctx.idType}, subject_type text, subject_id text, name text default 'body')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
  v_snapshot ${snapshots}%rowtype;
  v_write boolean;
begin
  select * into v_doc from ${documents} d
  where d.${c("subjectType")} = open_document.subject_type and d.${c("subjectId")} = open_document.subject_id and d.${c("name")} = open_document.name;
  if found and v_doc.${c("tenant")} <> open_document.tenant then
    ${notFound}
  end if;
  if not found then
    v_doc.${c("tenant")} := open_document.tenant;
    v_doc.${c("subjectType")} := open_document.subject_type;
    v_doc.${c("subjectId")} := open_document.subject_id;
    if not (${SERVICE_CALLER} or ${canWrite("v_doc")}) then
      if ${canRead("v_doc")} then
        ${notFound}
      end if;
      ${fail("DOCUMENT_FORBIDDEN", "not allowed to open this document")}
    end if;
    ${ctx.hook("before_document_create", [
      [ctx.idType, "open_document.tenant"],
      ["text", "open_document.subject_type"],
      ["text", "open_document.subject_id"],
      ["text", "open_document.name"],
    ])}
    insert into ${documents} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("name")}, ${c("createdBy")})
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict (${c("subjectType")}, ${c("subjectId")}, ${c("name")}) do nothing
    returning * into v_doc;
    if found then
      ${ctx.record({
        type: "document.created",
        payload: `jsonb_build_object('organizationId', v_doc.${c("tenant")}::text, 'subjectType', v_doc.${c("subjectType")}, 'subjectId', v_doc.${c("subjectId")}, 'id', v_doc.${c("id")}, 'name', v_doc.${c("name")})`,
        subject: `'documents/' || v_doc.${c("id")}::text`,
        tenant: `v_doc.${c("tenant")}`,
        audit: {
          category: "data",
          targetType: "document",
          recordId: `v_doc.${c("id")}::text`,
        },
      })}
      ${ctx.hook("after_document_create", [["uuid", `v_doc.${c("id")}`]])}
    else
      select * into v_doc from ${documents} d
      where d.${c("subjectType")} = open_document.subject_type and d.${c("subjectId")} = open_document.subject_id and d.${c("name")} = open_document.name;
    end if;
  elsif not (${SERVICE_CALLER} or ${canRead("v_doc")}) then
    ${notFound}
  end if;
  v_write := ${SERVICE_CALLER} or ${canWrite("v_doc")};
  select * into v_snapshot from ${snapshots} x where x.${s("document")} = v_doc.${c("id")};
  return ${json("v_doc")} || jsonb_build_object(
    'canWrite', v_write,
    'snapshot', case when v_snapshot.${s("document")} is null then null else ${b64(`v_snapshot.${s("state")}`)} end,
    'snapshotSeq', coalesce(v_snapshot.${s("seq")}, 0),
    'updates', ${fn("document_updates_after")}(v_doc.${c("id")}, coalesce(v_snapshot.${s("seq")}, 0))
  );
end;
$$;
${userGrant(`${fn("open_document")}(${ctx.idType}, text, text, text)`)}

create or replace function ${fn("document_updates_after")}(document_id uuid, after_seq bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('seq', x.${u("seq")}, 'update', ${b64(`x.${u("update")}`)}) order by x.${u("seq")}), '[]'::jsonb)
  from ${updates} x
  where x.${u("document")} = document_updates_after.document_id and x.${u("seq")} > document_updates_after.after_seq
$$;
revoke execute on function ${fn("document_updates_after")}(uuid, bigint) from public, anon, authenticated;

-- Appends a Yjs update (base64) and returns its sequence number. Past
-- options.compactAfter updates since the snapshot, enqueues documents.compact.
create or replace function ${fn("push_document_update")}(document_id uuid, payload text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = push_document_update.document_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${canWrite("v_doc")}) then
    ${fail("DOCUMENT_FORBIDDEN", "not allowed to edit this document")}
  end if;
  begin
    v_bytes := decode(push_document_update.payload, 'base64');
  exception when others then
    ${fail("DOCUMENT_UPDATE_INVALID", "the update must be base64", "22023")}
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    ${fail("DOCUMENT_UPDATE_INVALID", "the update is empty", "22023")}
  end if;
  if length(v_bytes) > ${String(maxBytes)} then
    ${fail("DOCUMENT_UPDATE_TOO_LARGE", `an update can be at most ${String(maxBytes)} bytes`, "54000")}
  end if;
  insert into ${updates} (${u("document")}, ${u("tenant")}, ${u("update")}, ${u("actor")})
  values (v_doc.${c("id")}, v_doc.${c("tenant")}, v_bytes, auth.uid())
  returning ${u("seq")} into v_seq;
  update ${documents} d set ${c("updatedAt")} = now() where d.${c("id")} = v_doc.${c("id")};
  select count(*) into v_since from ${updates} x
  where x.${u("document")} = v_doc.${c("id")}
    and x.${u("seq")} > coalesce((select y.${s("seq")} from ${snapshots} y where y.${s("document")} = v_doc.${c("id")}), 0);
  if v_since = ${String(compactAfter)} then
    ${compactJob}
  end if;
  return v_seq;
end;
$$;
${userGrant(`${fn("push_document_update")}(uuid, text)`)}

-- Updates after a sequence number, for a client that reconnects. When they
-- were compacted away, the snapshot comes back too.
create or replace function ${fn("pull_document_updates")}(document_id uuid, after_seq bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
  v_snapshot ${snapshots}%rowtype;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = pull_document_updates.document_id;
  if not found or not (${SERVICE_CALLER} or ${canRead("v_doc")}) then
    ${notFound}
  end if;
  select * into v_snapshot from ${snapshots} x where x.${s("document")} = v_doc.${c("id")};
  if v_snapshot.${s("document")} is not null and pull_document_updates.after_seq < v_snapshot.${s("seq")} then
    return jsonb_build_object(
      'snapshot', ${b64(`v_snapshot.${s("state")}`)},
      'snapshotSeq', v_snapshot.${s("seq")},
      'updates', ${fn("document_updates_after")}(v_doc.${c("id")}, v_snapshot.${s("seq")})
    );
  end if;
  return jsonb_build_object('updates', ${fn("document_updates_after")}(v_doc.${c("id")}, pull_document_updates.after_seq));
end;
$$;
${userGrant(`${fn("pull_document_updates")}(uuid, bigint)`)}

-- Stores the merged state of every update through a sequence number and
-- drops those updates. Yjs merges in JavaScript, so the compaction job (or
-- a manager) sends the state.
create or replace function ${fn("compact_document")}(document_id uuid, state text, through_seq bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc ${documents}%rowtype;
  v_current bigint;
  v_last bigint;
begin
  select * into v_doc from ${documents} d where d.${c("id")} = compact_document.document_id for update;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_doc.${c("tenant")}`, manage)}) then
    ${fail("DOCUMENT_FORBIDDEN", "not allowed to compact this document")}
  end if;
  select x.${s("seq")} into v_current from ${snapshots} x where x.${s("document")} = v_doc.${c("id")};
  select max(x.${u("seq")}) into v_last from ${updates} x where x.${u("document")} = v_doc.${c("id")};
  if compact_document.through_seq <= coalesce(v_current, 0) then
    return false;
  end if;
  if v_last is null or compact_document.through_seq > v_last then
    ${fail("DOCUMENT_COMPACT_INVALID", "through_seq is past the last update", "22023")}
  end if;
  insert into ${snapshots} (${s("document")}, ${s("tenant")}, ${s("state")}, ${s("seq")})
  values (v_doc.${c("id")}, v_doc.${c("tenant")}, decode(compact_document.state, 'base64'), compact_document.through_seq)
  on conflict (${s("document")}) do update
    set ${s("state")} = excluded.${s("state")}, ${s("seq")} = excluded.${s("seq")}, ${s("createdAt")} = now();
  delete from ${updates} x where x.${u("document")} = v_doc.${c("id")} and x.${u("seq")} <= compact_document.through_seq;
  return true;
end;
$$;
${userGrant(`${fn("compact_document")}(uuid, text, bigint)`)}

-- Documents with at least min_updates updates since their snapshot, for a
-- compaction sweep without the jobs module.
create or replace function ${fn("documents_to_compact")}(min_updates integer default ${String(compactAfter)}, max_documents integer default 50)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(t.document_id), '{}'::uuid[]) from (
  select x.${u("document")} as document_id
  from ${updates} x
  left join ${snapshots} y on y.${s("document")} = x.${u("document")}
  where x.${u("seq")} > coalesce(y.${s("seq")}, 0)
  group by x.${u("document")}
  having count(*) >= greatest(coalesce(documents_to_compact.min_updates, 1), 1)
  order by count(*) desc
  limit greatest(coalesce(documents_to_compact.max_documents, 50), 1)
  ) t
$$;
${serviceGrant(`${fn("documents_to_compact")}(integer, integer)`)}
${versionFunctions}
-- Readers join ${topic}:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${ctx.trigger("documents_receive")} on realtime.messages;
    create policy ${ctx.trigger("documents_receive")} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension in ('broadcast', 'presence')
        and ${fn("document_topic_access")}((select realtime.topic()), false)
      );
    drop policy if exists ${ctx.trigger("documents_send")} on realtime.messages;
    create policy ${ctx.trigger("documents_send")} on realtime.messages for insert to authenticated
      with check (
        (realtime.messages.extension = 'broadcast' and ${fn("document_topic_access")}((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and ${fn("document_topic_access")}((select realtime.topic()), false))
      );
  end if;
end;
$do$;
${subjectCascades(ctx, subjects, `delete from ${documents} d where d.${c("subjectType")} = v_type and d.${c("subjectId")} = v_id;`)}
`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "open_document",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "push_document_update", args: ["uuid", "text"], returns: "bigint" },
    {
      name: "pull_document_updates",
      args: ["uuid", "bigint"],
      returns: "jsonb",
    },
    {
      name: "compact_document",
      args: ["uuid", "text", "bigint"],
      returns: "boolean",
    },
  ];
}

export const DOCUMENTS: ModuleDefinition = {
  internal: ["document_updates_after"],
  name: "documents",
  scopes: ["tenant"],
  title: "Collaborative documents",
  description:
    "Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, and saved states through the versions module.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit", "jobs", "versions"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  topics: (ctx) => [`${documentsTopic(ctx)}:{document}`],
  contract,
  build,
};
