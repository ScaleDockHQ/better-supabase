import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  APPRAISAL_CYCLE_STATUSES,
  APPRAISAL_REVIEW_KINDS,
  APPRAISAL_STATUSES,
} from "../../sql/modules/appraisals-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a review cycle stands. */
export type AppraisalCycleStatus = (typeof APPRAISAL_CYCLE_STATUSES)[number];

/** Where one person's appraisal stands. */
export type AppraisalStatus = (typeof APPRAISAL_STATUSES)[number];

/** Who writes a review. */
export type AppraisalReviewKind = (typeof APPRAISAL_REVIEW_KINDS)[number];

/** A review cycle. */
export interface AppraisalCycle {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  /** A date, `YYYY-MM-DD`. */
  readonly startsOn: string;
  readonly endsOn: string;
  /** The key of the enrollment program the appraisals follow. */
  readonly program?: string;
  readonly status: AppraisalCycleStatus;
  readonly openedAt?: Temporal.Instant;
  readonly closedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  /** How many appraisals `openCycle` created; only on its result. */
  readonly appraisalsCreated?: number;
}

/** What `createCycle` takes. */
export interface AppraisalCycleInput {
  readonly name: string;
  readonly startsOn: string;
  readonly endsOn: string;
  readonly program?: string;
}

/** One person in a cycle and who reviews them. */
export interface AppraisalAssignment {
  readonly subjectUserId: string;
  readonly managerId?: string;
  readonly peerIds?: readonly string[];
}

/** A review of one appraisal. */
export interface AppraisalReview {
  readonly id: string;
  readonly reviewerId: string;
  readonly kind: AppraisalReviewKind;
  /** 1 to 5; unset until the review is submitted. */
  readonly rating?: number;
  readonly comments?: string;
  readonly submissionId?: string;
  readonly submittedAt?: Temporal.Instant;
}

/** What `submitReview` takes. */
export interface AppraisalReviewInput {
  readonly rating: number;
  readonly comments?: string;
  readonly submissionId?: string;
}

/** A step of a calibration session. */
export interface AppraisalCalibration {
  readonly id: string;
  /** The rating before the step, a decimal string. */
  readonly fromRating?: string;
  readonly toRating: number;
  readonly reason: string;
  readonly calibratedBy?: string;
  readonly calibratedAt: Temporal.Instant;
}

/** One person's appraisal in a cycle. */
export interface Appraisal {
  readonly id: string;
  readonly organizationId: string;
  readonly cycleId: string;
  readonly subjectUserId: string;
  readonly managerId?: string;
  readonly status: AppraisalStatus;
  /** The average of the submitted reviews, a decimal string. */
  readonly rating?: string;
  /** The rating a calibration set. */
  readonly calibratedRating?: number;
  /** The approvals request that signs the appraisal off. */
  readonly approvalId?: string;
  readonly signedOffAt?: Temporal.Instant;
  readonly signedOffBy?: string;
  /** Everyone's reviews for readers; the caller's own for everyone else. */
  readonly reviews: readonly AppraisalReview[];
  /** Only for readers. */
  readonly calibrations: readonly AppraisalCalibration[];
  readonly goalIds: readonly string[];
  readonly createdAt: Temporal.Instant;
}

/** Filters for `listAppraisals`. */
export interface AppraisalListOptions {
  readonly cycleId?: string;
  readonly status?: AppraisalStatus;
  readonly subjectUserId?: string;
  /** Only the appraisals the caller is the subject or a reviewer of. */
  readonly mine?: boolean;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface Appraisals {
  /** Creates a draft cycle; needs `appraisals.manage`. */
  createCycle(input: AppraisalCycleInput): AsyncResult<AppraisalCycle>;
  /**
   * Opens a cycle and creates the appraisals and review slots for the people
   * you assign. Call it again to add people to an open cycle.
   */
  openCycle(input: {
    cycleId: string;
    assignments: readonly AppraisalAssignment[];
  }): AsyncResult<AppraisalCycle>;
  /** Closes a cycle once every appraisal in it is signed off. */
  closeCycle(cycleId: string): AsyncResult<AppraisalCycle>;
  listCycles(): AsyncResult<readonly AppraisalCycle[]>;
  /** Submits a review the caller was assigned; needs `appraisals.review`. */
  submitReview(input: {
    reviewId: string;
    input: AppraisalReviewInput;
  }): AsyncResult<Appraisal>;
  /** Moves the rating of a reviewed appraisal and keeps the reason. */
  calibrate(input: {
    appraisalId: string;
    rating: number;
    reason: string;
  }): AsyncResult<Appraisal>;
  /** Replaces the goals the appraisal looks back on. */
  setGoals(input: {
    appraisalId: string;
    goalIds: readonly string[];
  }): AsyncResult<Appraisal>;
  /**
   * Signs an appraisal off. With the approvals block it files the sign-off and
   * the appraisal waits as `awaiting_signoff` until it is approved.
   */
  signOff(appraisalId: string): AsyncResult<Appraisal>;
  getAppraisal(appraisalId: string): AsyncResult<Appraisal>;
  listAppraisals(
    options?: AppraisalListOptions,
  ): AsyncResult<readonly Appraisal[]>;
}

/** Options for {@link createAppraisals}. */
export interface AppraisalsOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Appraisals>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

function cycleOf(value: unknown, fn: string): AppraisalCycle {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    startsOn: textOf(row["startsOn"]),
    endsOn: textOf(row["endsOn"]),
    status: enumOrThrow(
      row["status"],
      APPRAISAL_CYCLE_STATUSES,
      "cycle status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("program", optionalText(row["program"])),
    ...optional("openedAt", optionalInstant(row["openedAt"])),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("appraisalsCreated", numberOf(row["appraisalsCreated"])),
  };
}

function reviewOf(value: unknown, fn: string): AppraisalReview {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    reviewerId: textOf(row["reviewerId"]),
    kind: enumOrThrow(row["kind"], APPRAISAL_REVIEW_KINDS, "review kind"),
    ...optional("rating", numberOf(row["rating"])),
    ...optional("comments", optionalText(row["comments"])),
    ...optional("submissionId", optionalText(row["submissionId"])),
    ...optional("submittedAt", optionalInstant(row["submittedAt"])),
  };
}

