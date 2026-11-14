import type { StandardSchemaV1 } from "@standard-schema/spec";

import type {
  FacetResult,
  ListPage,
  PageOptions,
} from "../core/block-helpers.ts";
import type { EntityListSurface } from "../core/entity-list.ts";
import type { DbError, ValidationIssue } from "../core/errors.ts";

import { AsyncResult, err, ok } from "../core/result.ts";
import { decodeFilterQuery } from "./filter-query.ts";

/** The version of the `EntityPage` descriptor `gen` reads (ADR 0859). */
export const ENTITY_PAGE_API_VERSION = 1;

/**
 * The list surface and reads of an entity no block owns: an app table, or a
 * list the app reads itself. `defineEntityPage` takes it as `app` with an
 * entity named `app.<key>`.
 */
export interface EntityAppSource {
  /** What the list sorts, counts, filters and searches by. */
  readonly surface: {
    readonly sorts?: readonly string[];
    readonly facets?: readonly string[];
    /** Default: `facets`. */
    readonly filters?: readonly string[];
    readonly search?: boolean | readonly string[];
  };
  /**
   * The table behind the entity, so `gen` writes its indexes and scale test.
   * `columns` maps each sort, facet and column key to the database column.
   */
  readonly table?: {
    /** Default `public`. */
    readonly schema?: string;
    readonly name: string;
    /** The tenant column, when the table has one. */
    readonly tenant?: string;
    readonly columns: Readonly<Record<string, string>>;
  };
  /**
   * The module that holds the reads: its export is a function that takes the
   * route's `db` and returns the entity's `page` and `facets`
   * (`EntityListReads`). The generated routes call it in place of
   * `db.<reads>.<page>`.
   */
  readonly reads: { readonly module: string; readonly export: string };
}

/** One entity's page: what the app writes, and what every generator reads. */
export interface EntityPage {
  /** The version of this descriptor, so a breaking change needs a new one. */
  readonly apiVersion: typeof ENTITY_PAGE_API_VERSION;
  /**
   * The block entity as `<block>.<entity>` (`risks.risk`). The block manifest
   * supplies its sorts, facets, filters, search and permissions.
   */
  readonly entity: string;
  /** The page's route in the app (`/risks`). */
  readonly route: string;
  /**
   * The name of the generated files (`risks`). Default: the last segment of
   * `route`.
   */
  readonly name?: string;
  /**
   * The expression under `db` that holds the entity's `page`, `facets` and
   * `count` reads. Default: the block name.
   */
  readonly reads?: string;
  /**
   * The names of the `page` and `facets` methods on `reads`. Default `page` and
   * `facets`; a block that lists several entities names them per entity
   * (`periodPage`, `periodFacets`).
   */
  readonly methods?: { readonly page?: string; readonly facets?: string };
  /**
   * Names the per-call option a block takes for the organization
   * (`organizationId`, a `RequiredTenantOption`). The generated routes pass the
   * request's tenant under that name to `page`, `facets` and the export.
   */
  readonly tenantOption?: string;
  /**
   * An entity no block owns: an app table or a list the app reads itself. Then
   * `entity` is `app.<key>` and the surface, the table and the reads come from
   * here instead of a block manifest.
   */
  readonly app?: EntityAppSource;
  /** The list's paging; the entity documents its own default and cap. */
  readonly list?: {
    /** The `limit` a request gets without one. */
    readonly pageSize?: number;
    /** The most a request may ask for. */
    readonly maxPageSize?: number;
  };
  /** The nav area the page sits under. Read by the nav generator (lane M3). */
  readonly area?: string;
  /** The columns of the list, in order. Read by the column generator (lane M2). */
  readonly columns?: readonly string[];
  /** The sections of the detail page. Read by the detail generator (lane M2). */
  readonly sections?: readonly string[];
  /** The demo rows and tiers to seed. Read by the seed generator (lane M3). */
  readonly seed?: {
    readonly demo?: number;
    readonly tiers?: readonly string[];
  };
  /**
   * Adds a CSV download route over the page's filters: `gen` writes `GET
   * /api/<name>/export`, which reads the list query's `q`, `sort` and filters
   * and streams `exportResponse` over the entity's `page` (ADR 0880).
   */
  readonly export?: {
    /** The download's file name. Default `<name>.csv`. */
    readonly filename?: string;
    /**
     * The CSV columns, in order. Default: `columns`, else the first page's
     * keys.
     */
    readonly columns?: readonly string[];
    /** The most rows written. Default 100000 (`EXPORT_ROW_CAP`). */
    readonly maxRows?: number;
  };
}

/** What `defineEntityPage` takes: an `EntityPage` without its version. */
export type EntityPageInput = Omit<EntityPage, "apiVersion">;

