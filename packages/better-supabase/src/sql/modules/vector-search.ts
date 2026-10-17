import type { SqlModule } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { splitTable } from "../shared.ts";
import { vectorSchemaOf } from "../vector-schema.ts";

const vectorSearchSql = (schema: string): string =>
  `create extension if not exists vector with schema ${schema};

-- Functions for the tables in \`vectorSearch\` (better-supabase.config.ts); \`sql sync\` rewrites them.
-- They are security invoker, so RLS (a tenant policy, say) filters inside the
-- index scan. hnsw.iterative_scan keeps scanning until k visible rows are found
-- (pgvector 0.8+) instead of returning fewer.`;

export const VECTOR_SEARCH: SqlModule = {
  name: "vector-search",
  title: "Vector search",
  description:
    "search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.",
  requires: [],
  target: "schema",
  names: { tables: {}, options: ["schema"] },
  sql: vectorSearchSql("extensions"),
  build: (_ctx, layout) => vectorSearchSql(vectorSchemaOf(layout)),
  extras: (_ctx, layout) =>
    vectorSearchFunctions(layout.vectorSearch ?? [], vectorSchemaOf(layout)),
};

/** An embedding column `db.$search` can query. */
export interface VectorSearchTable {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly distance: "cosine" | "l2" | "inner_product";
  /** The column's type: pgvector's `vector` (default) or `halfvec`. */
  readonly type?: "vector" | "halfvec";
  /** The primary key column the scores function returns. Defaults to `id`. */
  readonly key?: string;
  /** Full-text ranking fused with the vector ranking (reciprocal rank fusion). */
  readonly hybrid?: {
    readonly tsvector: string;
    /** The text search configuration of the query. Defaults to `simple`. */
    readonly config?: string;
    /** The RRF constant. Defaults to 60. */
    readonly k?: number;
  };
  /** A SQL expression over the row `t` the score is multiplied by, such as `t.priority`. */
  readonly boost?: string;
  /** Columns `filter` narrows before ranking, such as `organization_id`. */
  readonly prefilter?: readonly string[];
  /** A SQL condition over the row `t` every candidate must meet. */
  readonly predicate?: string;
  /** How `boost` combines with the score. Defaults to `multiply`. */
  readonly boostMode?: "multiply" | "add";
  /** A SQL `order by` list over the row `t` that breaks score ties. */
  readonly order?: string;
}

const DISTANCE_OPERATORS: Readonly<
  Record<VectorSearchTable["distance"], string>
> = {
  cosine: "<=>",
  l2: "<->",
  inner_product: "<#>",
};

/** Similarity from a distance, higher is nearer. */
const SIMILARITY: Readonly<Record<VectorSearchTable["distance"], string>> = {
  cosine: "1 - v.distance",
  l2: "1 / (1 + v.distance)",
  inner_product: "-v.distance",
};

const OPERATOR_CLASSES: Readonly<
  Record<VectorSearchTable["distance"], string>
> = {
  cosine: "cosine_ops",
  l2: "l2_ops",
  inner_product: "ip_ops",
};

const REGCONFIG = /^[a-z_][a-z0-9_]*$/;

/** `vectorSearch.<table>.boost`: one expression, no statement separators or comments. */
function boostExpression(
  where: string,
  boost: string,
  example = '"t.priority"',
): string {
  if (/;|--|\/\*|\$\$/.test(boost)) {
    throw new TypeError(
      `${where} must be one SQL expression over the row t, such as ${example}`,
    );
  }
  return boost;
}

