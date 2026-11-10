import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { MAX_BATCH } from "../../core/batch-limit.ts";
import { subjectTypeIdent } from "../../core/subject-type.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { laterTables, tablesOf } from "../later-tables.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  fail,
  lockTable,
  quotedTable,
  schemaPreamble,
  serviceGrant,
  userGrant,
} from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { vectorSchemaOf } from "../vector-schema.ts";
import { OPERATIONS } from "./permissions-model.ts";
import {
  knownColumnType,
  refreshBranch,
  typedEqual,
  typedIn,
} from "./search-keys.ts";

const NAMES: BlockSqlNames = {
  hooks: ["before_search_document_index", "after_search_document_index"],
  options: ["config", "dimensions"],
  tables: {
    documents: {
      name: "search_documents",
      app: {},
      lifecycle: { tenant: "tenant", export: false },
      columns: {
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        title: "title",
        titleSearch: "title_search",
        body: "body",
        url: "url",
        tsv: "tsv",
        contentHash: "content_hash",
        embedding: "embedding",
        updatedAt: "updated_at",
        description: "description",
      },
      optional: ["embedding", "description"],
    },
  },
};

const REGCONFIG = /^[a-z_][a-z0-9_]{0,62}$/;

/** The text search configuration (`options.config`), default `simple`. */
function configOf(ctx: BlockSqlContext): string {
  const config = ctx.text("config", "simple");

  if (!REGCONFIG.test(config)) {
    throw new TypeError(
      "blocks.search.options.config must be a text search configuration name such as simple or english",
    );
  }

  return config;
}

/** The embedding size (`options.dimensions`), or 0 when the index keeps none. */
function dimensionsOf(ctx: BlockSqlContext): number {
  const dimensions = ctx.number("dimensions", 0);

  if (!Number.isInteger(dimensions) || dimensions < 0 || dimensions > 16_000) {
    throw new TypeError(
      "blocks.search.options.dimensions must be the embedding size, a whole number up to 16000",
    );
  }

  return dimensions;
}

/** The registered subjects with a `search` entry and a tenant column. */
function searchedSubjects(ctx: BlockSqlContext): readonly RegisteredSubject[] {
  return registeredSubjects(ctx.subjects, ctx.naming).filter(
    (subject) =>
      subject.config.search !== undefined &&
      subject.tenant !== undefined &&
      (subject.config.search.title ?? subject.config.title) !== undefined,
  );
}

/** Whether any searched subject returns a description with its hits. */
const describes = (subjects: readonly RegisteredSubject[]): boolean =>
  subjects.some((subject) => subject.config.search?.description !== undefined);

/** The columns whose change re-indexes a row. */
function watchedColumns(subject: RegisteredSubject): readonly string[] {
  const { config } = subject;
  const own = config.search?.from === undefined;

  const names = [
    config.id ?? "id",
    config.tenant === false ? undefined : (config.tenant ?? "organization_id"),
    own ? (config.search?.title ?? config.title) : undefined,
    ...(own ? (config.search?.body ?? []) : []),
    own ? config.search?.description : undefined,
    own ? config.search?.exclude : undefined,
    ...(own ? [] : (config.search.columns ?? [])),
    config.deletedAt,
    typeof config.template === "string"
      ? config.template
      : config.template?.column,
    ...[...(config.url ?? "").matchAll(/\{([^}]*)\}/g)].map((m) => m[1]),
  ];

  return [
    ...new Set(names.filter((name): name is string => name !== undefined)),
  ];
}

/** One `search.watch` entry of a subject, with where its trigger is created. */
interface WatchEntry {
  readonly subject: RegisteredSubject;
  readonly watched: NonNullable<
    NonNullable<RegisteredSubject["config"]["search"]>["watch"]
  >[number];
  readonly index: number;
  readonly qualified: string;
}

/** The qualified name of a watched table, `public` when it names no schema. */
function qualifiedWatched(table: string): string {
  return table.includes(".") ? table : `public.${table}`;
}

/** Whether a watched table is an app table, created after every block file. */
function isWatchedAppTable(ctx: BlockSqlContext, entry: WatchEntry): boolean {
  return (
    entry.qualified.startsWith("public.") &&
    ctx.appTables.has(entry.qualified.slice("public.".length))
  );
}

