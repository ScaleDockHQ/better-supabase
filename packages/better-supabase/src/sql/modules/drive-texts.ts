import type { DriveKit } from "./drive-kit.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { searchColumnStatements } from "../search-column.ts";
import { lockTable, SERVICE_CALLER, serviceGrant } from "../shared.ts";

const MIN_TEXT_BYTES = 1024;
const DEFAULT_TEXT_BYTES = 1_048_576;

/** The characters of a file's text that search indexes. */
const SEARCH_TEXT_CHARS = 100_000;

const METER = /^[a-z][a-z0-9_.-]{0,62}$/u;

/** `options.maxTextBytes`: the most text the drive keeps per file. */
function maxTextBytes(kit: DriveKit): number {
  const value = kit.ctx.number("maxTextBytes", DEFAULT_TEXT_BYTES);

  if (!Number.isInteger(value) || value < MIN_TEXT_BYTES) {
    throw new TypeError(
      `blocks.drive.options.maxTextBytes must be an integer of at least ${String(MIN_TEXT_BYTES)}`,
    );
  }

  return value;
}

/**
 * The text extracted from each file, its read policy and the view search reads
 * a node's title and text from. The view exists without the texts table too, so
 * the `drive_node` subject's search stays valid without drive-files.
 */
export function driveTextTableSql(kit: DriveKit): string {
  const { ctx, T, n, fn, roles } = kit;
  const kept = ctx.has("nodes", "attachment") && ctx.hasTable("texts");
  const X = kept ? ctx.table("texts") : undefined;
  const x = (column: string): string => ctx.col("texts", column);
  const view = `${ctx.schema}.${sqlIdent(`${ctx.tableName("nodes").name.replace(/s$/u, "")}_search`)}`;

  const table =
    X !== undefined && ctx.owns("texts")
      ? `-- The text drive_set_text stored for each file's current content.
create table if not exists ${X} (
  ${x("node")} uuid primary key references ${T} (${n("id")}) on delete cascade,
  ${x("tenant")} ${ctx.idType} not null,
  ${x("attachment")} uuid not null,
  ${x("extractor")} text,
  ${x("content")} text not null,
  ${x("extractedAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${ctx.tableName("texts").name}_tenant_idx`)} on ${X} (${x("tenant")});${
          ctx.flag("searchColumn", false)
            ? searchColumnStatements(
                X,
                `${ctx.tableName("texts").name}_search_tsv_idx`,
                [`left(${x("content")}, ${String(SEARCH_TEXT_CHARS)})`],
              )
            : ""
        }
${lockTable(X, { read: true })}
${renderPolicy(makePolicy({ table: X, name: ctx.naming.rename("drive_node_texts_read"), command: "select", roles: ["authenticated"], using: `${fn("drive_can")}(${x("node")}, ${sqlString(roles.read)})` }), { drop: true, target: X })}
`
      : "";

  const content =
    X === undefined
      ? "null::text"
      : `left(t.${x("content")}, ${String(SEARCH_TEXT_CHARS)})`;

  const join =
    X === undefined
      ? ""
      : `\n  left join ${X} t on t.${x("node")} = s.${n("id")}`;

  return `${table}
-- Each node's name and the start of its text, for the drive_node search subject.
create or replace view ${view} with (security_invoker = true) as
  select s.${n("id")} as id, s.${n("name")} as name, ${content} as content
  from ${T} s${join};
revoke all on ${view} from public, anon, authenticated;
grant select on ${view} to service_role;
`;
}

/**
 * `drive_text_source` and `drive_set_text`: the service role reads a file's
 * current content and stores the text an extractor found in it.
 */
export function driveTextFunctionsSql(kit: DriveKit): string {
  const { ctx, T, n, fn, A, a, live } = kit;

  if (
    A === undefined ||
    !ctx.has("nodes", "attachment") ||
    !ctx.hasTable("texts")
  ) {
    return "";
  }

  const X = ctx.table("texts");
  const x = (column: string): string => ctx.col("texts", column);
  const max = String(maxTextBytes(kit));

  const extra = [
    ...(ctx.has("texts", "extractor")
      ? [[x("extractor"), "drive_set_text.extractor"]]
      : []),
    ...(ctx.has("texts", "extractedAt") ? [[x("extractedAt"), "now()"]] : []),
  ];

  const columns = extra.map(([column]) => `, ${column ?? ""}`).join("");
  const values = extra.map(([, value]) => `, ${value ?? ""}`).join("");

  const updates = extra
    .map(([column]) => `, ${column ?? ""} = excluded.${column ?? ""}`)
    .join("");

  return `