const ENTITY = /^[a-z][a-z0-9-]*\.[a-z][a-z0-9_]*$/;

/**
 * Declares an entity page once so the generators can read it: `gen` writes the
 * list query, its route, its indexes and the scale test from it, and the later
 * generators add columns, detail, forms, seed rows and navigation. List it in
 * `gen.entityPages.pages`.
 */
export function defineEntityPage(input: EntityPageInput): EntityPage {
  if (!ENTITY.test(input.entity)) {
    throw new TypeError(
      `defineEntityPage: entity "${input.entity}" must be "<block>.<entity>", such as "risks.risk".`,
    );
  }

  if (!input.route.startsWith("/")) {
    throw new TypeError(
      `defineEntityPage: route "${input.route}" must start with "/".`,
    );
  }

  if (input.app !== undefined && !input.entity.startsWith("app.")) {
    throw new TypeError(
      `defineEntityPage: entity "${input.entity}" sets \`app\`, so it must be named "app.<entity>".`,
    );
  }

  if (input.app === undefined && input.entity.startsWith("app.")) {
    throw new TypeError(
      `defineEntityPage: entity "${input.entity}" is an app entity; set \`app\` with its surface and reads.`,
    );
  }

  return { apiVersion: ENTITY_PAGE_API_VERSION, ...input };
}

/** A page of rows with the facet counts under the same filters. */
export interface EntityListResult<Item> {
  readonly page: ListPage<Item>;
  readonly facets: readonly FacetResult[];
}

/** The URL form of a list's input: `URLSearchParams` or a `searchParams` record. */
export type EntityListSearchParams =
  | URLSearchParams
  | Readonly<Record<string, string | readonly string[] | undefined>>;

/** The checked options, or what is wrong with them. */
export type EntityListParse =
  | { readonly ok: true; readonly value: PageOptions }
  | { readonly ok: false; readonly issues: readonly ValidationIssue[] };

/** What `defineEntityListQuery` takes besides the surface. */
export interface EntityListQueryOptions {
  /** The entity, for messages (`risks.risk`). */
  readonly entity: string;
  /** The `limit` a request gets without one. Default: the entity's own. */
  readonly pageSize?: number;
  /** The most a request may ask for. Default 200. */
  readonly maxPageSize?: number;
}

/**
 * The reads of a block entity a list runs: its `page` and `facets`. A block
 * that takes the organization per call also takes it through `extra`.
 */
export interface EntityListReads<Item> {
  page(
    options: PageOptions & Readonly<Record<string, unknown>>,
  ): PromiseLike<ReadResult<ListPage<Item>>>;
  facets(
    options: Pick<PageOptions, "q" | "filters"> &
      Readonly<Record<string, unknown>>,
  ): PromiseLike<ReadResult<readonly FacetResult[]>>;
}

type ReadResult<T> =
  | { readonly ok: true; readonly data: T; readonly error: null }
  | { readonly ok: false; readonly data: null; readonly error: DbError };

/**
 * A list over a block entity's `page` and `facets`: it turns URL state or typed
 * input into `PageOptions`, refuses a sort, filter or `q` the entity does not
 * declare, and runs the page and its facet counts in one wave (ADR 0859).
 */
export interface EntityListQuery {
  readonly entity: string;
  readonly surface: EntityListSurface;
  /**
   * Reads `q`, `sort` (`key` or `key:asc|desc`), `limit`, repeated `after`
   * values and one parameter per declared filter (`status=open,closed`).
   */
  parse(input: EntityListSearchParams | undefined): EntityListParse;
  /**
   * The filters of a ReUI filter tree (`FilterQuery`): an `and` group of `is`,
   * `is_any_of` and `has_any_of` rules, one per declared filter. Any other
   * operator, a nested group, a negated rule or a repeated field is an issue.
   * `parse` reads the same tree from the `filter` parameter.
   */
  fromFilterTree(
    tree: unknown,
  ):
    | { readonly ok: true; readonly value: NonNullable<PageOptions["filters"]> }
    | { readonly ok: false; readonly issues: readonly ValidationIssue[] };
  /** The same checks over typed input, as a Standard Schema. */
  readonly schema: StandardSchemaV1<unknown, PageOptions>;
  /** The URL form of `options`, the inverse of `parse`. */
  toSearchParams(options: PageOptions): URLSearchParams;
  /** The page and the counts of every declared facet, under the same filters. */
  run<Row>(
    reads: EntityListReads<Row>,
    options: PageOptions,
    extra?: Readonly<Record<string, unknown>>,
  ): AsyncResult<EntityListResult<Row>>;
}

const DIRECTIONS: ReadonlySet<string> = new Set(["asc", "desc"]);

