import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `care_plan.*` event carries. */
export interface CarePlanEventData {
  readonly organizationId: string;
  /** The plan. */
  readonly id: string;
  /** The client the plan is for, any registered subject. */
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string;
  /** Its status after the change. */
  readonly status: string;
  /** 1 for the client's first plan, one more for each plan after it. */
  readonly version: number;
}

/** `care_plan.published`: the plan is the client's active plan. */
export interface CarePlanPublishedEventData extends CarePlanEventData {
  /** The plan it replaced, archived. */
  readonly previousPlanId: string | null;
  /** The versions snapshot of the published plan. */
  readonly versionId: string | null;
}

/** `care_plan.agreed`: the agreement request completed. */
export interface CarePlanAgreedEventData extends CarePlanEventData {
  readonly signatureRequestId: string;
}

/** `care_plan.review_date_reached`: the plan's review date has come. */
export interface CarePlanReviewDateReachedEventData extends CarePlanEventData {
  readonly ownerId: string | null;
  /** `YYYY-MM-DD`. */
  readonly reviewOn: string;
}

/** What the events of a plan's goals, evaluations and actions carry. */
export interface CarePlanChildEventData {
  readonly organizationId: string;
  readonly planId: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

/** `care_plan_goal.status_changed`. */
export interface CarePlanGoalStatusChangedEventData extends CarePlanChildEventData {
  readonly goalId: string;
  readonly title: string;
  readonly status: string;
  readonly previousStatus: string;
}

/** `care_plan_evaluation.created`. */
export interface CarePlanEvaluationCreatedEventData extends CarePlanChildEventData {
  readonly evaluationId: string;
  readonly goalId: string;
  /** The goal status the evaluation found. */
  readonly status: string;
}

/** What every `care_plan_action.*` event carries. */
export interface CarePlanActionEventData extends CarePlanChildEventData {
  readonly actionId: string;
  /** `intervention`, `appointment`, `task` or `measure`. */
  readonly kind: string;
  readonly title: string;
}

/** `care_plan_action.ended`. */
export interface CarePlanActionEndedEventData extends CarePlanActionEventData {
  readonly reason: string | null;
}

/** `care_plan_action.reviewed`. */
export interface CarePlanActionReviewedEventData extends CarePlanActionEventData {
  readonly note: string | null;
}

/**
 * `care_plan_action.review_date_reached`: the action's review interval has
 * lapsed.
 */
export interface CarePlanActionReviewDateReachedEventData extends CarePlanActionEventData {
  /** The plan's owner. */
  readonly ownerId: string | null;
  /** When the review fell due, an ISO timestamp. */
  readonly dueAt: string;
}

/** The events of the `care-plans` block: type to data. */
export type CarePlansEvents = {
  readonly "care_plan.created": CarePlanEventData;
  readonly "care_plan.updated": CarePlanEventData;
  readonly "care_plan.published": CarePlanPublishedEventData;
  readonly "care_plan.archived": CarePlanEventData;
  readonly "care_plan.agreed": CarePlanAgreedEventData;
  readonly "care_plan.review_date_reached": CarePlanReviewDateReachedEventData;
  readonly "care_plan_goal.status_changed": CarePlanGoalStatusChangedEventData;
  readonly "care_plan_evaluation.created": CarePlanEvaluationCreatedEventData;
  readonly "care_plan_action.started": CarePlanActionEventData;
  readonly "care_plan_action.ended": CarePlanActionEndedEventData;
  readonly "care_plan_action.review_date_reached": CarePlanActionReviewDateReachedEventData;
  readonly "care_plan_action.reviewed": CarePlanActionReviewedEventData;
};

/** The `care-plans` block's event types, for its manifest and `onBlockEvent`. */
export const carePlansEvents: Events<CarePlansEvents> = defineEvents({
  "care_plan.created": event<CarePlanEventData>(),
  "care_plan.updated": event<CarePlanEventData>(),
  "care_plan.published": event<CarePlanPublishedEventData>(),
  "care_plan.archived": event<CarePlanEventData>(),
  "care_plan.agreed": event<CarePlanAgreedEventData>(),
  "care_plan.review_date_reached": event<CarePlanReviewDateReachedEventData>(),
  "care_plan_goal.status_changed": event<CarePlanGoalStatusChangedEventData>(),
  "care_plan_evaluation.created": event<CarePlanEvaluationCreatedEventData>(),
  "care_plan_action.started": event<CarePlanActionEventData>(),
  "care_plan_action.ended": event<CarePlanActionEndedEventData>(),
  "care_plan_action.review_date_reached":
    event<CarePlanActionReviewDateReachedEventData>(),
  "care_plan_action.reviewed": event<CarePlanActionReviewedEventData>(),
});
