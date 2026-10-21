import type {
  DocumentFormat,
  LowerContext,
  SpecDiagnostic,
} from "../spec/format.ts";
import type {
  ApiModel,
  JsonObject,
  ModelOperation,
  ModelStep,
  ModelWorkflow,
} from "../spec/model.ts";
import type {
  AnyArazzoDocument,
  ArazzoDocuments,
  ArazzoSourceDescription,
  ArazzoStep,
  ArazzoVersion,
  ArazzoWorkflow,
} from "./types.ts";

import { ASYNCAPI_FILE_NAME } from "../asyncapi/types.ts";
import { isPlainObject } from "../core/clone.ts";
import { SPEC_PINS } from "../core/spec-pins.ts";
import { OPENAPI_FILE_NAME } from "../openapi/types.ts";
import { safeKey } from "../spec/events.ts";
import { defineDocumentFormat } from "../spec/format.ts";

type Json = Record<string, unknown>;

const ARAZZO_FIELD = {
  "1.0": SPEC_PINS.arazzo10,
  "1.1": SPEC_PINS.arazzo11,
} as const satisfies Record<ArazzoVersion, string>;

const ID = /^[A-Za-z0-9_-]+$/;
const STEP_OUTPUT = /\$steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)/g;
const INPUT = /\$inputs\.([A-Za-z0-9_-]+)/g;
const SOURCE = /\$sourceDescriptions\.([A-Za-z0-9_-]+)\./g;

/** Where the workflows' source documents live. */
export interface ArazzoSourceOptions {
  /** Defaults to `api`. */
  readonly name?: string;
  /** Defaults to the model's `self`, then the format's file name. */
  readonly url?: string;
}

export interface ArazzoFormatOptions {
  /** The OpenAPI document; its URL defaults to `openapi.json`. */
  readonly openapi?: ArazzoSourceOptions;
  /**
   * The AsyncAPI document channel steps use; defaults to `events` at
   * `asyncapi.json`.
   */
  readonly asyncapi?: ArazzoSourceOptions;
}

const omitUndefined = (value: Json): Json =>
  Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  );

function firstSuccess(operation: ModelOperation): string | undefined {
  return Object.keys(operation.responses)
    .filter((status) => /^2\d\d$/.test(status))
    .toSorted()[0];
}

function stripActionParameters(
  actions: readonly JsonObject[] | undefined,
  version: ArazzoVersion,
  report: (pointer: string) => void,
  pointer: string,
): Json[] | undefined {
  if (!actions) {
    return undefined;
  }

  return actions.map((action, index) => {
    const copy: Json = structuredClone({ ...action });

    if (version === "1.0" && "parameters" in copy) {
      delete copy["parameters"];
      report(`${pointer}/${String(index)}/parameters`);
    }

    return copy;
  });
}

interface Lowering {
  readonly model: ApiModel;
  readonly version: ArazzoVersion;
  readonly ctx: LowerContext;
  readonly operations: ReadonlyMap<string, ModelOperation>;
  readonly channels: ReadonlySet<string>;
  readonly apiName: string;
  readonly eventsName: string;
  readonly qualify: boolean;
}

