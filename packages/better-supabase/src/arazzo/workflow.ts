import type {
  JsonObject,
  JsonSchema,
  ModelStep,
  ModelWorkflow,
  ResourceOperation,
} from "../spec/model.ts";
import type { StandardLike } from "../spec/schemas.ts";

import { convertStandard } from "../spec/schemas.ts";

type PascalWord<S extends string> = S extends `${infer Head}_${infer Tail}`
  ? `${Capitalize<Head>}${PascalWord<Tail>}`
  : S extends `${infer Head}-${infer Tail}`
    ? `${Capitalize<Head>}${PascalWord<Tail>}`
    : Capitalize<S>;

/**
 * The operationIds `defineApi` gives resource operations by default
 * (`listCustomers`, `getCustomers`), for a typed `defineWorkflow`:
 * `defineWorkflow<ResourceOperationIds<"customers" | "notes">>(...)`.
 */
export type ResourceOperationIds<
  Table extends string,
  Op extends ResourceOperation = ResourceOperation,
> = Table extends string ? `${Op}${PascalWord<Table>}` : never;

/** Where a parameter goes; inferred from the target operation when left out. */
export type ParameterLocation = "path" | "query" | "header" | "cookie";

export interface StepParameter {
  readonly name: string;
  readonly in?: ParameterLocation;
  /** A literal or a runtime expression such as `$inputs.id`. */
  readonly value: unknown;
}

/** An Arazzo Criterion Object; `context` is required for every `type` but `simple`. */
export interface CriterionObject {
  readonly condition: string;
  readonly context?: string;
  readonly type?: "simple" | "regex" | "jsonpath" | "xpath" | JsonObject;
}

/** A success criterion: a simple condition string, or a Criterion Object. */
export type StepCriterion = string | CriterionObject;

interface StepBase {
  readonly id: string;
  readonly description?: string;
  /** A list, or a record of name to value (the location is inferred). */
  readonly parameters?:
    | readonly StepParameter[]
    | Readonly<Record<string, unknown>>;
  /** The request body; runtime expressions inside it are resolved. */
  readonly requestBody?: unknown;
  /** Defaults to the first 2xx status of the target operation. */
  readonly successCriteria?: readonly StepCriterion[];
  /** Output name to a runtime expression, e.g. `$response.body#/id`. */
  readonly outputs?: Readonly<Record<string, string>>;
  readonly onSuccess?: readonly JsonObject[];
  readonly onFailure?: readonly JsonObject[];
}

export interface OperationStep<Op extends string> extends StepBase {
  readonly operationId: Op;
  readonly workflowId?: never;
  readonly channel?: never;
}

export interface WorkflowCallStep extends StepBase {
  readonly workflowId: string;
  readonly operationId?: never;
  readonly channel?: never;
}

/** Sends or receives on an AsyncAPI channel; Arazzo 1.1 only. */
export interface ChannelStep extends StepBase {
  readonly channel: {
    readonly id: string;
    readonly action: "send" | "receive";
    readonly correlationId?: string;
  };
  readonly operationId?: never;
  readonly workflowId?: never;
}

export type WorkflowStep<Op extends string = string> =
  | OperationStep<Op>
  | WorkflowCallStep
  | ChannelStep;

export interface WorkflowInput<Op extends string = string> {
  readonly id: string;
  readonly summary?: string;
  readonly description?: string;
  /** A JSON Schema, or a Standard Schema converted through Standard JSON Schema. */
  readonly inputs?: JsonSchema | StandardLike;
  readonly steps: readonly WorkflowStep<Op>[];
  /** Output name to a runtime expression, e.g. `$steps.get.outputs.row`. */
  readonly outputs?: Readonly<Record<string, string>>;
}

function isStandard(value: unknown): value is StandardLike {
  return (
    typeof value === "object" &&
    value !== null &&
    "~standard" in value &&
    typeof value["~standard"] === "object"
  );
}

function inputsOf(inputs: JsonSchema | StandardLike): JsonSchema {
  if (!isStandard(inputs)) {
    return inputs;
  }

  const converted = convertStandard(inputs, "input");

  if (!converted) {
    throw new TypeError(
      "defineWorkflow: inputs is a Standard Schema without Standard JSON Schema; pass a JSON Schema instead",
    );
  }

  return converted.schema;
}

function parametersOf(
  parameters: StepBase["parameters"],
): ModelStep["parameters"] {
  if (parameters === undefined) {
    return undefined;
  }

  if (Array.isArray(parameters)) {
    return parameters.map((parameter: StepParameter) =>
      parameter.in === undefined
        ? { name: parameter.name, value: parameter.value }
        : { name: parameter.name, in: parameter.in, value: parameter.value },
    );
  }

  return Object.entries(parameters).map(([name, value]) => ({ name, value }));
}

function criterionOf(criterion: StepCriterion): CriterionObject {
  return typeof criterion === "string"
    ? { condition: criterion }
    : { ...criterion };
}

function stepOf<Op extends string>(step: WorkflowStep<Op>): ModelStep {
  const parameters = parametersOf(step.parameters);
  let target: Pick<ModelStep, "operationId" | "workflowId" | "channel"> = {};

  if (step.operationId) {
    target = { operationId: step.operationId };
  } else if (step.workflowId) {
    target = { workflowId: step.workflowId };
  } else if (step.channel) {
    target = { channel: step.channel };
  }

  return {
    id: step.id,
    ...(step.description === undefined
      ? {}
      : { description: step.description }),
    ...target,
    ...(parameters === undefined ? {} : { parameters }),
    ...(step.requestBody === undefined
      ? {}
      : { requestBody: { payload: step.requestBody } }),
    ...(step.successCriteria === undefined
      ? {}
      : { successCriteria: step.successCriteria.map(criterionOf) }),
    ...(step.outputs === undefined ? {} : { outputs: { ...step.outputs } }),
    ...(step.onSuccess === undefined ? {} : { onSuccess: step.onSuccess }),
    ...(step.onFailure === undefined ? {} : { onFailure: step.onFailure }),
  };
}

/**
 * A workflow for `defineApi`'s `workflows`, rendered by `arazzoFormat`.
 * Steps name operations by operationId; pass the ids as `Op` (for example
 * `ResourceOperationIds<"customers">`) to type them. Rendering reports
 * unknown operationIds, steps that read outputs of later or unknown steps,
 * and channel steps outside Arazzo 1.1.
 *
 * ```ts
 * const onboarding = defineWorkflow<ResourceOperationIds<"customers">>({
 *   id: "onboardCustomer",
 *   inputs: { type: "object", properties: { row: { type: "object" } } },
 *   steps: [
 *     { id: "create", operationId: "createCustomers", requestBody: "$inputs.row",
 *       outputs: { id: "$response.body#/id" } },
 *     { id: "get", operationId: "getCustomers", parameters: { id: "$steps.create.outputs.id" } },
 *   ],
 * });
 * ```
 */
export function defineWorkflow<const Op extends string = string>(
  workflow: WorkflowInput<Op>,
): ModelWorkflow {
  return {
    id: workflow.id,
    ...(workflow.summary === undefined ? {} : { summary: workflow.summary }),
    ...(workflow.description === undefined
      ? {}
      : { description: workflow.description }),
    ...(workflow.inputs === undefined
      ? {}
      : { inputs: inputsOf(workflow.inputs) }),
    steps: workflow.steps.map(stepOf),
    ...(workflow.outputs === undefined
      ? {}
      : { outputs: { ...workflow.outputs } }),
  };
}
