import type { VersionsEvents } from "../../blocks/versions/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  sha256Hex,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { subjectWritable } from "../subject-write.ts";
import {
  type Subject,
  qualifiedTable,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { OPERATIONS } from "./access-model.ts";

const SUBJECT_PAYLOAD = ["organizationId", "subjectType", "subjectId"] as const;

const EVENTS: ModuleEvents<VersionsEvents> = {
  "version.created": {
    subject: "versions",
    payload: [...SUBJECT_PAYLOAD, "id", "number", "label", "source"],
  },
  "version.restored": {
    subject: "versions",
    payload: [...SUBJECT_PAYLOAD, "id", "number", "restoredFrom"],
  },
  "version.deleted": {
    subject: "versions",
    payload: [...SUBJECT_PAYLOAD, "id", "number"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: [
    "before_version_snapshot",
    "after_version_snapshot",
    "before_version_restore",
    "after_version_restore",
  ],
  options: ["subjects", "keep", "debounce", "extraColumns"],
  tables: {
    versions: {
      name: "versions",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        number: "number",
        label: "label",
        content: "content",
        storagePath: "storage_path",
        contentHash: "content_hash",
        source: "source",
        frozen: "frozen",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
  },
};

const COLUMN = /^[a-z_][a-z0-9_]*$/;
const FUNCTION = /^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$/;
const RESTORING = "better_supabase.versions_restoring";

interface Versioned {
  readonly type: string;
  readonly subject: Subject;
  /** The columns a snapshot copies and a restore writes back. */
  readonly columns: readonly string[];
  /** `schema.function(subject_id text, content jsonb)` that applies a restore. */
  readonly apply?: string;
  /** Snapshot on every change to `columns`, debounced. */
  readonly auto: boolean;
  /** Freeze a version when `column` changes to one of `values`. */
  readonly freeze?: { readonly column: string; readonly values: string[] };
}

function versioned(ctx: ModuleContext): readonly Versioned[] {
  const where = "blocks.versions.options.subjects";

  return subjectsOption(ctx, ["columns", "apply", "auto", "freeze"]).map(
    ([type, subject]) => {
      const extra = subject.extra;
      const columns = extra["columns"] ?? [];

      if (!isColumnList(columns)) {
        throw new TypeError(
          `${where}.${type}.columns must be a list of column names`,
        );
      }

      const apply = extra["apply"];

      if (
        apply !== undefined &&
        (typeof apply !== "string" || !FUNCTION.test(apply))
      ) {
        throw new TypeError(
          `${where}.${type}.apply must name a function, such as public.apply_document_version`,
        );
      }

      const auto = extra["auto"] ?? false;

      if (typeof auto !== "boolean") {
        throw new TypeError(`${where}.${type}.auto must be true or false`);
      }

      const freeze = freezeOf(extra["freeze"], `${where}.${type}.freeze`);

      if ((auto || freeze) && columns.length === 0) {
        throw new TypeError(
          `${where}.${type}: auto and freeze snapshot the columns listed in columns`,
        );
      }

      return {
        type,
        subject,
        columns,
        ...(apply === undefined ? {} : { apply }),
        auto,
        ...(freeze === undefined ? {} : { freeze }),
      };
    },
  );
}

const isColumnList = (value: unknown): value is string[] =>
  Array.isArray(value) &&
  value.every((column) => typeof column === "string" && COLUMN.test(column));

const isFreezeValues = (value: unknown): value is string[] =>
  Array.isArray(value) &&
  value.length > 0 &&
  value.every(
    (item) =>
      typeof item === "string" && item.length > 0 && !item.includes(","),
  );

interface FreezeInput {
  readonly column?: unknown;
  readonly values?: unknown;
}

const isFreezeInput = (value: unknown): value is FreezeInput =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function freezeOf(
  value: unknown,
  where: string,
): Versioned["freeze"] | undefined {
  if (value === undefined) {
    return undefined;
  }

  const expected = `${where} must be { column, values }`;

  if (!isFreezeInput(value)) {
    throw new TypeError(expected);
  }

  const { column, values } = value;

  if (typeof column !== "string" || !COLUMN.test(column)) {
    throw new TypeError(expected);
  }

  if (!isFreezeValues(values)) {
    throw new TypeError(
      `${where}.values must be a list of values without commas`,
    );
  }

  return { column, values };
}

const functionName = (name: string): string =>
  name.includes(".")
    ? name
        .split(".")
        .map((part) => sqlIdent(part))
        .join(".")
    : `public.${sqlIdent(name)}`;

/** `jsonb_object_agg` of `columns` from the row `s` of `subject`, into `target`. */
function captureCase(
  list: readonly Versioned[],
  type: string,
  id: string,
  target: string,
): string {
  const whens = list
    .filter((entry) => entry.columns.length > 0)
    .map(
      (entry) => `    when ${sqlString(entry.type)} then
      select jsonb_object_agg(e.key, e.value) into ${target}
      from ${qualifiedTable(entry.subject.table)} s, jsonb_each(to_jsonb(s)) e
      where ${subjectIdMatches(entry.subject, id)}
        and e.key = any (${sqlString(`{${entry.columns.join(",")}}`)}::text[]);`,
    );

  if (whens.length === 0) {
    return "";
  }

  return `case ${type}
${whens.join("\n")}
    else null;
  end case;`;
}

function restoreCase(list: readonly Versioned[]): string {
  const whens = list.flatMap((entry) => {
    if (entry.apply !== undefined) {
      return [
        `    when ${sqlString(entry.type)} then
      perform ${functionName(entry.apply)}(v_subject_id, v_content);`,
      ];
    }

    if (entry.columns.length === 0) {
      return [];
    }

    const table = qualifiedTable(entry.subject.table);

    const sets = entry.columns
      .map((column) => `${sqlIdent(column)} = r.${sqlIdent(column)}`)
      .join(", ");

    return [
      `    when ${sqlString(entry.type)} then
      update ${table} s set ${sets}
      from jsonb_populate_record(null::${table}, v_content) r
      where ${subjectIdMatches(entry.subject, "v_subject_id")};`,
    ];
  });

  const unsupported = fail(
    "VERSION_RESTORE_UNSUPPORTED",
    "this subject type has no columns or apply function to restore into",
    "22023",
  );

  if (whens.length === 0) {
    return unsupported;
  }

  return `perform set_config(${sqlString(RESTORING)}, 'on', true);
  case v_subject_type
${whens.join("\n")}
    else
      ${unsupported}
  end case;
  perform set_config(${sqlString(RESTORING)}, '', true);`;
}

function captureTriggers(
  ctx: ModuleContext,
  list: readonly Versioned[],
): string {
  const capture = ctx.fn("versions_capture");

  return list
    .flatMap((entry) => {
      const table = qualifiedTable(entry.subject.table);

      const args = (freeze: Versioned["freeze"]) =>
        [
          entry.type,
          entry.subject.id ?? "id",
          entry.subject.tenant === false
            ? ""
            : (entry.subject.tenant ?? "organization_id"),
          entry.columns.join(","),
          freeze?.column ?? "",
          freeze?.values.join(",") ?? "",
        ]
          .map((value) => sqlString(value))
          .join(", ");

      const statements: string[] = [];

      if (entry.auto) {
        const trigger = ctx.trigger(`versions_${entry.type}_auto`);
        statements.push(`drop trigger if exists ${trigger} on ${table};
create trigger ${trigger}
  after insert or update of ${entry.columns.map((column) => sqlIdent(column)).join(", ")} on ${table}
  for each row execute function ${capture}(${args(undefined)});`);
      }

      if (entry.freeze) {
        const trigger = ctx.trigger(`versions_${entry.type}_freeze`);
        statements.push(`drop trigger if exists ${trigger} on ${table};
create trigger ${trigger}
  after insert or update of ${sqlIdent(entry.freeze.column)} on ${table}
  for each row execute function ${capture}(${args(entry.freeze)});`);
      }

      return statements;
    })
    .join("\n\n");
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const versions = ctx.table("versions");
  const c = (column: string): string => ctx.col("versions", column);
  const read = ctx.permission("read", OPERATIONS["versions.read"]);
  const create = ctx.permission("create", OPERATIONS["versions.create"]);
  const restore = ctx.permission("restore", OPERATIONS["versions.restore"]);
  const manage = ctx.permission("manage", OPERATIONS["versions.manage"]);
  const list = versioned(ctx);
  const subjects = list.map((entry) => [entry.type, entry.subject] as const);
  const keep = ctx.number("keep", 50);
  const debounce = ctx.number("debounce", 300);

  if (!Number.isInteger(keep) || keep < 1) {
    throw new TypeError("blocks.versions.options.keep must be at least 1");
  }

  if (!Number.isInteger(debounce) || debounce < 0) {
    throw new TypeError(
      "blocks.versions.options.debounce must be a whole number of seconds",
    );
  }

  const fn = (name: string): string => ctx.fn(name);

  const readable = (prefix: string) =>
    subjectReadable(ctx, subjects, {
      type: `${prefix}subject_type`,
      id: `${prefix}subject_id`,
      tenant: `${prefix}tenant`,
    });

  const forbidden = fail(
    "VERSION_FORBIDDEN",
    "not allowed to read these versions",
  );

  const notFound = fail("VERSION_NOT_FOUND", "version not found", "P0002");
  // The version's extra columns: snapshot_version sets them, reads by
  // members return them under fields; the anon read of a shared version
  // leaves them out.
  const extras = ctx.extraColumns("versions", ["fields", "content"]);
  const extra = extraFieldsArg(extras);

  const summary = (row: string, withFields = true): string =>
    withExtraFields(
      `jsonb_build_object('id', ${row}.${c("id")}, 'number', ${row}.${c("number")}, 'label', ${row}.${c("label")}, 'source', ${row}.${c("source")}, 'frozen', ${row}.${c("frozen")}, 'contentHash', ${row}.${c("contentHash")}, 'storagePath', ${row}.${c("storagePath")}, 'subjectType', ${row}.${c("subjectType")}, 'subjectId', ${row}.${c("subjectId")}, 'createdBy', ${row}.${c("createdBy")}, 'createdAt', ${row}.${c("createdAt")})`,
      row,
      withFields ? extras : [],
    );

  const tables = ctx.manages
    ? `create table if not exists ${versions} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("number")} integer not null check (${c("number")} > 0),
  ${c("label")} text check (length(${c("label")}) between 1 and 120),
  ${c("content")} jsonb,
  ${c("storagePath")} text,
  ${c("contentHash")} text not null,
  ${c("source")} text not null default 'manual' check (${c("source")} in ('manual', 'auto', 'restore')),
  ${c("frozen")} boolean not null default false,
  ${c("createdBy")} uuid,
  ${c("createdAt")} timestamptz not null default now(),
  unique (${c("subjectType")}, ${c("subjectId")}, ${c("number")}),
  check (${c("content")} is not null or ${c("storagePath")} is not null)
);${addExtraColumns(versions, extras)}
create index if not exists ${sqlIdent(`${ctx.tableName("versions").name}_tenant_idx`)} on ${versions} (${c("tenant")});
${lockTable(versions, { read: true })}
drop policy if exists "versions_read" on ${versions};
create policy "versions_read" on ${versions} for select to authenticated
  using (${ctx.scope.check(c("tenant"), read)});
`
    : "";

  const capture = captureCase(
    list,
    "snapshot_version.subject_type",
    "snapshot_version.subject_id",
    "v_content",
  );

  return `${schemaPreamble(ctx)}
${tables}
-- Writes a version, numbered per subject. A version without a label whose
-- content matches the latest is not written again; an auto snapshot within
-- the debounce window of the previous auto snapshot replaces its content.
-- Keeps the newest ${String(keep)} versions without a label or freeze.
create or replace function ${fn("version_insert")}(tenant ${ctx.idType}, subject_type text, subject_id text, content jsonb, storage_path text, label text, source text, frozen boolean, actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := ${sha256Hex("coalesce(version_insert.content::text, '') || coalesce(version_insert.storage_path, '')")};
  v_last_id uuid;
  v_last_number integer;
  v_last_hash text;
  v_last_open boolean;
  v_last_source text;
  v_last_at timestamptz;
  v_id uuid;
  v_number integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('better_supabase.versions:' || version_insert.subject_type || ':' || version_insert.subject_id, 0));
  select v.${c("id")}, v.${c("number")}, v.${c("contentHash")}, v.${c("label")} is null and not v.${c("frozen")}, v.${c("source")}, v.${c("createdAt")}
    into v_last_id, v_last_number, v_last_hash, v_last_open, v_last_source, v_last_at
    from ${versions} v
    where v.${c("subjectType")} = version_insert.subject_type and v.${c("subjectId")} = version_insert.subject_id
    order by v.${c("number")} desc
    limit 1;
  if v_last_id is not null and version_insert.label is null and not version_insert.frozen and v_last_hash = v_hash then
    return jsonb_build_object('id', v_last_id, 'number', v_last_number, 'contentHash', v_hash, 'unchanged', true);
  end if;
  if version_insert.source = 'auto' and version_insert.label is null and not version_insert.frozen
    and v_last_open and v_last_source = 'auto' and v_last_at > now() - make_interval(secs => ${String(debounce)}) then
    update ${versions}
      set ${c("content")} = version_insert.content, ${c("storagePath")} = version_insert.storage_path, ${c("contentHash")} = v_hash
      where ${c("id")} = v_last_id;
    return jsonb_build_object('id', v_last_id, 'number', v_last_number, 'contentHash', v_hash, 'unchanged', false);
  end if;
  v_number := coalesce(v_last_number, 0) + 1;
  insert into ${versions} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("number")}, ${c("label")}, ${c("content")}, ${c("storagePath")}, ${c("contentHash")}, ${c("source")}, ${c("frozen")}, ${c("createdBy")}, ${c("createdAt")})
  values (version_insert.tenant, version_insert.subject_type, version_insert.subject_id, v_number, version_insert.label, version_insert.content, version_insert.storage_path, v_hash, version_insert.source, version_insert.frozen, version_insert.actor, now())
  returning ${c("id")} into v_id;
  delete from ${versions} v
  where v.${c("subjectType")} = version_insert.subject_type and v.${c("subjectId")} = version_insert.subject_id
    and v.${c("label")} is null and not v.${c("frozen")}
    and v.${c("id")} not in (
      select x.${c("id")} from ${versions} x
      where x.${c("subjectType")} = version_insert.subject_type and x.${c("subjectId")} = version_insert.subject_id
        and x.${c("label")} is null and not x.${c("frozen")}
      order by x.${c("number")} desc
      limit ${String(keep)}
    );
  ${ctx.record({
    type: "version.created",
    payload: `jsonb_build_object('organizationId', version_insert.tenant, 'subjectType', version_insert.subject_type, 'subjectId', version_insert.subject_id, 'id', v_id, 'number', v_number, 'label', version_insert.label, 'source', version_insert.source)`,
    subject: `'versions/' || v_id::text`,
    tenant: "version_insert.tenant",
    audit: false,
  })}
  return jsonb_build_object('id', v_id, 'number', v_number, 'contentHash', v_hash, 'unchanged', false);
end;
$$;
${serviceGrant(`${fn("version_insert")}(${ctx.idType}, text, text, jsonb, text, text, text, boolean, uuid)`)}

-- fields: the extra columns (blocks.versions.options.extraColumns) to set
-- on the version written, or on the latest one when the content is unchanged.
${extra.drop(fn("snapshot_version"), `${ctx.idType}, text, text, jsonb, text, text`)}
create or replace function ${fn("snapshot_version")}(tenant ${ctx.idType}, subject_type text, subject_id text, content jsonb default null, label text default null, storage_path text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_content jsonb := snapshot_version.content;
  v_result jsonb;
begin
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "snapshot_version.tenant", create)} and ${readable("snapshot_version.")})) then
    ${fail("VERSION_FORBIDDEN", "not allowed to snapshot this record")}
  end if;
  if v_content is null and snapshot_version.storage_path is null then
    ${capture}
    if v_content is null then
      ${fail("VERSION_CONTENT_REQUIRED", "pass content or a storage path, or list the subject's columns", "22023")}
    end if;
  end if;
  ${ctx.hook("before_version_snapshot", [
    [ctx.idType, "snapshot_version.tenant"],
    ["text", "snapshot_version.subject_type"],
    ["text", "snapshot_version.subject_id"],
  ])}
  v_result := ${fn("version_insert")}(snapshot_version.tenant, snapshot_version.subject_type, snapshot_version.subject_id, v_content, snapshot_version.storage_path, nullif(trim(snapshot_version.label), ''), 'manual', false, auth.uid());${writeExtraColumns(versions, extras, "snapshot_version.fields", `x.${c("id")} = (v_result ->> 'id')::uuid`)}
  ${ctx.hook("after_version_snapshot", [
    ["uuid", "(v_result ->> 'id')::uuid"],
    ["text", "snapshot_version.subject_type"],
    ["text", "snapshot_version.subject_id"],
  ])}
  return v_result;
end;
$$;
${userGrant(`${fn("snapshot_version")}(${ctx.idType}, text, text, jsonb, text, text${extra.type})`)}

create or replace function ${fn("list_versions")}(tenant ${ctx.idType}, subject_type text, subject_id text, page_size integer default 50, before integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "list_versions.tenant", read)} and ${readable("list_versions.")})) then
    ${forbidden}
  end if;
  select coalesce(jsonb_agg(${summary("v")} order by v.${c("number")} desc), '[]'::jsonb) into v_rows
  from (
    select * from ${versions} x
    where x.${c("tenant")} = list_versions.tenant
      and x.${c("subjectType")} = list_versions.subject_type
      and x.${c("subjectId")} = list_versions.subject_id
      and (list_versions.before is null or x.${c("number")} < list_versions.before)
    order by x.${c("number")} desc
    limit ${pageSize("list_versions.page_size", 50, 200)}
  ) v;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_versions")}(${ctx.idType}, text, text, integer, integer)`)}

create or replace function ${fn("get_version")}(version_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${versions}%rowtype;
begin
  select * into v_row from ${versions} where ${c("id")} = get_version.version_id;
  if not found then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", `v_row.${c("tenant")}`, read)} and ${subjectReadable(ctx, subjects, { type: `v_row.${c("subjectType")}`, id: `v_row.${c("subjectId")}`, tenant: `v_row.${c("tenant")}` })})) then
    ${forbidden}
  end if;
  return ${summary("v_row")} || jsonb_build_object('content', v_row.${c("content")});
end;
$$;
${userGrant(`${fn("get_version")}(uuid)`)}
${
  ctx.installed("share-links")
    ? `
-- A share link pinned to a version (create_share_link's version_id) reads
-- that version with the token alone, for anon. Volatile: resolving the link
-- counts a use.
create or replace function ${fn("get_shared_version")}(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_link jsonb;
  v_row ${versions}%rowtype;
begin
  if get_shared_version.token is null or get_shared_version.token !~ '^[0-9a-f]{48}$' then
    return null;
  end if;
  v_link := ${fn("resolve_share_link")}(get_shared_version.token);
  if v_link is null or v_link ->> 'versionId' is null then
    return null;
  end if;
  select * into v_row from ${versions}
  where ${c("id")} = (v_link ->> 'versionId')::uuid
    and ${c("subjectType")} = v_link ->> 'subjectType'
    and ${c("subjectId")} = v_link ->> 'subjectId';
  if not found then
    return null;
  end if;
  return (${summary("v_row", false)} - 'createdBy') || jsonb_build_object('content', v_row.${c("content")});
end;
$$;
revoke all on function ${fn("get_shared_version")}(text) from public, anon, authenticated;
grant execute on function ${fn("get_shared_version")}(text) to anon, authenticated, service_role;
`
    : ""
}

-- Writes a version's content back to its subject, through the subject's apply
-- function or its columns, then records the result as a new version.
create or replace function ${fn("restore_version")}(version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_subject_type text;
  v_subject_id text;
  v_number integer;
  v_content jsonb;
  v_result jsonb;
begin
  select ${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("number")}, ${c("content")}
    into v_tenant, v_subject_type, v_subject_id, v_number, v_content
    from ${versions} where ${c("id")} = restore_version.version_id;
  if v_subject_type is null then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "v_tenant", restore)} and ${subjectReadable(ctx, subjects, { type: "v_subject_type", id: "v_subject_id", tenant: "v_tenant" })} and ${subjectWritable(ctx, subjects, { type: "v_subject_type", tenant: "v_tenant" })})) then
    ${fail("VERSION_FORBIDDEN", "not allowed to restore this version")}
  end if;
  if v_content is null then
    ${fail("VERSION_RESTORE_UNSUPPORTED", "a version kept in Storage is restored by the app", "22023")}
  end if;
  ${ctx.hook("before_version_restore", [["uuid", "restore_version.version_id"]])}
  ${restoreCase(list)}
  v_result := ${fn("version_insert")}(v_tenant, v_subject_type, v_subject_id, v_content, null, null, 'restore', false, auth.uid());
  ${ctx.record({
    type: "version.restored",
    payload: `jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', (v_result ->> 'id')::uuid, 'number', (v_result ->> 'number')::integer, 'restoredFrom', v_number)`,
    subject: `'versions/' || (v_result ->> 'id')`,
    tenant: "v_tenant",
    audit: {
      category: "data",
      targetType: "version",
      recordId: "restore_version.version_id::text",
      summary: `'restored version ' || v_number::text`,
    },
  })}
  ${ctx.hook("after_version_restore", [
    ["uuid", "restore_version.version_id"],
    ["uuid", "(v_result ->> 'id')::uuid"],
  ])}
  return v_result || jsonb_build_object('content', v_content, 'restoredFrom', v_number);
end;
$$;
${userGrant(`${fn("restore_version")}(uuid)`)}

-- A label keeps a version out of retention; null removes it.
create or replace function ${fn("label_version")}(version_id uuid, label text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_subject_type text;
  v_subject_id text;
begin
  select ${c("tenant")}, ${c("subjectType")}, ${c("subjectId")} into v_tenant, v_subject_type, v_subject_id
    from ${versions} where ${c("id")} = label_version.version_id;
  if v_subject_type is null then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", "v_tenant", create)} and ${subjectReadable(ctx, subjects, { type: "v_subject_type", id: "v_subject_id", tenant: "v_tenant" })})) then
    ${fail("VERSION_FORBIDDEN", "not allowed to label this version")}
  end if;
  update ${versions} set ${c("label")} = nullif(trim(label_version.label), '')
    where ${c("id")} = label_version.version_id and not ${c("frozen")};
  if not found then
    ${fail("VERSION_FROZEN", "a frozen version keeps its label", "55000")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("label_version")}(uuid, text)`)}

create or replace function ${fn("delete_version")}(version_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_subject_type text;
  v_subject_id text;
  v_number integer;
  v_frozen boolean;
begin
  select ${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("number")}, ${c("frozen")}
    into v_tenant, v_subject_type, v_subject_id, v_number, v_frozen
    from ${versions} where ${c("id")} = delete_version.version_id;
  if v_subject_type is null then
    ${notFound}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "v_tenant", manage)}) then
    ${fail("VERSION_FORBIDDEN", "not allowed to delete versions")}
  end if;
  if v_frozen then
    ${fail("VERSION_FROZEN", "a frozen version can't be deleted", "55000")}
  end if;
  delete from ${versions} where ${c("id")} = delete_version.version_id;
  ${ctx.record({
    type: "version.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'subjectType', v_subject_type, 'subjectId', v_subject_id, 'id', delete_version.version_id, 'number', v_number)`,
    subject: `'versions/' || delete_version.version_id::text`,
    tenant: "v_tenant",
    audit: {
      category: "data",
      targetType: "version",
      recordId: "delete_version.version_id::text",
      summary: `'deleted version ' || v_number::text`,
    },
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_version")}(uuid)`)}

-- options.subjects.<type>.auto and .freeze: tg_argv is the subject type, its
-- id and tenant columns, the snapshot columns, then the freeze column and
-- values (empty for auto). A restore sets ${RESTORING}, so it isn't
-- snapshotted twice.
create or replace function ${fn("versions_capture")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_columns text[] := string_to_array(tg_argv[3], ',');
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_content jsonb;
  v_previous jsonb;
  v_label text;
begin
  if coalesce(current_setting(${sqlString(RESTORING)}, true), '') = 'on' then
    return null;
  end if;
  select jsonb_object_agg(e.key, e.value) into v_content from jsonb_each(v_new) e where e.key = any (v_columns);
  if tg_argv[4] = '' then
    if v_old is not null then
      select jsonb_object_agg(e.key, e.value) into v_previous from jsonb_each(v_old) e where e.key = any (v_columns);
      if v_previous is not distinct from v_content then
        return null;
      end if;
    end if;
    perform ${fn("version_insert")}((v_new ->> tg_argv[2])::${ctx.idType}, tg_argv[0], v_new ->> tg_argv[1], v_content, null, null, 'auto', false, auth.uid());
  else
    v_label := v_new ->> tg_argv[4];
    if v_label = any (string_to_array(tg_argv[5], ',')) and (v_old is null or (v_old ->> tg_argv[4]) is distinct from v_label) then
      perform ${fn("version_insert")}((v_new ->> tg_argv[2])::${ctx.idType}, tg_argv[0], v_new ->> tg_argv[1], v_content, null, v_label, 'auto', true, auth.uid());
    end if;
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("versions_capture")}() from public, anon, authenticated;
${captureTriggers(ctx, list)}
`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("versions", ["fields", "content"]),
  ).contract;

  return [
    {
      name: "version_insert",
      args: [
        "{id}",
        "text",
        "text",
        "jsonb",
        "text",
        "text",
        "text",
        "boolean",
        "uuid",
      ],
      returns: "jsonb",
    },
    {
      name: "snapshot_version",
      args: ["{id}", "text", "text", "jsonb", "text", "text", ...extra],
      returns: "jsonb",
    },
    { name: "get_version", args: ["uuid"], returns: "jsonb" },
    { name: "restore_version", args: ["uuid"], returns: "jsonb" },
  ];
}

export const VERSIONS: ModuleDefinition = {
  name: "versions",
  scopes: ["tenant"],
  title: "Versions",
  description:
    "Numbered snapshots of a subject's content: manual, debounced auto and frozen snapshots, restore through columns or an apply function, and retention.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit", "share-links"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
