import type {
  CarePlan,
  CarePlanAction,
  CarePlanActionKind,
  CarePlanActionStatus,
  CarePlanGoal,
  CarePlanGoalStatus,
  CarePlanProblem,
  CarePlanStatus,
} from "../blocks/care-plans/care-plans.ts";
import type { FhirSubjectOptions } from "./shared.ts";
import type {
  FhirCarePlan,
  FhirCarePlanActivity,
  FhirCarePlanActivityDetail,
  FhirCarePlanActivityStatus,
  FhirCarePlanStatus,
  FhirCodeableConcept,
  FhirCoding,
  FhirCondition,
  FhirGoal,
  FhirGoalLifecycleStatus,
  FhirGoalTarget,
  FhirPeriod,
  FhirQuantity,
  FhirReference,
  FhirTimingRepeat,
} from "./types.ts";

import {
  compact,
  fhirTime,
  isObject,
  nonEmpty,
  notes,
  subjectOf,
  text,
  userOf,
} from "./shared.ts";

const ACHIEVEMENT = "http://terminology.hl7.org/CodeSystem/goal-achievement";
const CLINICAL = "http://terminology.hl7.org/CodeSystem/condition-clinical";

/** The action fields the care plan mappers read. */
export type FhirCarePlanActionSource = Pick<
  CarePlanAction,
  "id" | "goalId" | "kind" | "title" | "status"
> &
  Partial<
    Pick<
      CarePlanAction,
      "instructions" | "frequency" | "startsOn" | "endsOn" | "endReason"
    >
  >;

/** The goal fields the care plan mappers read. */
export type FhirGoalSource = Pick<
  CarePlanGoal,
  "id" | "problemId" | "title" | "status"
> &
  Partial<Pick<CarePlanGoal, "targetOn" | "measure">>;

/** The problem fields `toFhirCarePlan` reads. */
export type FhirCarePlanProblemSource = Pick<
  CarePlanProblem,
  "id" | "codeSystem" | "title" | "status"
> &
  Partial<Pick<CarePlanProblem, "code" | "description">> & {
    readonly goals: readonly (FhirGoalSource & {
      readonly actions: readonly FhirCarePlanActionSource[];
    })[];
  };

/** The plan fields `toFhirCarePlan` reads: a plan from `db.carePlans.get`. */
export type FhirCarePlanSource = Pick<
  CarePlan,
  "id" | "subjectId" | "title" | "status" | "createdAt"
> &
  Partial<Pick<CarePlan, "startsOn" | "ownerId">> & {
    readonly problems: readonly FhirCarePlanProblemSource[];
  };

export interface FhirCarePlanOptions extends FhirSubjectOptions {
  /**
   * The URI of each of the block's `codeSystems`, such as `{ icf:
   * "http://hl7.org/fhir/sid/icf-nl" }`. A problem code without one carries no
   * system.
   */
  readonly codeSystems?: Readonly<Record<string, string>>;
}

export interface FhirGoalOptions extends FhirSubjectOptions {
  /** The problem the goal addresses. Default `Condition/<problemId>`. */
  readonly addresses?: FhirReference;
}

