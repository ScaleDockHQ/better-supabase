import type { Queryable } from "./typegen.ts";

import { LARGE_TABLE_ROWS } from "./extras.ts";

/** Catalogs whose rows only change with DDL, grants, comments or settings. */
const CATALOGS = [
  "pg_namespace",
  "pg_attribute",
  "pg_attrdef",
  "pg_constraint",
  "pg_index",
  "pg_inherits",
  "pg_rewrite",
  "pg_policy",
  "pg_trigger",
  "pg_proc",
  "pg_type",
  "pg_enum",
  "pg_description",
  "pg_db_role_setting",
  "pg_publication",
  "pg_publication_rel",
  "pg_extension",
] as const;

const digest = (from: string): string =>
  `(select md5(coalesce(string_agg(x::text, ',' order by x::text), '')) from ${from} x)`;

/**
 * One cheap query whose result changes whenever introspection could. pg_class
 * leaves out the planner statistics that VACUUM and ANALYZE rewrite, except
 * the row-count threshold the snapshot records. pg_depend is limited to the
 * policies' rows, which name the tables and functions each policy uses. Bucket rows are data, so they
 * are hashed when `storage.buckets` exists.
 */
const FINGERPRINT_SQL = `select md5(concat_ws('|',
  ${digest(`(select oid, relname, relnamespace, relkind, relacl, reloptions, relrowsecurity, relforcerowsecurity, relreplident, relispartition, reltuples >= ${LARGE_TABLE_ROWS} as large from pg_catalog.pg_class)`)},
  ${CATALOGS.map((name) => digest(`pg_catalog.${name}`)).join(",\n  ")},
  ${digest(`(select objid, refclassid, refobjid, refobjsubid, deptype from pg_catalog.pg_depend where classid = 'pg_catalog.pg_policy'::regclass)`)},
  (select md5(coalesce(string_agg(rolname, ',' order by rolname), '')) from pg_catalog.pg_roles),
  case when to_regclass('storage.buckets') is not null
    then md5(query_to_xml('select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id', false, false, '')::text)
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