function watchEntries(subjects: readonly RegisteredSubject[]): WatchEntry[] {
  return subjects.flatMap((subject) =>
    (subject.config.search?.watch ?? []).map((watched, index) => ({
      subject,
      watched,
      index,
      qualified: qualifiedWatched(watched.table),
    })),
  );
}

/** A watch trigger and its function, for a table that exists when this runs. */
function watchTrigger(
  ctx: BlockSqlContext,
  entry: WatchEntry,
  layout: BlockSqlLayout,
): string {
  const { subject, watched, index } = entry;
  const notes: string[] = [];

  const fn = ctx.fn(
    `search_watch_${subjectTypeIdent(subject.type)}_${String(index)}`,
  );

  const base = `bsb_search_${subjectTypeIdent(subject.type)}_watch_${String(index)}`;

  const trigger = sqlIdent(base.slice(0, 63));

  const updateTrigger = sqlIdent(
    (base.length + 2 <= 63 ? `${base}_u` : `${base.slice(0, 61)}_u`).slice(
      0,
      63,
    ),
  );

  const key = sqlIdent(watched.key);
  const table = quotedTable(watched.table);
  const hops = watched.through ?? [];
  const enqueue = ctx.fn("search_enqueue");

  const columns = [...new Set([watched.key, ...(watched.columns ?? [])])];

  const columnType = (relation: string, column: string): string | undefined =>
    knownColumnType(layout, subject, relation, column);

  const values = (row: "old" | "new"): string => {
    let query = `select ${row}.${key}`;
    let currentType = columnType(watched.table, watched.key);

    for (const [at, hop] of hops.entries()) {
      const fromType = columnType(hop.table, hop.from);

      query = `select h${String(at)}.${sqlIdent(hop.to)} from ${quotedTable(hop.table)} h${String(at)} where ${typedIn(
        `h${String(at)}.${sqlIdent(hop.from)}`,
        fromType,
        query,
        currentType,
        `${subject.type} watch ${hop.table}.${hop.from}`,
        subject,
        notes,
      )}`;
      currentType = columnType(hop.table, hop.to);
    }

    return query;
  };

  const refresh = (row: "old" | "new"): string => {
    if (watched.via === undefined && hops.length === 0) {
      return `perform ${enqueue}(${sqlString(subject.type)}, ${row}.${key}::text);`;
    }

    const ids =
      watched.via === undefined
        ? `select v.value::text from (${values(row)}) v(value)`
        : hops.length === 0
          ? `select s.${subject.id}::text from ${subject.qualified} s where ${typedEqual(
              `s.${sqlIdent(watched.via)}`,
              columnType(`${subject.schema}.${subject.table}`, watched.via),
              `${row}.${key}`,
              columnType(watched.table, watched.key),
              `${subject.type} watch ${watched.table}.${watched.key}`,
              subject,
              notes,
            )}`
          : `select s.${subject.id}::text from ${subject.qualified} s where ${typedIn(
              `s.${sqlIdent(watched.via)}`,
              columnType(`${subject.schema}.${subject.table}`, watched.via),
              values(row),
              columnType(
                hops.at(-1)?.table ?? watched.table,
                hops.at(-1)?.to ?? watched.key,
              ),
              `${subject.type} watch ${watched.table}.${watched.key}`,
              subject,
              notes,
            )}`;

    return `for v_id in ${ids} loop
      perform ${enqueue}(${sqlString(subject.type)}, v_id);
    end loop;`;
  };

  const changed = columns
    .map(
      (column) =>
        `old.${sqlIdent(column)} is distinct from new.${sqlIdent(column)}`,
    )
    .join(" or ");

  return `${notes.join("\n")}
-- A change in ${watched.table} re-indexes the ${subject.type} it points at.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text;
begin
  if tg_op in ('UPDATE', 'DELETE') and old.${key} is not null then
    ${refresh("old")}
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.${key} is not null then
    ${refresh("new")}
  end if;
  return null;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${table};
drop trigger if exists ${updateTrigger} on ${table};
create trigger ${trigger} after insert or delete on ${table}
  for each row execute function ${fn}();
create trigger ${updateTrigger} after update of ${columns.map(sqlIdent).join(", ")} on ${table}
  for each row when (${changed})
  execute function ${fn}();`;
}

