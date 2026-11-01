import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  CARE_PLAN_ACTION_KINDS,
  CARE_PLAN_ACTION_STATUSES,
  CARE_PLAN_GOAL_STATUSES,
  CARE_PLAN_PROBLEM_STATUSES,
  CARE_PLAN_STATUSES,
} from "../../sql/modules/care-plans-sql.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a plan stands: `draft`, then `active`, then `archived`. */
export type CarePlanStatus = (typeof CARE_PLAN_STATUSES)[number];

/** `active` or `resolved`. */
export type CarePlanProblemStatus = (typeof CARE_PLAN_PROBLEM_STATUSES)[number];

/** `planned`, `in_progress`, `achieved`, `not_achieved` or `canceled`. */
export type CarePlanGoalStatus = (typeof CARE_PLAN_GOAL_STATUSES)[number];

/**
 * What an action is. A `task` creates a work item when it starts (tasks block);
 * a `measure` is a restrictive measure that starts only once approved.
 */
export type CarePlanActionKind = (typeof CARE_PLAN_ACTION_KINDS)[number];

/** `planned` until it starts, `active`, then `ended`. */
export type CarePlanActionStatus = (typeof CARE_PLAN_ACTION_STATUSES)[number];

/** JSON the app shapes, such as a FHIR Timing `repeat` or a goal target. */
export type CarePlanJson = Readonly<Record<string, unknown>>;

export interface CarePlanAction {
  readonly id: string;
  readonly planId: string;
  readonly goalId: string;
  readonly kind: CarePlanActionKind;
  readonly title: string;
  readonly status: CarePlanActionStatus;
  readonly requiresApproval: boolean;
  /** The order within its goal. */
  readonly rank: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly instructions?: string;
  /**
   * How often it happens, such as `{ "frequency": 2, "period": 1, "periodUnit":
   * "d" }`.
   */
  readonly frequency?: CarePlanJson;
  /** The team role that carries it out, such as `nurse`. */
  readonly teamRole?: string;
  /** For a measure: one of `options.measureKinds`. */
  readonly measureKind?: string;
  /** The work item it created (tasks block). */
  readonly taskId?: string;
  /** The recurring booking it runs as (bookings block). */
  readonly bookingSeriesId?: string;
  /** The approval request it waits for or started on (approvals block). */
  readonly approvalId?: string;
  /** How often it is reviewed while active. */
  readonly reviewEvery?: Temporal.Duration;
  readonly reviewedAt?: Temporal.Instant;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly startedAt?: Temporal.Instant;
  readonly endedAt?: Temporal.Instant;
  readonly endReason?: string;
}

export interface CarePlanGoal {
  readonly id: string;
  readonly planId: string;
  readonly problemId: string;
  readonly title: string;
  readonly status: CarePlanGoalStatus;
  readonly rank: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly targetOn?: Temporal.PlainDate;
  /** What counts as reaching it, such as `{ "code": "...", "target": 3 }`. */
  readonly measure?: CarePlanJson;
  /** In rank order. Present on a plan's tree. */
  readonly actions: readonly CarePlanAction[];
}

export interface CarePlanProblem {
  readonly id: string;
  readonly planId: string;
  /** One of `options.codeSystems`. */
  readonly codeSystem: string;
  readonly title: string;
  readonly status: CarePlanProblemStatus;
  readonly rank: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly code?: string;
  readonly description?: string;
  /** In rank order. Present on a plan's tree. */
  readonly goals: readonly CarePlanGoal[];
}

export interface CarePlanEvaluation {
  readonly id: string;
  readonly planId: string;
  readonly goalId: string;
  readonly status: CarePlanGoalStatus;
  readonly evaluatedAt: Temporal.Instant;
  readonly outcome?: string;
  /** The forms submission it came from. */
  readonly submissionId?: string;
  readonly authorId?: string;
}

/** A plan without its problems, as `list` returns it. */
export interface CarePlanSummary<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** The client, any registered subject. */
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string;
  readonly status: CarePlanStatus;
  readonly version: number;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
  readonly startsOn?: Temporal.PlainDate;
  readonly reviewOn?: Temporal.PlainDate;
  readonly ownerId?: string;
  /** The agreement request (signatures block). */
  readonly signatureRequestId?: string;
  readonly agreedAt?: Temporal.Instant;
  /** The versions snapshot taken when it was published. */
  readonly publishedVersionId?: string;
  readonly publishedAt?: Temporal.Instant;
  readonly publishedBy?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdBy?: string;
}

