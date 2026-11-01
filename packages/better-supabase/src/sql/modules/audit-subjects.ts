import type {
  AuditIpHeader,
  AuditSubjectColumn,
} from "../../blocks/audit/options.ts";
import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";

const HEADER = /^[a-z0-9-]+$/;
const COLUMN = /^[a-z_][a-z0-9_]*$/;
const CLAIM = /^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)*$/i;

const UUID =
  "'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'";

type SubjectType = AuditSubjectColumn["type"];

/**
 * The types a subject column may take; each cast is guarded so a bad value is
 * null.
 */
const SUBJECT_TYPES: readonly SubjectType[] = ["text", "uuid", "bigint"];

function ipHeader(ctx: BlockSqlContext): Required<AuditIpHeader> {
  const raw = ctx.option("ipHeader");
  const where = "blocks.audit.options.ipHeader";

  if (raw === undefined) {
    return { name: "x-forwarded-for", hop: "last" };
  }

  const value = typeof raw === "string" ? { name: raw } : raw;

  if (!isRecord(value) || typeof value["name"] !== "string") {
    throw new TypeError(
      `${where} must be a header name or { name, hop: "first" | "last" }`,
    );
  }

  const name = value["name"].toLowerCase();
  const hop = value["hop"] ?? "last";

  if (!HEADER.test(name)) {
    throw new TypeError(`${where}: "${value["name"]}" is not a header name`);
  }

  if (hop !== "first" && hop !== "last") {
    throw new TypeError(`${where}.hop must be "first" or "last"`);
  }

  return { name, hop };
}

/**
 * `better_supabase.request_ip()`: the client address from the configured
 * header. The default, the right-most `x-forwarded-for` hop, is the one the API
 * gateway appended; clients can forge the ones before it. An app that relays
 * writes through its own API names the header its proxy sets.
 */
export function requestIpSql(ctx: BlockSqlContext): string {
  const { name, hop } = ipHeader(ctx);
  const header = `nullif(current_setting('request.headers', true), '')::json ->> ${sqlString(name)}`;

  const value =
    hop === "first"
      ? `split_part(${header}, ',', 1)`
      : `reverse(split_part(reverse(${header}), ',', 1))`;

  const comment =
    name === "x-forwarded-for" && hop === "last"
      ? `-- The client address the API gateway appended to x-forwarded-for (the
-- right-most hop; clients can forge the ones before it), or null.`
      : `-- The client address from the ${name} header (the ${hop} hop), or null.`;

  return `${comment}
create or replace function better_supabase.request_ip()
returns inet
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(trim(${value}), '')::inet;
exception when others then
  return null;
end;
$$;`;
}

/**
 * The `staff` actor kind's test, from `blocks.audit.options.staffClaim` (a
 * dotted JWT path such as `app_metadata.platform_role`), or undefined.
 */
function staffTest(ctx: BlockSqlContext): string | undefined {
  const raw = ctx.option("staffClaim");

  if (raw === undefined) {
    return undefined;
  }

  if (typeof raw !== "string" || !CLAIM.test(raw)) {
    throw new TypeError(
      'blocks.audit.options.staffClaim must be a dotted claim path such as "app_metadata.platform_role"',
    );
  }

  return `auth.jwt() #>> ${sqlString(`{${raw.split(".").join(",")}}`)} is not null`;
}

/** `blocks.audit.options.subjectColumns`, checked. */
function subjectColumns(
  ctx: BlockSqlContext,
  taken: readonly string[],
): readonly (readonly [string, Required<AuditSubjectColumn>])[] {
  const raw = ctx.option("subjectColumns");
  const where = "blocks.audit.options.subjectColumns";

  if (raw === undefined) {
    return [];
  }

  if (!isRecord(raw)) {
    throw new TypeError(`${where} must map column names to { type, from }`);
  }

  return Object.entries(raw).map(([name, entry]) => {
    // 46 leaves room for the audit_events_<name>_idx index name.
    if (!COLUMN.test(name) || name.length > 46) {
      throw new TypeError(`${where}: "${name}" is not a valid column name`);
    }

    if (taken.includes(name)) {
      throw new TypeError(
        `${where}: "${name}" is already a column of the audit log`,
      );
    }

    const type = isRecord(entry) ? entry["type"] : undefined;
    const from = isRecord(entry) ? (entry["from"] ?? name) : undefined;

    if (!SUBJECT_TYPES.some((known) => known === type)) {
      throw new TypeError(
        `${where}.${name}.type must be one of ${SUBJECT_TYPES.join(", ")}`,
      );
    }

    if (typeof from !== "string" || from === "") {
      throw new TypeError(`${where}.${name}.from must be a non-empty key`);
    }

    // SAFETY: the check above found `type` in SUBJECT_TYPES.
    return [name, { type: type as SubjectType, from }] as const;
  });
}

function guardedCast(value: string, type: SubjectType): string {
  switch (type) {
    case "text": {
      return value;
    }

    case "uuid": {
      return `case when ${value} ~ ${UUID} then (${value})::uuid end`;
    }

    case "bigint": {
      return `case when ${value} ~ '^-?[0-9]{1,18}$' then (${value})::bigint end`;
    }

    default: {
      const unknown: never = type;
      throw new TypeError(`unknown subject column type ${String(unknown)}`);
    }
  }
}

/**
 * The generated subject columns and their indexes: each reads its key from the
 * new row, the old row, then the event metadata, so a row change and an
 * `audit_event` about the same record share one indexed column.
 */
export function subjectColumnsSql(
  ctx: BlockSqlContext,
  log: string,
  sources: readonly string[],
  taken: readonly string[],
): string {
  const columns = subjectColumns(ctx, taken);

  if (columns.length === 0) {
    return "";
  }

  if (sources.length === 0) {
    throw new TypeError(
      "blocks.audit.options.subjectColumns needs the old_record, new_record or metadata column",
    );
  }

  return columns
    .map(([name, { type, from }]) => {
      const key = sqlString(from);
      const value = `coalesce(${sources.map((source) => `${source} ->> ${key}`).join(", ")})`;
      const column = sqlIdent(name);

      return `alter table ${log} add column if not exists ${column} ${type} generated always as (${guardedCast(value, type)}) stored;
create index if not exists ${sqlIdent(`audit_events_${name}_idx`)} on ${log} (${column}) where ${column} is not null;`;
    })
    .join("\n");
}

/**
 * How the caller acted: service, support, impersonation, oauth-client, staff
 * (with `staffClaim`), user or system.
 */
export function actorKind(ctx: BlockSqlContext): string {
  const staff = staffTest(ctx);

  return `case
      when better_supabase.import_run() is not null then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'${
        staff === undefined ? "" : `\n      when ${staff} then 'staff'`
      }
      when auth.uid() is not null then 'user'
      else 'system'
    end`;
}