function lowerStep(
  step: ModelStep,
  pointer: string,
  state: Lowering,
): ArazzoStep | undefined {
  const { ctx, version } = state;

  const operation =
    step.operationId === undefined
      ? undefined
      : state.operations.get(step.operationId);

  let target: Pick<
    ArazzoStep,
    "operationId" | "workflowId" | "channelPath" | "action" | "correlationId"
  > = {};

  if (step.operationId !== undefined) {
    if (!operation) {
      ctx.report({
        code: "arazzo-operation-unknown",
        severity: "error",
        message: `Step "${step.id}" calls operation "${step.operationId}", which the API does not have`,
        pointer: `${pointer}/operationId`,
      });
    }

    target = {
      operationId: state.qualify
        ? `$sourceDescriptions.${state.apiName}.${step.operationId}`
        : step.operationId,
    };
  } else if (step.workflowId !== undefined) {
    target = { workflowId: step.workflowId };
  } else if (step.channel) {
    if (version === "1.0") {
      ctx.report({
        code: "arazzo-channel-step-unsupported",
        severity: "error",
        message: `Step "${step.id}" uses an AsyncAPI channel, which needs Arazzo 1.1; the step is left out`,
        pointer,
      });

      return undefined;
    }

    if (!state.channels.has(step.channel.id)) {
      ctx.report({
        code: "arazzo-channel-unknown",
        severity: "error",
        message: `Step "${step.id}" uses channel "${step.channel.id}", which the API does not have`,
        pointer: `${pointer}/channelPath`,
      });
    }

    target = {
      channelPath: `{$sourceDescriptions.${state.eventsName}.url}#/channels/${safeKey(step.channel.id)}`,
      action: step.channel.action,
      ...(step.channel.correlationId === undefined
        ? {}
        : { correlationId: step.channel.correlationId }),
    };
  }

  const parameters = step.parameters?.map((parameter, index) => {
    const location =
      parameter.in ??
      operation?.parameters.find(
        (candidate) => candidate.name === parameter.name,
      )?.in;

    if (location === undefined && step.operationId !== undefined) {
      ctx.report({
        code: "arazzo-parameter-in-missing",
        severity: "error",
        message: `Parameter "${parameter.name}" of step "${step.id}" has no "in", and operation "${step.operationId}" has no parameter by that name`,
        pointer: `${pointer}/parameters/${String(index)}`,
      });
    }

    return omitUndefined({
      name: parameter.name,
      in: location,
      value: structuredClone(parameter.value),
    });
  });

  const contentType = operation?.requestBody
    ? Object.keys(operation.requestBody.content)[0]
    : undefined;

  const success = operation ? firstSuccess(operation) : undefined;

  const successCriteria =
    step.successCriteria?.map((criterion) => ({ ...criterion })) ??
    (success === undefined
      ? undefined
      : [{ condition: `$statusCode == ${success}` }]);

  const reportParameters = (where: string) => {
    ctx.report({
      code: "arazzo-action-parameters-unsupported",
      severity: "warning",
      message: `Action parameters need Arazzo 1.1; they are left out of step "${step.id}"`,
      pointer: where,
    });
  };

  const onSuccess = stripActionParameters(
    step.onSuccess,
    version,
    reportParameters,
    `${pointer}/onSuccess`,
  );

  const onFailure = stripActionParameters(
    step.onFailure,
    version,
    reportParameters,
    `${pointer}/onFailure`,
  );

  return {
    stepId: step.id,
    ...(step.description === undefined
      ? {}
      : { description: step.description }),
    ...target,
    ...(parameters === undefined ? {} : { parameters }),
    ...(step.requestBody
      ? {
          requestBody: omitUndefined({
            contentType,
            payload: structuredClone(step.requestBody.payload),
          }),
        }
      : {}),
    ...(successCriteria === undefined ? {} : { successCriteria }),
    ...(onSuccess === undefined ? {} : { onSuccess }),
    ...(onFailure === undefined ? {} : { onFailure }),
    ...(step.outputs ? { outputs: { ...step.outputs } } : {}),
  };
}

function lowerWorkflow(
  workflow: ModelWorkflow,
  index: number,
  state: Lowering,
): ArazzoWorkflow {
  const pointer = `/workflows/${String(index)}`;

  const steps = workflow.steps.flatMap((step, stepIndex) => {
    const lowered = lowerStep(
      step,
      `${pointer}/steps/${String(stepIndex)}`,
      state,
    );

    return lowered ? [lowered] : [];
  });

  return {
    workflowId: workflow.id,
    ...(workflow.summary === undefined ? {} : { summary: workflow.summary }),
    ...(workflow.description === undefined
      ? {}
      : { description: workflow.description }),
    ...(workflow.inputs ? { inputs: structuredClone(workflow.inputs) } : {}),
    steps,
    ...(workflow.outputs ? { outputs: { ...workflow.outputs } } : {}),
  };
}

