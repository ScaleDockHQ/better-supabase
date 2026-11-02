import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { Assignment } from "../assignment/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { TargetProgress } from "../goals/index.ts";
import type { Sales } from "../sales/index.ts";
import type { SegmentMembership } from "../segments/index.ts";
import type { CrmParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { createDealClosers } from "../sales/index.ts";

/** What `crm.route` returns. */
export interface RoutedLead {
  /** The segments the record is in, which the queues' territories can match. */
  readonly segments: readonly SegmentMembership[];
  /** The owner the queues picked, or `undefined` when no queue matched. */
  readonly assignment: Assignment | undefined;
}

/** The progress of the targets that share one metric. */
export interface MetricAttainment {
  readonly metric: string;
  readonly progress: bigint;
  readonly goal: bigint;
  /** Progress over goal: 0.5 is halfway. 0 when the goals add up to 0. */
  readonly attainment: number;
}

/** What `crm.attainment` returns. */
export interface Attainment {
  readonly targets: readonly TargetProgress[];
  /** The sums per metric, so amounts and counts never mix. */
  readonly byMetric: readonly MetricAttainment[];
  /** How much of the day's period has passed, from 0 to 1. */
  readonly pace: number;
  /** The targets whose attainment is below `pace`. */
  readonly behind: readonly TargetProgress[];
}

/** What `crm.attainment` reads. */
export interface AttainmentInput {
  organizationId: string;
  /** The day to measure on. Default: today. */
  on?: Temporal.PlainDate | undefined;
  /** One member's targets only. */
  ownerId?: string | undefined;
}

/**
 * The helpers `crm` adds over its parts: the ones `sales` shares for closing
 * deals, `route` and `attainment`.
 */
export interface Crm extends Pick<Sales, "closeWon" | "closeLost"> {
  /**
   * Picks an owner for a record. It reads the segments the record is in
   * (`segments.of`), then runs the assignment queues (`assignment.assign`) with
   * the segment names under the `segments` field, so a queue territory can
   * match `segments` for a segment. Writing the owner onto the record is up to
   * the app, as with `assignment.assign`.
   */
  route(input: {
    organizationId: string;
    subject: { readonly type: string; readonly id: string };
    /** More fields for the territories, merged over the segment names. */
    fields?: Readonly<Record<string, unknown>> | undefined;
  }): AsyncResult<RoutedLead>;
  /**
   * How the running targets stand (`goals.progress`): per target, summed per
   * metric, and which ones are behind the share of the period that has passed.
   */
  attainment(input: AttainmentInput): AsyncResult<Attainment>;
}

const fraction = (progress: bigint, goal: bigint): number =>
  goal === 0n ? 0 : Number((progress * 10_000n) / goal) / 10_000;

/** The share of `[start, end]` (both days included) that has passed on `on`. */
function periodPace(
  starts: Temporal.PlainDate,
  ends: Temporal.PlainDate,
  on: Temporal.PlainDate,
): number {
  const total = starts.until(ends, { largestUnit: "days" }).days + 1;
  const passed = starts.until(on, { largestUnit: "days" }).days + 1;

  return Math.min(1, Math.max(0, passed / total));
}

/** Sums targets per metric and finds the ones behind the period's pace. */
function summarizeAttainment(
  targets: readonly TargetProgress[],
  on: Temporal.PlainDate,
): Attainment {
  const sums = new Map<string, { progress: bigint; goal: bigint }>();

  for (const target of targets) {
    const sum = sums.get(target.metric) ?? { progress: 0n, goal: 0n };

    sums.set(target.metric, {
      progress: sum.progress + target.progress,
      goal: sum.goal + target.goal,
    });
  }

  const byMetric = [...sums].map(([metric, { progress, goal }]) => ({
    metric,
    progress,
    goal,
    attainment: fraction(progress, goal),
  }));

  const pace =
    targets.length === 0
      ? 0
      : Math.max(
          ...targets.map((t) => periodPace(t.periodStart, t.periodEnd, on)),
        );

  const behind = targets.filter(
    (t) => t.attainment < periodPace(t.periodStart, t.periodEnd, on),
  );

  return { targets, byMetric, pace, behind };
}

/** What the `crm` creator receives. */
export type CrmOptions = BlockContext &
  CompositeOptions<CrmParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Crm>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `crm` helpers over the clients of its parts. */
export function createCrm(options: CrmOptions): Crm {
  const { deals, quotes, segments, assignment, goals } = options.parts;

  const client: Crm = {
    ...createDealClosers({ deals, quotes }),

    route: ({ organizationId, subject, fields }) =>
      Async.from(async () => {
        const member = await segments.of({
          type: subject.type,
          id: subject.id,
        });

        if (!member.ok) {
          return member;
        }

        const picked = await assignment.assign({
          organizationId,
          subject: {
            ...subject,
            fields: {
              segments: member.data.map((entry) => entry.name),
              ...fields,
            },
          },
        });

        return picked.ok
          ? ok({ segments: member.data, assignment: picked.data })
          : picked;
      }),

    attainment: ({ organizationId, on, ownerId }) =>
      Async.from(async () => {
        const day = on ?? temporal().Now.plainDateISO();

        const progress = await goals.progress({
          organizationId,
          on: day,
          ...(ownerId === undefined ? {} : { ownerId }),
        });

        return progress.ok
          ? ok(summarizeAttainment(progress.data, day))
          : progress;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "crm",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