function listOf(names: readonly string[] | undefined): string {
  return names === undefined || names.length === 0 ? "none" : names.join(", ");
}

function valuesOf(
  input: EntityListSearchParams,
  key: string,
): readonly string[] {
  const raw = input instanceof URLSearchParams ? input.getAll(key) : input[key];

  const list = raw === undefined ? [] : typeof raw === "string" ? [raw] : raw;

  return list.flatMap((value) => value.split(",")).filter((v) => v !== "");
}

function isPlain(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isStrings(value: unknown): value is readonly string[] {
  return Array.isArray(value) && value.every((v) => typeof v === "string");
}

/**
 * The list query over one entity's declared surface. `gen` writes a call to it
 * per entity page; the surface comes from the block manifest.
 */
export function defineEntityListQuery(
  surface: EntityListSurface,
  options: EntityListQueryOptions,
): EntityListQuery {
  const maxLimit = options.maxPageSize ?? 200;
  const filterNames = surface.filters ?? surface.facets ?? [];

  function check(candidate: PageOptions): readonly ValidationIssue[] {
    const issues: ValidationIssue[] = [];

    if (
      candidate.q !== undefined &&
      (surface.search === undefined || surface.search === false)
    ) {
      issues.push({ message: `${options.entity} has no search.`, path: ["q"] });
    }

    if (
      candidate.sort !== undefined &&
      !(surface.sorts ?? []).includes(candidate.sort.by)
    ) {
      issues.push({
        message: `Sort by ${candidate.sort.by} is not declared; use ${listOf(surface.sorts)}.`,
        path: ["sort"],
      });
    }

    for (const key of Object.keys(candidate.filters ?? {})) {
      if (!filterNames.includes(key)) {
        issues.push({
          message: `Filter ${key} is not declared; use ${listOf(filterNames)}.`,
          path: ["filters", key],
        });
      }
    }

    if (
      candidate.limit !== undefined &&
      (!Number.isInteger(candidate.limit) ||
        candidate.limit < 1 ||
        candidate.limit > maxLimit)
    ) {
      issues.push({
        message: `limit must be a whole number from 1 to ${String(maxLimit)}.`,
        path: ["limit"],
      });
    }

    return issues;
  }

  const TREE_OPERATORS: ReadonlySet<string> = new Set([
    "is",
    "is_any_of",
    "has_any_of",
  ]);

  function fromFilterTree(
    tree: unknown,
  ): ReturnType<EntityListQuery["fromFilterTree"]> {
    const issues: ValidationIssue[] = [];
    const filters: Record<string, readonly string[]> = {};
    const path = ["filter"];

    if (
      !isPlain(tree) ||
      tree["type"] !== "group" ||
      tree["combinator"] !== "and"
    ) {
      return {
        ok: false,
        issues: [{ message: "A filter tree is one `and` group.", path }],
      };
    }

    const rules: unknown = tree["rules"];

    for (const rule of Array.isArray(rules) ? rules : []) {
      if (
        !isPlain(rule) ||
        rule["type"] !== "rule" ||
        rule["negated"] === true ||
        !TREE_OPERATORS.has(String(rule["operator"]))
      ) {
        issues.push({
          message:
            "A filter rule is `is` or `is any of`, not negated, on a declared filter.",
          path,
        });
        continue;
      }

      const fieldPath: unknown = rule["path"];

      // SAFETY: Array.isArray narrows to any[]; the entry is checked as a string below.
      const field: unknown = Array.isArray(fieldPath)
        ? (fieldPath as unknown[])[0]
        : undefined;

      const raw: unknown = rule["value"];
      const values = typeof raw === "string" ? [raw] : raw;

      if (typeof field !== "string" || !filterNames.includes(field)) {
        issues.push({
          message: `Filter ${String(field)} is not declared; use ${listOf(filterNames)}.`,
          path: [...path, String(field)],
        });
      } else if (field in filters) {
        issues.push({
          message: `Filter ${field} appears twice.`,
          path: [...path, field],
        });
      } else if (!isStrings(values) || values.length === 0) {
        issues.push({
          message: `Filter ${field} needs one or more values.`,
          path: [...path, field],
        });
      } else {
        filters[field] = values;
      }
    }

    return issues.length > 0
      ? { ok: false, issues }
      : { ok: true, value: filters };
  }

  function parse(input: EntityListSearchParams | undefined): EntityListParse {
    const source = input ?? new URLSearchParams();
    const issues: ValidationIssue[] = [];
    const [q] = valuesOf(source, "q");
    const [sortText] = valuesOf(source, "sort");
    const [limitText] = valuesOf(source, "limit");
    const after = valuesOf(source, "after");

    let sort: PageOptions["sort"];

    if (sortText !== undefined) {
      const [by = "", direction] = sortText.split(":");

      if (direction !== undefined && !DIRECTIONS.has(direction)) {
        issues.push({
          message: "A sort direction is asc or desc.",
          path: ["sort"],
        });
      } else {
        sort = {
          by,
          ...(direction === undefined
            ? {}
            : { direction: direction === "asc" ? "asc" : "desc" }),
        };
      }
    }

    const filters: Record<string, readonly string[]> = {};

    for (const key of filterNames) {
      const values = valuesOf(source, key);

      if (values.length > 0) {
        filters[key] = values;
      }
    }

    const [treeText] = valuesOf(source, "filter");

    if (treeText !== undefined) {
      const tree = fromFilterTree(decodeFilterQuery(treeText));

      if (tree.ok) {
        for (const [key, values] of Object.entries(tree.value)) {
          if (key in filters) {
            issues.push({
              message: `Filter ${key} is set by its parameter and by the filter tree.`,
              path: ["filter", key],
            });
          } else {
            filters[key] = values;
          }
        }
      } else {
        issues.push(...tree.issues);
      }
    }

    const candidate: PageOptions = {
      ...(q === undefined ? {} : { q }),
      ...(sort === undefined ? {} : { sort }),
      ...(Object.keys(filters).length === 0 ? {} : { filters }),
      ...(after.length === 0 ? {} : { after }),
      ...(limitText === undefined ? {} : { limit: Number(limitText) }),
    };

    issues.push(...check(candidate));

    return issues.length > 0
      ? { ok: false, issues }
      : { ok: true, value: candidate };
  }

  const schema: StandardSchemaV1<unknown, PageOptions> = {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate(value) {
        if (value === undefined) {
          return { value: {} };
        }

        if (!isPlain(value)) {
          return { issues: [{ message: "Expected an object." }] };
        }

        const { q, sort, filters, after, limit } = value;
        const issues: ValidationIssue[] = [];

        if (q !== undefined && typeof q !== "string") {
          issues.push({ message: "q must be text.", path: ["q"] });
        }

        if (
          sort !== undefined &&
          !(isPlain(sort) && typeof sort["by"] === "string")
        ) {
          issues.push({ message: "sort needs a `by`.", path: ["sort"] });
        }

        if (
          filters !== undefined &&
          !(
            isPlain(filters) &&
            Object.values(filters).every((entry) => isStrings(entry))
          )
        ) {
          issues.push({
            message: "filters hold a list of values per name.",
            path: ["filters"],
          });
        }

        if (after !== undefined && !isStrings(after)) {
          issues.push({ message: "after must be a list.", path: ["after"] });
        }

        if (limit !== undefined && typeof limit !== "number") {
          issues.push({ message: "limit must be a number.", path: ["limit"] });
        }

        if (issues.length > 0) {
          return { issues };
        }

        // SAFETY: each key was checked above, so the object has the shape of
        // `PageOptions`.
        const candidate = value as PageOptions;
        const declared = check(candidate);

        return declared.length > 0
          ? { issues: [...declared] }
          : { value: candidate };
      },
    },
  };

  return {
    entity: options.entity,
    surface,
    parse,
    fromFilterTree,
    schema,
    toSearchParams(page) {
      const params = new URLSearchParams();

      if (page.q !== undefined && page.q !== "") {
        params.set("q", page.q);
      }

      if (page.sort !== undefined) {
        params.set(
          "sort",
          page.sort.direction === undefined
            ? page.sort.by
            : `${page.sort.by}:${page.sort.direction}`,
        );
      }

      for (const [key, values] of Object.entries(page.filters ?? {})) {
        if (values.length > 0) {
          params.set(key, values.join(","));
        }
      }

      for (const value of page.after ?? []) {
        params.append("after", value);
      }

      if (page.limit !== undefined) {
        params.set("limit", String(page.limit));
      }

      return params;
    },
    run(reads, page, extra = {}) {
      const withLimit: PageOptions = {
        ...page,
        ...(page.limit === undefined && options.pageSize !== undefined
          ? { limit: options.pageSize }
          : {}),
      };

      const facetOptions = {
        ...(page.q === undefined ? {} : { q: page.q }),
        ...(page.filters === undefined ? {} : { filters: page.filters }),
        ...extra,
      };

      return AsyncResult.from(async () => {
        const [rows, facets] = await Promise.all([
          reads.page({ ...withLimit, ...extra }),
          reads.facets(facetOptions),
        ]);

        if (!rows.ok) {
          return err(rows.error);
        }

        if (!facets.ok) {
          return err(facets.error);
        }

        return ok({ page: rows.data, facets: facets.data });
      });
    },
  };
}