function planStatusOf(status: CarePlanStatus): FhirCarePlanStatus {
  switch (status) {
    case "draft": {
      return "draft";
    }

    case "active": {
      return "active";
    }

    case "archived": {
      return "completed";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function lifecycleOf(status: CarePlanGoalStatus): {
  readonly lifecycle: FhirGoalLifecycleStatus;
  readonly achievement?: string;
} {
  switch (status) {
    case "planned": {
      return { lifecycle: "planned" };
    }

    case "in_progress": {
      return { lifecycle: "active", achievement: "in-progress" };
    }

    case "achieved": {
      return { lifecycle: "completed", achievement: "achieved" };
    }

    case "not_achieved": {
      return { lifecycle: "completed", achievement: "not-achieved" };
    }

    case "canceled": {
      return { lifecycle: "cancelled" };
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function activityStatusOf(
  status: CarePlanActionStatus,
): FhirCarePlanActivityStatus {
  switch (status) {
    case "planned": {
      return "not-started";
    }

    case "active": {
      return "in-progress";
    }

    case "ended": {
      return "completed";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function activityKindOf(
  kind: CarePlanActionKind,
): FhirCarePlanActivityDetail["kind"] {
  switch (kind) {
    case "appointment": {
      return "Appointment";
    }

    case "task": {
      return "Task";
    }

    case "intervention":
    case "measure": {
      return undefined;
    }

    default: {
      const never: never = kind;

      return never;
    }
  }
}

/**
 * A goal's `measure` JSON as a target: `code` (and `system`) for the measure,
 * `target` for the detail, `unit` for a numeric target's unit.
 */
function targetOf(goal: FhirGoalSource): FhirGoalTarget[] | undefined {
  const measure = isObject(goal.measure) ? goal.measure : {};
  const { code, system, target, unit } = measure;

  const entry = compact<FhirGoalTarget>({
    measure:
      typeof code === "string"
        ? {
            coding: [
              compact<FhirCoding>({
                system: typeof system === "string" ? system : undefined,
                code,
              }),
            ],
          }
        : undefined,
    detailQuantity:
      typeof target === "number"
        ? compact<FhirQuantity>({
            value: target,
            unit: typeof unit === "string" ? unit : undefined,
          })
        : undefined,
    detailString: typeof target === "string" ? target : undefined,
    detailBoolean: typeof target === "boolean" ? target : undefined,
    dueDate: fhirTime(goal.targetOn),
  });

  return Object.keys(entry).length === 0 ? undefined : [entry];
}

function goalOf(
  goal: FhirGoalSource,
  subject: FhirReference,
  addresses: FhirReference,
): FhirGoal {
  const { lifecycle, achievement } = lifecycleOf(goal.status);

  return compact<FhirGoal>({
    resourceType: "Goal",
    id: goal.id,
    lifecycleStatus: lifecycle,
    achievementStatus:
      achievement === undefined
        ? undefined
        : { coding: [{ system: ACHIEVEMENT, code: achievement }] },
    description: { text: goal.title },
    subject,
    target: targetOf(goal),
    addresses: [addresses],
  });
}

/**
 * A care plan goal as a FHIR R4 `Goal` of the record. Goal statuses map to a
 * lifecycle status and, once worked on, an achievement status.
 */
export function toFhirGoal(
  goal: FhirGoalSource,
  subjectId: string,
  options?: FhirGoalOptions,
): FhirGoal {
  return goalOf(
    goal,
    subjectOf(options, subjectId),
    options?.addresses ?? { reference: `Condition/${goal.problemId}` },
  );
}

function conditionOf(
  problem: FhirCarePlanProblemSource,
  subject: FhirReference,
  options: FhirCarePlanOptions | undefined,
): FhirCondition {
  const code: FhirCodeableConcept =
    problem.code === undefined
      ? { text: problem.title }
      : {
          coding: [
            compact<FhirCoding>({
              system: options?.codeSystems?.[problem.codeSystem],
              code: problem.code,
              display: problem.title,
            }),
          ],
          text: problem.title,
        };

  return compact<FhirCondition>({
    resourceType: "Condition",
    id: problem.id,
    clinicalStatus: { coding: [{ system: CLINICAL, code: problem.status }] },
    code,
    subject,
    note: notes(problem.description),
  });
}

function activityOf(action: FhirCarePlanActionSource): FhirCarePlanActivity {
  const period = compact<FhirPeriod>({
    start: fhirTime(action.startsOn),
    end: fhirTime(action.endsOn),
  });

  const bounded = Object.keys(period).length > 0;

  return {
    detail: compact<FhirCarePlanActivityDetail>({
      kind: activityKindOf(action.kind),
      code: { text: action.title },
      goal: [{ reference: `#${action.goalId}` }],
      status: activityStatusOf(action.status),
      statusReason: text(action.endReason),
      scheduledTiming:
        action.frequency === undefined
          ? undefined
          : {
              repeat: compact<FhirTimingRepeat>({
                ...action.frequency,
                boundsPeriod: bounded ? period : undefined,
              }),
            },
      scheduledPeriod:
        action.frequency === undefined && bounded ? period : undefined,
      description: action.instructions,
    }),
  };
}

/**
 * A care plan with its tree (`db.carePlans.get`) as a FHIR R4 `CarePlan`.
 * Problems become contained `Condition`s it addresses, goals contained `Goal`s,
 * and actions activities that point at their goal. Evaluations are left out:
 * each goal's achievement status carries the latest outcome.
 */
export function toFhirCarePlan(
  plan: FhirCarePlanSource,
  options?: FhirCarePlanOptions,
): FhirCarePlan {
  const subject = subjectOf(options, plan.subjectId);
  const goals = plan.problems.flatMap((problem) => problem.goals);

  return compact<FhirCarePlan>({
    resourceType: "CarePlan",
    id: plan.id,
    contained: nonEmpty([
      ...plan.problems.map((problem) => conditionOf(problem, subject, options)),
      ...goals.map((goal) =>
        goalOf(goal, subject, { reference: `#${goal.problemId}` }),
      ),
    ]),
    status: planStatusOf(plan.status),
    intent: "plan",
    title: plan.title,
    subject,
    period:
      plan.startsOn === undefined
        ? undefined
        : compact<FhirPeriod>({ start: fhirTime(plan.startsOn) }),
    created: fhirTime(plan.createdAt),
    author: userOf(options, plan.ownerId),
    addresses: nonEmpty(
      plan.problems.map((problem) => ({ reference: `#${problem.id}` })),
    ),
    goal: nonEmpty(goals.map((goal) => ({ reference: `#${goal.id}` }))),
    activity: nonEmpty(goals.flatMap((goal) => goal.actions.map(activityOf))),
  });
}
