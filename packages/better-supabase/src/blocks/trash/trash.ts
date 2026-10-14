import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface TrashOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /** `sql.modules.trash.schema`, or the API schema of its wrappers. */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Trash>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
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
export interface TrashItem extends TrashBatch {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title?: string;
  readonly trashedBy?: string;
  readonly trashedAt: Temporal.Instant;
  /** When `purge_expired_trash` deletes it; absent when retention is off. */
  readonly purgeAfter?: Temporal.Instant;
}

export interface TrashListOptions {
  readonly subjectType?: string;
  readonly pageSize?: number;
  /** Items trashed before this time, for the next page. */
  readonly before?: Temporal.Instant;
}

export interface Trash {
  /** Trashes the subject and its children in one batch. */
  trash(
    organizationId: string,
    subjectType: string,
    subjectId: string,
  ): AsyncResult<TrashBatch>;
  /** Restores the whole batch of a trash item. */
  restore(id: string): AsyncResult<TrashBatch>;
  /** Newest first, one entry per batch. */
  list(
    organizationId: string,
    options?: TrashListOptions,
  ): AsyncResult<readonly TrashItem[]>;
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
    ...(title === undefined ? {} : { title }),
    ...(trashedBy === undefined ? {} : { trashedBy }),
    ...(row["purgeAfter"] === null || row["purgeAfter"] === undefined
      ? {}
      : { purgeAfter: requiredInstant(row["purgeAfter"], "purgeAfter") }),
  };
}

/** The `trash` SQL module as typed calls. */
export function createTrash(options: TrashOptions): Trash {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Trash = {
    trash: (organizationId, subjectType, subjectId) =>
      call(
        "trash",
        {
          tenant: organizationId,
          subject_type: subjectType,
          subject_id: subjectId,
        },
        (value) => batchOf(value, "trash"),
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
      ),
    purge: (id) => call("purge_trash", { item_id: id }, Number),
  };
  return withBlockHooks(client, options.hooks, {
    block: "trash",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
