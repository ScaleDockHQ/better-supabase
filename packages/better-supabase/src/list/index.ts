import type { StandardSchemaV1 } from '@standard-schema/spec';

import type { BetterSupabase } from '../core/define.ts';
import type { ValidationIssue } from '../core/errors.ts';
import type {
  FindExt,
  OffsetPage,
  OffsetPageArgs,
  RepositoryOf,
} from '../core/repository-types.ts';
import type { AsyncResult } from '../core/result.ts';
import type {
  IncludeArgs,
  OrderByArg,
  Payload,
  SelectArg,
  WhereInput,
} from '../ir/args.ts';
import type {
  AnyFunctions,
  AnyModels,
  Row,
  TableKey,
  TableMeta,
} from '../schema/types.ts';

/** Facet value meaning "not set": filters with `is null`. */
export const UNSET = '__unset__';

type Column<M extends AnyModels, T extends keyof M> = Extract<
  keyof Row<M, T>,
  string
>;
type TextColumn<M extends AnyModels, T extends keyof M> = {
  [K in Column<M, T>]: [NonNullable<Row<M, T>[K]>] extends [string] ? K : never;
}[Column<M, T>];

export interface ListQueryConfig<
  M extends AnyModels,
  T extends keyof M,
  S extends string,
  F extends string,
> {
  /** Text columns matched case-insensitively (OR), or a full-text column. */
  readonly search?:
    | readonly TextColumn<M, T>[]
    | { readonly fts: Column<M, T>; readonly config?: string };
  /** Filterable columns by URL key. Values are validated against enums and CHECK unions. */
  readonly facets?: { readonly [K in F]: Column<M, T> };
  /** Named orderings. Add a unique column last for stable pages. */
  readonly sorts: { readonly [K in S]: OrderByArg<M, T> };
  readonly defaultSort: NoInfer<S>;
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
  /** 1-based. */
  readonly page: number;
  readonly size: number;
  readonly facets: { readonly [K in F]?: readonly string[] };
}

/** Typed input (JSON APIs, actions, MCP tools). Everything is optional. */
export interface ListQueryInput<S extends string, F extends string> {
  readonly q?: string;
  readonly sort?: S;
  readonly page?: number;
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
  readonly in: 'query';
  readonly required: false;
  readonly description: string;
  readonly schema: Readonly<Record<string, unknown>>;
  readonly style?: 'form';
  readonly explode?: boolean;
}

export interface FacetInfo {
  readonly key: string;
  readonly column: string;
  readonly nullable: boolean;
  /** Allowed values when the column is an enum or CHECK union. */
  readonly values?: readonly string[];
}

export interface ListDefinition<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
  S extends string,
  F extends string,
> {
  readonly table: T;
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
  /** Repository arguments: `where`, `orderBy`, `page`, `size`, `count`. */
  args(query: ListQuery<S, F>): OffsetPageArgs<M, T>;
  /** Runs the list against a table, merging your `select`, `include` and `where`. */
  run<const A extends ListExtra<M, T> & FindExt<E, M, T>>(
    db: { readonly [K in T]: RepositoryOf<M, K, E> },
    query: ListQuery<S, F>,
    extra?: A,
  ): AsyncResult<OffsetPage<Payload<M, T, A>>>;
  /** OpenAPI 3.1 query parameters. */
  readonly openapi: readonly OpenApiParameter[];
  /** JSON Schema of the typed input, e.g. for MCP tool arguments. */
  readonly jsonSchema: Readonly<Record<string, unknown>>;
}

export interface ListExtra<M extends AnyModels, T extends keyof M> {
  readonly select?: SelectArg<M, T>;
  readonly include?: IncludeArgs<M, T>;
  readonly where?: WhereInput<M, T>;
}

export type ListParsers<S extends string, F extends string> = {
  readonly q: ParserSpec<string>;
  readonly sort: ParserSpec<S>;
  readonly page: ParserSpec<number>;
  readonly size: ParserSpec<number>;
} & { readonly [K in F]: ParserSpec<readonly string[]> };

const RESERVED = new Set(['q', 'sort', 'page', 'size']);

function first(
  value: string | readonly string[] | undefined,
): string | undefined {
  return typeof value === 'string' ? value : value?.[0];
}

