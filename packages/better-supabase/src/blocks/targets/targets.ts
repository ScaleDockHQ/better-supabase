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
import { attrsArg, compact, plainDate } from "../sales-shared.ts";
import {
  bigintOf,
  applyTemporal,
  blockCall,
  type BlockOptions,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/**
 * A metric the database computes, or any other name the app keeps the actual
 * value of itself.
 */
export type TargetMetric =
  | "deals.won_amount"
  | "deals.won_count"
  | "work_items.completed"
  | "invoices.paid_amount"
  | (string & {});

/** A target. `F` types the extra columns the `fields` schema describes. */
export interface Target<F extends object = Record<never, never>> {
  readonly id: string;
  readonly name: string;
  readonly metric: TargetMetric;
  /** The member it is for; `undefined` for a team or the organization. */
  readonly ownerId?: string;
  readonly teamId?: string;
  readonly periodStart: Temporal.PlainDate;
  readonly periodEnd: Temporal.PlainDate;
  /** For amount metrics. */
  readonly currency?: string;
  /** Minor units for amounts, a count otherwise. */
  readonly goal: bigint;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface TargetProgress<
  F extends object = Record<never, never>,
> extends Target<F> {
  readonly progress: bigint;
  /** Progress over the goal: 0.5 is halfway. */
  readonly attainment: number;
}

export interface TargetInput<F extends object = Record<never, never>> {
  readonly id?: string;
  readonly name?: string;
  readonly metric?: TargetMetric;
  readonly ownerId?: string;
  readonly teamId?: string;
  readonly periodStart?: Temporal.PlainDate;
  readonly periodEnd?: Temporal.PlainDate;
  readonly currency?: string;
  readonly goal?: bigint;
  /** The value of a metric no block computes. */
  readonly actual?: bigint;
  readonly archived?: boolean;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface Targets<F extends object = Record<never, never>> {
  save(organizationId: string, target: TargetInput<F>): AsyncResult<Target<F>>;
  /** The targets running on `on` (today by default), with progress. */
  progress(
    organizationId: string,
    options?: { readonly on?: Temporal.PlainDate; readonly ownerId?: string },
  ): AsyncResult<TargetProgress<F>[]>;
}

export interface TargetsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the target's extra columns
   * (`blocks.targets.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `save`.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Targets<FieldsOf<S>>>>;
  readonly logger?: Logger;
}

function targetOf(value: unknown): Target {
  const row = recordOf(value, "target");

  return compact<Target>({
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    metric: textOf(row["metric"]),
    ownerId: optionalText(row["owner_user_id"]),
    teamId: optionalText(row["team_id"]),
    periodStart: plainDate(row["period_start"]) ?? plainDate("1970-01-01")!,
    periodEnd: plainDate(row["period_end"]) ?? plainDate("1970-01-01")!,
    currency: optionalText(row["currency"]),
    goal: bigintOf(row["goal"], "target goal"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  });
}

/**
 * The targets block: goals per period for a member, a team or the organization,
 * and their progress.
 */
export function createTargets<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: TargetsOptions<S>): Targets<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "target fields");

  const client: Targets<F> = {
    save: (organizationId, target) => {
      const { id, goal, actual, fields: extra, ...rest } = target;

      return fields
        .args(extra)
        .andThen((checked) =>
          call(
            "save_target",
            {
              tenant: organizationId,
              target: id ?? null,
              attrs: {
                ...attrsArg(rest),
                ...(goal === undefined ? {} : { goal: goal.toString() }),
                ...(actual === undefined ? {} : { actual: actual.toString() }),
                ...(checked === undefined ? {} : { fields: checked }),
              },
            },
            targetOf,
          ).andThen(fields.row),
        );
    },
    progress: (organizationId, progress = {}) =>
      call(
        "target_progress",
        {
          tenant: organizationId,
          on_date: progress.on === undefined ? null : progress.on.toString(),
          owner: progress.ownerId ?? null,
        },
        (value) =>
          recordsOf(value, "target_progress").map((row) => ({
            ...targetOf(row),
            progress: bigintOf(row["progress"], "target progress"),
            attainment: Number(row["attainment"] ?? 0),
          })),
      ).andThen(fields.rows),
  };

  return withBlockHooks(client, options.hooks, {
    block: "targets",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
