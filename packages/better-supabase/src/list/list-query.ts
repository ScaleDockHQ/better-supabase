import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { ValidationIssue } from "../core/errors.ts";
import type {
  CursorPage,
  CursorPageParams,
  FindExt,
  OffsetPage,
  OffsetPageOptions,
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
import type { TableModule } from "../schema/define.ts";
import type {
  AnyFunctions,
  AnyModels,
  Relations,
  Row,
  TableKey,
  TableMeta,
} from "../schema/types.ts";
import type {
  FilterClock,
  FilterFieldInfo,
  FilterFieldLabels,
  FilterField,
  FilterLimits,
  FilterQuery,
  ListFilterConfig,
} from "./filter-query.ts";

import {
  checkFilterQuery,
  decodeFilterQuery,
  encodeFilterQuery,
  toFilterFields,
  filterFieldsOf,
  filterJsonSchema,
  filterWhere,
} from "./filter-query.ts";
import { facetCacheKey, loadFacetCounts, openListRun } from "./list-facets.ts";
import {
  all,
  countsOf,
  facetSchema,
  filterParser,
  first,
  intParser,
  isSearchParams,
  listParser,
  MAX_FILTER_PARAM,
  readRecord,
  toInt,
  UNSET,
  validTimeZone,
} from "./list-params.ts";

export { UNSET } from "./list-params.ts";

type Column<M extends AnyModels, T extends keyof M> = Extract<
  keyof Row<M, T>,
  string
>;

type TextColumn<M extends AnyModels, T extends keyof M> = {
  [K in Column<M, T>]: [NonNullable<Row<M, T>[K]>] extends [string] ? K : never;
}[Column<M, T>];

type RelationKey<M extends AnyModels, T extends keyof M> = Extract<
  keyof Relations<M, T>,
  string
>;

type RelationTargetColumn<
  M extends AnyModels,
  T extends keyof M,
  K extends RelationKey<M, T>,
> = Relations<M, T>[K] extends { readonly table: infer X extends keyof M }
  ? Extract<keyof Row<M, X>, string>
  : never;

/**
 * A facet on a column of a related table: `{ relation: "tags", column: "name"
 * }` matches rows with a related tag named by any of the values (a to-many
 * relation) or whose related row has that value (a to-one relation).
 */
export type ListRelationFacet<M extends AnyModels, T extends keyof M> = {
  readonly [K in RelationKey<M, T>]: {
    readonly relation: K;
    readonly column: RelationTargetColumn<M, T, K>;
  };
}[RelationKey<M, T>];

/** One term of a free sort: a column of `sortable` and its direction. */
export interface ListOrder {
  readonly column: string;
  readonly direction: "asc" | "desc";
}

/** A free sort, built by `freeSort` (`better-supabase/list/order`). */
export interface ListFreeSort {
  readonly sortable: readonly string[];
  /** Checks the `order` input and reports what is wrong. */
  check(raw: unknown, issues: ValidationIssue[]): ListOrder[] | undefined;
  /** The repository `orderBy` of an order, ending in the tiebreak column. */
  orderBy(order: readonly ListOrder[]): Record<string, string>[];
  readonly parser: ParserSpec<readonly ListOrder[]>;
  serialize(order: readonly ListOrder[]): string;
  readonly openapi: OpenApiParameter;
  readonly jsonSchema: Readonly<Record<string, unknown>>;
}

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
   * Also count rows per facet value, with one grouped aggregate per facet that
   * runs next to the page: one wave. Needs PostgREST aggregates.
   * `facetCountMode: "capped"` reads a bounded sample instead of grouping the
   * whole match.
   */
  readonly facetCounts?: C;
  /**
   * `exact` groups every matching row. `capped` reads at most `facetScanCap`
   * rows per facet and counts those, so a large tenant is not scanned. The page
   * then sets `facetCountsCapped` when the cap was reached. Defaults to
   * `exact`.
   */
  readonly facetCountMode?: "exact" | "capped";
  /** Rows read per facet when `facetCountMode` is `capped`. Defaults to 1000. */
  readonly facetScanCap?: number;
  /**
   * How the page total is counted. Defaults to `'planned'`, the planner's
   * estimate.
   */
  readonly count?: CountMode;
  /** Text columns matched case-insensitively (OR), or a full-text column. */
  readonly search?:
    | readonly TextColumn<M, T>[]
    | { readonly fts: Column<M, T>; readonly config?: string };
  /**
   * Filterable columns by URL key. Values are validated against enums and CHECK
   * unions. A facet can name a column of a related table instead (a
   * `ListRelationFacet`); it filters but has no counts, so its `facetCounts`
   * entry is empty.
   */
  readonly facets?: {
    readonly [K in F]: Column<M, T> | ListRelationFacet<M, T>;
  };
  /**
   * A free sort from `freeSort` in `better-supabase/list/order`: the caller
   * picks up to three columns through the `order` URL parameter or input. It
   * lives in its own entry, so a list without it does not carry its code.
   */
  readonly freeSort?: ListFreeSort;
  /**
   * Fields a filter tree (ReUI Filters' `FilterQuery`) may name, by field id.
   * Each has a type and, optionally, the subset of its operators to allow.
   */
  readonly filters?: Readonly<Record<string, ListFilterConfig<Column<M, T>>>>;
  /** Most nested group levels in a filter tree, the root included. Defaults to 4. */
  readonly maxFilterDepth?: number;
  /** Most rules in a filter tree. Defaults to 50. */
  readonly maxFilterRules?: number;
  /** Named orderings. Add a unique column last for stable pages. */
  readonly sorts: { readonly [K in S]: OrderByArg<M, T> };
  readonly defaultSort: NoInfer<S>;
  /**
   * `cursor` takes an `after` cursor instead of `page` and returns
   * `nextCursor`: the cost of a page stays the same however deep it is, and
   * rows inserted meanwhile don't shift it. Defaults to `cursor`; `offset`
   * takes `page` and returns `total` and `pageCount`.
   */
  readonly pagination?: P;
  /** Defaults to 50. */
  readonly pageSize?: number;
  /** Defaults to 200. */
  readonly maxPageSize?: number;
  /** Defaults to 200 characters. */
  readonly maxSearchLength?: number;
  /**
   * Most values counted per facet; a facet with more lists its key in
   * `facetCountsTruncated`. Defaults to 100.
   */
  readonly facetLimit?: number;
}