/**
 * Triggers on the tables a subject's `search.watch` names: a change there
 * re-indexes the record its row points at. A table that exists after the search
 * file (an app table, or a block that renders later) gets its trigger from its
 * own file, like the index triggers.
 */
function watchTriggers(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
  subjects: readonly RegisteredSubject[],
): string {
  const later = laterTables(ctx, layout, "search");

  return watchEntries(subjects)
    .filter((entry) => !isWatchedAppTable(ctx, entry))
    .filter((entry) => !later.has(quotedTable(entry.watched.table)))
    .map((entry) => watchTrigger(ctx, entry, layout))
    .join("\n");
}

/**
 * Whether a subject's table is an app table, which exists only after every
 * block file.
 */
function isAppTable(ctx: BlockSqlContext, subject: RegisteredSubject): boolean {
  return subject.schema === "public" && ctx.appTables.has(subject.table);
}

/** The trigger that re-indexes a subject's row; `fn` is `search_index_row`. */
function triggerSql(fn: string, subject: RegisteredSubject): string {
  const trigger = sqlIdent(`bsb_search_${subject.type}_index`.slice(0, 63));

  const update =
    subject.config.search?.from === undefined
      ? `update of ${watchedColumns(subject).map(sqlIdent).join(", ")}`
      : subject.config.search.columns === undefined
        ? "update"
        : `update of ${watchedColumns(subject).map(sqlIdent).join(", ")}`;

  return `drop trigger if exists ${trigger} on ${subject.qualified};
create trigger ${trigger}
  after insert or delete or ${update} on ${subject.qualified}
  for each row execute function ${fn}(${sqlString(subject.type)}, ${sqlString(subject.config.id ?? "id")});`;
}

/**
 * When `search_reindex` reads a subject's rows. An app table may not exist yet
 * when the block's data runs, so its branch checks first.
 */
function reindexCondition(
  ctx: BlockSqlContext,
  subject: RegisteredSubject,
): string {
  const type = `search_reindex.subject_type is null or search_reindex.subject_type = ${sqlString(subject.type)}`;

  return isAppTable(ctx, subject)
    ? `(${type}) and to_regclass(${sqlString(subject.qualified)}) is not null`
    : type;
}

function triggers(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
  subjects: readonly RegisteredSubject[],
): string {
  const fn = ctx.fn("search_index_row");
  const later = laterTables(ctx, layout, "search");

  return subjects
    .filter((subject) => !isAppTable(ctx, subject))
    .filter((subject) => !later.has(subject.qualified))
    .map((subject) => triggerSql(fn, subject))
    .join("\n\n");
}

/**
 * The index triggers on the tables of `owner`, a block instance that renders
 * after search, which `owner`'s file adds. `search` is the search module's
 * context.
 */
export function ownerSearchTriggers(
  search: BlockSqlContext,
  owner: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  if (search.mode === "custom" || owner.mode === "custom") {
    return "";
  }

  const fn = search.fn("search_index_row");
  const tables = tablesOf(owner);

  const subjects = searchedSubjects(search);

  const index = subjects
    .filter(
      (subject) =>
        !isAppTable(search, subject) && tables.has(subject.qualified),
    )
    .map((subject) => triggerSql(fn, subject));

  const watch = watchEntries(subjects)
    .filter(
      (entry) =>
        !isWatchedAppTable(search, entry) &&
        tables.has(quotedTable(entry.watched.table)),
    )
    .map((entry) => watchTrigger(search, entry, layout));

  return [...index, ...watch].join("\n\n");
}

/**
 * The indexing triggers on the app tables that are subjects with a `search`
 * entry, which the app tables file adds once the tables exist. `ctx` is the
 * search module's context.
 */
export function appTableSearchTriggers(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const fn = ctx.fn("search_index_row");

  const subjects = searchedSubjects(ctx);

  const index = subjects
    .filter((subject) => isAppTable(ctx, subject))
    .map((subject) => triggerSql(fn, subject));

  const watch = watchEntries(subjects)
    .filter((entry) => isWatchedAppTable(ctx, entry))
    .map((entry) => watchTrigger(ctx, entry, layout));

  return [...index, ...watch].join("\n\n");
}

interface SearchNames {
  readonly docs: string;
  readonly c: (column: string) => string;
  readonly config: string;
  readonly vector: string | undefined;
}

