import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  APPRAISAL_ANONYMITY,
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

/** Who learns which peer wrote a review (`none`, `subject` or `all`). */
export type AppraisalAnonymity = (typeof APPRAISAL_ANONYMITY)[number];

/** One competency of a cycle's rubric. */
export interface AppraisalCompetencyDefinition {
  /** Lowercase letters, digits and underscores, starting with a letter. */
  readonly key: string;
  readonly name: string;
  /** Above 0, at most 1000. Default 1. */
  readonly weight?: number;
}

/** A competency of a cycle's rubric as stored. */
export interface AppraisalRubricCompetency {
  readonly key: string;
  readonly name: string;
  readonly weight: number;
}

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
  readonly anonymity: AppraisalAnonymity;
  /** Whether the appraised person reads the feedback once signed off. */
  readonly shareFeedback: boolean;
  /** The rubric; empty when the cycle rates one overall rating. */
  readonly competencies: readonly AppraisalRubricCompetency[];
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
  /** Default `subject`: peer reviewers stay hidden from the appraised person. */
  readonly anonymity?: AppraisalAnonymity;
  /** Default false. */
  readonly shareFeedback?: boolean;
  /** A rubric of weighted competencies, at most 20. */
  readonly competencies?: readonly AppraisalCompetencyDefinition[];
}

/** One person in a cycle and who reviews them. */
export interface AppraisalAssignment {
  readonly subjectUserId: string;
  readonly managerId?: string;
  readonly peerIds?: readonly string[];
}

/** One rating of a competency in a review. */
export interface AppraisalReviewRating {
  readonly competency: string;
  readonly rating: number;
  readonly comment?: string;
}

/** A competency's result on an appraisal. */
export interface AppraisalCompetencyResult extends AppraisalRubricCompetency {
  /** The average of the submitted ratings, a decimal string. */
  readonly average?: string;
  /** The rating a calibration set. */
  readonly calibrated?: number;
}

/** A review of one appraisal. */
export interface AppraisalReview {
  readonly id: string;
  /**
   * Unset for a peer review the caller may not attribute (see the cycle's
   * `anonymity`).
   */
  readonly reviewerId?: string;
  readonly kind: AppraisalReviewKind;
  /** 1 to 5; unset until the review is submitted. */
  readonly rating?: number;
  readonly comments?: string;
  readonly submissionId?: string;
  readonly submittedAt?: Temporal.Instant;
  /** The competency ratings of a rubric cycle. */
  readonly ratings: readonly AppraisalReviewRating[];
}

/** What `submitReview` takes: `rating` without a rubric, `ratings` with one. */
export interface AppraisalReviewInput {
  readonly rating?: number;
  readonly ratings?: readonly AppraisalReviewRating[];
  readonly comments?: string;
  readonly submissionId?: string;
}