export interface ListQuery<S extends string, F extends string> {
  readonly q?: string;
  readonly sort: S;
  /** A free sort (`sortable`). When set, it replaces `sort`. */
  readonly order?: readonly ListOrder[];
  /** 1-based. Always 1 with cursor pagination. */
  readonly page: number;
  /** Cursor pagination: the `nextCursor` of the previous page. */
  readonly after?: string;
  readonly size: number;
  readonly facets: { readonly [K in F]?: readonly string[] };
  /** The checked filter tree, without unfinished rules and empty groups. */
  readonly filter?: FilterQuery;
  /** The IANA time zone date filters resolve in, from `parse`'s options. */
  readonly timeZone?: string;
}

/** Typed input (JSON APIs, actions, MCP tools). Everything is optional. */
export interface ListQueryInput<S extends string, F extends string> {
  readonly q?: string;
  readonly sort?: S;
  readonly order?: readonly ListOrder[];
  readonly page?: number;
  readonly after?: string;
  readonly size?: number;
  readonly facets?: { readonly [K in F]?: readonly string[] };
  readonly filter?: FilterQuery;
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
  /** Equality for object values, which nuqs uses to skip URL updates. */
  eq?(a: V, b: V): boolean;
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

export interface ListParseOptions {
  /**
   * IANA time zone that date filters resolve in, such as the request's.
   * Defaults to `UTC`.
   */
  readonly timeZone?: string;
}

export interface FacetInfo {
  readonly key: string;
  /** The column filtered: of the related table for a relation facet. */
  readonly column: string;
  /** Set for a facet on a related table. */
  readonly relation?: { readonly name: string; readonly many: boolean };
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
  P extends ListPagination = "cursor",
> = ([P] extends ["cursor"] ? CursorPage<R> : OffsetPage<R>) &
  ([C] extends [true]
    ? FacetCountFields<F>
    : [C] extends [false]
      ? unknown
      : Partial<FacetCountFields<F>>);

/** The facet fields of a page with `facetCounts: true`. */
export interface FacetCountFields<F extends string> {
  readonly facetCounts: FacetCounts<F>;
  /** Facets with more values than `facetLimit`, whose counts are cut. */
  readonly facetCountsTruncated: readonly F[];
  /**
   * `true` when a capped read stopped at `facetScanCap`, so the counts are not
   * the whole match.
   */
  readonly facetCountsCapped?: boolean;
}

export interface ListDefinition<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
  S extends string,
  F extends string,
  C extends boolean = false,
  P extends ListPagination = "cursor",
> {
  readonly table: T;
  readonly pagination: P;
  readonly defaults: ListQuery<S, F>;
  readonly facets: readonly FacetInfo[];
  /** The checked `filters` config. */
  readonly filters: readonly FilterFieldInfo[];
  /** Validates typed input or URL params. Also a Standard Schema (`schema`). */
  parse(
    input: ListQueryInput<S, F> | ListSearchParams | undefined,
    options?: ListParseOptions,
  ): ListParseResult<S, F>;
  /** `FilterField` objects for ReUI Filters, with labels you can translate. */
  filterFields(labels?: FilterFieldLabels): FilterField[];
  /**
   * The repository `where` of the query's filter tree; relative dates resolve
   * against `clock.now`.
   */
  filterWhere(
    query: ListQuery<S, F>,
    clock?: Pick<FilterClock, "now">,
  ): WhereInput<M, T> | undefined;
  readonly schema: StandardSchemaV1<
    ListQueryInput<S, F> | ListSearchParams | undefined,
    ListQuery<S, F>
  >;
  /** URL params, leaving out defaults. */
  toSearchParams(query: Partial<ListQuery<S, F>>): URLSearchParams;
  /**
   * `{ parse, serialize }` per URL key, for routers and nuqs
   * (`list.nuqs(createParser)`).
   */
  readonly parsers: ListParsers<S, F>;
  nuqs<P>(createParser: (spec: ParserSpec<unknown>) => P): {
    readonly [K in keyof ListParsers<S, F>]: P;
  };
  /**
   * Repository arguments: `where`, `orderBy`, `size`, and `page` and `count` or
   * `after`.
   */
  args(
    query: ListQuery<S, F>,
    clock?: Pick<FilterClock, "now">,
  ): [P] extends ["cursor"] ? CursorPageParams<M, T> : OffsetPageOptions<M, T>;
  /**
   * Runs the list against a table, merging your `select`, `include`, `where`
   * and `count`. One request, plus one per facet for `facetCounts`, always one
   * wave.
   */
  run<const A extends ListExtra<M, T> & FindExt<E, M, T>>(
    db: { readonly [K in T]: RepositoryOf<M, K, E> },
    query: ListQuery<S, F>,
    extra?: A,
  ): AsyncResult<ListPage<Payload<M, T, A>, F, C, P>>;
  /**
   * The facet counts for `query`, ignoring page, cursor and size. Cache the
   * result under `facetCacheKey` and pass it back as `extra.facetCounts`.
   */
  countFacets(
    db: { readonly [K in T]: RepositoryOf<M, K, E> },
    query: ListQuery<S, F>,
    extra?: ListExtra<M, T>,
  ): AsyncResult<FacetCountFields<F>>;
  /** Stable while the page, cursor and size change, and the filters do not. */
  facetCacheKey(query: ListQuery<S, F>): string;
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
  /**
   * Facet counts already loaded, for example from a cache keyed by
   * `facetCacheKey`. `run` attaches them and does not count again.
   */
  readonly facetCounts?: FacetCountFields<string>;
}

export type ListParsers<S extends string, F extends string> = {
  readonly q: ParserSpec<string>;
  readonly sort: ParserSpec<S>;
  /** The free sort as `column:direction` pairs, when the list has `sortable`. */
  readonly order?: ParserSpec<readonly ListOrder[]>;
  readonly page: ParserSpec<number>;
  readonly after: ParserSpec<string>;
  readonly size: ParserSpec<number>;
  /**
   * The filter tree as base64url JSON, when the list has `filters`; `parse`
   * checks it.
   */
  readonly filter?: ParserSpec<FilterQuery>;
} & { readonly [K in F]: ParserSpec<readonly string[]> };

const RESERVED = new Set(["q", "sort", "page", "after", "size"]);

/**
 * A reusable list endpoint for one table: search, facets, sorts and pagination,
 * validated from URL params or typed input, with URL parsers, OpenAPI
 * parameters and a JSON Schema derived from the same definition.
 *
 * ```ts
 * export const customerList = defineListQuery(
 *   betterSupabase,
 *   "customers",
 *   {
 *     search: ["name", "kvk"],
 *     facets: { status: "status" },
 *     sorts: {
 *       name: { name: "asc" },
 *       newest: [{ createdAt: "desc" }, { id: "asc" }],
 *     },
 *     defaultSort: "newest",
 *   },
 * );
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
  const P extends ListPagination = "cursor",
>(
  betterSupabase: BetterSupabase<M, D, Fn, E>,
  source: T | TableModule<T>,
  config: ListQueryConfig<M, T, S, F, C, P>,
): ListDefinition<M, T, E, S, F, C, P> {
  // A table module (`tables/customers.ts`) registers with a definition whose
  // schema sets `lazyTables`, so a module that only defines a list loads one
  // table's metadata and not the app's.
  if (typeof source !== "string" && betterSupabase.meta.lazyTables === true) {
    betterSupabase.registerTable(source);
  }

  const table: T = typeof source === "string" ? source : source.key;
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];

  if (!meta) {
    throw new TypeError(`defineListQuery: unknown table "${table}"`);
  }

  const pageSize = config.pageSize ?? 50;
  const maxPageSize = config.maxPageSize ?? 200;
  const maxSearch = config.maxSearchLength ?? 200;
  const facetLimit = config.facetLimit ?? 100;
  const facetCountMode = config.facetCountMode ?? "exact";
  const facetScanCap = config.facetScanCap ?? 1000;
  const cursor = config.pagination !== "offset";
  // SAFETY: config.sorts is keyed by S, and Object.keys widens the keys to string.
  const sortKeys = Object.keys(config.sorts) as S[];

  // SAFETY: config.facets is keyed by F, and Object.entries widens the keys to string.
  const facetEntries = Object.entries(config.facets ?? {}) as [
    F,
    string | { readonly relation: string; readonly column: string },
  ][];

  const ordering = config.freeSort;
  const filterFields = filterFieldsOf(meta, config.filters ?? {});
  const filtering = filterFields.length > 0;

  const limits: FilterLimits = {
    maxDepth: config.maxFilterDepth ?? 4,
    maxRules: config.maxFilterRules ?? 50,
    maxValueLength: maxSearch,
    maxValues: facetLimit,
  };

  for (const [key, entry] of facetEntries) {
    if (
      RESERVED.has(key) ||
      (filtering && key === "filter") ||
      (ordering && key === "order")
    ) {
      throw new TypeError(`defineListQuery: facet key "${key}" is reserved`);
    }

    if (typeof entry === "string") {
      if (!meta.columns[entry]) {
        throw new TypeError(
          `defineListQuery: unknown column "${table}.${entry}"`,
        );
      }

      continue;
    }

    if (!meta.relations[entry.relation]) {
      throw new TypeError(
        `defineListQuery: unknown relation "${table}.${entry.relation}"`,
      );
    }
  }

  if (!sortKeys.includes(config.defaultSort)) {
    throw new TypeError(
      `defineListQuery: defaultSort "${config.defaultSort}" is not in sorts`,
    );
  }

  const facets: FacetInfo[] = facetEntries.map(([key, entry]) => {
    if (typeof entry !== "string") {
      const relation = meta.relations[entry.relation]!;

      const columnMeta =
        betterSupabase.meta.tables[relation.table]?.columns[entry.column];

      return {
        key,
        column: entry.column,
        relation: { name: entry.relation, many: relation.kind === "many" },
        nullable: false,
        ...(columnMeta?.enum ? { values: columnMeta.enum } : {}),
      };
    }

    const columnMeta = meta.columns[entry]!;

    return {
      key,
      column: entry,
      nullable: columnMeta.nullable === true,
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
    order?: unknown;
    page?: unknown;
    after?: unknown;
    size?: unknown;
    facets: Partial<Record<string, readonly string[]>>;
    filter?: unknown;
    timeZone?: string | undefined;
  }): ListParseResult<S, F> {
    const issues: ValidationIssue[] = [];
    let filter: FilterQuery | undefined;

    if (raw.filter !== undefined && raw.filter !== null) {
      if (filtering) {
        filter = checkFilterQuery(raw.filter, filterFields, limits, issues);
      } else {
        issues.push({ message: "This list has no filters", path: ["filter"] });
      }
    }

    if (raw.timeZone !== undefined && !validTimeZone(raw.timeZone)) {
      issues.push({ message: "Unknown time zone", path: ["timeZone"] });
    }

    let q: string | undefined;

    if (raw.q !== undefined && raw.q !== null) {
      if (typeof raw.q !== "string") {
        issues.push({ message: "Must be text", path: ["q"] });
      } else if (raw.q.trim().length > maxSearch) {
        issues.push({
          message: `At most ${String(maxSearch)} characters`,
          path: ["q"],
        });
      } else if (raw.q.trim()) {
        q = raw.q.trim();
      }
    }

    let sort = config.defaultSort;

    // SAFETY: sortKeys holds S values, which are strings, so includes can take any string.
    if (raw.sort !== undefined && raw.sort !== "") {
      if (
        typeof raw.sort === "string" &&
        (sortKeys as string[]).includes(raw.sort)
      ) {
        // SAFETY: the includes check above makes raw.sort one of the sort keys.
        sort = raw.sort as S;
      } else {
        issues.push({
          message: `Must be one of: ${sortKeys.join(", ")}`,
          path: ["sort"],
        });
      }
    }

    let order: ListOrder[] | undefined;

    if (raw.order !== undefined && raw.order !== null && raw.order !== "") {
      order = ordering
        ? ordering.check(raw.order, issues)
        : void issues.push({
            message: "This list has no free sort",
            path: ["order"],
          });
    }

    const page =
      raw.page === undefined || raw.page === "" ? 1 : toInt(raw.page);

    if (page === undefined || !Number.isInteger(page) || page < 1) {
      issues.push({
        message: "Must be a whole number of at least 1",
        path: ["page"],
      });
    } else if (cursor && page !== 1) {
      issues.push({
        message: "This list pages with `after`, not `page`",
        path: ["page"],
      });
    }

    let after: string | undefined;

    if (raw.after !== undefined && raw.after !== "") {
      if (cursor && typeof raw.after === "string") {
        after = raw.after;
      } else {
        issues.push({
          message: cursor
            ? "Must be text"
            : "This list pages with `page`, not `after`",
          path: ["after"],
        });
      }
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

      if (!values || values.length === 0) {
        continue;
      }

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

    if (issues.length > 0) {
      return { ok: false, issues };
    }

    return {
      ok: true,
      value: {
        ...(q ? { q } : {}),
        sort,
        ...(order && order.length > 0 ? { order } : {}),
        page: page ?? 1,
        ...(after ? { after } : {}),
        size: size ?? pageSize,
        facets: facetValues,
        ...(filter ? { filter } : {}),
        ...(raw.timeZone === undefined ? {} : { timeZone: raw.timeZone }),
      },
    };
  }

  function parse(
    input: ListQueryInput<S, F> | ListSearchParams | undefined,
    options: ListParseOptions = {},
  ): ListParseResult<S, F> {
    const timeZone = options.timeZone;

    // oxlint-disable-next-line typescript/no-unnecessary-condition -- search params from JavaScript can be null.
    if (input === undefined || input === null) {
      return timeZone === undefined
        ? { ok: true, value: defaults }
        : normalize({ facets: {}, timeZone });
    }

    if (typeof input !== "object") {
      return {
        ok: false,
        issues: [{ message: "Expected an object or URL parameters" }],
      };
    }

    if (isSearchParams(input)) {
      const record = readRecord(input);
      const facetValues: Record<string, string[]> = {};

      for (const facet of facets) {
        facetValues[facet.key] = all(record[facet.key]);
      }

      const encoded = filtering ? first(record["filter"]) : undefined;
      let filter: unknown;

      if (encoded !== undefined && encoded !== "") {
        filter =
          encoded.length > MAX_FILTER_PARAM
            ? undefined
            : decodeFilterQuery(encoded);

        if (filter === undefined) {
          return {
            ok: false,
            issues: [
              {
                message: "Must be a filter tree as base64url JSON",
                path: ["filter"],
              },
            ],
          };
        }
      }

      return normalize({
        filter,
        timeZone,
        q: first(record["q"]),
        sort: first(record["sort"]),
        order: first(record["order"]),
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
      filter: typed.filter,
      timeZone,
      q: typed.q,
      sort: typed.sort,
      order: typed.order,
      page: typed.page,
      after: typed.after,
      size: typed.size,
      facets: rawFacets as Record<string, string[]>,
    });
  }

  type Where = Record<string, unknown>;

  function searchWhere(query: ListQuery<S, F>): Where | undefined {
    if (!query.q || !config.search) {
      return undefined;
    }

    if (Array.isArray(config.search)) {
      // SAFETY: the Array.isArray check narrows the search config to its column-list form.
      const columns = config.search as readonly string[];

      if (columns.length === 0) {
        return undefined;
      }

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
    if (!values || values.length === 0) {
      return undefined;
    }

    if (facet.relation) {
      const related = { [facet.column]: { in: [...values] } };

      return {
        [facet.relation.name]: facet.relation.many
          ? { some: related }
          : related,
      };
    }

    const unset = values.includes(UNSET);
    const set = values.filter((value) => value !== UNSET);

    if (unset && set.length === 0) {
      return { [facet.column]: null };
    }

    if (!unset) {
      return { [facet.column]: { in: set } };
    }

    return { OR: [{ [facet.column]: { in: set } }, { [facet.column]: null }] };
  }

  function and(parts: readonly (Where | undefined)[]): Where | undefined {
    const present = parts.filter((part): part is Where => part !== undefined);

    if (present.length === 0) {
      return undefined;
    }

    return present.length === 1 ? present[0] : { AND: present };
  }

  function treeWhere(
    query: ListQuery<S, F>,
    clock: Pick<FilterClock, "now"> = {},
  ): Where | undefined {
    if (!query.filter || !filtering) {
      return undefined;
    }

    return filterWhere(query.filter, filterFields, {
      ...clock,
      ...(query.timeZone === undefined ? {} : { timeZone: query.timeZone }),
    });
  }

  function where(
    query: ListQuery<S, F>,
    clock?: Pick<FilterClock, "now">,
  ): Where | undefined {
    // SAFETY: facets are built from config.facets, which is keyed by F.
    return and([
      searchWhere(query),
      treeWhere(query, clock),
      // oxlint-disable-next-line typescript/no-unsafe-enum-assignment -- false positive: the key type is a string, not an enum (ADR 0634: 9 findings, tsgolint 7.0.2006 treats the mapped-type key as an enum)
      ...facets.map((facet) => facetWhere(facet, query.facets[facet.key as F])),
    ]);
  }

  function args(
    query: ListQuery<S, F>,
    clock?: Pick<FilterClock, "now">,
  ): [P] extends ["cursor"] ? CursorPageParams<M, T> : OffsetPageOptions<M, T> {
    const filter = where(query, clock);

    const paging = cursor
      ? { after: query.after ?? null }
      : { page: query.page, count: config.count ?? "planned" };

    // oxlint-disable-next-line typescript/no-unsafe-enum-assignment -- false positive: the key type is a string, not an enum (ADR 0634: 9 findings, tsgolint 7.0.2006 treats the mapped-type key as an enum)
    const sorted = config.sorts[query.sort];

    // SAFETY: orderBy comes from config.sorts for table T, the filter is
    // built from its columns, and `paging` matches the pagination P.
    return {
      ...(filter ? { where: filter } : {}),
      orderBy:
        ordering && query.order && query.order.length > 0
          ? ordering.orderBy(query.order)
          : sorted,
      size: query.size,
      ...paging,
    } as never;
  }

  // SAFETY: the object has q, sort, page and size parsers, a filter parser when
  // filters are configured, and one list parser per facet key in F.
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
    ...(ordering ? { order: ordering.parser } : {}),
    page: intParser,
    after: {
      parse: (value: string) => value || null,
      serialize: (value: string) => value,
    },
    size: intParser,
    ...(filtering ? { filter: filterParser } : {}),
    ...Object.fromEntries(facets.map((facet) => [facet.key, listParser])),
  } as ListParsers<S, F>;

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
    ...(ordering ? [ordering.openapi] : []),
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
    ...(filtering
      ? [
          {
            name: "filter",
            in: "query",
            required: false,
            description: `A filter tree (ReUI Filters' FilterQuery) as base64url JSON. Fields: ${filterFields.map((field) => `${field.id} (${field.type})`).join(", ")}. At most ${String(limits.maxRules)} rules and ${String(limits.maxDepth)} levels.`,
            schema: { type: "string", maxLength: MAX_FILTER_PARAM },
          } as const,
        ]
      : []),
    ...facets.map((facet): OpenApiParameter => ({
      name: facet.key,
      in: "query",
      required: false,
      description: `Filter on ${facet.relation ? `${facet.relation.name}.` : ""}${facet.column}. Comma-separated; any value matches.${facet.nullable ? ` \`${UNSET}\` matches empty.` : ""}`,
      schema: facetSchema(facet),
      style: "form",
      explode: false,
    })),
  ];

  const filterSchema = filtering
    ? filterJsonSchema(filterFields, limits)
    : undefined;

  const jsonSchema = {
    ...(filterSchema ? { $defs: filterSchema["$defs"] } : {}),
    type: "object",
    additionalProperties: false,
    properties: {
      ...(filterSchema ? { filter: { $ref: "#/$defs/filterGroup" } } : {}),
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
      ...(ordering ? { order: ordering.jsonSchema } : {}),
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

  function facetFilter(
    query: ListQuery<S, F>,
    facet: { readonly key: string },
    extraWhere: Where | undefined,
  ): Where | undefined {
    const search = searchWhere(query);
    const tree = treeWhere(query);

    const others = facets.filter((other) => other.key !== facet.key);

    return and([
      extraWhere,
      search,
      tree,
      ...others.map((other) => {
        // SAFETY: facets are built from config.facets, which is keyed by F.
        // oxlint-disable-next-line typescript/no-unsafe-enum-assignment -- false positive: the key type is a string, not an enum (ADR 0634: 9 findings, tsgolint 7.0.2006 treats the mapped-type key as an enum)
        const selected = query.facets[other.key as F];

        return facetWhere(other, selected);
      }),
    ]);
  }

  function readFacetCounts(
    loaded: ReturnType<typeof openRun>,
    query: ListQuery<S, F>,
  ): AsyncResult<FacetCountFields<F>> {
    const countable = facets.filter((facet) => !facet.relation);
    const related = facets.filter((facet) => facet.relation);

    const counts = loadFacetCounts({
      enabled: config.facetCounts === true,
      mode: facetCountMode,
      facets: countable,
      facetLimit,
      scanCap: facetScanCap,
      options: loaded.options,
      filterFor: (facet) => facetFilter(query, facet, loaded.extraWhere),
      list: (request) => loaded.repository.list(request),
      aggregate: (request) => loaded.repository.aggregate(request),
      countsOf: (facet, groups) =>
        countsOf({ ...facet, nullable: false }, groups),
    });

    // SAFETY: facet keys are F, the names from config.facets.
    return (
      related.length === 0 || config.facetCounts !== true
        ? counts
        : counts.map((data) => ({
            ...data,
            facetCounts: {
              ...data.facetCounts,
              ...Object.fromEntries(related.map((facet) => [facet.key, {}])),
            },
          }))
    ) as AsyncResult<FacetCountFields<F>>;
  }

  function openRun(
    db: { readonly [K in T]: RepositoryOf<M, K, E> },
    query: ListQuery<S, F>,
    extra: ListExtra<M, T> | undefined,
    page = true,
  ) {
    // SAFETY: args() returns an object of page options.
    const base = args(query) as Record<string, unknown>;

    // SAFETY: extra is the optional list input, read as a record so the page can drop cached counts.
    const raw = extra as Record<string, unknown> | undefined;

    return openListRun({
      table: db[table],
      base,
      extra: raw,
      cursor,
      page,
      combine: (left, right) => and([left, right]),
    });
  }

  return {
    table,
    // SAFETY: `pagination` is P when given, and P defaults to `cursor`.
    pagination: (config.pagination ?? "cursor") as P,
    defaults,
    facets,
    filters: filterFields,
    parse,
    filterFields: (labels) => toFilterFields(filterFields, labels),
    // SAFETY: the tree is compiled from the checked filter fields of table T.
    filterWhere: (query, clock) =>
      treeWhere(query, clock) as WhereInput<M, T> | undefined,
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

      if (query.q) {
        params.set("q", query.q);
      }

      if (query.sort && query.sort !== config.defaultSort) {
        params.set("sort", query.sort);
      }

      if (ordering && query.order && query.order.length > 0) {
        params.set("order", ordering.serialize(query.order));
      }

      if (query.page && query.page !== 1) {
        params.set("page", String(query.page));
      }

      if (query.after) {
        params.set("after", query.after);
      }

      if (
        query.size !== undefined &&
        query.size > 0 &&
        query.size !== pageSize
      ) {
        params.set("size", String(query.size));
      }

      if (query.filter && query.filter.rules.length > 0) {
        params.set("filter", encodeFilterQuery(query.filter));
      }

      for (const facet of facets) {
        // SAFETY: facets are built from config.facets, which is keyed by F.
        // oxlint-disable-next-line typescript/no-unsafe-enum-assignment -- false positive: the key type is a string, not an enum (ADR 0634: 9 findings, tsgolint 7.0.2006 treats the mapped-type key as an enum)
        const values = query.facets?.[facet.key as F];

        if (values && values.length > 0) {
          params.set(facet.key, values.join(","));
        }
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
      const loaded = openRun(db, query, extra);

      if (!config.facetCounts || loaded.cachedCounts) {
        const counts = loaded.cachedCounts;

        if (!counts) {
          // SAFETY: without facet counts, run returns the page result as is.
          return loaded.page as AsyncResult<never>;
        }

        const attached = loaded.page.map((data) => {
          // SAFETY: page returns a page object.
          const row = data as object;

          return { ...row, ...counts };
        });

        // SAFETY: the cached counts are the facet fields of this page.
        return attached as AsyncResult<never>;
      }

      const countsPromise = readFacetCounts(loaded, query);

      const withCounts = loaded.page.andThen(async (data) => {
        const counts = await countsPromise;

        if (!counts.ok) {
          return counts;
        }

        // SAFETY: page returns a page object.
        const row = data as object;

        // A literal, not ok(), keeps the error classes out of this entry.
        return {
          ok: true as const,
          data: { ...row, ...counts.data },
          error: null,
        };
      });

      // SAFETY: the counts are the facet fields of this page.
      return withCounts as AsyncResult<never>;
    },
    countFacets(db, query, extra) {
      return readFacetCounts(openRun(db, query, extra, false), query);
    },
    facetCacheKey,
    openapi,
    jsonSchema,
  };
}