/** A plan with its problems, goals, actions and evaluations. */
export interface CarePlan<
  F extends object = Record<never, never>,
> extends CarePlanSummary<F> {
  readonly problems: readonly CarePlanProblem[];
  /** The newest first. */
  readonly evaluations: readonly CarePlanEvaluation[];
}

/** An action of kind `measure` with its plan, for a register. */
export interface CarePlanMeasure extends CarePlanAction {
  readonly planTitle: string;
  readonly planStatus: CarePlanStatus;
  readonly subjectType: string;
  readonly subjectId: string;
}

export interface CarePlanInput<F extends object = Record<never, never>> {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string;
  readonly startsOn?: Temporal.PlainDate | null;
  readonly reviewOn?: Temporal.PlainDate | null;
  readonly ownerId?: string | null;
  /**
   * An earlier plan of the same client: its problems, goals and the actions
   * that haven't ended are copied into the new draft.
   */
  readonly copyFromPlanId?: string;
  readonly fields?: Partial<F>;
}

/**
 * What `update` changes on a draft or active plan; keys left out keep their
 * value.
 */
export type CarePlanChange<F extends object = Record<never, never>> = Partial<
  Omit<CarePlanInput<F>, "subjectType" | "subjectId" | "copyFromPlanId">
>;

export interface CarePlanProblemInput {
  /** Default the first of `options.codeSystems`. */
  readonly codeSystem?: string;
  readonly code?: string | null;
  readonly title: string;
  readonly description?: string | null;
  /** A rank key; default after the last. */
  readonly rank?: string;
}

/** On an active plan, only `status` changes. */
export type CarePlanProblemChange = Partial<CarePlanProblemInput> & {
  readonly status?: CarePlanProblemStatus;
};

export interface CarePlanGoalInput {
  readonly title: string;
  readonly targetOn?: Temporal.PlainDate | null;
  readonly measure?: CarePlanJson | null;
  readonly rank?: string;
}

/** On an active plan, only `status` changes. */
export type CarePlanGoalChange = Partial<CarePlanGoalInput> & {
  readonly status?: CarePlanGoalStatus;
};

export interface CarePlanActionInput {
  /** Default `intervention`. */
  readonly kind?: CarePlanActionKind;
  readonly title: string;
  readonly instructions?: string | null;
  readonly frequency?: CarePlanJson | null;
  readonly teamRole?: string | null;
  readonly measureKind?: string | null;
  readonly bookingSeriesId?: string | null;
  /** Always `true` for a measure. */
  readonly requiresApproval?: boolean;
  /** Positive. */
  readonly reviewEvery?: Temporal.Duration | null;
  readonly startsOn?: Temporal.PlainDate | null;
  readonly endsOn?: Temporal.PlainDate | null;
  readonly rank?: string;
}

/**
 * On an active plan, only how the action runs changes: `bookingSeriesId`,
 * `endsOn`, `frequency`, `instructions`, `reviewEvery` and `teamRole`.
 */
export type CarePlanActionChange = Partial<CarePlanActionInput>;

export interface CarePlanEvaluationInput {
  /** The goal status found; a new one becomes the goal's status. */
  readonly status: CarePlanGoalStatus;
  readonly outcome?: string;
  readonly submissionId?: string;
}