/** The ranked ids and scores of one search, as a SQL query over `query`, `k`, `filter` and `text_query`. */
function vectorRanking(
  entry: VectorSearchTable,
  target: string,
  advanced: boolean,
  vector: string,
): string {
  const where = `vectorSearch.${entry.table}`;
  const key = `t.${sqlIdent(entry.key ?? "id")}`;
  const column = `t.${sqlIdent(entry.column)}`;
  const operator = `operator(${vector}.${DISTANCE_OPERATORS[entry.distance]})`;
  const prefilter = (entry.prefilter ?? [])
    .map((name) => {
      const quoted = sqlIdent(name);
      const values = `case jsonb_typeof(filter -> ${sqlString(name)}) when 'array' then filter -> ${sqlString(name)} else jsonb_build_array(filter -> ${sqlString(name)}) end`;
      // jsonb_populate_record casts each value to the column's type, so the
      // comparison is a typed = any (array) that an index on the column serves.
      return `
      and (not filter ? ${sqlString(name)} or t.${quoted} = any (array(
        select (jsonb_populate_record(null::${target}, jsonb_build_object(${sqlString(name)}, f.v))).${quoted}
        from jsonb_array_elements(${values}) f(v) where f.v <> 'null'::jsonb
      )) or (t.${quoted} is null and ${values} @> '[null]'::jsonb))`;
    })
    .join("");
  const predicate =
    advanced && entry.predicate !== undefined
      ? `\n      and (${boostExpression(`${where}.predicate`, entry.predicate, '"t.expires_at > now()"')})`
      : "";
  const order =
    advanced && entry.order !== undefined
      ? boostExpression(`${where}.order`, entry.order, '"t.created_at desc"')
      : undefined;
  const widened =
    advanced &&
    (entry.hybrid !== undefined ||
      entry.boost !== undefined ||
      entry.predicate !== undefined);
  const candidates = widened
    ? "least(greatest(k, 1) * 4, 1000)"
    : "least(greatest(k, 1), 1000)";
  const hybrid = entry.hybrid;
  let text = "";
  let fused = `select v.id, ${SIMILARITY[entry.distance]} as score from vector_ranked v`;
  if (advanced && hybrid) {
    const config = hybrid.config ?? "simple";
    if (!REGCONFIG.test(config)) {
      throw new TypeError(
        `${where}.hybrid.config must be a text search configuration name, such as "english"`,
      );
    }
    const rrf = hybrid.k ?? 60;
    if (!Number.isInteger(rrf) || rrf < 1) {
      throw new TypeError(`${where}.hybrid.k must be a positive integer`);
    }
    const tsv = `t.${sqlIdent(hybrid.tsvector)}`;
    text = `,
  text_hits as materialized (
    select ${key} as id, ts_rank_cd(${tsv}, q) as text_score
    from ${target} t, websearch_to_tsquery(${sqlString(config)}::regconfig, text_query) q
    where text_query is not null and ${tsv} @@ q${prefilter}${predicate}
    order by text_score desc
    limit ${candidates}
  ),
  text_ranked as (
    select x.id, row_number() over (order by x.text_score desc) as rank from text_hits x
  )`;
    fused = `select coalesce(v.id, x.id) as id,
      coalesce(1.0 / (${String(rrf)} + v.rank), 0) + coalesce(1.0 / (${String(rrf)} + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.id = v.id`;
  }
  const boost =
    advanced && entry.boost !== undefined
      ? boostExpression(`${where}.boost`, entry.boost)
      : undefined;
  const boostMode = entry.boostMode ?? "multiply";
  const modes: readonly string[] = ["multiply", "add"];
  if (!modes.includes(boostMode)) {
    throw new TypeError(`${where}.boostMode must be "multiply" or "add"`);
  }
  const score = boost
    ? boostMode === "add"
      ? `(f.score + coalesce((${boost})::double precision, 0))::double precision`
      : `(f.score * coalesce((${boost})::double precision, 1))::double precision`
    : "f.score::double precision";
  const scored =
    boost || order
      ? `select f.id, ${score} as score, row_number() over (order by ${score} desc${order ? `, ${order}` : ""}) as ord
  from fused f join ${target} t on ${key} = f.id`
      : `select f.id, ${score} as score, row_number() over (order by ${score} desc) as ord from fused f`;
  return `with vector_hits as materialized (
    select ${key} as id, ${column} ${operator} query as distance
    from ${target} t
    where ${column} is not null${advanced ? `${prefilter}${predicate}\n      and query is not null` : ""}
    order by ${column} ${operator} query
    limit ${candidates}
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  )${text},
  fused as (
    ${fused}
  )
  ${scored}
  order by ord
  limit least(greatest(k, 1), 1000)`;
}

const ITERATIVE_SCAN = `#variable_conflict use_column
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
begin
  perform set_config('hnsw.iterative_scan', 'strict_order', true);`;

const RESTORE_SCAN = `  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
end;`;

