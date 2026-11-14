import type {
  BlockCall,
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "./block-helpers.ts";
import type { ExportOptions } from "./entity-export.ts";
import type { Result } from "./result.ts";
import type { BlockTenant } from "./tenant-source.ts";

import { pageRowsOf, recordOf, recordsOf, textOf } from "./block-helpers.ts";
import { requireTenant } from "./block-tenant.ts";
import { exportCsv } from "./entity-export.ts";
import { dbError } from "./errors.ts";
import { AsyncResult, err, ok } from "./result.ts";

/**
 * The part of an entity's declared surface a list reads (ADR 0749): the names
 * `sort.by`, `filters` and the facets may use, and whether `q` is accepted. The
 * block manifest declares them in `entities`; the SQL list function declares
 * the same names, and a test keeps the two equal.
 */
export interface EntityListSurface {
  readonly sorts?: readonly string[];
  readonly facets?: readonly string[];
  readonly filters?: readonly string[];
  readonly search?: boolean | readonly string[];
}

/**
 * What a list adds when its organization comes with the call instead of the
 * block's `tenant` option (ADR 0939). Without it the list reads the block's
 * `tenant`, and fails with `TENANT_REQUIRED` when neither is set.
 */
export interface TenantOption {
  /** The organization to read. Default: the block's `tenant` option. */
  readonly organizationId?: string;
}

/**
 * What a list adds when its block has no `tenant` option, so every call names
 * the organization (ADR 0939).
 */
export interface RequiredTenantOption {
  /** The organization to read. */
  readonly organizationId: string;
}

/**
 * The arguments of a read: the options are required when `Extra` has a required
 * key.
 */
export type ListCallParams<
  Options extends object,
  Extra extends object,
> = object extends Extra
  ? [options?: Options & Extra]
  : [options: Options & Extra];

/** What `facets` reads: the filters of `page`, and the facets to count. */
export interface FacetOptions extends Pick<PageOptions, "q" | "filters"> {
  /** The facets to count. Default every facet the entity declares. */
  readonly facets?: readonly string[];
}

/** What `count` reads: the filters of `page`. */
export type CountOptions = Pick<PageOptions, "q" | "filters">;

/**
 * The three reads every list entity has (ADR 0749). `Extra` is what a block
 * adds to all three options, such as `TenantOption` for a list that takes the
 * organization per call (ADR 0939).
 */
export interface EntityList<Item, Extra extends object = object> {
  /** One keyset page, in the order of `sort` (the entity's default without it). */
  readonly page: (
    ...args: ListCallParams<PageOptions, Extra>
  ) => AsyncResult<ListPage<Item>>;
  /** The values of each facet and how many rows hold each, under the filters. */
  readonly facets: (
    ...args: ListCallParams<FacetOptions, Extra>
  ) => AsyncResult<readonly FacetResult[]>;
  /** How many rows match; `exact` is `false` when the count stopped at a cap. */
  readonly count: (
    ...args: ListCallParams<CountOptions, Extra>
  ) => AsyncResult<Count>;
}

/**
 * An `EntityList` with `export` (ADR 0855): what `entityList` builds. A block
 * that writes its own `page` exports with `exportCsv(page, options)`.
 */
export interface ExportableEntityList<
  Item,
  Extra extends object = object,
> extends EntityList<Item, Extra> {
  /**
   * The rows `page` returns for the same filters as a CSV stream, one page at a
   * time (ADR 0855).
   */
  readonly export: (
    ...args: ListArgs<ExportOptions, Extra>
  ) => ReadableStream<string>;
}

/** What `entityList` needs from a block. */
export interface EntityListSpec<Item> {
  /** The entity key, for error messages. */
  readonly entity: string;
  readonly surface: EntityListSurface;
  readonly call: BlockCall;
  /**
   * The organization to read, given the call's `organizationId` when it has
   * one. A block with a `tenant` option passes `() => requireTenant(...)`; a
   * block that takes the organization per call passes `tenantOrOption`.
   */
  readonly tenant: (organizationId?: string) => AsyncResult<string>;
  /** The block's SQL list function. */
  readonly fn: string;
  readonly rowOf: (row: Record<string, unknown>, fn: string) => Item;
  /** Filters the list always sends, such as `{ mine: true }` for a member. */
  readonly base?: Readonly<Record<string, unknown>>;
}

/**
 * The `tenant` of a list that takes the organization per call (ADR 0939): the
 * call's `organizationId` when set, else the block's `tenant` option through
 * `requireTenant`.
 */
export function tenantOrOption(
  tenant: BlockTenant | undefined,
): (organizationId?: string) => AsyncResult<string> {
  return (organizationId) =>
    organizationId === undefined
      ? requireTenant(tenant)
      : AsyncResult.ok(organizationId);
}

const invalid = <T>(message: string): Result<T> =>
  err(dbError("invalid_input", message));

const listOf = (names: readonly string[] | undefined): string =>
  names === undefined || names.length === 0 ? "none" : names.join(", ");

/**
 * The filters object the SQL list function reads for `options`, or an
 * `invalid_input` error for a sort, filter or `q` the entity does not declare.
 */
export function listFilters(
  spec: Pick<EntityListSpec<unknown>, "entity" | "surface" | "base">,
  options: PageOptions = {},
): Result<Record<string, unknown>> {
  const { entity, surface } = spec;
  const filters: Record<string, unknown> = { ...spec.base };

  if (options.sort !== undefined) {
    if (!(surface.sorts ?? []).includes(options.sort.by)) {
      return invalid(
        `${entity} sorts by ${listOf(surface.sorts)}, not "${options.sort.by}"`,
      );
    }

    filters["sort"] = options.sort.by;

    if (options.sort.direction !== undefined) {
      filters["direction"] = options.sort.direction;
    }
  }

  for (const [key, values] of Object.entries(options.filters ?? {})) {
    if (!(surface.filters ?? []).includes(key)) {
      return invalid(
        `${entity} filters by ${listOf(surface.filters)}, not "${key}"`,
      );
    }

    filters[key] = [...values];
  }

  if (options.q !== undefined && options.q !== "") {
    if (surface.search === undefined || surface.search === false) {
      return invalid(`${entity} has no text search`);
    }

    filters["search"] = options.q;
  }

  if (options.after !== undefined) {
    filters["after"] = [...options.after];
  }

  if (options.limit !== undefined) {
    filters["limit"] = options.limit;
  }

  return ok(filters);
}

/** A `{ value, exact }` reply as a `Count`. */
function countOf(value: unknown, fn: string): Count {
  const row = recordOf(value, fn);
  const counted = row["value"];

  if (typeof counted !== "number") {
    throw new TypeError(`${fn} returned ${JSON.stringify(value)}`);
  }

  return { value: counted, exact: row["exact"] === true };
}

/** A `{ facet, values }` reply as a `FacetResult`. */
function facetOf(value: unknown, fn: string): FacetResult {
  const row = recordOf(value, fn);

  return {
    facet: textOf(row["facet"]),
    values: recordsOf(row["values"], fn).map((entry) => ({
      value: textOf(entry["value"]),
      count: countOf(entry["count"], fn),
    })),
  };
}

/**
 * `page`, `facets` and `count` over one SQL list function (ADR 0749). The three
 * read the same filters, so a page and the facet counts beside it always agree.
 * A block builds one per list entity from the entity's declared surface; it
 * keeps its own `list` for the capped convenience.
 */
export function entityList<Item, Extra extends object = object>(
  spec: EntityListSpec<Item>,
): ExportableEntityList<Item, Extra>;
export function entityList<Item>(
  spec: EntityListSpec<Item>,
): ExportableEntityList<Item, TenantOption> {
  const { call, fn, tenant } = spec;

  const read = <T>(
    organization: string | undefined,
    filters: Result<Record<string, unknown>>,
    extra: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T,
  ): AsyncResult<T> =>
    filters.ok
      ? tenant(organization).andThen((organizationId) =>
          call(
            fn,
            { tenant: organizationId, filters: { ...filters.data, ...extra } },
            then,
          ),
        )
      : AsyncResult.err(filters.error);

  const page = (options: PageOptions & TenantOption = {}) =>
    read(
      options.organizationId,
      listFilters(spec, options),
      { paged: true },
      (value) => {
        const page = pageRowsOf(value, fn);

        return { ...page, items: page.items.map((row) => spec.rowOf(row, fn)) };
      },
    );

  return {
    page,
    facets: (options: FacetOptions & TenantOption = {}) => {
      const names = options.facets ?? spec.surface.facets ?? [];

      const unknown = names.find(
        (name) => !(spec.surface.facets ?? []).includes(name),
      );

      if (unknown !== undefined) {
        return AsyncResult.err(
          dbError(
            "invalid_input",
            `${spec.entity} has facets ${listOf(spec.surface.facets)}, not "${unknown}"`,
          ),
        );
      }

      const filters = listFilters(spec, options);

      return AsyncResult.from(async () => {
        const results: FacetResult[] = [];

        const reads = await Promise.all(
          names.map((facet) =>
            read(options.organizationId, filters, { facet }, (value) =>
              facetOf(value, fn),
            ),
          ),
        );

        for (const found of reads) {
          if (!found.ok) {
            return found;
          }

          results.push(found.data);
        }

        return ok<readonly FacetResult[]>(results);
      });
    },
    count: (options: CountOptions & TenantOption = {}) =>
      read(
        options.organizationId,
        listFilters(spec, options),
        { count: true },
        (value) => countOf(value, fn),
      ),
    export: (options: ExportOptions & TenantOption = {}) =>
      exportCsv(
        (exportPage) =>
          page({
            ...exportPage,
            ...(options.organizationId === undefined
              ? {}
              : { organizationId: options.organizationId }),
          }),
        options,
      ),
  };
}
