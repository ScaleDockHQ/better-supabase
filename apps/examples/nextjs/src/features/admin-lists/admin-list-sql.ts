import "server-only";
import type { SqlClient } from "better-supabase/postgres";

import type { AdminList, AdminListQuery } from "@/lib/admin-list";

/** The page the list route answers with and the server renders first. */
export interface AdminListPage<Row> {
  readonly items: readonly Row[];
  readonly nextCursor: string | null;
  readonly facetCounts: Readonly<
    Record<string, Readonly<Record<string, number>>>
  >;
  readonly facetCountsCapped: boolean;
}

/** A table the admin list pages over, as the SQL that reads it. */
export interface AdminListSource<Raw, Out extends { readonly id: string }> {
  /** `better_supabase.hostnames h`: the table with its alias. */
  readonly from: string;
  readonly idColumn: string;
  /** The Postgres type of the id, for the cursor: uuid, bigint or text. */
  readonly idType: "uuid" | "bigint" | "text";
  readonly timeColumn: string;
  /** A condition on the tenant, with `$1` as the tenant id. */
  readonly scope: string;
  /** Text expressions the search matches with `ilike`. */
  readonly search: readonly string[];
  /** The text expression of each facet. */
  readonly facetSql: Readonly<Record<string, string>>;
  /** The select list, without the id and the sort time. */
  readonly select: string;
  map(raw: Raw): Out;
}

/** Facet counts stop at this many scanned rows, like `facetCountMode: "capped"`. */
const FACET_SCAN_CAP = 1000;

const SORT_TIME_FORMAT = `'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'`;

const escapeLike = (value: string): string =>
  value.replaceAll(/[\\%_]/g, (char) => `\\${char}`);

interface Condition {
  readonly where: string;
  readonly params: unknown[];
}

function conditions<Raw, Out extends { readonly id: string }>(
  source: AdminListSource<Raw, Out>,
  tenant: string,
  query: AdminListQuery,
  skipFacet?: string,
): Condition {
  const params: unknown[] = [tenant];
  const clauses = [source.scope];

  if (query.q) {
    params.push(`%${escapeLike(query.q)}%`);
    const index = String(params.length);

    clauses.push(
      `(${source.search.map((expression) => `${expression} ilike $${index}`).join(" or ")})`,
    );
  }

  for (const [key, values] of Object.entries(query.facets)) {
    const expression = source.facetSql[key];

    if (key === skipFacet || !expression || !values || values.length === 0) {
      continue;
    }

    params.push(values);
    clauses.push(`${expression} = any($${String(params.length)}::text[])`);
  }

  return { where: clauses.join(" and "), params };
}

interface FacetScan {
  readonly key: string;
  readonly counts: readonly {
    readonly value: string;
    readonly count: string;
  }[];
  readonly capped: boolean;
}

/** The columns every page query adds to the source's select list. */
export interface AdminListRaw {
  readonly id: string;
  readonly sort_at: string;
}

/**
 * One page of an admin list: keyset paging on the time column and the id, a
 * search over the source's text columns, the facets, and the count per facet
 * value (capped at 1,000 scanned rows). The caller's connection decides the
 * rows: `asUser` lets RLS decide, the admin connection needs `tenant` and a
 * permission check before it.
 */
export async function runAdminList<
  Raw extends AdminListRaw,
  Out extends { readonly id: string },
>(
  sql: Pick<SqlClient, "queryRaw">,
  list: AdminList,
  source: AdminListSource<Raw, Out>,
  tenant: string,
  query: AdminListQuery,
): Promise<AdminListPage<Out>> {
  const { where, params } = conditions(source, tenant, query);
  const newest = query.sort === "newest";
  const compare = newest ? "<" : ">";
  const direction = newest ? "desc" : "asc";
  const pageParams = [...params];
  let cursorClause = "";

  const [cursorTime, cursorId] = query.after?.split("|") ?? [];

  if (cursorTime && cursorId) {
    pageParams.push(cursorTime, cursorId);
    const at = String(pageParams.length - 1);
    const id = String(pageParams.length);

    cursorClause = ` and (${source.timeColumn}, ${source.idColumn}) ${compare} ($${at}::timestamptz, $${id}::${source.idType})`;
  }

  const pageQuery = sql.queryRaw<Raw>(
    `select ${source.idColumn}::text as id,
       to_char(${source.timeColumn} at time zone 'utc', ${SORT_TIME_FORMAT}) as sort_at,
       ${source.select}
     from ${source.from}
     where ${where}${cursorClause}
     order by ${source.timeColumn} ${direction}, ${source.idColumn} ${direction}
     limit ${String(list.pageSize + 1)}`,
    pageParams,
  );

  // Each facet counts its own values with the other filters applied, so a chip
  // shows what choosing it would leave.
  const facetQueries = list.facetKeys.map(async (key): Promise<FacetScan> => {
    const expression = source.facetSql[key];

    if (!expression) {
      return { key, counts: [], capped: false };
    }

    const own = conditions(source, tenant, query, key);

    const rows = await sql.queryRaw<{ value: string; count: string }>(
      `select value, count(*)::text as count
       from (select ${expression} as value from ${source.from}
             where ${own.where} limit ${String(FACET_SCAN_CAP + 1)}) scanned
       group by value`,
      own.params,
    );

    const scanned = rows.reduce((total, row) => total + Number(row.count), 0);

    return { key, counts: rows, capped: scanned > FACET_SCAN_CAP };
  });

  const [rows, facets] = await Promise.all([
    pageQuery,
    Promise.all(facetQueries),
  ]);

  const more = rows.length > list.pageSize;
  const page = more ? rows.slice(0, list.pageSize) : rows;
  const last = page.at(-1);

  return {
    items: page.map((raw) => source.map(raw)),
    nextCursor: more && last ? `${last.sort_at}|${last.id}` : null,
    facetCounts: Object.fromEntries(
      facets.map((facet) => [
        facet.key,
        Object.fromEntries(
          facet.counts.map((row) => [row.value, Number(row.count)]),
        ),
      ]),
    ),
    facetCountsCapped: facets.some((facet) => facet.capped),
  };
}
