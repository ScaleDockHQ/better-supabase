import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { ValidationIssue } from "../core/errors.ts";
import type {
  CursorPage,
  CursorPageArgs,
  FindExt,
  OffsetPage,
  OffsetPageArgs,
  RepositoryOf,
} from "../core/repository-types.ts";
import type { AsyncResult } from "../core/result.ts";
import type {
  IncludeArg,
  OrderByArg,
  Payload,
  SelectArg,
  WhereInput,
} from "../ir/args.ts";
import type { CountMode } from "../ir/types.ts";
import type {
  AnyFunctions,
  AnyModels,
  Row,
  TableKey,
  TableMeta,
} from "../schema/types.ts";

/** Facet value meaning "not set": filters with `is null`. */
export const UNSET = "__unset__";

type Column<M extends AnyModels, T extends keyof M> = Extract<
  keyof Row<M, T>,
  string
>;
type TextColumn<M extends AnyModels, T extends keyof M> = {
  [K in Column<M, T>]: [NonNullable<Row<M, T>[K]>] extends [string] ? K : never;
}[Column<M, T>];

/** `offset` pages by number; `cursor` continues after the last row (keyset). */
export type ListPagination = "offset" | "cursor";

export interface ListQueryConfig<
  M extends AnyModels,
  T extends keyof M,
  S extends string,
  F extends string,
  C extends boolean = boolean,
  P extends ListPagination = ListPagination,
> {
  /**
   * Also count rows per facet value, with one grouped aggregate that runs
   * next to the page: 2 calls, 1 wave. Needs PostgREST aggregates.
   */
  readonly facetCounts?: C;
  /** How the page total is counted. Defaults to `'exact'`. */
  readonly count?: CountMode;
  /** Text columns matched case-insensitively (OR), or a full-text column. */
  readonly search?:
    | readonly TextColumn<M, T>[]
    | { readonly fts: Column<M, T>; readonly config?: string };
  /** Filterable columns by URL key. Values are validated against enums and CHECK unions. */
  readonly facets?: { readonly [K in F]: Column<M, T> };
  /** Named orderings. Add a unique column last for stable pages. */
  readonly sorts: { readonly [K in S]: OrderByArg<M, T> };
  readonly defaultSort: NoInfer<S>;
  /**
   * `cursor` takes an `after` cursor instead of `page` and returns
   * `nextCursor`: the cost of a page stays the same however deep it is, and
   * rows inserted meanwhile don't shift it. Defaults to `offset`.
   */
  readonly pagination?: P;
  /** Defaults to 50. */
  readonly pageSize?: number;
  /** Defaults to 200. */
  readonly maxPageSize?: number;
  /** Defaults to 200 characters. */
  readonly maxSearchLength?: number;
}

export interface ListQuery<S extends string, F extends string> {
  readonly q?: string;
  readonly sort: S;
  /** 1-based. Always 1 with cursor pagination. */
  readonly page: number;
  /** Cursor pagination: the `nextCursor` of the previous page. */
  readonly after?: string;
  readonly size: number;
  readonly facets: { readonly [K in F]?: readonly string[] };
}

/** Typed input (JSON APIs, actions, MCP tools). Everything is optional. */
export interface ListQueryInput<S extends string, F extends string> {
  readonly q?: string;
  readonly sort?: S;
  readonly page?: number;
  readonly after?: string;
  readonly size?: number;
  readonly facets?: { readonly [K in F]?: readonly string[] };
}

/** URL input: `URLSearchParams` or a Next.js `searchParams` record. */
export type ListSearchParams =
  | URLSearchParams
  | Readonly<Record<string, string | readonly string[] | undefined>>;

export type ListParseResult<S extends string, F extends string> =
  | {
      readonly ok: true;
      readonly value: ListQuery<S, F>;
      readonly issues?: undefined;
    }
  | {
      readonly ok: false;
      readonly value?: undefined;
      readonly issues: readonly ValidationIssue[];
    };

export interface ParserSpec<V> {
  parse(value: string): V | null;
  serialize(value: V): string;
}

