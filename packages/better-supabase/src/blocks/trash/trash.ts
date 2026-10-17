import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type ExtraFields,
  type FieldsOf,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface TrashOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the trash item's extra columns
   * (`blocks.trash.options.extraColumns`), keyed by database name, such as a
   * reason. It types and parses them on `list`, and validates them on
   * `trash`.
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
  /** Trashes the subject and its children in one batch; `fields` sets the item's extra columns. */
  trash(
    organizationId: string,
    subjectType: string,
    subjectId: string,
    fields?: Partial<F>,
  ): AsyncResult<TrashBatch>;
  /** Restores the whole batch of a trash item. */
  restore(id: string): AsyncResult<TrashBatch>;
  /** Newest first, one entry per batch. */
  list(
    organizationId: string,
    options?: TrashListOptions,
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

  const client: Trash<F> = {
    trash: (organizationId, subjectType, subjectId, extra) =>
      fields.args(extra).andThen((checked) =>
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
    list: (organizationId, page = {}) =>
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