function calibrationOf(value: unknown, fn: string): AppraisalCalibration {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    toRating: Number(row["toRating"]),
    reason: textOf(row["reason"]),
    calibratedAt: requiredInstant(row["calibratedAt"], "calibratedAt"),
    ...optional("fromRating", optionalText(row["fromRating"])),
    ...optional("calibratedBy", optionalText(row["calibratedBy"])),
  };
}

function appraisalOf(value: unknown, fn: string): Appraisal {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    cycleId: textOf(row["cycleId"]),
    subjectUserId: textOf(row["subjectUserId"]),
    status: enumOrThrow(row["status"], APPRAISAL_STATUSES, "appraisal status"),
    reviews: recordsOf(row["reviews"] ?? [], fn).map((item) =>
      reviewOf(item, fn),
    ),
    calibrations: recordsOf(row["calibrations"] ?? [], fn).map((item) =>
      calibrationOf(item, fn),
    ),
    goalIds: Array.isArray(row["goalIds"]) ? row["goalIds"].map(textOf) : [],
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("managerId", optionalText(row["managerId"])),
    ...optional("rating", optionalText(row["rating"])),
    ...optional("calibratedRating", numberOf(row["calibratedRating"])),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional("signedOffAt", optionalInstant(row["signedOffAt"])),
    ...optional("signedOffBy", optionalText(row["signedOffBy"])),
  };
}

/**
 * Appraisals: review cycles, self, peer and manager reviews, calibration and
 * sign-off through approvals.
 */
export function createAppraisals(options: AppraisalsOptions): Appraisals {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const cycle = (fn: string) => (value: unknown) => cycleOf(value, fn);
  const appraisal = (fn: string) => (value: unknown) => appraisalOf(value, fn);

  const client: Appraisals = {
    createCycle: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_appraisal_cycle",
          { tenant: organizationId, input: definedOf(input) },
          cycle("create_appraisal_cycle"),
        ),
      ),
    openCycle: ({ cycleId, assignments }) =>
      call(
        "open_appraisal_cycle",
        {
          cycle_id: cycleId,
          assignments: assignments.map((item) => definedOf(item)),
        },
        cycle("open_appraisal_cycle"),
      ),
    closeCycle: (cycleId) =>
      call(
        "close_appraisal_cycle",
        { cycle_id: cycleId },
        cycle("close_appraisal_cycle"),
      ),
    listCycles: () =>
      tenant().andThen((organizationId) =>
        call("list_appraisal_cycles", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_appraisal_cycles").map((row) =>
            cycleOf(row, "list_appraisal_cycles"),
          ),
        ),
      ),
    submitReview: ({ reviewId, input }) =>
      call(
        "submit_appraisal_review",
        { review_id: reviewId, input: definedOf(input) },
        appraisal("submit_appraisal_review"),
      ),
    calibrate: ({ appraisalId, rating, reason }) =>
      call(
        "calibrate_appraisal",
        { appraisal_id: appraisalId, rating, reason },
        appraisal("calibrate_appraisal"),
      ),
    setGoals: ({ appraisalId, goalIds }) =>
      call(
        "set_appraisal_goals",
        { appraisal_id: appraisalId, goal_ids: [...goalIds] },
        appraisal("set_appraisal_goals"),
      ),
    signOff: (appraisalId) =>
      call(
        "sign_off_appraisal",
        { appraisal_id: appraisalId },
        appraisal("sign_off_appraisal"),
      ),
    getAppraisal: (appraisalId) =>
      call(
        "get_appraisal",
        { appraisal_id: appraisalId },
        appraisal("get_appraisal"),
      ),
    listAppraisals: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_appraisals",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_appraisals").map((row) =>
              appraisalOf(row, "list_appraisals"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "appraisals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
