import type { Queryable } from "./typegen.ts";

import { LARGE_TABLE_ROWS } from "./extras.ts";

/**
 * Catalogs whose rows only change with DDL, grants, comments or settings,
 * with the column that ties a row to a relation or namespace, if any.
 */
const CATALOGS: readonly (readonly [string, string?])[] = [
  ["pg_namespace", "oid"],
  ["pg_attribute", "attrelid"],
  ["pg_attrdef", "adrelid"],
  ["pg_constraint", "conrelid"],
  ["pg_index", "indrelid"],
  ["pg_inherits"],
  ["pg_rewrite"],
  ["pg_policy"],
  ["pg_trigger", "tgrelid"],
  ["pg_proc"],
  ["pg_type", "typnamespace"],
  ["pg_enum"],
  ["pg_description"],
  ["pg_db_role_setting"],
  ["pg_publication"],
  ["pg_publication_rel"],
  ["pg_extension"],
];

// Every session's temporary tables live in pg_temp_N; they come and go with
// app traffic and never reach a snapshot.
const TEMP_NAMESPACES = String.raw`(select oid from pg_catalog.pg_namespace where nspname like 'pg\_temp\_%' or nspname like 'pg\_toast\_temp\_%')`;
const TEMP_RELATIONS = `(select oid from pg_catalog.pg_class where relnamespace in ${TEMP_NAMESPACES})`;

const catalogRows = ([name, column]: readonly [string, string?]): string => {
  if (column === undefined) return `pg_catalog.${name}`;
  const temp =
    column === "oid" || column === "typnamespace"
      ? TEMP_NAMESPACES
      : TEMP_RELATIONS;
  return `(select * from pg_catalog.${name} where ${column} not in ${temp})`;
};

const digest = (from: string): string =>
  `(select md5(coalesce(string_agg(x::text, ',' order by x::text), '')) from ${from} x)`;

/**
 * One cheap query whose result changes whenever introspection could. pg_class
 * leaves out the planner statistics that VACUUM and ANALYZE rewrite, except
 * the row-count threshold the snapshot records. pg_depend is limited to the
 * policies' rows, which name the tables and functions each policy uses.
 * pg_auth_members decides which privileges a role inherits, so the execute
 * lists change with it. Bucket rows are data, so they are hashed when
 * `storage.buckets` exists.
 */
const FINGERPRINT_SQL = `select md5(concat_ws('|',
  ${digest(`(select oid, relname, relnamespace, relkind, relacl, reloptions, relrowsecurity, relforcerowsecurity, relreplident, relispartition, reltuples >= ${LARGE_TABLE_ROWS} as large from pg_catalog.pg_class where relnamespace not in ${TEMP_NAMESPACES})`)},
  ${CATALOGS.map((entry) => digest(catalogRows(entry))).join(",\n  ")},
  ${digest(`(select objid, refclassid, refobjid, refobjsubid, deptype from pg_catalog.pg_depend where classid = 'pg_catalog.pg_policy'::regclass)`)},
  (select md5(coalesce(string_agg(rolname, ',' order by rolname), '')) from pg_catalog.pg_roles),
  ${digest("pg_catalog.pg_auth_members")},
  case when to_regclass('storage.buckets') is not null
    then md5(query_to_xml('select id, public, file_size_limit, allowed_mime_types, to_jsonb(b) -> ''versioning_status'' as versioning, to_jsonb(b) -> ''lifecycle_configuration'' as lifecycle from storage.buckets b order by id', false, false, '')::text)
  end
)) as fingerprint`;

/** A hash of the catalog; equal values mean introspection would return the same snapshot. */
export async function catalogFingerprint(db: Queryable): Promise<string> {
  const rows: readonly unknown[] = (await db.query(FINGERPRINT_SQL)).rows;
  const [row] = rows;
  const value: unknown =
    row && typeof row === "object" && "fingerprint" in row
      ? row.fingerprint
      : undefined;
  if (typeof value !== "string")
    throw new TypeError("The catalog fingerprint query returned no row.");
  return value;
}
