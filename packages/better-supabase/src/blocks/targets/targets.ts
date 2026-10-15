import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { attrsArg, big, compact, plainDate } from "../sales-shared.ts";
import {
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/**
 * A metric the database computes, or any other name the app keeps the
 * actual value of itself.
 */
export type TargetMetric =
  | "deals.won_amount"
  | "deals.won_count"
  | "work_items.completed"
  | "invoices.paid_amount"
  | (string & {});

export interface Target {
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
}

export interface TargetProgress extends Target {
  readonly progress: bigint;
  /** Progress over the goal: 0.5 is halfway. */
  readonly attainment: number;
}

export interface TargetInput {
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
}

export interface Targets {
  save(organizationId: string, target: TargetInput): AsyncResult<Target>;
  /** The targets running on `on` (today by default), with progress. */
  progress(
    organizationId: string,
    options?: { readonly on?: Temporal.PlainDate; readonly ownerId?: string },
  ): AsyncResult<TargetProgress[]>;
}

export interface TargetsOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Targets>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
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
    goal: big(row["goal"]),
  });
}

/**
 * The targets block: goals per period for a member, a team or the
 * organization, and their progress.
 */
export function createTargets(options: TargetsOptions): Targets {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Targets = {
    save: (organizationId, target) => {
      const { id, goal, actual, ...rest } = target;
      return call(
        "save_target",
        {
          tenant: organizationId,
          target: id ?? null,
          attrs: {
            ...attrsArg(rest),
            ...(goal === undefined ? {} : { goal: goal.toString() }),
            ...(actual === undefined ? {} : { actual: actual.toString() }),
          },
        },
        targetOf,
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
            progress: big(row["progress"]),
            attainment: Number(row["attainment"] ?? 0),
          })),
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "targets",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
