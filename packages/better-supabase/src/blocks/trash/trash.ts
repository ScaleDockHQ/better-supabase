import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  entityList,
  foundOrNotFound,
  tenantOrOption,
} from "../../core/entity-list.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { trashListSurface } from "./lists.ts";

export interface TrashOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the trash item's extra columns (columns the app's
   * schema files add to the table), keyed by database name, such as a reason.
   * It types and parses them on `list`, and validates them on `trash`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Trash<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** What `trash` and `restore` return: the batch and how many rows it holds. */
export interface TrashBatch {
  /** The trash item of the subject that was trashed. */
  readonly id: string;
  readonly batchId: string;
  /** The subject and the children trashed with it. */
  readonly count: number;
}

/** A subject in the trash, with the children trashed along with it counted in. */
export interface TrashItem<
  F extends object = Record<never, never>,
> extends TrashBatch {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title?: string;
  readonly trashedBy?: string;
  readonly trashedAt: Temporal.Instant;
  /** When `purge_expired_trash` deletes it; absent when retention is off. */
  readonly purgeAfter?: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface TrashListOptions {
  readonly subjectType?: string;
  readonly pageSize?: number;
  /** Items trashed before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface Trash<F extends object = Record<never, never>> {
  /**
   * Trashes the subject and its children in one batch; `fields` sets the item's
   * extra columns.
   */
  trash(input: {
    organizationId: string;
    subjectType: string;
    subjectId: string;
    fields?: Partial<F> | undefined;
  }): AsyncResult<TrashBatch>;
  /** Restores the whole batch of a trash item. */
  restore(id: string): AsyncResult<TrashBatch>;
  /**
   * One keyset page of the organization's trash, newest first, one entry per
   * batch. `filters` takes `subjectType`; `q` matches the title (ADR 1077).
   */
  page(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<TrashItem<F>>>;
  /** Counts per `subjectType` for the page's `q` and filters. */
  facets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many batches match the page's `q` and filters. */
  count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** One trash item, or a `not_found` error. */
  get(id: string): AsyncResult<TrashItem<F>>;
  /**
   * Newest first, one entry per batch.
   *
   * @deprecated Use `page` (ADR 1077).
   */
  list(
    input: { organizationId: string } & TrashListOptions,
  ): AsyncResult<readonly TrashItem<F>[]>;
  /** Deletes the batch's rows for good; returns how many were deleted. */
  purge(id: string): AsyncResult<number>;
}

function batchOf(value: unknown, fn: string): TrashBatch {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    batchId: textOf(row["batchId"]),
    count: Number(row["count"]),
  };
}

function itemOf(value: unknown, fn: string): TrashItem {
  const row = recordOf(value, fn);
  const title = optionalText(row["title"]);
  const trashedBy = optionalText(row["trashedBy"]);

  return {
    ...batchOf(row, fn),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    trashedAt: requiredInstant(row["trashedAt"], "trashedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...(title === undefined ? {} : { title }),
    ...(trashedBy === undefined ? {} : { trashedBy }),
    ...(row["purgeAfter"] === null || row["purgeAfter"] === undefined
      ? {}
      : { purgeAfter: requiredInstant(row["purgeAfter"], "purgeAfter") }),
  };
}

/** The `trash` SQL module as typed calls. */
export function createTrash<S extends StandardSchemaV1 | undefined = undefined>(
  options: TrashOptions<S>,
): Trash<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "trash item fields",
  );

  const trashPages = entityList<TrashItem, RequiredTenantOption>({
    entity: "trash item",
    surface: trashListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_trash",
    rowOf: (row) => itemOf(row, "page_trash"),
  });

  const client: Trash<F> = {
    page: (pageOptions) =>
      trashPages
        .page(pageOptions)
        .andThen((page) =>
          fields.rows(page.items).map((items) => ({ ...page, items })),
        ),
    facets: trashPages.facets,
    count: trashPages.count,
    get: (id) =>
      call("get_trash", { item_id: id }, (value) =>
        value === null || value === undefined
          ? undefined
          : itemOf(value, "get_trash"),
      )
        .andThen((item) => foundOrNotFound("trash item", item, id))
        .andThen(fields.row),
    trash: ({ organizationId, subjectType, subjectId, fields: extra }) =>
      fields
        .args(extra)
        .andThen((checked) =>
          call(
            "trash",
            {
              tenant: organizationId,
              subject_type: subjectType,
              subject_id: subjectId,
              fields: checked,
            },
            (value) => batchOf(value, "trash"),
          ),
        ),
    restore: (id) =>
      call("restore_trash", { item_id: id }, (value) =>
        batchOf(value, "restore_trash"),
      ),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated method stays an alias until 0.70 (ADR 1077)
    list: ({ organizationId, ...page }) =>
      call(
        "list_trash",
        {
          tenant: organizationId,
          subject_type: page.subjectType ?? null,
          page_size: page.pageSize ?? null,
          before: page.before?.toString() ?? null,
        },
        (value) =>
          recordsOf(value, "list_trash").map((row) =>
            itemOf(row, "list_trash"),
          ),
      ).andThen(fields.rows),
    purge: (id) => call("purge_trash", { item_id: id }, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "trash",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