export interface CarePlans<F extends object = Record<never, never>> {
  /** A draft plan for a client; needs `care_plans.write`. */
  create(input: CarePlanInput<F>): AsyncResult<CarePlan<F>>;
  update(input: {
    planId: string;
    change: CarePlanChange<F>;
  }): AsyncResult<CarePlan<F>>;
  /** Adds a problem to a draft plan. */
  addProblem(input: {
    planId: string;
    input: CarePlanProblemInput;
  }): AsyncResult<CarePlanProblem>;
  updateProblem(input: {
    problemId: string;
    change: CarePlanProblemChange;
  }): AsyncResult<CarePlanProblem>;
  /** Adds a goal under a problem of a draft plan. */
  addGoal(input: {
    problemId: string;
    input: CarePlanGoalInput;
  }): AsyncResult<CarePlanGoal>;
  /** A status change on an active plan needs `care_plans.evaluate`. */
  updateGoal(input: {
    goalId: string;
    change: CarePlanGoalChange;
  }): AsyncResult<CarePlanGoal>;
  /** Adds an action toward a goal of a draft plan. */
  addAction(input: {
    goalId: string;
    input: CarePlanActionInput;
  }): AsyncResult<CarePlanAction>;
  updateAction(input: {
    actionId: string;
    change: CarePlanActionChange;
  }): AsyncResult<CarePlanAction>;
  /**
   * Makes a draft the client's active plan, archives the plan before it and
   * starts its actions; needs `care_plans.publish`.
   */
  publish(planId: string): AsyncResult<CarePlan<F>>;
  /** Archives a plan and ends its actions; needs `care_plans.publish`. */
  archive(planId: string): AsyncResult<CarePlan<F>>;
  get(planId: string): AsyncResult<CarePlan<F>>;
  /** A client's plans, the newest version first. */
  list(
    input: { subjectType: string; subjectId: string } & {
      readonly includeArchived?: boolean;
    },
  ): AsyncResult<readonly CarePlanSummary<F>[]>;
  /** Evaluates a goal of an active plan; needs `care_plans.evaluate`. */
  evaluate(input: {
    goalId: string;
    input: CarePlanEvaluationInput;
  }): AsyncResult<CarePlanEvaluation>;
  /**
   * Starts a planned action. An action that requires an approval starts once
   * approved; without one, this asks for it and returns the action planned.
   */
  startAction(actionId: string): AsyncResult<CarePlanAction>;
  endAction(input: {
    actionId: string;
    reason?: string | undefined;
  }): AsyncResult<CarePlanAction>;
  /** Records a review of an active action; needs `care_plans.evaluate`. */
  reviewAction(input: {
    actionId: string;
    note?: string | undefined;
  }): AsyncResult<CarePlanAction>;
  /** The organization's restrictive measures, the ones in force by default. */
  measures(options?: {
    readonly activeOnly?: boolean;
  }): AsyncResult<readonly CarePlanMeasure[]>;
  /**
   * Asks members who speak for the client to agree to an active plan, a
   * signature request with meaning `agreed` (signatures block).
   */
  requestAgreement(input: {
    planId: string;
    signers: readonly string[];
    message?: string | undefined;
  }): AsyncResult<CarePlan<F>>;
  /** Reports the plans and actions whose review is due; service role only. */
  dueReviews(): AsyncResult<number>;
  /**
   * Creates the plan with its problems, goals and actions in order and returns
   * the plan as `get` reads it. It stops at the first failure and leaves what
   * it saved.
   */
  createTree(input: {
    plan: CarePlanInput<F>;
    problems: readonly (CarePlanProblemInput & {
      readonly goals?: readonly (CarePlanGoalInput & {
        readonly actions?: readonly CarePlanActionInput[];
      })[];
    })[];
  }): AsyncResult<CarePlan<F>>;
}

export interface CarePlansOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the plan's extra columns
   * (`blocks.care-plans.options.extraColumns`), keyed by database name. It
   * types and parses them on reads, and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<CarePlans<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const optionalDuration = (value: unknown): Temporal.Duration | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().Duration.from(value)
    : undefined;

const optionalJson = (value: unknown): CarePlanJson | undefined =>
  isRecord(value) ? value : undefined;

const listOf = <T>(
  value: unknown,
  map: (row: Readonly<Record<string, unknown>>) => T,
): readonly T[] =>
  Array.isArray(value) ? value.filter(isRecord).map(map) : [];

function actionOf(row: Readonly<Record<string, unknown>>): CarePlanAction {
  return {
    id: textOf(row["id"]),
    planId: textOf(row["planId"]),
    goalId: textOf(row["goalId"]),
    kind: enumOrThrow(
      row["kind"],
      CARE_PLAN_ACTION_KINDS,
      "care plan action kind",
    ),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      CARE_PLAN_ACTION_STATUSES,
      "care plan action status",
    ),
    requiresApproval: row["requiresApproval"] === true,
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("instructions", optionalText(row["instructions"])),
    ...optional("frequency", optionalJson(row["frequency"])),
    ...optional("teamRole", optionalText(row["teamRole"])),
    ...optional("measureKind", optionalText(row["measureKind"])),
    ...optional("taskId", optionalText(row["taskId"])),
    ...optional("bookingSeriesId", optionalText(row["bookingSeriesId"])),
    ...optional("approvalId", optionalText(row["approvalId"])),
    ...optional("reviewEvery", optionalDuration(row["reviewEvery"])),
    ...optional("reviewedAt", optionalInstant(row["reviewedAt"])),
    ...optional("startsOn", optionalDate(row["startsOn"])),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("startedAt", optionalInstant(row["startedAt"])),
    ...optional("endedAt", optionalInstant(row["endedAt"])),
    ...optional("endReason", optionalText(row["endReason"])),
  };
}