-- The current content of a file for a text extractor: its node, the stored
-- object and the attachment's scan status, found by node or by the attachment
-- that is a file's content. Null for a folder, a file without content, a node
-- in the bin or an attachment of another record.
create or replace function ${fn("drive_text_source")}(node uuid default null, attachment uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('nodeId', s.${n("id")}, 'organizationId', s.${n("tenant")}, 'name', s.${n("name")},
    'attachmentId', f.${a("id")}, 'bucket', f.${a("bucket")}, 'path', f.${a("path")}, 'mimeType', f.${a("mimeType")},
    'size', f.${a("size")}, 'status', f.${a("status")})
  from ${T} s
  join ${A} f on f.${a("id")} = s.${n("attachment")}
  where s.${n("id")} = coalesce(drive_text_source.node, (select x.${n("id")} from ${T} x where x.${n("attachment")} = drive_text_source.attachment limit 1))
    and (drive_text_source.attachment is null or s.${n("attachment")} = drive_text_source.attachment)
    and s.${n("kind")} = 'file'${live("s")}
    and f.${a("uploadedAt")} is not null
$$;
${serviceGrant(`${fn("drive_text_source")}(uuid, uuid)`)}

-- Stores the text extracted from attachment, the file's content, cut to
-- ${max} bytes. Null content forgets the file's text. Returns false when
-- attachment is no longer the file's content, so a slow extraction of an
-- older revision never replaces a newer one.
create or replace function ${fn("drive_set_text")}(node uuid, attachment uuid, content text, extractor text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_node ${T}%rowtype;
  v_content text := drive_set_text.content;
begin
  if not ${SERVICE_CALLER} then
    raise exception 'only the service role stores extracted text' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from ${T} s where s.${n("id")} = drive_set_text.node for update;
  if not found or v_node.${n("attachment")} is distinct from drive_set_text.attachment then
    return false;
  end if;
  if v_content is null or btrim(v_content) = '' then
    delete from ${X} t where t.${x("node")} = v_node.${n("id")};
    return true;
  end if;
  if octet_length(v_content) > ${max} then
    v_content := left(v_content, ${max});
    while octet_length(v_content) > ${max} loop
      v_content := left(v_content, length(v_content) - greatest(1, (octet_length(v_content) - ${max}) / 4));
    end loop;
  end if;
  insert into ${X} as t (${x("node")}, ${x("tenant")}, ${x("attachment")}, ${x("content")}${columns})
  values (v_node.${n("id")}, v_node.${n("tenant")}, drive_set_text.attachment, v_content${values})
  on conflict (${x("node")}) do update
    set ${x("tenant")} = excluded.${x("tenant")}, ${x("attachment")} = excluded.${x("attachment")}, ${x("content")} = excluded.${x("content")}${updates};
  return true;
end;
$$;
${serviceGrant(`${fn("drive_set_text")}(uuid, uuid, text, text)`)}
`;
}

/**
 * The check `drive_create_file` and `drive_upload_revision` run before a new
 * upload with `options.quota` and the usage block: a member over the meter's
 * quota gets `DRIVE_QUOTA_EXCEEDED`. The service role is never limited.
 */
export function driveQuotaCheck(
  kit: DriveKit,
  tenant: string,
  size: string,
): string {
  const quota = kit.ctx.option("quota");

  if (quota === undefined || quota === null) {
    return "";
  }

  const meter =
    typeof quota === "object" && "meter" in quota ? quota.meter : undefined;

  if (typeof meter !== "string" || !METER.test(meter)) {
    throw new TypeError(
      "blocks.drive.options.quota must be { meter }, a usage meter name in lowercase",
    );
  }

  if (!kit.own.installed("usage")) {
    throw new TypeError(
      "blocks.drive.options.quota needs the usage block for its meter",
    );
  }

  const name = sqlString(meter);
  const detail = sqlString(JSON.stringify({ meter }));

  return `
  if not ${SERVICE_CALLER} and not ${kit.own.of("usage").fn("within_quota")}(${tenant}, ${name}, greatest(coalesce(${size}, 0), 0)) then
    raise exception 'this upload would pass the organization''s quota for %', ${name} using errcode = '53400', hint = 'DRIVE_QUOTA_EXCEEDED', detail = ${detail};
  end if;`;
}