function all(value: string | readonly string[] | undefined): string[] {
  const values = typeof value === 'string' ? [value] : [...(value ?? [])];
  return values
    .flatMap((entry) => entry.split(','))
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function isSearchParams(value: object): value is ListSearchParams {
  return (
    value instanceof URLSearchParams ||
    !(
      'facets' in value &&
      typeof (value as { facets: unknown }).facets === 'object'
    )
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
  if (typeof raw === 'number') return raw;
  if (typeof raw !== 'string' || !/^\d+$/.test(raw)) return Number.NaN;
  return Number(raw);
}

/**
 * A reusable list endpoint for one table: search, facets, sorts and
 * pagination, validated from URL params or typed input, with URL parsers,
 * OpenAPI parameters and a JSON Schema derived from the same definition.
 *
 * ```ts
 * export const customerList = defineListQuery(sb, 'customers', {
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
>(
  sb: BetterSupabase<M, D, Fn, E>,
  table: T,
  config: ListQueryConfig<M, T, S, F>,
): ListDefinition<M, T, E, S, F> {
  const meta: TableMeta | undefined = sb.meta.tables[table];
  if (!meta) throw new TypeError(`defineListQuery: unknown table "${table}"`);
  const pageSize = config.pageSize ?? 50;
  const maxPageSize = config.maxPageSize ?? 200;
  const maxSearch = config.maxSearchLength ?? 200;
  const sortKeys = Object.keys(config.sorts) as S[];
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
    size?: unknown;
    facets: Partial<Record<string, readonly string[]>>;
  }): ListParseResult<S, F> {
    const issues: ValidationIssue[] = [];
    let q: string | undefined;
    if (raw.q !== undefined && raw.q !== null) {
      if (typeof raw.q !== 'string')
        issues.push({ message: 'Must be text', path: ['q'] });
      else if (raw.q.trim().length > maxSearch)
        issues.push({
          message: `At most ${String(maxSearch)} characters`,
          path: ['q'],
        });
      else if (raw.q.trim()) q = raw.q.trim();
    }
    let sort = config.defaultSort;
    if (raw.sort !== undefined && raw.sort !== '') {
      if (
        typeof raw.sort === 'string' &&
        (sortKeys as string[]).includes(raw.sort)
      )
        sort = raw.sort as S;
      else
        issues.push({
          message: `Must be one of: ${sortKeys.join(', ')}`,
          path: ['sort'],
        });
    }
    const page =
      raw.page === undefined || raw.page === '' ? 1 : toInt(raw.page);
    if (page === undefined || !Number.isInteger(page) || page < 1)
      issues.push({
        message: 'Must be a whole number of at least 1',
        path: ['page'],
      });
    const size =
      raw.size === undefined || raw.size === '' ? pageSize : toInt(raw.size);
    if (
      size === undefined ||
      !Number.isInteger(size) ||
      size < 1 ||
      size > maxPageSize
    ) {
      issues.push({
        message: `Must be a whole number from 1 to ${String(maxPageSize)}`,
        path: ['size'],
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
                ? 'This filter cannot be empty'
                : `Must be one of: ${(facet.values ?? []).join(', ')}`,
            path: ['facets', facet.key],
          });
        }
      }
      facetValues[facet.key as F] = [...new Set(values)];
    }
    if (issues.length > 0) return { ok: false, issues };
    return {
      ok: true,
      value: {
        ...(q ? { q } : {}),
        sort,
        page: page ?? 1,
        size: size ?? pageSize,
        facets: facetValues,
      },
    };
  }

  function parse(
    input: ListQueryInput<S, F> | ListSearchParams | undefined,
  ): ListParseResult<S, F> {
    if (input === undefined || input === null)
      return { ok: true, value: defaults };
    if (typeof input !== 'object')
      return {
        ok: false,
        issues: [{ message: 'Expected an object or URL parameters' }],
      };
    if (isSearchParams(input)) {
      const record = readRecord(input);
      const facetValues: Record<string, string[]> = {};
      for (const facet of facets)
        facetValues[facet.key] = all(record[facet.key]);
      return normalize({
        q: first(record['q']),
        sort: first(record['sort']),
        page: first(record['page']),
        size: first(record['size']),
        facets: facetValues,
      });
    }
    const typed = input as ListQueryInput<S, F>;
    const rawFacets = (typed.facets ?? {}) as Partial<Record<string, unknown>>;
    for (const [key, value] of Object.entries(rawFacets)) {
      if (
        !Array.isArray(value) ||
        value.some((entry) => typeof entry !== 'string')
      ) {
        return {
          ok: false,
          issues: [
            { message: 'Must be a list of values', path: ['facets', key] },
          ],
        };
      }
    }
    return normalize({
      q: typed.q,
      sort: typed.sort,
      page: typed.page,
      size: typed.size,
      facets: rawFacets as Record<string, string[]>,
    });
  }

  function where(query: ListQuery<S, F>): Record<string, unknown> | undefined {
    const parts: Record<string, unknown>[] = [];
    if (query.q && config.search) {
      if (Array.isArray(config.search)) {
        const columns = config.search as readonly string[];
        if (columns.length > 0)
          parts.push({
            OR: columns.map((column) => ({ [column]: { contains: query.q } })),
          });
      } else {
        const fts = config.search as { fts: string; config?: string };
        parts.push({
          [fts.fts]: {
            search: fts.config
              ? { query: query.q, config: fts.config }
              : query.q,
          },
        });
      }
    }
    for (const facet of facets) {
      const values = query.facets[facet.key as F];
      if (!values || values.length === 0) continue;
      const unset = values.includes(UNSET);
      const set = values.filter((value) => value !== UNSET);
      if (unset && set.length === 0) parts.push({ [facet.column]: null });
      else if (!unset) parts.push({ [facet.column]: { in: set } });
      else
        parts.push({
          OR: [{ [facet.column]: { in: set } }, { [facet.column]: null }],
        });
    }
    if (parts.length === 0) return undefined;
    return parts.length === 1 ? parts[0] : { AND: parts };
  }

  function args(query: ListQuery<S, F>): OffsetPageArgs<M, T> {
    const filter = where(query);
    return {
      ...(filter ? { where: filter } : {}),
      orderBy: config.sorts[query.sort],
      page: query.page,
      size: query.size,
      count: 'exact',
    } as OffsetPageArgs<M, T>;
  }

  const listParser: ParserSpec<readonly string[]> = {
    parse: (value) => {
      const values = all(value);
      return values.length > 0 ? values : null;
    },
    serialize: (values) => values.join(','),
  };
  const intParser: ParserSpec<number> = {
    parse: (value) => (/^\d+$/.test(value) ? Number(value) : null),
    serialize: String,
  };
  const parsers = {
    q: {
      parse: (value: string) => value.trim() || null,
      serialize: (value: string) => value,
    },
    sort: {
      parse: (value: string) =>
        (sortKeys as string[]).includes(value) ? (value as S) : null,
      serialize: (value: S) => value,
    },
    page: intParser,
    size: intParser,
    ...Object.fromEntries(facets.map((facet) => [facet.key, listParser])),
  } as ListParsers<S, F>;

  const facetSchema = (facet: FacetInfo): Record<string, unknown> => ({
    type: 'array',
    items: {
      type: 'string',
      ...(facet.values
        ? { enum: [...facet.values, ...(facet.nullable ? [UNSET] : [])] }
        : {}),
    },
    uniqueItems: true,
  });
  const searchDescription = config.search
    ? Array.isArray(config.search)
      ? `Case-insensitive search in ${(config.search as readonly string[]).join(', ')}.`
      : 'Full-text search (web search syntax).'
    : undefined;

  const openapi: OpenApiParameter[] = [
    ...(searchDescription
      ? [
          {
            name: 'q',
            in: 'query',
            required: false,
            description: searchDescription,
            schema: { type: 'string', maxLength: maxSearch },
          } as const,
        ]
      : []),
    {
      name: 'sort',
      in: 'query',
      required: false,
      description: `Ordering. Default \`${config.defaultSort}\`.`,
      schema: { type: 'string', enum: sortKeys, default: config.defaultSort },
    },
    {
      name: 'page',
      in: 'query',
      required: false,
      description: '1-based page number.',
      schema: { type: 'integer', minimum: 1, default: 1 },
    },
    {
      name: 'size',
      in: 'query',
      required: false,
      description: 'Page size.',
      schema: {
        type: 'integer',
        minimum: 1,
        maximum: maxPageSize,
        default: pageSize,
      },
    },
    ...facets.map((facet): OpenApiParameter => ({
      name: facet.key,
      in: 'query',
      required: false,
      description: `Filter on ${facet.column}. Comma-separated; any value matches.${facet.nullable ? ` \`${UNSET}\` matches empty.` : ''}`,
      schema: facetSchema(facet),
      style: 'form',
      explode: false,
    })),
  ];

  const jsonSchema = {
    type: 'object',
    additionalProperties: false,
    properties: {
      ...(searchDescription
        ? {
            q: {
              type: 'string',
              maxLength: maxSearch,
              description: searchDescription,
            },
          }
        : {}),
      sort: { type: 'string', enum: sortKeys, default: config.defaultSort },
      page: { type: 'integer', minimum: 1, default: 1 },
      size: {
        type: 'integer',
        minimum: 1,
        maximum: maxPageSize,
        default: pageSize,
      },
      ...(facets.length > 0
        ? {
            facets: {
              type: 'object',
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
    defaults,
    facets,
    parse,
    schema: {
      '~standard': {
        version: 1,
        vendor: 'better-supabase',
        validate(value) {
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
      if (query.q) params.set('q', query.q);
      if (query.sort && query.sort !== config.defaultSort)
        params.set('sort', query.sort);
      if (query.page && query.page !== 1)
        params.set('page', String(query.page));
      if (query.size && query.size !== pageSize)
        params.set('size', String(query.size));
      for (const facet of facets) {
        const values = query.facets?.[facet.key as F];
        if (values && values.length > 0)
          params.set(facet.key, values.join(','));
      }
      return params;
    },
    parsers,
    nuqs: (createParser) =>
      Object.fromEntries(
        Object.entries(parsers).map(([key, spec]) => [
          key,
          createParser(spec as ParserSpec<unknown>),
        ]),
      ) as never,
    args,
    run(db, query, extra) {
      const base = args(query) as Record<string, unknown>;
      const extraWhere = extra?.where;
      const combined =
        base['where'] && extraWhere
          ? { AND: [extraWhere, base['where']] }
          : (extraWhere ?? base['where']);
      const repository = db[table] as unknown as {
        paginate: (input: Record<string, unknown>) => AsyncResult<unknown>;
      };
      return repository.paginate({
        ...extra,
        ...base,
        ...(combined ? { where: combined } : {}),
      }) as AsyncResult<never>;
    },
    openapi,
    jsonSchema,
  };
}