function goalOf(row: Readonly<Record<string, unknown>>): CarePlanGoal {
  return {
    id: textOf(row["id"]),
    planId: textOf(row["planId"]),
    problemId: textOf(row["problemId"]),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      CARE_PLAN_GOAL_STATUSES,
      "care plan goal status",
    ),
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    actions: listOf(row["actions"], actionOf),
    ...optional("targetOn", optionalDate(row["targetOn"])),
    ...optional("measure", optionalJson(row["measure"])),
  };
}

function problemOf(row: Readonly<Record<string, unknown>>): CarePlanProblem {
  return {
    id: textOf(row["id"]),
    planId: textOf(row["planId"]),
    codeSystem: textOf(row["codeSystem"]),
    title: textOf(row["title"]),
    status: enumOrThrow(
      row["status"],
      CARE_PLAN_PROBLEM_STATUSES,
      "care plan problem status",
    ),
    rank: textOf(row["rank"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    goals: listOf(row["goals"], goalOf),
    ...optional("code", optionalText(row["code"])),
    ...optional("description", optionalText(row["description"])),
  };
}

function evaluationOf(
  row: Readonly<Record<string, unknown>>,
): CarePlanEvaluation {
  return {
    id: textOf(row["id"]),
    planId: textOf(row["planId"]),
    goalId: textOf(row["goalId"]),
    status: enumOrThrow(
      row["status"],
      CARE_PLAN_GOAL_STATUSES,
      "care plan evaluation status",
    ),
    evaluatedAt: requiredInstant(row["evaluatedAt"], "evaluatedAt"),
    ...optional("outcome", optionalText(row["outcome"])),
    ...optional("submissionId", optionalText(row["submissionId"])),
    ...optional("authorId", optionalText(row["authorId"])),
  };
}

function summaryOf(row: Readonly<Record<string, unknown>>): CarePlanSummary {
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], CARE_PLAN_STATUSES, "care plan status"),
    version: numberOf(row["version"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...optional("startsOn", optionalDate(row["startsOn"])),
    ...optional("reviewOn", optionalDate(row["reviewOn"])),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("signatureRequestId", optionalText(row["signatureRequestId"])),
    ...optional("agreedAt", optionalInstant(row["agreedAt"])),
    ...optional("publishedVersionId", optionalText(row["publishedVersionId"])),
    ...optional("publishedAt", optionalInstant(row["publishedAt"])),
    ...optional("publishedBy", optionalText(row["publishedBy"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function planOf(value: unknown, fn: string): CarePlan {
  const row = recordOf(value, fn);

  return {
    ...summaryOf(row),
    problems: listOf(row["problems"], problemOf),
    evaluations: listOf(row["evaluations"], evaluationOf),
  };
}

function measureOf(row: Readonly<Record<string, unknown>>): CarePlanMeasure {
  return {
    ...actionOf(row),
    planTitle: textOf(row["planTitle"]),
    planStatus: enumOrThrow(
      row["planStatus"],
      CARE_PLAN_STATUSES,
      "care plan status",
    ),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
  };
}

/**
 * The input as the SQL reads it: undefined keys left out, dates and durations
 * as ISO text.
 */
const wire = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input)
      .filter(([, value]) => value !== undefined)
      .map(([key, value]) => [
        key,
        value instanceof temporal().PlainDate ||
        value instanceof temporal().Duration
          ? value.toString()
          : value,
      ]),
  );

/**
 * Care plans for any subject: problems with coded findings, goals with a
 * target, and actions (interventions, appointments, tasks and restrictive
 * measures) that start when the plan is published and are evaluated and
 * reviewed until the next version replaces it.
 */
export function createCarePlans<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: CarePlansOptions<S>): CarePlans<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "care plan fields",
  );

  const plan = (fn: string) => (value: unknown) => planOf(value, fn);

  const row =
    <T>(fn: string, map: (row: Readonly<Record<string, unknown>>) => T) =>
    (value: unknown): T =>
      map(recordOf(value, fn));

  const withFields = (
    input: object & { readonly fields?: Partial<F> },
  ): AsyncResult<Record<string, unknown>> =>
    fields
      .args(input.fields)
      .map((checked) => ({
        ...wire(input),
        ...(checked === undefined ? {} : { fields: checked }),
      }));

  const client: CarePlans<F> = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        withFields(input).andThen((attrs) =>
          call(
            "create_care_plan",
            { tenant: organizationId, input: attrs },
            plan("create_care_plan"),
          ).andThen(fields.row),
        ),
      ),
    update: ({ planId, change }) =>
      withFields(change).andThen((attrs) =>
        call(
          "update_care_plan",
          { plan_id: planId, changes: attrs },
          plan("update_care_plan"),
        ).andThen(fields.row),
      ),
    addProblem: ({ planId, input }) =>
      call(
        "add_care_plan_problem",
        { plan_id: planId, input: wire(input) },
        row("add_care_plan_problem", problemOf),
      ),
    updateProblem: ({ problemId, change }) =>
      call(
        "update_care_plan_problem",
        { problem_id: problemId, changes: wire(change) },
        row("update_care_plan_problem", problemOf),
      ),
    addGoal: ({ problemId, input }) =>
      call(
        "add_care_plan_goal",
        { problem_id: problemId, input: wire(input) },
        row("add_care_plan_goal", goalOf),
      ),
    updateGoal: ({ goalId, change }) =>
      call(
        "update_care_plan_goal",
        { goal_id: goalId, changes: wire(change) },
        row("update_care_plan_goal", goalOf),
      ),
    addAction: ({ goalId, input }) =>
      call(
        "add_care_plan_action",
        { goal_id: goalId, input: wire(input) },
        row("add_care_plan_action", actionOf),
      ),
    updateAction: ({ actionId, change }) =>
      call(
        "update_care_plan_action",
        { action_id: actionId, changes: wire(change) },
        row("update_care_plan_action", actionOf),
      ),
    publish: (planId) =>
      call(
        "publish_care_plan",
        { plan_id: planId },
        plan("publish_care_plan"),
      ).andThen(fields.row),
    archive: (planId) =>
      call(
        "archive_care_plan",
        { plan_id: planId },
        plan("archive_care_plan"),
      ).andThen(fields.row),
    get: (planId) =>
      call("get_care_plan", { plan_id: planId }, plan("get_care_plan")).andThen(
        fields.row,
      ),
    list: ({ subjectType, subjectId, ...list }) =>
      call(
        "list_care_plans",
        {
          subject_type: subjectType,
          subject_id: subjectId,
          include_archived: list.includeArchived ?? false,
        },
        (value) => recordsOf(value, "list_care_plans").map(summaryOf),
      ).andThen(fields.rows),
    evaluate: ({ goalId, input }) =>
      call(
        "record_care_plan_evaluation",
        {
          goal_id: goalId,
          status: input.status,
          outcome: input.outcome ?? null,
          submission_id: input.submissionId ?? null,
        },
        row("record_care_plan_evaluation", evaluationOf),
      ),
    startAction: (actionId) =>
      call(
        "start_care_plan_action",
        { action_id: actionId },
        row("start_care_plan_action", actionOf),
      ),
    endAction: ({ actionId, reason }) =>
      call(
        "end_care_plan_action",
        { action_id: actionId, reason: reason ?? null },
        row("end_care_plan_action", actionOf),
      ),
    reviewAction: ({ actionId, note }) =>
      call(
        "review_care_plan_action",
        { action_id: actionId, note: note ?? null },
        row("review_care_plan_action", actionOf),
      ),
    measures: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_care_plan_measures",
          { tenant: organizationId, active_only: list.activeOnly ?? true },
          (value) => recordsOf(value, "list_care_plan_measures").map(measureOf),
        ),
      ),
    requestAgreement: ({ planId, signers, message }) =>
      call(
        "request_care_plan_agreement",
        { plan_id: planId, signers, message: message ?? null },
        plan("request_care_plan_agreement"),
      ).andThen(fields.row),
    dueReviews: () =>
      call("due_care_plan_reviews", {}, (value) => numberOf(value)),
    createTree: ({ plan, problems }) =>
      AsyncResult.from(async () => {
        const created = await hooked.create(plan);

        if (!created.ok) {
          return created;
        }

        for (const { goals = [], ...problem } of problems) {
          const savedProblem = await hooked.addProblem({
            planId: created.data.id,
            input: problem,
          });

          if (!savedProblem.ok) {
            return savedProblem;
          }

          for (const { actions = [], ...goal } of goals) {
            const savedGoal = await hooked.addGoal({
              problemId: savedProblem.data.id,
              input: goal,
            });

            if (!savedGoal.ok) {
              return savedGoal;
            }

            for (const action of actions) {
              const savedAction = await hooked.addAction({
                goalId: savedGoal.data.id,
                input: action,
              });

              if (!savedAction.ok) {
                return savedAction;
              }
            }
          }
        }

        return hooked.get(created.data.id);
      }),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: CarePlans<F> = withBlockHooks(client, options.hooks, {
    block: "care-plans",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