function lowerArazzo(
  options: ArazzoFormatOptions,
  model: ApiModel,
  version: ArazzoVersion,
  ctx: LowerContext,
): AnyArazzoDocument {
  const apiName = options.openapi?.name ?? "api";
  const eventsName = options.asyncapi?.name ?? "events";

  const usesChannels =
    version === "1.1" &&
    model.workflows.some((workflow) =>
      workflow.steps.some((step) => step.channel !== undefined),
    );

  const usesOperations = model.workflows.some((workflow) =>
    workflow.steps.some((step) => step.operationId !== undefined),
  );

  const sources: ArazzoSourceDescription[] = [];

  if (usesOperations || !usesChannels) {
    sources.push({
      name: apiName,
      url: options.openapi?.url ?? model.self ?? OPENAPI_FILE_NAME,
      type: "openapi",
    });
  }

  if (usesChannels) {
    sources.push({
      name: eventsName,
      url: options.asyncapi?.url ?? ASYNCAPI_FILE_NAME,
      type: "asyncapi",
    });
  }

  const state: Lowering = {
    model,
    version,
    ctx,
    operations: new Map(
      model.operations.map((operation) => [operation.id, operation]),
    ),
    channels: new Set(model.channels.map((channel) => channel.id)),
    apiName,
    eventsName,
    qualify: sources.length > 1,
  };

  if (model.workflows.length === 0) {
    ctx.report({
      code: "arazzo-workflows-empty",
      severity: "error",
      message:
        "The API has no workflows; an Arazzo document needs at least one (pass workflows, or a built-in such as paginationWorkflows())",
      pointer: "/workflows",
    });
  }

  const { info } = model;

  return {
    arazzo: ARAZZO_FIELD[version],
    info: {
      title: info.title,
      version: info.version,
      ...(info.summary === undefined ? {} : { summary: info.summary }),
      ...(info.description === undefined
        ? {}
        : { description: info.description }),
    },
    sourceDescriptions: sources,
    workflows: model.workflows.map((workflow, index) =>
      lowerWorkflow(workflow, index, state),
    ),
  };
}

function strings(value: unknown, out: string[]): void {
  if (typeof value === "string") {
    out.push(value);
  } else if (Array.isArray(value)) {
    // SAFETY: Array.isArray narrows to any[]; each item is read as unknown.
    for (const item of value as readonly unknown[]) {
      strings(item, out);
    }
  } else if (isPlainObject(value)) {
    for (const item of Object.values(value)) {
      strings(item, out);
    }
  }
}

function inputNames(inputs: Json | undefined): Set<string> | undefined {
  if (!inputs || !isPlainObject(inputs["properties"])) {
    return undefined;
  }

  return new Set(Object.keys(inputs["properties"]));
}

function lintWorkflow(
  workflow: ArazzoWorkflow,
  index: number,
  workflowIds: ReadonlySet<string>,
  sourceNames: ReadonlySet<string>,
  diagnostics: SpecDiagnostic[],
): void {
  const pointer = `/workflows/${String(index)}`;
  const stepIndex = new Map<string, number>();
  const outputsOf = new Map<string, ReadonlySet<string>>();

  for (const [position, step] of workflow.steps.entries()) {
    if (stepIndex.has(step.stepId)) {
      diagnostics.push({
        code: "arazzo-step-id-duplicate",
        severity: "error",
        message: `Workflow "${workflow.workflowId}" has two steps "${step.stepId}"`,
        pointer: `${pointer}/steps/${String(position)}`,
      });
    } else {
      stepIndex.set(step.stepId, position);
    }

    outputsOf.set(step.stepId, new Set(Object.keys(step.outputs ?? {})));
  }

  const inputs = inputNames(workflow.inputs);

  const checkExpressions = (
    value: unknown,
    where: string,
    position?: number,
  ) => {
    const texts: string[] = [];
    strings(value, texts);

    for (const text of texts) {
      for (const [, stepId = "", output = ""] of text.matchAll(STEP_OUTPUT)) {
        const target = stepIndex.get(stepId);

        if (target === undefined || !outputsOf.get(stepId)?.has(output)) {
          diagnostics.push({
            code: "arazzo-step-output-unknown",
            severity: "error",
            message: `"$steps.${stepId}.outputs.${output}" names an output no step "${stepId}" declares`,
            pointer: where,
          });
        } else if (position !== undefined && target >= position) {
          diagnostics.push({
            code: "arazzo-step-output-order",
            severity: "error",
            message: `"$steps.${stepId}.outputs.${output}" is read before step "${stepId}" runs`,
            pointer: where,
          });
        }
      }

      if (inputs) {
        for (const [, name = ""] of text.matchAll(INPUT)) {
          if (!inputs.has(name)) {
            diagnostics.push({
              code: "arazzo-input-undeclared",
              severity: "warning",
              message: `"$inputs.${name}" is not a property of workflow "${workflow.workflowId}" inputs`,
              pointer: where,
            });
          }
        }
      }

      for (const [, name = ""] of text.matchAll(SOURCE)) {
        if (!sourceNames.has(name)) {
          diagnostics.push({
            code: "arazzo-source-unknown",
            severity: "error",
            message: `"$sourceDescriptions.${name}" is not a listed source description`,
            pointer: where,
          });
        }
      }
    }
  };

  for (const [position, step] of workflow.steps.entries()) {
    const where = `${pointer}/steps/${String(position)}`;

    if (!ID.test(step.stepId)) {
      diagnostics.push({
        code: "arazzo-id-invalid",
        severity: "error",
        message: `Step id "${step.stepId}" has characters Arazzo ids do not allow`,
        pointer: where,
      });
    }

    const targets = [
      step.operationId,
      step.operationPath,
      step.channelPath,
      step.workflowId,
    ].filter((target) => target !== undefined);

    if (targets.length !== 1) {
      diagnostics.push({
        code: "arazzo-step-target",
        severity: "error",
        message: `Step "${step.stepId}" needs exactly one of operationId, operationPath, channelPath or workflowId`,
        pointer: where,
      });
    }

    if (step.workflowId !== undefined && !workflowIds.has(step.workflowId)) {
      diagnostics.push({
        code: "arazzo-workflow-unknown",
        severity: "error",
        message: `Step "${step.stepId}" calls workflow "${step.workflowId}", which the document does not have`,
        pointer: `${where}/workflowId`,
      });
    }

    checkExpressions(
      [
        step.operationId,
        step.channelPath,
        step.parameters,
        step.requestBody,
        step.successCriteria,
      ],
      where,
      position,
    );
    checkExpressions([step.outputs, step.onSuccess, step.onFailure], where);

    for (const action of [
      ...(step.onSuccess ?? []),
      ...(step.onFailure ?? []),
    ]) {
      if (action["type"] !== "goto" && action["type"] !== "retry") {
        continue;
      }

      const stepId = action["stepId"];
      const workflowId = action["workflowId"];

      if (
        (typeof stepId === "string" && !stepIndex.has(stepId)) ||
        (typeof workflowId === "string" &&
          !workflowIds.has(workflowId) &&
          !workflowId.startsWith("$sourceDescriptions."))
      ) {
        diagnostics.push({
          code: "arazzo-goto-unknown",
          severity: "error",
          message: `Action "${String(action["name"])}" of step "${step.stepId}" goes to a step or workflow that does not exist`,
          pointer: where,
        });
      }
    }
  }

  checkExpressions(workflow.outputs, `${pointer}/outputs`);
}