/** A step of a calibration session. */
export interface AppraisalCalibration {
  readonly id: string;
  /** The rating before the step, a decimal string. */
  readonly fromRating?: string;
  readonly toRating: number;
  /** The competency ratings the step set, by key. */
  readonly competencyRatings: Readonly<Record<string, number>>;
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
  /** The cycle's rubric. */
  readonly rubric: readonly AppraisalRubricCompetency[];
  /**
   * Per competency results; for readers, and for the appraised person once a
   * sharing cycle is signed off.
   */
  readonly competencies: readonly AppraisalCompetencyResult[];
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
  openCycle(
    cycleId: string,
    assignments: readonly AppraisalAssignment[],
  ): AsyncResult<AppraisalCycle>;
  /** Closes a cycle once every appraisal in it is signed off. */
  closeCycle(cycleId: string): AsyncResult<AppraisalCycle>;
  listCycles(): AsyncResult<readonly AppraisalCycle[]>;
  /** Submits a review the caller was assigned; needs `appraisals.review`. */
  submitReview(
    reviewId: string,
    input: AppraisalReviewInput,
  ): AsyncResult<Appraisal>;
  /** Moves the rating of a reviewed appraisal and keeps the reason. */
  calibrate(
    appraisalId: string,
    rating: number,
    reason: string,
  ): AsyncResult<Appraisal>;
  /** Replaces the rubric of a draft cycle. */
  setCompetencies(
    cycleId: string,
    competencies: readonly AppraisalCompetencyDefinition[],
  ): AsyncResult<AppraisalCycle>;
  /**
   * Moves competency ratings of a reviewed appraisal; the calibrated rating
   * becomes the weighted rating of the result.
   */
  calibrateCompetencies(
    appraisalId: string,
    competencies: Readonly<Record<string, number>>,
    reason: string,
  ): AsyncResult<Appraisal>;
  /** Replaces the goals the appraisal looks back on. */
  setGoals(
    appraisalId: string,
    goalIds: readonly string[],
  ): AsyncResult<Appraisal>;
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

function rubricOf(value: unknown, fn: string): AppraisalRubricCompetency[] {
  return recordsOf(value ?? [], fn).map((item) => ({
    key: textOf(item["key"]),
    name: textOf(item["name"]),
    weight: Number(item["weight"]),
  }));
}

function ratingOf(value: unknown, fn: string): AppraisalReviewRating {
  const row = recordOf(value, fn);

  return {
    competency: textOf(row["competency"]),
    rating: Number(row["rating"]),
    ...optional("comment", optionalText(row["comment"])),
  };
}

function resultOf(value: unknown, fn: string): AppraisalCompetencyResult {
  const row = recordOf(value, fn);

  return {
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    weight: Number(row["weight"]),
    ...optional("average", optionalText(row["average"])),
    ...optional("calibrated", numberOf(row["calibrated"])),
  };
}

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
    anonymity: enumOrThrow(
      row["anonymity"],
      APPRAISAL_ANONYMITY,
      "cycle anonymity",
    ),
    shareFeedback: row["shareFeedback"] === true,
    competencies: rubricOf(row["competencies"], fn),
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
    kind: enumOrThrow(row["kind"], APPRAISAL_REVIEW_KINDS, "review kind"),
    ratings: recordsOf(row["ratings"] ?? [], fn).map((item) =>
      ratingOf(item, fn),
    ),
    ...optional("reviewerId", optionalText(row["reviewerId"])),
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
    competencyRatings: Object.fromEntries(
      Object.entries(recordOf(row["competencyRatings"] ?? {}, fn)).map(
        ([key, rating]) => [key, Number(rating)],
      ),
    ),
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
    rubric: rubricOf(row["rubric"], fn),
    competencies: recordsOf(row["competencies"] ?? [], fn).map((item) =>
      resultOf(item, fn),
    ),
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
          {
            tenant: organizationId,
            input: {
              ...definedOf(input),
              ...(input.competencies === undefined
                ? {}
                : {
                    competencies: input.competencies.map((item) =>
                      definedOf(item),
                    ),
                  }),
            },
          },
          cycle("create_appraisal_cycle"),
        ),
      ),
    openCycle: (cycleId, assignments) =>
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
    submitReview: (reviewId, input) =>
      call(
        "submit_appraisal_review",
        {
          review_id: reviewId,
          input: {
            ...definedOf(input),
            ...(input.ratings === undefined
              ? {}
              : { ratings: input.ratings.map((item) => definedOf(item)) }),
          },
        },
        appraisal("submit_appraisal_review"),
      ),
    calibrate: (appraisalId, rating, reason) =>
      call(
        "calibrate_appraisal",
        { appraisal_id: appraisalId, rating, reason },
        appraisal("calibrate_appraisal"),
      ),
    setCompetencies: (cycleId, competencies) =>
      call(
        "set_appraisal_competencies",
        {
          cycle_id: cycleId,
          competencies: competencies.map((item) => definedOf(item)),
        },
        cycle("set_appraisal_competencies"),
      ),
    calibrateCompetencies: (appraisalId, competencies, reason) =>
      call(
        "calibrate_appraisal_competencies",
        { appraisal_id: appraisalId, competencies, reason },
        appraisal("calibrate_appraisal_competencies"),
      ),
    setGoals: (appraisalId, goalIds) =>
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
