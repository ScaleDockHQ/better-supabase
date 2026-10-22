import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** One column's change on one record. */
export interface FieldChange {
  /** Increases with every change; pass it as `before` for the next page. */
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The column name. */
  readonly field: string;
  /** The values as JSON: `null` for SQL null, a number for a numeric column. */
  readonly before: unknown;
  readonly after: unknown;
  /** `undefined` for a change the service role or a job made. */
  readonly changedBy: string | undefined;
  readonly changedAt: Temporal.Instant;
}

export interface FieldHistory {
  /**
   * A record's changes, newest first. Needs `history.read` and read access to
   * the record.
   */
  of(
    subject: { readonly type: string; readonly id: string },
    options?: {
      /** Only this column's changes. */
      readonly field?: string;
      /** The `id` of the last change of the previous page. */
      readonly before?: string;
      /** At most this many. Default: 50, at most 500. */
      readonly limit?: number;
    },
  ): AsyncResult<FieldChange[]>;
}

export interface FieldHistoryOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<FieldHistory>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function changeOf(row: Readonly<Record<string, unknown>>): FieldChange {
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    field: textOf(row["field"]),
    before: row["before"] ?? null,
    after: row["after"] ?? null,
    changedBy: optionalText(row["changedBy"]),
    changedAt: requiredInstant(row["changedAt"], "changedAt"),
  };
}

/**
 * The field-history block: the old and new value of chosen columns of any
 * registered record on every update, read per record.
 */
export function createFieldHistory(options: FieldHistoryOptions): FieldHistory {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: FieldHistory = {
    of: (subject, filter = {}) =>
      call(
        "field_history",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          field: filter.field ?? null,
          before: filter.before ?? null,
          max_count: filter.limit ?? null,
        },
        (value) => recordsOf(value, "field_history").map(changeOf),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "field-history",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
