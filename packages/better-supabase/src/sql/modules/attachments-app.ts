import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";
import type { Subject } from "../subjects.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { installedTables, laterTables } from "../later-tables.ts";
import { fail, quotedTable, SERVICE_CALLER } from "../shared.ts";
import { subjectReadable, subjectsOption } from "../subjects.ts";

/**
 * A row of `table` as JSON under the module's default column names, which the
 * TypeScript side reads, with `values` in place of some columns. On the app's
 * table `to_jsonb` would return the app's own names and its other columns, so
 * the object names each column the table has.
 */
export function namedRowJson(
  ctx: BlockSqlContext,
  table: string,
  row: string,
  values: Readonly<Record<string, string>>,
): string {
  const columns = ctx.names.tables[table]?.columns ?? {};

  return `jsonb_build_object(${Object.entries(columns)
    .filter(([logical]) => ctx.has(table, logical))
    .map(
      ([logical, name]) =>
        `${sqlString(name)}, ${values[logical] ?? `${row}.${ctx.col(table, logical)}`}`,
    )
    .join(", ")})`;
}

/** `row.column`, or null when the table lacks the optional column. */
export const columnOrNull = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/**
 * The status of a `from` row written to `to`, whose status may be the app's
 * type.
 */
export const statusFrom = (
  ctx: BlockSqlContext,
  to: string,
  from: string,
  value: string,
): string => ctx.cast(to, "status", ctx.owns(from) ? value : `${value}::text`);

/**
 * On the app's table the app's grants stay, so a client's insert can't be
 * trusted to leave the scan and upload columns at their defaults.
 */
export function attachmentInsertDefaults(ctx: BlockSqlContext): string {
  if (ctx.owns("attachments")) {
    return "";
  }

  const t = ctx.table("attachments");
  const c = (logical: string): string => ctx.col("attachments", logical);
  const fn = ctx.fn("attachment_insert_defaults");

  const cleared = ["detail", "scannedAt", "sha256", "hashVerifiedAt"]
    .filter((logical) => ctx.has("attachments", logical))
    .map((logical) => `\n    new.${c(logical)} := null;`)
    .join("");

  return `create or replace function ${fn}()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) then
    new.${c("status")} := 'pending';
    new.${c("uploadedBy")} := auth.uid();
    new.${c("uploadedAt")} := null;
    new.${c("version")} := 1;${cleared}
  end if;
  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists bsb_attachments_insert_defaults on ${t};
create trigger bsb_attachments_insert_defaults
  before insert on ${t}
  for each row execute function ${fn}();
`;
}

/** The scans columns the table has, for its upserts and its JSON. */
export function scanColumns(ctx: BlockSqlContext): {
  readonly detail: boolean;
  readonly set: string;
  readonly pending: string;
  readonly json: (row: string) => string;
} {
  const sc = (logical: string): string => ctx.col("scans", logical);
  const detail = ctx.has("scans", "detail");

  const reset = (logical: string, value?: string): string[] =>
    ctx.has("scans", logical)
      ? [`${sc(logical)} = ${value ?? `excluded.${sc(logical)}`}`]
      : [];

  return {
    detail,
    set: [
      `${sc("status")} = excluded.${sc("status")}`,
      ...reset("detail"),
      `${sc("scannedAt")} = excluded.${sc("scannedAt")}`,
    ].join(", "),
    pending: [
      `${sc("status")} = 'pending'`,
      ...reset("detail", "null"),
      `${sc("scannedAt")} = null`,
      ...reset("createdAt", "now()"),
    ].join(", "),
    json: (row) =>
      ctx.owns("scans")
        ? `to_jsonb(${row})`
        : namedRowJson(ctx, "scans", row, {}),
  };
}