export interface OpenApiParameter {
  readonly name: string;
  readonly in: "query";
  readonly required: false;
  readonly description: string;
  readonly schema: Readonly<Record<string, unknown>>;
  readonly style?: "form";
  readonly explode?: boolean;
}

export interface FacetInfo {
  readonly key: string;
  readonly column: string;
  readonly nullable: boolean;
  /** Allowed values when the column is an enum or CHECK union. */
  readonly values?: readonly string[];
}

/** Rows per facet value, keyed by facet and then by value (`UNSET` for empty). */
export type FacetCounts<F extends string> = {
  readonly [K in F]: Readonly<Record<string, number>>;
};

/** A page of a list; with `facetCounts: true`, also the counts per facet value. */
export type ListPage<
  R,
  F extends string,
  C extends boolean,
  P extends ListPagination = "offset",
> = ([P] extends ["cursor"] ? CursorPage<R> : OffsetPage<R>) &
  ([C] extends [true]
    ? { readonly facetCounts: FacetCounts<F> }
    : [C] extends [false]
      ? unknown
      : { readonly facetCounts?: FacetCounts<F> });

export interface ListDefinition<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
  S extends string,
  F extends string,
  C extends boolean = false,
  P extends ListPagination = "offset",
> {
  readonly table: T;
  readonly pagination: P;
  readonly defaults: ListQuery<S, F>;
  readonly facets: readonly FacetInfo[];
  /** Validates typed input or URL params. Also a Standard Schema (`schema`). */
  parse(
    input: ListQueryInput<S, F> | ListSearchParams | undefined,
  ): ListParseResult<S, F>;
  readonly schema: StandardSchemaV1<
    ListQueryInput<S, F> | ListSearchParams | undefined,
    ListQuery<S, F>
  >;
  /** URL params, leaving out defaults. */
  toSearchParams(query: Partial<ListQuery<S, F>>): URLSearchParams;
  /** `{ parse, serialize }` per URL key, for routers and nuqs (`list.nuqs(createParser)`). */
  readonly parsers: ListParsers<S, F>;
  nuqs<P>(createParser: (spec: ParserSpec<unknown>) => P): {
    readonly [K in keyof ListParsers<S, F>]: P;
  };
  /** Repository arguments: `where`, `orderBy`, `size`, and `page` and `count` or `after`. */
  args(
    query: ListQuery<S, F>,
  ): [P] extends ["cursor"] ? CursorPageArgs<M, T> : OffsetPageArgs<M, T>;
  /**
   * Runs the list against a table, merging your `select`, `include`, `where`
   * and `count`. One request, plus one for `facetCounts`, always one wave.
   */
  run<const A extends ListExtra<M, T> & FindExt<E, M, T>>(
    db: { readonly [K in T]: RepositoryOf<M, K, E> },
    query: ListQuery<S, F>,
    extra?: A,
  ): AsyncResult<ListPage<Payload<M, T, A>, F, C, P>>;
  /** OpenAPI 3.1 query parameters. */
  readonly openapi: readonly OpenApiParameter[];
  /** JSON Schema of the typed input, e.g. for MCP tool arguments. */
  readonly jsonSchema: Readonly<Record<string, unknown>>;
}

export interface ListExtra<M extends AnyModels, T extends keyof M> {
  readonly select?: SelectArg<M, T>;
  readonly include?: IncludeArg<M, T>;
  readonly where?: WhereInput<M, T>;
  /** Overrides the config's `count` for this run. */
  readonly count?: CountMode;
}

export type ListParsers<S extends string, F extends string> = {
  readonly q: ParserSpec<string>;
  readonly sort: ParserSpec<S>;
  readonly page: ParserSpec<number>;
  readonly after: ParserSpec<string>;
  readonly size: ParserSpec<number>;
} & { readonly [K in F]: ParserSpec<readonly string[]> };

const RESERVED = new Set(["q", "sort", "page", "after", "size"]);

function first(
  value: string | readonly string[] | undefined,
): string | undefined {
  return typeof value === "string" ? value : value?.[0];
}