/** The `search(...)` function, as the caller. */
function searchFunction(
  ctx: BlockSqlContext,
  names: SearchNames,
  described: boolean,
): string {
  const { docs, c, config, vector } = names;
  const subjects = ctx.of("subjects");
  const canSubject = subjects.fn("can_subject");
  const normalize = ctx.fn("search_normalize");

  const embeddingArg = vector
    ? `, query_embedding ${vector}.vector default null`
    : "";

  const embeddingType = vector ? `, ${vector}.vector` : "";

  const fused = vector
    ? `vector_hits as materialized (
      select d.${c("subjectType")} as subject_type, d.${c("subjectId")} as subject_id,
        row_number() over (order by d.${c("embedding")} operator(${vector}.<=>) search.query_embedding) as rank
      from ${docs} d
      where search.query_embedding is not null
        and d.${c("embedding")} is not null
        and (search.types is null or d.${c("subjectType")} = any (search.types))
        and (search.tenant is null or d.${c("tenant")} = search.tenant)
      order by d.${c("embedding")} operator(${vector}.<=>) search.query_embedding
      limit v_pool
    ),
    fused as (
      select coalesce(t.subject_type, v.subject_type) as subject_type,
        coalesce(t.subject_id, v.subject_id) as subject_id,
        case when search.query_embedding is null then coalesce(t.score, 0)
          else coalesce(1.0 / (60 + t.rank), 0) + coalesce(1.0 / (60 + v.rank), 0)
        end as score
      from text_hits t
      full join vector_hits v on v.subject_type = t.subject_type and v.subject_id = t.subject_id
    )`
    : `fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    )`;

  return `
-- Full-text and trigram matches (plus nearest embeddings when the query
-- carries one, fused by reciprocal rank), as the caller: the policy keeps
-- the caller's tenants and can_subject drops what they can't read, trashed
-- rows included.
create or replace function ${ctx.fn("search")}(q text, types text[] default null, tenant ${ctx.idType} default null, max_results integer default 20${embeddingArg})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    ${fail("SEARCH_QUERY_TOO_LONG", "a search query is at most 256 characters", "22023")}
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := ${normalize}(v_q);
  v_web := websearch_to_tsquery('${config}', v_norm);
  select to_tsquery('${config}', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d.${c("subjectType")} as subject_type, d.${c("subjectId")} as subject_id,
          2 * coalesce(ts_rank_cd(d.${c("tsv")}, v_web), 0)
            + coalesce(ts_rank_cd(d.${c("tsv")}, v_prefix), 0)
            + extensions.similarity(d.${c("titleSearch")}, v_norm) as score
        from ${docs} d
        where (search.types is null or d.${c("subjectType")} = any (search.types))
          and (search.tenant is null or d.${c("tenant")} = search.tenant)
          and (d.${c("tsv")} @@ v_web
            or (v_prefix is not null and d.${c("tsv")} @@ v_prefix)
            or d.${c("titleSearch")} operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    ${fused},
    visible as (
      select d.${c("tenant")} as tenant, d.${c("subjectType")} as subject_type, d.${c("subjectId")} as subject_id,
        d.${c("title")} as title, d.${c("url")} as url, d.${c("body")} as body,${described ? ` d.${c("description")} as description,` : ""} f.score
      from fused f
      join ${docs} d on d.${c("subjectType")} = f.subject_type and d.${c("subjectId")} = f.subject_id
      where ${canSubject}(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,${described ? "\n      'description', v.description," : ""}
      'snippet', case when v.body is null then null
        else ts_headline('${config}', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${ctx.fn("search")}(text, text[], ${ctx.idType}, integer${embeddingType})`)}`;
}

interface StateNames {
  readonly table: string;
  readonly col: (column: string) => string;
}

/** Recents and favorites over the share-links block's per-user state. */
function userStateFunctions(
  ctx: BlockSqlContext,
  state: StateNames | undefined,
): string {
  const subjects = ctx.of("subjects");
  const canSubject = subjects.fn("can_subject");
  const title = subjects.fn("subject_title");
  const url = subjects.fn("subject_url");
  const fn = (name: string): string => ctx.fn(name);

  const rows = state
    ? `select s.${state.col("subjectType")}, s.${state.col("subjectId")}, s.${state.col("starredAt")}, s.${state.col("lastOpenedAt")}
  from ${state.table} s
  where s.${state.col("user")} = auth.uid()`
    : "select null::text, null::text, null::timestamptz, null::timestamptz where false";

  const upsert = (set: "opened" | "starred"): string => {
    if (!state) {
      return "return false;";
    }

    const keys = `${state.col("subjectType")}, ${state.col("subjectId")}, ${state.col("user")}`;

    const value =
      set === "opened"
        ? `${state.col("lastOpenedAt")}) values (search_touch.subject_type, search_touch.subject_id, auth.uid(), now())
  on conflict (${keys}) do update set ${state.col("lastOpenedAt")} = now();`
        : `${state.col("starredAt")}) values (search_star.subject_type, search_star.subject_id, auth.uid(), case when search_star.starred then now() end)
  on conflict (${keys}) do update set ${state.col("starredAt")} = case when search_star.starred then coalesce(st.${state.col("starredAt")}, now()) end;`;

    return `insert into ${state.table} as st (${keys}, ${value}
  return true;`;
  };

  const list = (
    name: "search_recents" | "search_favorites",
    at: "opened_at" | "starred_at",
  ): string => `
create or replace function ${fn(name)}(max_results integer default 10, types text[] default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.${at} as at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', ${title}(s.subject_type, s.subject_id),
      'url', ${url}(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from ${fn("search_user_state")}() s
    where s.${at} is not null
      and (${name}.types is null or s.subject_type = any (${name}.types))
      and ${canSubject}(s.subject_type, s.subject_id, 'read')
    order by s.${at} desc
    limit least(greatest(coalesce(${name}.max_results, 10), 1), 100)
  ) x
$$;
${userGrant(`${fn(name)}(integer, text[])`)}`;

  return `
-- The caller's own rows of the share-links per-user state. The lists below
-- run as the caller, so can_subject sees what they can read.
create or replace function ${fn("search_user_state")}()
returns table (subject_type text, subject_id text, starred_at timestamptz, opened_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  ${rows}
$$;
${userGrant(`${fn("search_user_state")}()`)}
${list("search_recents", "opened_at")}
${list("search_favorites", "starred_at")}

create or replace function ${fn("search_touch")}(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    ${fail("SEARCH_SIGNED_OUT", "sign in to keep recents")}
  end if;
  ${upsert("opened")}
end;
$$;
${userGrant(`${fn("search_touch")}(text, text)`)}

create or replace function ${fn("search_star")}(subject_type text, subject_id text, starred boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    ${fail("SEARCH_SIGNED_OUT", "sign in to keep favorites")}
  end if;
  ${upsert("starred")}
end;
$$;
${userGrant(`${fn("search_star")}(text, text, boolean)`)}`;
}

function embeddingFunctions(
  ctx: BlockSqlContext,
  names: SearchNames,
  vector: string,
): string {
  const { docs, c } = names;
  const fn = (name: string): string => ctx.fn(name);

  return `
-- Documents whose text changed since their embedding was set (or that have
-- none), for a job that embeds them and calls search_set_embedding.
create or replace function ${fn("search_pending_embeddings")}(max_results integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectType', p.${c("subjectType")},
    'subjectId', p.${c("subjectId")},
    'contentHash', p.${c("contentHash")},
    'text', concat_ws(E'\\n', p.${c("title")}, p.${c("body")})
  ) order by p.${c("updatedAt")}), '[]'::jsonb)
  from (
    select * from ${docs} d
    where d.${c("embedding")} is null
    order by d.${c("updatedAt")}
    limit least(greatest(coalesce(search_pending_embeddings.max_results, 100), 1), 1000)
  ) p
$$;
${serviceGrant(`${fn("search_pending_embeddings")}(integer)`)}

-- Stores an embedding unless the text changed after it was computed.
create or replace function ${fn("search_set_embedding")}(subject_type text, subject_id text, content_hash text, embedding ${vector}.vector)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  update ${docs} set ${c("embedding")} = search_set_embedding.embedding
  where ${c("subjectType")} = search_set_embedding.subject_type
    and ${c("subjectId")} = search_set_embedding.subject_id
    and ${c("contentHash")} = search_set_embedding.content_hash;
  return found;
end;
$$;
${serviceGrant(`${fn("search_set_embedding")}(text, text, text, ${vector}.vector)`)}

-- search_set_embedding for many documents in one update: element i of each
-- array is one document. Returns how many it stored.
create or replace function ${fn("search_set_embeddings")}(subject_types text[], subject_ids text[], content_hashes text[], embeddings text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  stored integer;
begin
  if cardinality(subject_types) is distinct from cardinality(subject_ids)
    or cardinality(subject_types) is distinct from cardinality(content_hashes)
    or cardinality(subject_types) is distinct from cardinality(embeddings) then
    ${fail("SEARCH_EMBEDDINGS_MISMATCH", "Every array needs one element per document", "22023")}
  end if;
  if cardinality(subject_types) > ${String(MAX_BATCH)} then
    ${fail("SEARCH_EMBEDDINGS_TOO_LARGE", `At most ${String(MAX_BATCH)} embeddings per call`, "22023")}
  end if;
  update ${docs} d set ${c("embedding")} = u.embedding::${vector}.vector
  from unnest(subject_types, subject_ids, content_hashes, embeddings)
    as u(subject_type, subject_id, content_hash, embedding)
  where d.${c("subjectType")} = u.subject_type
    and d.${c("subjectId")} = u.subject_id
    and d.${c("contentHash")} = u.content_hash;
  get diagnostics stored = row_count;
  return stored;
end;
$$;
${serviceGrant(`${fn("search_set_embeddings")}(text[], text[], text[], text[])`)}`;
}

function vectorOf(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string | undefined {
  if (dimensionsOf(ctx) === 0 || !ctx.installed("vector-search")) {
    return undefined;
  }

  return sqlIdent(vectorSchemaOf(layout));
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const docs = ctx.table("documents");
  const c = (column: string): string => ctx.col("documents", column);
  const config = configOf(ctx);
  const dimensions = dimensionsOf(ctx);

  const vector = ctx.has("documents", "embedding")
    ? vectorOf(ctx, layout)
    : undefined;

  const read = ctx.permission("read", OPERATIONS["search.read"]);
  const subjects = searchedSubjects(ctx);
  const names: SearchNames = { docs, c, config, vector };
  const described = describes(subjects) && ctx.has("documents", "description");
  const fn = (name: string): string => ctx.fn(name);

  const shareLinks = ctx.installed("share-links")
    ? ctx.of("share-links")
    : undefined;

  const state =
    shareLinks?.hasTable("state") === true
      ? {
          table: shareLinks.table("state"),
          col: (column: string) => shareLinks.col("state", column),
        }
      : undefined;

  const tables = ctx.manages
    ? `create table if not exists ${docs} (
  ${c("tenant")} ${ctx.idType} not null,
  ${c("subjectType")} text not null,
  ${c("subjectId")} text not null,
  ${c("title")} text,
  ${c("titleSearch")} text not null default '',
  ${c("body")} text,
  ${c("url")} text,
  ${c("tsv")} tsvector not null,
  ${c("contentHash")} text not null,
  ${c("updatedAt")} timestamptz not null default now(),
  primary key (${c("subjectType")}, ${c("subjectId")})
);${described ? `\nalter table ${docs} add column if not exists ${c("description")} text;` : ""}${vector ? `\n-- Also for an index created before embeddings were turned on.\nalter table ${docs} add column if not exists ${c("embedding")} ${vector}.vector(${String(dimensions)});` : ""}
${lockTable(docs, { read: true })}
create index if not exists search_documents_tsv_idx on ${docs} using gin (${c("tsv")});
create index if not exists search_documents_title_trgm_idx on ${docs} using gin (${c("titleSearch")} extensions.gin_trgm_ops);
create index if not exists search_documents_tenant_idx on ${docs} (${c("tenant")}, ${c("subjectType")});${vector ? `\ncreate index if not exists search_documents_embedding_idx on ${docs} using hnsw (${c("embedding")} ${vector}.vector_cosine_ops);\ncreate index if not exists search_documents_pending_idx on ${docs} (${c("updatedAt")}) where ${c("embedding")} is null;` : ""}

${renderPolicy(makePolicy({ table: docs, name: "search_documents_read", command: "select", roles: ["authenticated"], using: ctx.scope.check(c("tenant"), read) }), { target: docs })}
`
    : "";

  const notes: string[] = [];

  const cases =
    subjects.length === 0
      ? "    when '' then null;"
      : subjects
          .map((subject) => refreshBranch(subject, described, layout, notes))
          .join("\n");

  return `${notes.length === 0 ? "" : `${notes.join("\n")}\n`}${schemaPreamble(ctx)}
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
${tables}
-- Lowercase and without accents. unaccent is stable because its dictionary
-- can change; pinning the dictionary makes this safe to index.
create or replace function ${fn("search_normalize")}(value text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(value, '')))
$$;
${userGrant(`${fn("search_normalize")}(text)`)}

-- Reads one registered subject row (config.subjects.<type>.search) into the
-- index, or drops it when the row is gone or soft-deleted (deletedAt).
create or replace function ${fn("search_refresh")}(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_title text;
  v_body text;
  v_url text;${described ? "\n  v_description text;" : ""}
  v_found boolean := false;
  v_hash text;
begin
  ${ctx.hook("before_search_document_index", [
    ["text", "search_refresh.subject_type"],
    ["text", "search_refresh.subject_id"],
  ])}
  case search_refresh.subject_type
${cases}
    else
      ${fail("SEARCH_SUBJECT_UNKNOWN", "this subject type has no search entry in config.subjects", "22023")}
  end case;
  if not v_found then
    delete from ${docs}
    where ${c("subjectType")} = search_refresh.subject_type and ${c("subjectId")} = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\\x1f' || coalesce(v_body, ''));
  insert into ${docs} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("title")}, ${c("titleSearch")}, ${c("body")}, ${c("url")}, ${c("tsv")}, ${c("contentHash")}, ${c("updatedAt")}${described ? `, ${c("description")}` : ""})
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, ${fn("search_normalize")}(v_title), v_body, v_url,
    setweight(to_tsvector('${config}', ${fn("search_normalize")}(v_title)), 'A')
      || setweight(to_tsvector('${config}', ${fn("search_normalize")}(v_body)), 'B'),
    v_hash, now()${described ? ", v_description" : ""}
  )
  on conflict (${c("subjectType")}, ${c("subjectId")}) do update set
    ${c("tenant")} = excluded.${c("tenant")},
    ${c("title")} = excluded.${c("title")},
    ${c("titleSearch")} = excluded.${c("titleSearch")},
    ${c("body")} = excluded.${c("body")},
    ${c("url")} = excluded.${c("url")},${described ? `\n    ${c("description")} = excluded.${c("description")},` : ""}
    ${c("tsv")} = excluded.${c("tsv")},${vector ? `\n    ${c("embedding")} = case when ${docs}.${c("contentHash")} = excluded.${c("contentHash")} then ${docs}.${c("embedding")} end,` : ""}
    ${c("contentHash")} = excluded.${c("contentHash")},
    ${c("updatedAt")} = now()
  where (${docs}.${c("tenant")}, ${docs}.${c("title")}, ${docs}.${c("body")}, ${docs}.${c("url")}${described ? `, ${docs}.${c("description")}` : ""})
    is distinct from (excluded.${c("tenant")}, excluded.${c("title")}, excluded.${c("body")}, excluded.${c("url")}${described ? `, excluded.${c("description")}` : ""});
  ${ctx.hook("after_search_document_index", [
    ["text", "search_refresh.subject_type"],
    ["text", "search_refresh.subject_id"],
  ])}
  return true;
end;
$$;
${serviceGrant(`${fn("search_refresh")}(text, text)`)}

-- Drops a subject from the index, for a soft delete the registry doesn't
-- describe (the trash block's subject.trashed, through searchSink).
create or replace function ${fn("search_remove")}(subject_type text, subject_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from ${docs}
  where ${c("subjectType")} = search_remove.subject_type and ${c("subjectId")} = search_remove.subject_id;
  return found;
end;
$$;
${serviceGrant(`${fn("search_remove")}(text, text)`)}

-- Indexes every row of one registered type, or of all of them.
create or replace function ${fn("search_reindex")}(subject_type text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_id text;
begin
${
  subjects.length === 0
    ? "  null;"
    : subjects
        .map(
          (subject) => `  if ${reindexCondition(ctx, subject)} then
    for v_id in select s.${subject.id}::text from ${subject.qualified} s loop
      if ${fn("search_refresh")}(${sqlString(subject.type)}, v_id) then
        v_count := v_count + 1;
      end if;
    end loop;
  end if;`,
        )
        .join("\n")
}
  return v_count;
end;
$$;
${serviceGrant(`${fn("search_reindex")}(text)`)}

-- Runs as its caller (the definer trigger functions and import_upsert_batch
-- call it), so it adds no definer function. Indexes a record now, or, while an import batch runs with
-- better_supabase.search_deferred on (import_upsert_batch sets it), notes the
-- key once in better_supabase.search_dirty (a transaction-local setting, one
-- line per key) so search_refresh_dirty indexes it once at the end of the batch.
create or replace function ${fn("search_enqueue")}(subject_type text, subject_id text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := search_enqueue.subject_type || E'\\x1f' || search_enqueue.subject_id;
  v_dirty text;
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' then
    v_dirty := coalesce(current_setting('better_supabase.search_dirty', true), '');
    if position(E'\\n' || v_key || E'\\n' in E'\\n' || v_dirty) = 0 then
      perform set_config('better_supabase.search_dirty', v_dirty || v_key || E'\\n', true);
    end if;
  else
    perform ${fn("search_refresh")}(search_enqueue.subject_type, search_enqueue.subject_id);
  end if;
end;
$$;
revoke execute on function ${fn("search_enqueue")}(text, text) from public, anon, authenticated;

-- Indexes every record noted by search_enqueue in this transaction, once each.
-- Returns how many it indexed.
create or replace function ${fn("search_refresh_dirty")}()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_dirty text := coalesce(current_setting('better_supabase.search_dirty', true), '');
  v_line text;
begin
  perform set_config('better_supabase.search_dirty', '', true);
  for v_line in select l from string_to_table(v_dirty, E'\\n') l where l <> '' loop
    if ${fn("search_refresh")}(split_part(v_line, E'\\x1f', 1), split_part(v_line, E'\\x1f', 2)) then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("search_refresh_dirty")}()`)}

create or replace function ${fn("search_index_row")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) ->> tg_argv[1] end;
  v_new text := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) ->> tg_argv[1] end;
begin
  if v_old is not null and v_old is distinct from v_new then
    perform ${fn("search_enqueue")}(tg_argv[0], v_old);
  end if;
  if v_new is not null then
    perform ${fn("search_enqueue")}(tg_argv[0], v_new);
  end if;
  return null;
end;
$$;
revoke execute on function ${fn("search_index_row")}() from public, anon, authenticated;

${triggers(ctx, layout, subjects)}${watchTriggers(ctx, layout, subjects)}
${searchFunction(ctx, names, described)}
${userStateFunctions(ctx, state)}
${vector ? embeddingFunctions(ctx, names, vector) : ""}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const embedded = dimensionsOf(ctx) > 0 && ctx.installed("vector-search");

  return [
    {
      name: "search",
      args: [
        "text",
        "text[]",
        "{id}",
        "integer",
        ...(embedded ? ["vector"] : []),
      ],
      returns: "jsonb",
    },
    { name: "search_recents", args: ["integer", "text[]"], returns: "jsonb" },
    { name: "search_favorites", args: ["integer", "text[]"], returns: "jsonb" },
    { name: "search_touch", args: ["text", "text"], returns: "boolean" },
    {
      name: "search_star",
      args: ["text", "text", "boolean"],
      returns: "boolean",
    },
    { name: "search_refresh", args: ["text", "text"], returns: "boolean" },
    { name: "search_remove", args: ["text", "text"], returns: "boolean" },
    { name: "search_reindex", args: ["text"], returns: "integer" },
  ];
}

export const SEARCH: BlockSqlDefinition = {
  internal: [
    "search_user_state",
    "search_normalize",
    "search_enqueue",
    "search_refresh_dirty",
  ],
  name: "search",
  scopes: ["tenant"],
  title: "Search",
  description:
    "A search_documents index kept up by triggers from each config.subjects search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["share-links", "vector-search"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "search_set_embeddings stores many embeddings in one update, and embedPending calls it once per run.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract,
  build,
  data: (ctx) =>
    ctx.mode === "custom" || searchedSubjects(ctx).length === 0
      ? ""
      : `-- Indexes the rows that existed before the triggers.
select ${ctx.fn("search_reindex")}();
`,
};