/** The SET list of `set_attachment_status`, with the columns the table has. */
export function statusAssignments(
  ctx: BlockSqlContext,
  c: (logical: string) => string,
  has: (logical: string) => boolean,
): string {
  return [
    `${c("status")} = ${ctx.cast("attachments", "status", "set_attachment_status.status")}`,
    ...(has("detail") ? [`${c("detail")} = set_attachment_status.detail`] : []),
    ...(has("scannedAt") ? [`${c("scannedAt")} = now()`] : []),
    ...(has("sha256")
      ? [
          `${c("sha256")} = coalesce(set_attachment_status.sha256, a.${c("sha256")})`,
        ]
      : []),
    ...(has("hashVerifiedAt")
      ? [
          `${c("hashVerifiedAt")} = case when set_attachment_status.sha256 is null then a.${c("hashVerifiedAt")} else now() end`,
        ]
      : []),
  ].join(",\n    ");
}

/** The hash columns of an attachments table, when it has them. */
export function hashColumnsSql(
  table: string,
  c: (logical: string) => string,
  has: (logical: string) => boolean,
): string {
  const add = (logical: string, type: string): string =>
    `\nalter table ${table} add column if not exists ${c(logical)} ${type};`;

  return `${
    has("sha256")
      ? `\n-- The SHA-256 of the file's bytes, hex, recorded by the scan step from the\n-- stored object. A client never supplies it.${add("sha256", `text check (${c("sha256")} ~ '^[0-9a-f]{64}$')`)}`
      : ""
  }${has("hashVerifiedAt") ? add("hashVerifiedAt", "timestamptz") : ""}`;
}

/**
 * The branch of `confirm_attachment` for an object Storage doesn't have: the
 * service role passes `object` ({ size, mimetype }) from another store such as
 * Vercel Blob, checked against the limits of `bucket` (a SQL expression). Any
 * other caller still gets `ATTACHMENT_NOT_UPLOADED`.
 */
export const externalObjectSql = (
  bucket: string,
): string => `if confirm_attachment.object is null or not (${SERVICE_CALLER}) then
      ${fail("ATTACHMENT_NOT_UPLOADED", "The file was not uploaded yet", "P0002")}
    end if;
    if (case when jsonb_typeof(confirm_attachment.object -> 'size') = 'number'
        then (confirm_attachment.object ->> 'size')::numeric < 0
          or (confirm_attachment.object ->> 'size')::numeric <> trunc((confirm_attachment.object ->> 'size')::numeric)
        else true end)
      or coalesce(confirm_attachment.object ->> 'mimetype', '') !~ '^[^/[:space:]]+/[^[:space:]]+$' then
      ${fail("ATTACHMENT_OBJECT_INVALID", "object needs a whole size of 0 or more and a MIME type", "22023")}
    end if;
    v_meta := jsonb_build_object('size', confirm_attachment.object -> 'size', 'mimetype', lower(confirm_attachment.object ->> 'mimetype'));
    if exists (
      select 1 from storage.buckets b
      where b.id = ${bucket}
        and ((b.file_size_limit is not null and (v_meta ->> 'size')::bigint > b.file_size_limit)
          or (coalesce(cardinality(b.allowed_mime_types), 0) > 0
            and not exists (select 1 from unnest(b.allowed_mime_types) m where v_meta ->> 'mimetype' like replace(lower(m), '*', '%'))))
    ) then
      ${fail("ATTACHMENT_OBJECT_REFUSED", "The file breaks the size limit or MIME types of its bucket", "22023")}
    end if;`;

/** The version 9 to 10 step: `confirm_attachment` takes the object. */
export const CONFIRM_UPGRADE = {
  from: 9,
  description:
    "confirm_attachment takes an optional object ({ size, mimetype }) that only the service role may pass, for a file in another store such as Vercel Blob; the one-argument function goes.",
  sql: (ctx: BlockSqlContext): string =>
    `drop function if exists ${ctx.fn("confirm_attachment")}(uuid);`,
};

/** The version 8 to 9 step: scan results carry the file's SHA-256. */
export const HASH_UPGRADE = {
  from: 8,
  description:
    "Attachments record the SHA-256 of the file's bytes: set_attachment_status takes a sha256 from the scan step, and the row keeps it with hash_verified_at, also on earlier versions.",
  sql: (ctx: BlockSqlContext): string =>
    `drop function if exists ${ctx.fn("set_attachment_status")}(uuid, text, text);`,
};

/**
 * A subject without `idType` whose id column the app's schema files declare as
 * `uuid` compares on that type. Only the inline policies use it: each branch
 * runs for its own subject type, so another type's text id never reaches the
 * cast.
 */
function withInferredId(entry: Subject, layout: BlockSqlLayout): Subject {
  if (entry.idType !== undefined) {
    return entry;
  }

  const table = entry.table.includes(".")
    ? entry.table
    : `public.${entry.table}`;

  const column = entry.id ?? "id";

  return layout.uuidColumns?.[table]?.includes(column) === true
    ? { ...entry, idType: "uuid", idInferred: true }
    : entry;
}

/**
 * The policy form of `attachment_subject_readable` over the row's columns (ADR
 * 0424): the subjects whose table exists inline, a later module's subject types
 * through `fallback`, which binds late.
 */
export function inlineSubjectReadable(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
  subjects: readonly (readonly [string, Subject])[],
  columns: {
    readonly type: string;
    readonly id: string;
    readonly tenant: string;
    readonly fallback: string;
  },
  options: {
    /** The module whose later modules' tables go through `fallback`. */
    readonly module?: string;
    /** Let in a guest granted `read` on the record. Default true. */
    readonly guest?: boolean;
    /** Also require the subject row to be live. */
    readonly live?: boolean;
    /** Skip the `type is null` guard of a column that is not null. */
    readonly typeNotNull?: boolean;
    /** The record team check of a type, or-ed with its permission. */
    readonly team?: (type: string, id: string) => string | undefined;
  } = {},
): string {
  if (subjects.length === 0) {
    return "true";
  }

  const later = laterTables(ctx, layout, options.module ?? "attachments");

  const known = installedTables(ctx, layout);
  const own = `"${ctx.schemaName}".`;

  // A block-schema table no installed block creates, such as `tasks` when the
  // block is only installed as a renamed instance, would fail an early-bound
  // policy, so its type goes through the fallback too.
  const early = subjects.filter(([, entry]) => {
    const table = quotedTable(entry.table);

    return !later.has(table) && (!table.startsWith(own) || known.has(table));
  });

  const { fallback, ...args } = columns;

  const readable = subjectReadable(
    ctx,
    early.map(
      ([type, entry]) => [type, withInferredId(entry, layout)] as const,
    ),
    args,
    {
      guest: options.guest ?? true,
      ...(options.live === true ? { live: true } : {}),
      ...(options.team === undefined ? {} : { team: options.team }),
      tenantColumn: true,
      fallback,
    },
  );

  return options.typeNotNull === true
    ? readable
    : `(${columns.type} is null or ${readable})`;
}

/**
 * The policy form of `can_subject(type, id, 'read')` over the row's columns for
 * a table whose rows name any registered record (ADR 0606): the registry's
 * subjects inline, the types a later module's table holds through
 * `can_subject`. A type whose record team holds the read action also lets the
 * team in, through `is_subject_member`. The columns are qualified with their
 * table, so a subject's own `tenant_id` can't capture the row's.
 */
export function registryReadable(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
  module: string,
  columns: {
    readonly type: string;
    readonly id: string;
    readonly tenant: string;
  },
): string {
  const canSubject = ctx.of("subjects").fn("can_subject");
  const fallback = `coalesce(${canSubject}(${columns.type}, ${columns.id}, 'read'), false)`;

  const inline = subjectsOption(ctx, ["deletedAt", "team"], {
    registryOnly: true,
  });

  const members = new Set(
    inline.flatMap(([type, subject]) => {
      const { team } = subject.extra;

      return isRecord(team) &&
        Array.isArray(team["actions"]) &&
        team["actions"].includes("read")
        ? [type]
        : [];
    }),
  );

  // Without a type to inline, the function answers for all of them.
  return inline.length === 0
    ? fallback
    : inlineSubjectReadable(
        ctx,
        layout,
        inline,
        { ...columns, fallback },
        {
          module,
          guest: false,
          typeNotNull: true,
          team: (type, id) =>
            members.has(type)
              ? `${ctx.of("subjects").fn("is_subject_member")}(${sqlString(type)}, ${id})`
              : undefined,
        },
      );
}