function all(value: string | readonly string[] | undefined): string[] {
  const values = typeof value === "string" ? [value] : [...(value ?? [])];
  return values
    .flatMap((entry) => entry.split(","))
    .map((entry) => entry.trim())
    .filter(Boolean);
}

const isParamValue = (value: unknown): boolean =>
  value === undefined ||
  typeof value === "string" ||
  (Array.isArray(value) && value.every((entry) => typeof entry === "string"));

function isSearchParams(value: object): value is ListSearchParams {
  return (
    value instanceof URLSearchParams ||
    (!("facets" in value && typeof value.facets === "object") &&
      Object.values(value).every(isParamValue))
  );
}

function readRecord(
  input: ListSearchParams,
): Record<string, string | readonly string[] | undefined> {
  if (!(input instanceof URLSearchParams)) return input;
  const out: Record<string, string[]> = {};
  for (const [key, value] of input) (out[key] ??= []).push(value);
  return out;
}

function toInt(raw: unknown): number | undefined {
  if (typeof raw === "number") return raw;
  if (typeof raw !== "string" || !/^\d+$/.test(raw)) return Number.NaN;
  return Number(raw);
}

/**
 * A reusable list endpoint for one table: search, facets, sorts and
 * pagination, validated from URL params or typed input, with URL parsers,
 * OpenAPI parameters and a JSON Schema derived from the same definition.
 *
 * ```ts
 * export const customerList = defineListQuery(betterSupabase, 'customers', {
 *   search: ['name', 'kvk'],
 *   facets: { status: 'status' },
 *   sorts: { name: { name: 'asc' }, newest: [{ createdAt: 'desc' }, { id: 'asc' }] },
 *   defaultSort: 'newest',
 * });
 * ```
 */
export function defineListQuery<
  M extends AnyModels,
  D,
  Fn extends AnyFunctions,
  E,
  T extends TableKey<M>,
  const S extends string,
  const F extends string = never,
  const C extends boolean = false,
  const P extends ListPagination = "offset",
