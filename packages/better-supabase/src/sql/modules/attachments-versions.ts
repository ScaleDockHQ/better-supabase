import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, revokeTable } from "../shared.ts";

type Column = (logical: string) => string;

/** SQL for where each version of an attachments row lives in Storage. */
export interface VersionPaths {
  /**
   * The object path of a row's current version: version 1 at object_path, later
   * ones at object_path-v<version>, so a replaced file keeps its object.
   */
  readonly current: (row: string) => string;
  /**
   * Whether path is the current object of row; the any() keeps the (bucket,
   * object_path) index usable.
   */
  readonly atCurrent: (row: string, path: string) => string;
}

export function versionPaths(c: Column): VersionPaths {
  const current = (row: string): string =>
    `(case when ${row}.${c("version")} > 1 then ${row}.${c("path")} || '-v' || ${row}.${c("version")}::text else ${row}.${c("path")} end)`;

  return {
    current,
    atCurrent: (row, path) =>
      `${row}.${c("path")} = any (array[${path}, regexp_replace(${path}, '-v[0-9]+$', '')]) and ${current(row)} = ${path}`,
  };
}

export interface AttachmentVersionsOptions {
  /** The tenant column type. */
  readonly id: string;
  /** Whether some subject types store files without a tenant. */
  readonly tenantless: boolean;
  /** The row of v_row as the API's JSON. */
  readonly json: (row: string) => string;
  /** Whether the caller may change the versions of v_row. */
  readonly mayVersion: string;
}

export interface AttachmentVersionsSql {
  /** The versions table, its grants and its read policy. */
  readonly table: string;
  /** Replace_attachment, restore_attachment_version, list_attachment_versions. */
  readonly functions: string;
}

/**
 * The earlier versions of each attachment: replace_attachment() moves the
 * current file to the versions table and starts the next version,
 * restore_attachment_version() swaps one back. No object moves.
 */