function lintArazzo(document: AnyArazzoDocument): SpecDiagnostic[] {
  const diagnostics: SpecDiagnostic[] = [];
  const workflowIds = new Set<string>();

  for (const [index, workflow] of document.workflows.entries()) {
    if (!ID.test(workflow.workflowId)) {
      diagnostics.push({
        code: "arazzo-id-invalid",
        severity: "error",
        message: `Workflow id "${workflow.workflowId}" has characters Arazzo ids do not allow`,
        pointer: `/workflows/${String(index)}`,
      });
    }

    if (workflowIds.has(workflow.workflowId)) {
      diagnostics.push({
        code: "arazzo-workflow-id-duplicate",
        severity: "error",
        message: `Two workflows have the id "${workflow.workflowId}"`,
        pointer: `/workflows/${String(index)}`,
      });
    }

    workflowIds.add(workflow.workflowId);
  }

  const sourceNames = new Set(
    document.sourceDescriptions.map((source) => source.name),
  );

  for (const [index, workflow] of document.workflows.entries()) {
    lintWorkflow(workflow, index, workflowIds, sourceNames, diagnostics);
  }

  return diagnostics;
}

/**
 * An Arazzo format whose source descriptions point at your OpenAPI and AsyncAPI
 * URLs. `arazzoFormat` is this with the defaults: `api` at the model's `self`
 * or `openapi.json`, and `events` at `asyncapi.json`.
 */
export function createArazzoFormat(
  options: ArazzoFormatOptions = {},
): DocumentFormat<"arazzo", ArazzoVersion, AnyArazzoDocument, ArazzoDocuments> {
  return defineDocumentFormat<
    "arazzo",
    ArazzoVersion,
    AnyArazzoDocument,
    ArazzoDocuments
  >({
    id: "arazzo",
    versions: {
      "1.0": { pin: SPEC_PINS.arazzo10, status: "stable" },
      "1.1": { pin: SPEC_PINS.arazzo11, status: "stable" },
    },
    defaultVersion: "1.0",
    lower: (model, version, ctx) => lowerArazzo(options, model, version, ctx),
    lint: lintArazzo,
    fileName: () => "arazzo.json",
  });
}

/**
 * Arazzo as a `DocumentFormat`, for the model's `workflows`. 1.0 is the
 * default; channel steps (AsyncAPI send and receive) and action `parameters`
 * need 1.1.
 */
export const arazzoFormat: DocumentFormat<
  "arazzo",
  ArazzoVersion,
  AnyArazzoDocument,
  ArazzoDocuments
> = createArazzoFormat();