>(
  betterSupabase: BetterSupabase<M, D, Fn, E>,
  table: T,
  config: ListQueryConfig<M, T, S, F, C, P>,
): ListDefinition<M, T, E, S, F, C, P> {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
  if (!meta) throw new TypeError(`defineListQuery: unknown table "${table}"`);
  const pageSize = config.pageSize ?? 50;
  const maxPageSize = config.maxPageSize ?? 200;
  const maxSearch = config.maxSearchLength ?? 200;
  const cursor = config.pagination === "cursor";
  // SAFETY: config.sorts is keyed by S, and Object.keys widens the keys to string.
  const sortKeys = Object.keys(config.sorts) as S[];
  // SAFETY: config.facets is keyed by F, and Object.entries widens the keys to string.
  const facetEntries = Object.entries(config.facets ?? {}) as [F, string][];

  for (const [key, column] of facetEntries) {
    if (RESERVED.has(key))
      throw new TypeError(`defineListQuery: facet key "${key}" is reserved`);
    if (!meta.columns[column])
      throw new TypeError(
        `defineListQuery: unknown column "${table}.${column}"`,
      );
  }
  if (!sortKeys.includes(config.defaultSort)) {
    throw new TypeError(
      `defineListQuery: defaultSort "${config.defaultSort}" is not in sorts`,
    );
  }

  const facets: FacetInfo[] = facetEntries.map(([key, column]) => {
    const columnMeta = meta.columns[column]!;
    return {
      key,
      column,
      nullable: columnMeta.nullable,
      ...(columnMeta.enum ? { values: columnMeta.enum } : {}),
    };
  });

  const defaults: ListQuery<S, F> = {
    sort: config.defaultSort,
    page: 1,
    size: pageSize,
    facets: {},
  };

  function normalize(raw: {
    q?: unknown;
    sort?: unknown;
    page?: unknown;
    after?: unknown;
    size?: unknown;
    facets: Partial<Record<string, readonly string[]>>;
  }): ListParseResult<S, F> {
    const issues: ValidationIssue[] = [];
    let q: string | undefined;
    if (raw.q !== undefined && raw.q !== null) {
      if (typeof raw.q !== "string")
        issues.push({ message: "Must be text", path: ["q"] });
      else if (raw.q.trim().length > maxSearch)
        issues.push({
          message: `At most ${String(maxSearch)} characters`,
          path: ["q"],
        });
      else if (raw.q.trim()) q = raw.q.trim();
    }
    let sort = config.defaultSort;
    // SAFETY: sortKeys holds S values, which are strings, so includes can take any string.
    if (raw.sort !== undefined && raw.sort !== "") {
      if (
        typeof raw.sort === "string" &&
        (sortKeys as string[]).includes(raw.sort)
      )
        // SAFETY: the includes check above makes raw.sort one of the sort keys.
        sort = raw.sort as S;
      else
        issues.push({
          message: `Must be one of: ${sortKeys.join(", ")}`,
          path: ["sort"],
        });
    }
    const page =
      raw.page === undefined || raw.page === "" ? 1 : toInt(raw.page);
    if (page === undefined || !Number.isInteger(page) || page < 1)
      issues.push({
        message: "Must be a whole number of at least 1",
        path: ["page"],
      });
    else if (cursor && page !== 1)
      issues.push({
        message: "This list pages with `after`, not `page`",
        path: ["page"],
      });
    let after: string | undefined;
    if (raw.after !== undefined && raw.after !== "") {
      if (cursor && typeof raw.after === "string") after = raw.after;
      else
        issues.push({
          message: cursor
            ? "Must be text"
            : "This list pages with `page`, not `after`",
          path: ["after"],
        });
    }
    const size =
      raw.size === undefined || raw.size === "" ? pageSize : toInt(raw.size);
    if (
      size === undefined ||
      !Number.isInteger(size) ||
      size < 1 ||
      size > maxPageSize
    ) {
      issues.push({
        message: `Must be a whole number from 1 to ${String(maxPageSize)}`,
        path: ["size"],
      });
    }
    const facetValues: Partial<Record<F, readonly string[]>> = {};
    for (const facet of facets) {
      const values = raw.facets[facet.key];
      if (!values || values.length === 0) continue;
      for (const value of values) {
        const allowed =
          value === UNSET
            ? facet.nullable
            : !facet.values || facet.values.includes(value);
        if (!allowed) {
          issues.push({
            message:
              value === UNSET
                ? "This filter cannot be empty"
                : `Must be one of: ${(facet.values ?? []).join(", ")}`,
            path: ["facets", facet.key],
          });
        }
      }
      // SAFETY: facets are built from config.facets, which is keyed by F.
      facetValues[facet.key as F] = [...new Set(values)];
    }
    if (issues.length > 0) return { ok: false, issues };
    return {
      ok: true,
      value: {
        ...(q ? { q } : {}),
        sort,
        page: page ?? 1,
        ...(after ? { after } : {}),
        size: size ?? pageSize,
        facets: facetValues,
      },
    };
  }

  function parse(
    input: ListQueryInput<S, F> | ListSearchParams | undefined,
  ): ListParseResult<S, F> {
    // oxlint-disable-next-line typescript/no-unnecessary-condition -- search params from JavaScript can be null.
    if (input === undefined || input === null)
      return { ok: true, value: defaults };
    if (typeof input !== "object")
      return {
        ok: false,
        issues: [{ message: "Expected an object or URL parameters" }],
      };
    if (isSearchParams(input)) {
      const record = readRecord(input);
      const facetValues: Record<string, string[]> = {};
      for (const facet of facets)
        facetValues[facet.key] = all(record[facet.key]);
      return normalize({
        q: first(record["q"]),
        sort: first(record["sort"]),
        page: first(record["page"]),
        after: first(record["after"]),
        size: first(record["size"]),
        facets: facetValues,
      });
    }
    const typed = input;
    // SAFETY: the list input types facets as a record of facet values; each
    // value is checked below.
    const rawFacets = (typed.facets ?? {}) as Partial<Record<string, unknown>>;
    for (const [key, value] of Object.entries(rawFacets)) {
      if (
        !Array.isArray(value) ||
        value.some((entry) => typeof entry !== "string")
      ) {
        return {
          ok: false,
          issues: [
            { message: "Must be a list of values", path: ["facets", key] },
          ],
        };
      }
    }
    // SAFETY: the loop above rejected every facet value that is not a list of strings.
    return normalize({
      q: typed.q,
      sort: typed.sort,
      page: typed.page,
      after: typed.after,
      size: typed.size,
      facets: rawFacets as Record<string, string[]>,
    });
  }

  type Where = Record<string, unknown>;

  function searchWhere(query: ListQuery<S, F>): Where | undefined {
    if (!query.q || !config.search) return undefined;
    if (Array.isArray(config.search)) {
      // SAFETY: the Array.isArray check narrows the search config to its column-list form.
      const columns = config.search as readonly string[];
      if (columns.length === 0) return undefined;
      return {
        OR: columns.map((column) => ({ [column]: { contains: query.q } })),
      };
    }
    // SAFETY: a search config that is not a column list is the full-text form.
    const fts = config.search as { fts: string; config?: string };
    return {
      [fts.fts]: {
        search: fts.config ? { query: query.q, config: fts.config } : query.q,
      },
    };
  }

  function facetWhere(
    facet: FacetInfo,
    values: readonly string[] | undefined,
  ): Where | undefined {
    if (!values || values.length === 0) return undefined;
    const unset = values.includes(UNSET);
    const set = values.filter((value) => value !== UNSET);
    if (unset && set.length === 0) return { [facet.column]: null };
    if (!unset) return { [facet.column]: { in: set } };
    return { OR: [{ [facet.column]: { in: set } }, { [facet.column]: null }] };
  }

  function and(parts: readonly (Where | undefined)[]): Where | undefined {
    const present = parts.filter((part): part is Where => part !== undefined);
    if (present.length === 0) return undefined;
    return present.length === 1 ? present[0] : { AND: present };
  }

  function where(query: ListQuery<S, F>): Where | undefined {
    // SAFETY: facets are built from config.facets, which is keyed by F.
    return and([
      searchWhere(query),
      ...facets.map((facet) => facetWhere(facet, query.facets[facet.key as F])),
    ]);
  }

  function args(
    query: ListQuery<S, F>,
  ): [P] extends ["cursor"] ? CursorPageArgs<M, T> : OffsetPageArgs<M, T> {
    const filter = where(query);
    const paging = cursor
      ? { after: query.after ?? null }
      : { page: query.page, count: config.count ?? "exact" };
    // SAFETY: orderBy comes from config.sorts for table T, the filter is
    // built from its columns, and `paging` matches the pagination P.
    return {
      ...(filter ? { where: filter } : {}),
      orderBy: config.sorts[query.sort],
      size: query.size,
      ...paging,
    } as never;
  }

  /** Whether a group's value passes the facet's selected values. */
  function selects(
    value: unknown,
    selected: readonly string[] | undefined,
  ): boolean {
    if (!selected || selected.length === 0) return true;
    return value === null || value === undefined
      ? selected.includes(UNSET)
      : selected.includes(String(value));
  }

  /**
   * Per facet, rows per value under every other facet's selection: the
   * usual faceted-search counts, where picking a value doesn't zero the
   * other values of the same facet.
   */
  function marginals(
    groups: readonly Record<string, unknown>[],
    query: ListQuery<S, F>,
  ): FacetCounts<F> {
    const out: Record<string, Record<string, number>> = {};
    for (const facet of facets) {
      const counts: Record<string, number> = {};
      for (const value of facet.values ?? []) counts[value] = 0;
      for (const group of groups) {
        // SAFETY: facets are built from config.facets, which is keyed by F.
        const others = facets.every(
          (other) =>
            other === facet ||
            selects(group[other.column], query.facets[other.key as F]),
        );
        if (!others) continue;
        const raw = group[facet.column];
        const key = raw === null || raw === undefined ? UNSET : String(raw);
        counts[key] = (counts[key] ?? 0) + Number(group["_count"] ?? 0);
      }
      out[facet.key] = counts;
    }
    // SAFETY: the loop above wrote counts for every facet key in F.
    return out as FacetCounts<F>;
  }

  const listParser: ParserSpec<readonly string[]> = {
    parse: (value) => {
      const values = all(value);
      return values.length > 0 ? values : null;
    },
    serialize: (values) => values.join(","),
  };
  const intParser: ParserSpec<number> = {
    parse: (value) => (/^\d+$/.test(value) ? Number(value) : null),
    serialize: String,
  };
  // SAFETY: the object has q, sort, page and size parsers plus one list parser
  // per facet key in F.
  const parsers = {
    q: {
      parse: (value: string) => value.trim() || null,
      serialize: (value: string) => value,
    },
    // SAFETY: sortKeys holds S values; the includes check makes value one of them.
    sort: {
      parse: (value: string) =>
        (sortKeys as string[]).includes(value) ? (value as S) : null,
      serialize: (value: S) => value,
    },
    page: intParser,
    after: {
      parse: (value: string) => value || null,
      serialize: (value: string) => value,
    },
    size: intParser,
    ...Object.fromEntries(facets.map((facet) => [facet.key, listParser])),
  } as ListParsers<S, F>;

  const facetSchema = (facet: FacetInfo): Record<string, unknown> => ({
    type: "array",
    items: {
      type: "string",
      ...(facet.values
        ? { enum: [...facet.values, ...(facet.nullable ? [UNSET] : [])] }
        : {}),
    },
    uniqueItems: true,
  });
  // SAFETY: the Array.isArray check narrows the search config to its column-list form.
  const searchDescription = config.search
    ? Array.isArray(config.search)
      ? `Case-insensitive search in ${(config.search as readonly string[]).join(", ")}.`
      : "Full-text search (web search syntax)."
    : undefined;

  const openapi: OpenApiParameter[] = [
    ...(searchDescription
      ? [
          {
            name: "q",
            in: "query",
            required: false,
            description: searchDescription,
            schema: { type: "string", maxLength: maxSearch },
          } as const,
        ]
      : []),
    {
      name: "sort",
      in: "query",
      required: false,
      description: `Ordering. Default \`${config.defaultSort}\`.`,
      schema: { type: "string", enum: sortKeys, default: config.defaultSort },
    },
    cursor
      ? {
          name: "after",
          in: "query",
          required: false,
          description:
            "`nextCursor` of the previous page. Leave it out for the first page.",
          schema: { type: "string" },
        }
      : {
          name: "page",
          in: "query",
          required: false,
          description: "1-based page number.",
          schema: { type: "integer", minimum: 1, default: 1 },
        },
    {
      name: "size",
      in: "query",
      required: false,
      description: "Page size.",
      schema: {
        type: "integer",
        minimum: 1,
        maximum: maxPageSize,
        default: pageSize,
      },
    },
    ...facets.map((facet): OpenApiParameter => ({
      name: facet.key,
      in: "query",
      required: false,
      description: `Filter on ${facet.column}. Comma-separated; any value matches.${facet.nullable ? ` \`${UNSET}\` matches empty.` : ""}`,
      schema: facetSchema(facet),
      style: "form",
      explode: false,
    })),
  ];

  const jsonSchema = {
    type: "object",
    additionalProperties: false,
    properties: {
      ...(searchDescription
        ? {
            q: {
              type: "string",
              maxLength: maxSearch,
              description: searchDescription,
            },
          }
        : {}),
      sort: { type: "string", enum: sortKeys, default: config.defaultSort },
      ...(cursor
        ? { after: { type: "string" } }
        : { page: { type: "integer", minimum: 1, default: 1 } }),
      size: {
        type: "integer",
        minimum: 1,
        maximum: maxPageSize,
        default: pageSize,
      },
      ...(facets.length > 0
        ? {
            facets: {
              type: "object",
              additionalProperties: false,
              properties: Object.fromEntries(
                facets.map((facet) => [facet.key, facetSchema(facet)]),
              ),
            },
          }
        : {}),
    },
  };

  return {
    table,
    // SAFETY: `pagination` is P when given, and P defaults to `offset`.
    pagination: (config.pagination ?? "offset") as P,
    defaults,
    facets,
    parse,
    schema: {
      "~standard": {
        version: 1,
        vendor: "better-supabase",
        validate(value) {
          // SAFETY: parse accepts any input and reports anything that is not a
          // list query as an issue.
          const result = parse(
            value as ListQueryInput<S, F> | ListSearchParams | undefined,
          );
          return result.ok
            ? { value: result.value }
            : { issues: result.issues };
        },
      },
    },
    toSearchParams(query) {
      const params = new URLSearchParams();
      if (query.q) params.set("q", query.q);
      if (query.sort && query.sort !== config.defaultSort)
        params.set("sort", query.sort);
      if (query.page && query.page !== 1)
        params.set("page", String(query.page));
      if (query.after) params.set("after", query.after);
      if (query.size !== undefined && query.size > 0 && query.size !== pageSize)
        params.set("size", String(query.size));
      for (const facet of facets) {
        // SAFETY: facets are built from config.facets, which is keyed by F.
        const values = query.facets?.[facet.key as F];
        if (values && values.length > 0)
          params.set(facet.key, values.join(","));
      }
      return params;
    },
    parsers,
    // SAFETY: nuqs' createParser returns a parser per key; the caller's nuqs
    // types apply to the result.
    // SAFETY: each spec parses and serializes its own value type, which nuqs receives untyped.
    nuqs: (createParser) =>
      Object.fromEntries(
        Object.entries(parsers).map(([key, spec]) => [
          key,
          createParser(spec as ParserSpec<unknown>),
        ]),
      ) as never,
    args,
    run(db, query, extra) {
      // SAFETY: args() returns an object of paginate options.
      const base = args(query) as Record<string, unknown>;
      // SAFETY: extra is optional ListExtra, and the rest spread keeps its
      // other paginate options.
      const {
        where: extraWhere,
        count,
        select: _select,
        include: _include,
        ...options
      } = (extra ?? {}) as ListExtra<M, T> & Record<string, unknown>;
      // SAFETY: base comes from args(), whose where is a Where for table T.
      const combined = and([extraWhere, base["where"] as Where | undefined]);
      // SAFETY: db is generic over M; this helper only calls paginate and
      // aggregate on table T.
      // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- `db` is generic over M; this helper only needs paginate and aggregate.
      const repository = db[table] as unknown as {
        paginate: (input: Record<string, unknown>) => AsyncResult<unknown>;
        aggregate: (input: Record<string, unknown>) => AsyncResult<unknown>;
      };
      const page = repository.paginate({
        ...extra,
        ...base,
        ...(cursor ? {} : { count: count ?? base["count"] }),
        ...(combined ? { where: combined } : {}),
      });
      if (!config.facetCounts) {
        // SAFETY: without facet counts, run returns the paginate result as is.
        return page as AsyncResult<never>;
      }
      if (facets.length === 0) {
        // SAFETY: paginate returns a page object, which gets an empty facetCounts field.
        return page.map((data) => ({
          ...(data as object),
          facetCounts: {},
        })) as AsyncResult<never>;
      }
      const facetFilter = and([extraWhere, searchWhere(query)]);
      const groups = repository.aggregate({
        ...options,
        ...(facetFilter ? { where: facetFilter } : {}),
        groupBy: [...new Set(facets.map((facet) => facet.column))],
        _count: true,
      });
      // SAFETY: paginate returns a page object, and aggregate with groupBy
      // returns one row per group.
      return page.andThen((data) =>
        groups.map((rows) => ({
          ...(data as object),
          facetCounts: marginals(rows as Record<string, unknown>[], query),
        })),
      ) as AsyncResult<never>;
    },
    openapi,
    jsonSchema,
  };
}