function vectorSearchFunctions(
  tables: readonly VectorSearchTable[],
  vector: string,
): string {
  if (tables.length === 0) {
    return "";
  }
  const functions = tables.map((entry) => {
    const [schema, table] = splitTable(entry.table);
    const target = `${sqlIdent(schema)}.${sqlIdent(table)}`;
    const fn = `${sqlIdent(schema)}.${sqlIdent(`search_${table}`)}`;
    const scores = `${sqlIdent(schema)}.${sqlIdent(`search_${table}_scores`)}`;
    const column = `t.${sqlIdent(entry.column)}`;
    const operator = DISTANCE_OPERATORS[entry.distance];
    const type = entry.type ?? "vector";
    const advanced =
      entry.hybrid !== undefined ||
      entry.boost !== undefined ||
      entry.predicate !== undefined ||
      entry.order !== undefined ||
      (entry.prefilter?.length ?? 0) > 0;
    const params = advanced
      ? `query ${vector}.${type}, k integer default 10, filter jsonb default '{}', text_query text default null`
      : `query ${vector}.${type}, k integer default 10`;
    const types = advanced
      ? `${vector}.${type}, integer, jsonb, text`
      : `${vector}.${type}, integer`;
    const options = [
      entry.distance,
      type === "halfvec" ? "halfvec" : "",
      entry.hybrid ? `hybrid with ${entry.hybrid.tsvector}` : "",
      entry.boost ? `boost ${entry.boost}` : "",
      entry.prefilter?.length ? `prefilter ${entry.prefilter.join(", ")}` : "",
      entry.predicate ? `predicate ${entry.predicate}` : "",
      entry.boostMode === "add" ? "additive boost" : "",
      entry.order ? `ties by ${entry.order}` : "",
    ]
      .filter(Boolean)
      .join(", ");
    const main = advanced
      ? `create or replace function ${fn}(${params})
returns setof ${target}
language plpgsql
stable
security invoker
set search_path = ''
as $$
${ITERATIVE_SCAN}
  return query select t.* from (
  ${vectorRanking(entry, target, true, vector)}
  ) r
  join ${target} t on t.${sqlIdent(entry.key ?? "id")} = r.id
  order by r.ord;
${RESTORE_SCAN}
$$;`
      : `create or replace function ${fn}(${params})
returns setof ${target}
language plpgsql
stable
security invoker
set search_path = ''
as $$
${ITERATIVE_SCAN}
  return query select t.* from ${target} t
  where ${column} is not null
  order by ${column} operator(${vector}.${operator}) query
  limit least(greatest(k, 1), 1000);
${RESTORE_SCAN}
$$;`;
    const other = advanced
      ? `${vector}.${type}, integer`
      : `${vector}.${type}, integer, jsonb, text`;
    return `-- ${entry.table}.${entry.column} (${options})
drop function if exists ${fn}(${other});
drop function if exists ${scores}(${other});
${main}
revoke execute on function ${fn}(${types}) from public, anon;
grant execute on function ${fn}(${types}) to authenticated, service_role;

-- The ids and scores of the same search, best first, for db.$search({ score: true }).
create or replace function ${scores}(${params})
returns table (id jsonb, score double precision)
language plpgsql
stable
security invoker
set search_path = ''
as $$
${ITERATIVE_SCAN}
  return query select to_jsonb(r.id), r.score from (
  ${vectorRanking(entry, target, advanced, vector)}
  ) r
  order by r.ord;
${RESTORE_SCAN}
$$;
revoke execute on function ${scores}(${types}) from public, anon;
grant execute on function ${scores}(${types}) to authenticated, service_role;
do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_am am on am.oid = c.relam
    join pg_catalog.pg_opclass oc on oc.oid = i.indclass[0]
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = i.indkey[0]
    where i.indrelid = ${sqlString(target)}::regclass
      and a.attname = ${sqlString(entry.column)}
      and am.amname in ('hnsw', 'ivfflat')
      and oc.opcname = ${sqlString(`${type}_${OPERATOR_CLASSES[entry.distance]}`)}
  ) then
    raise notice '%', ${sqlString(`${entry.table}.${entry.column} has no hnsw or ivfflat index with ${type}_${OPERATOR_CLASSES[entry.distance]}, so search_${table} scans the table`)};
  end if;
end;
$$;`;
  });
  return `\n-- config.vectorSearch\n${functions.join("\n\n")}\n`;
}
