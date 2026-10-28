import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { raise, serviceGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

export const DOCUMENTS = {
  scopeKey: "scope_key",
  path: "path",
  content: "content",
  version: "version",
  expiresAt: "expires_at",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

/**
 * The memory documents an agent runtime keeps (eve's file memory and replay
 * records): the table and the service-role functions over it.
 */
export function memoryDocumentsSql(
  ctx: BlockSqlContext,
  maxContent: number,
): string {
  const documents = ctx.table("documents");

  const doc = (column: keyof typeof DOCUMENTS): boolean =>
    ctx.has("documents", column);

  const col = (column: keyof typeof DOCUMENTS): string =>
    doc(column) ? ctx.col("documents", column) : "";

  const d = {
    scopeKey: col("scopeKey"),
    path: col("path"),
    content: col("content"),
    version: col("version"),
    expiresAt: col("expiresAt"),
    createdAt: col("createdAt"),
    updatedAt: col("updatedAt"),
  };

  const fn = (name: string): string => ctx.fn(name);

  const signature = (name: string, args: string): string =>
    `${fn(name)}(${args})`;

  const line = (present: boolean, definition: string): string =>
    present ? `\n  ${definition},` : "";

  const unique = ctx.owns("documents")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("documents").name}_path_key`)} on ${documents} (${d.scopeKey}, ${d.path});`;

  const checkContent = (content: string): string => `
  if length(${content}) > ${String(maxContent)} then
    ${raise("memory content is limited to % characters", "22023", "MEMORY_TOO_LARGE", String(maxContent))}
  end if;`;

  return `-- Documents an agent runtime keeps under an opaque scope key, such as eve's
-- file memory and its replay records. Only the service role reads or writes
-- them; a write names the version it read, so a stale write fails.
create table if not exists ${documents} (
  ${d.scopeKey} text not null check (length(${d.scopeKey}) <= 4096),
  ${d.path} text not null check (length(${d.path}) <= 1024),
  ${d.content} text not null check (length(${d.content}) <= ${String(maxContent)}),
  ${d.version} bigint not null default 1,${line(doc("expiresAt"), `${d.expiresAt} timestamptz`)}${line(doc("createdAt"), `${d.createdAt} timestamptz not null default now()`)}${line(doc("updatedAt"), `${d.updatedAt} timestamptz not null default now()`)}
  primary key (${d.scopeKey}, ${d.path})
);${unique}
${doc("expiresAt") ? `create index if not exists ${ctx.naming.rename("memory_documents_expires_idx")} on ${documents} (${d.expiresAt}) where ${d.expiresAt} is not null;\n` : ""}${lockModuleTable(ctx, "documents")}

-- A document and its version, or null.
create or replace function ${fn("memory_document_read")}(scope_key text, path text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('content', x.${d.content}, 'version', x.${d.version}::text)
  from ${documents} x
  where x.${d.scopeKey} = memory_document_read.scope_key and x.${d.path} = memory_document_read.path${doc("expiresAt") ? `\n    and (x.${d.expiresAt} is null or x.${d.expiresAt} > now())` : ""}
$$;
${serviceGrant(signature("memory_document_read", "text, text"))}

-- Writes a document when its version is still expected_version; null means
-- it must not exist yet. Otherwise raises MEMORY_DOCUMENT_CONFLICT.
create or replace function ${fn("memory_document_write")}(scope_key text, path text, content text, expected_version text default null, expires_in integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${documents}%rowtype;
  v_expires timestamptz := case when memory_document_write.expires_in is null then null else now() + make_interval(secs => memory_document_write.expires_in) end;
begin${checkContent("memory_document_write.content")}${
    doc("expiresAt")
      ? `
  delete from ${documents} x
  where x.${d.scopeKey} = memory_document_write.scope_key and x.${d.path} = memory_document_write.path
    and x.${d.expiresAt} <= now();`
      : ""
  }
  if memory_document_write.expected_version is null then
    insert into ${documents} (${d.scopeKey}, ${d.path}, ${d.content}${doc("expiresAt") ? `, ${d.expiresAt}` : ""})
    values (memory_document_write.scope_key, memory_document_write.path, memory_document_write.content${doc("expiresAt") ? ", v_expires" : ""})
    on conflict (${d.scopeKey}, ${d.path}) do nothing
    returning * into v_row;
  else
    update ${documents} x set ${[`${d.content} = memory_document_write.content`, `${d.version} = x.${d.version} + 1`].join(", ")}${
      doc("expiresAt") || doc("updatedAt")
        ? `,\n      ${[...(doc("expiresAt") ? [`${d.expiresAt} = v_expires`] : []), ...(doc("updatedAt") ? [`${d.updatedAt} = now()`] : [])].join(", ")}`
        : ""
    }
    where x.${d.scopeKey} = memory_document_write.scope_key and x.${d.path} = memory_document_write.path
      and x.${d.version}::text = memory_document_write.expected_version
    returning * into v_row;
  end if;
  if not found then
    ${raise("% changed since version %", "40001", "MEMORY_DOCUMENT_CONFLICT", "memory_document_write.path", "coalesce(memory_document_write.expected_version, 'none')")}
  end if;
  return jsonb_build_object('content', v_row.${d.content}, 'version', v_row.${d.version}::text);
end;
$$;
${serviceGrant(signature("memory_document_write", "text, text, text, text, integer"))}

-- Deletes expired documents, at most batch. Returns how many.
create or replace function ${fn("purge_memory_documents")}(batch integer default 1000)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${
    doc("expiresAt")
      ? `
  delete from ${documents} x
  where (x.${d.scopeKey}, x.${d.path}) in (
    select y.${d.scopeKey}, y.${d.path} from ${documents} y
    where y.${d.expiresAt} <= now()
    limit least(greatest(purge_memory_documents.batch, 1), 10000)
  );
  get diagnostics v_count = row_count;`
      : `
  v_count := 0;`
  }
  return v_count;
end;
$$;
${serviceGrant(signature("purge_memory_documents", "integer"))}`;
}