export function attachmentVersionsSql(
  ctx: BlockSqlContext,
  options: AttachmentVersionsOptions,
): AttachmentVersionsSql {
  const t = ctx.table("attachments");
  const c: Column = (logical) => ctx.col("attachments", logical);
  const versions = ctx.table("versions");
  const vc: Column = (logical) => ctx.col("versions", logical);
  const fn = (name: string): string => ctx.fn(name);
  const { current } = versionPaths(c);
  const { json, mayVersion } = options;
  const versionsName = ctx.tableName("versions").name;

  const record = (
    type: "attachment.replaced" | "attachment.restored",
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('attachmentId', v_row.${c("id")}, 'organizationId', v_row.${c("tenant")}::text, 'subjectType', v_row.${c("subjectType")}, 'subjectId', v_row.${c("subjectId")}, ${type === "attachment.replaced" ? `'uploadedBy', v_row.${c("uploadedBy")}, ` : ""}'version', v_row.${c("version")})`,
      subject: `'attachments/' || v_row.${c("id")}::text`,
      tenant: `v_row.${c("tenant")}`,
      audit: {
        category: "data",
        targetType: "attachment",
        recordId: `v_row.${c("id")}::text`,
      },
    });

  const copied = [
    "tenant",
    "attachment",
    "version",
    "bucket",
    "path",
    "name",
    "mimeType",
    "size",
    "width",
    "height",
    "pages",
    "status",
    "detail",
    "uploadedBy",
    "uploadedAt",
    "scannedAt",
  ];

  const fromRow: Readonly<Record<string, string>> = {
    attachment: `v_row.${c("id")}`,
    path: current("v_row"),
  };

  // Moves the current version, once uploaded, to the versions table.
  const archive = `if v_row.${c("uploadedAt")} is not null then
    insert into ${versions} (${copied.map(vc).join(", ")})
    values (${copied.map((logical) => fromRow[logical] ?? `v_row.${c(logical)}`).join(", ")});
  end if;`;

  const restored = [
    "version",
    "name",
    "mimeType",
    "size",
    "width",
    "height",
    "pages",
    "status",
    "detail",
    "uploadedBy",
    "uploadedAt",
    "scannedAt",
  ];

  const table = `-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table if not exists ${versions} (
  ${vc("id")} uuid primary key default gen_random_uuid(),
  ${vc("tenant")} ${options.id}${options.tenantless ? "" : " not null"},
  ${vc("attachment")} uuid not null references ${t} (${c("id")}) on delete cascade,
  ${vc("version")} integer not null check (${vc("version")} >= 1),
  ${vc("bucket")} text not null,
  ${vc("path")} text not null,
  ${vc("name")} text not null,
  ${vc("mimeType")} text not null,
  ${vc("size")} bigint not null,
  ${vc("width")} integer,
  ${vc("height")} integer,
  ${vc("pages")} integer,
  ${vc("status")} text not null check (${vc("status")} in ('pending', 'clean', 'infected', 'failed')),
  ${vc("detail")} text,
  ${vc("uploadedBy")} uuid references auth.users (id) on delete set null,
  ${vc("uploadedAt")} timestamptz,
  ${vc("scannedAt")} timestamptz,
  ${vc("archivedAt")} timestamptz not null default now(),
  unique (${vc("attachment")}, ${vc("version")}),
  unique (${vc("bucket")}, ${vc("path")})
);
create index if not exists ${ctx.naming.rename("attachment_versions_uploaded_by_idx")} on ${versions} (${vc("uploadedBy")});
alter table ${versions} enable row level security;
${revokeTable(versions)}
grant select on ${versions} to authenticated;
grant all on ${versions} to service_role;
drop policy if exists ${sqlIdent(`${versionsName}_read`)} on ${versions};
create policy ${sqlIdent(`${versionsName}_read`)} on ${versions} for select to authenticated
  using (exists (select 1 from ${t} a where a.${c("id")} = ${vc("attachment")}));
`;

  const functions = `
-- Starts a new version of a file: the current one, once uploaded, moves to
-- ${versionsName}, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function ${fn("replace_attachment")}(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
  v_next integer;
begin
  select * into v_row from ${t} a where a.${c("id")} = replace_attachment.id for update;
  if v_row.${c("id")} is null or not (${mayVersion}) then
    ${fail("ATTACHMENT_NOT_FOUND", "No attachment you may replace has this id", "P0002")}
  end if;
  ${archive}
  select greatest(v_row.${c("version")} - case when v_row.${c("uploadedAt")} is null then 1 else 0 end, coalesce(max(v.${vc("version")}), 0)) + 1
  into v_next
  from ${versions} v where v.${vc("attachment")} = v_row.${c("id")};
  update ${t} a set
    ${c("version")} = v_next,
    ${c("name")} = replace_attachment.name,
    ${c("mimeType")} = lower(replace_attachment.mime_type),
    ${c("size")} = replace_attachment.size,
    ${c("width")} = replace_attachment.width,
    ${c("height")} = replace_attachment.height,
    ${c("pages")} = replace_attachment.pages,
    ${c("status")} = 'pending',
    ${c("detail")} = null,
    ${c("uploadedBy")} = coalesce(auth.uid(), a.${c("uploadedBy")}),
    ${c("uploadedAt")} = null,
    ${c("scannedAt")} = null
  where a.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${record("attachment.replaced")}
  return ${json("v_row")};
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function ${fn("restore_attachment_version")}(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t};
  v_old ${versions};
begin
  select * into v_row from ${t} a where a.${c("id")} = restore_attachment_version.id for update;
  if v_row.${c("id")} is null or not (${mayVersion}) then
    ${fail("ATTACHMENT_NOT_FOUND", "No attachment you may restore has this id", "P0002")}
  end if;
  select * into v_old from ${versions} v
  where v.${vc("attachment")} = v_row.${c("id")} and v.${vc("version")} = restore_attachment_version.version
  for update;
  if v_old.${vc("id")} is null then
    ${fail("ATTACHMENT_VERSION_NOT_FOUND", "The file has no earlier version with this number", "P0002")}
  end if;
  delete from ${versions} v where v.${vc("id")} = v_old.${vc("id")};
  ${archive}
  update ${t} a set
    ${restored.map((logical) => `${c(logical)} = v_old.${vc(logical)}`).join(",\n    ")}
  where a.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${record("attachment.restored")}
  return ${json("v_row")};
end;
$$;

-- A file's earlier versions, newest first.
create or replace function ${fn("list_attachment_versions")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(v) order by v.${vc("version")} desc), '[]'::jsonb)
  from ${versions} v where v.${vc("attachment")} = list_attachment_versions.id
$$;
revoke execute on function ${fn("replace_attachment")}(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function ${fn("restore_attachment_version")}(uuid, integer) from public, anon;
revoke execute on function ${fn("list_attachment_versions")}(uuid) from public, anon;
grant execute on function ${fn("replace_attachment")}(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function ${fn("restore_attachment_version")}(uuid, integer) to authenticated, service_role;
grant execute on function ${fn("list_attachment_versions")}(uuid) to authenticated, service_role;`;

  return { table, functions };
}
