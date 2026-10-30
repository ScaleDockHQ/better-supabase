import type { EntitySchema } from "../entity-schema.ts";
import type {
  CarePlanActionInput,
  CarePlanGoalInput,
  CarePlanInput,
  CarePlanProblemInput,
} from "./care-plans.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const carePlanInputSchema: EntitySchema<CarePlanInput> =
  entitySchema<CarePlanInput>({
    title: "CarePlanInput",
    fields: {
      subjectType: { kind: "string", minLength: 1, maxLength: 63 },
      subjectId: { kind: "string", minLength: 1, maxLength: 200 },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      startsOn: { kind: "plainDate", optional: true, nullable: true },
      reviewOn: { kind: "plainDate", optional: true, nullable: true },
      ownerId: { kind: "uuid", optional: true, nullable: true },
      copyFromPlanId: { kind: "uuid", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** What `addProblem` takes. */
export const carePlanProblemInputSchema: EntitySchema<CarePlanProblemInput> =
  entitySchema<CarePlanProblemInput>({
    title: "CarePlanProblemInput",
    fields: {
      codeSystem: {
        kind: "string",
        optional: true,
        description: "One of `options.codeSystems`.",
      },
      code: { kind: "string", optional: true, nullable: true, maxLength: 200 },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      description: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      rank: { kind: "string", optional: true },
    },
  });

/** What `addGoal` takes. */
export const carePlanGoalInputSchema: EntitySchema<CarePlanGoalInput> =
  entitySchema<CarePlanGoalInput>({
    title: "CarePlanGoalInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 300 },
      targetOn: { kind: "plainDate", optional: true, nullable: true },
      measure: {
        kind: "json",
        optional: true,
        nullable: true,
        description: "What counts as reaching the goal, an object.",
      },
      rank: { kind: "string", optional: true },
    },
  });

/** What `addAction` takes. */
export const carePlanActionInputSchema: EntitySchema<CarePlanActionInput> =
  entitySchema<CarePlanActionInput>({
    title: "CarePlanActionInput",
    fields: {
      kind: {
        kind: "enum",
        optional: true,
        values: ["intervention", "appointment", "task", "measure"],
      },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      instructions: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      frequency: {
        kind: "json",
        optional: true,
        nullable: true,
        description: "How often the action happens, an object.",
      },
      teamRole: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 63,
      },
      measureKind: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 63,
        description: "For a measure: one of `options.measureKinds`.",
      },
      bookingSeriesId: { kind: "uuid", optional: true, nullable: true },
      requiresApproval: { kind: "boolean", optional: true },
      reviewEvery: {
        kind: "string",
        optional: true,
        nullable: true,
        description: "An ISO 8601 duration, such as `P1M`.",
      },
      startsOn: { kind: "plainDate", optional: true, nullable: true },
      endsOn: { kind: "plainDate", optional: true, nullable: true },
      rank: { kind: "string", optional: true },
    },
  });
