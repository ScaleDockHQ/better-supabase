import type { PostgresCacheNames } from "./names.ts";
import type {
  Backend,
  EntryRow,
  LookupRow,
  PostgresCacheSqlClient,
  TagRow,
} from "./store-core.ts";

import { sqlIdent } from "../core/template.ts";
import { MISSING } from "./store-core.ts";

export function sqlBackend(
  sql: PostgresCacheSqlClient,
  names: PostgresCacheNames,
): Backend {
  const schema = sqlIdent(names.schema);
  const entries = `${schema}.${sqlIdent(names.entriesTable)}`;
  const tags = `${schema}.${sqlIdent(names.tagsTable)}`;
  const getFn = `${schema}.${sqlIdent(names.getFunction)}`;
  const markFn = `${schema}.${sqlIdent(names.markTagsFunction)}`;
  const leases = `${schema}.${sqlIdent(names.leasesTable)}`;
  const leaseFn = `${schema}.${sqlIdent(names.leaseFunction)}`;

  // Postgres answers 42883 (undefined_function) for a function it does not know.
  const isMissing = (error: unknown): boolean =>
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "42883";

  return {
    async selectEntry(key) {
      const [row] = await sql.queryRaw<EntryRow>(
        `select key, value, tags, stored_at, expires_at, path, meta from ${entries} where key = $1`,
        [key],
      );

      return row;
    },
    async callGet(key, softTags, now) {
      try {
        const [row] = await sql.queryRaw<LookupRow>(
          `select * from ${getFn}($1::text, $2::text[], $3::bigint)`,
          [key, [...softTags], now],
        );

        return row;
      } catch (error) {
        if (isMissing(error)) {
          return MISSING;
        }

        throw error;
      }
    },
    async upsertEntry(row) {
      await sql.queryRaw(
        `insert into ${entries} (key, value, tags, stored_at, expires_at, path, meta)
values ($1, $2, $3::text[], $4::bigint, $5::bigint, $6, $7::jsonb)
on conflict (key) do update set value = excluded.value, tags = excluded.tags,
  stored_at = excluded.stored_at, expires_at = excluded.expires_at,
  path = excluded.path, meta = excluded.meta`,
        [
          row.key,
          row.value,
          row.tags,
          row.stored_at,
          row.expires_at,
          row.path,
          JSON.stringify(row.meta),
        ],
      );
    },
    async deleteWhere(column, value) {
      await sql.queryRaw(
        `delete from ${entries} where ${sqlIdent(column)} = $1`,
        [value],
      );
    },
    async deleteExpired(now) {
      await sql.queryRaw(`delete from ${entries} where expires_at < $1`, [now]);
    },
    async selectTags(chunk) {
      return sql.queryRaw<TagRow>(
        `select * from ${tags} where tag = any($1::text[])`,
        [[...chunk]],
      );
    },
    async upsertTags(rows) {
      await sql.queryRaw(
        `insert into ${tags} (tag, stale_at, expired_at)
select * from unnest($1::text[], $2::bigint[], $3::bigint[])
on conflict (tag) do update set stale_at = excluded.stale_at, expired_at = excluded.expired_at`,
        [
          rows.map((row) => row.tag),
          rows.map((row) => row.stale_at),
          rows.map((row) => row.expired_at),
        ],
      );
    },
    async callMarkTags(chunk, mode, expireSeconds, now) {
      try {
        await sql.queryRaw(
          `select ${markFn}($1::text[], $2::text, $3::bigint, $4::bigint)`,
          [[...chunk], mode, expireSeconds, now],
        );

        return true;
      } catch (error) {
        if (isMissing(error)) {
          return MISSING;
        }

        throw error;
      }
    },
    async callLease(key, holder, ttlMs, now) {
      try {
        const [row] = await sql.queryRaw<{ won: boolean }>(
          `select ${leaseFn}($1::text, $2::text, $3::bigint, $4::bigint) as won`,
          [key, holder, ttlMs, now],
        );

        return row?.won === true;
      } catch (error) {
        if (isMissing(error)) {
          return MISSING;
        }

        throw error;
      }
    },
    async deleteLease(key, holder) {
      await sql.queryRaw(
        `delete from ${leases} where key = $1 and holder = $2`,
        [key, holder],
      );
    },
  };
}
