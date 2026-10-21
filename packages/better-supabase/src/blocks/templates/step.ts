import type { GraphStepCall } from "../workflow-builder/executor.ts";
import type { WorkflowStepInfo } from "../workflow-builder/types.ts";
import type { Templates } from "./templates.ts";

import { DbException } from "../../core/db-exception.ts";
import { dbError } from "../../core/errors.ts";
import { isRecord } from "../shared.ts";

/** The `templates.apply` step for the workflow-builder step library. */
export const TEMPLATES_APPLY_STEP: WorkflowStepInfo = {
  name: "templates.apply",
  title: "Create from template",
  description:
    "Creates a record from a template's published version in the run's organization, then starts the template's workflows on it.",
  operation: "templates.apply",
  inputSchema: {
    type: "object",
    properties: {
      template: { type: "string", format: "uuid" },
      values: { type: "object" },
    },
    required: ["template"],
    additionalProperties: false,
  },
  outputSchema: {
    type: "object",
    properties: {
      applicationId: { type: "string" },
      subject: {
        type: "object",
        properties: { type: { type: "string" }, id: { type: "string" } },
        required: ["type", "id"],
      },
      runs: { type: "array" },
    },
    required: ["applicationId", "subject", "runs"],
  },
};

/** What a `templates.apply` node returns: plain data, so it serializes. */
export interface TemplatesApplyOutput {
  readonly applicationId: string;
  readonly subject: { readonly type: string; readonly id: string };
  readonly runs: readonly (
    | { readonly definition: string; readonly runId: string }
    | { readonly definition: string; readonly error: string }
  )[];
}

/**
 * Runs a `templates.apply` node: applies `config.template` in the run's
 * organization, with `config.values`, and keys the apply on `<runKey>:<node>`
 * so the type's `apply` can find the record a retry already created. Pass the
 * client, or a function that builds one for the call (for example as the run's
 * actor). Throws a `DbException` on error, which fails the node.
 */
export function templatesApplyStep(
  templates:
    | Templates
    | ((call: GraphStepCall) => Templates | Promise<Templates>),
): (call: GraphStepCall) => Promise<TemplatesApplyOutput> {
  return async (call) => {
    const template = call.config["template"];

    if (typeof template !== "string" || template === "") {
      throw new DbException(
        dbError("invalid_request", "templates.apply needs config.template"),
      );
    }

    if (call.tenant === undefined) {
      throw new DbException(
        dbError("invalid_request", "templates.apply needs a run with a tenant"),
      );
    }

    const values = call.config["values"];

    const client =
      typeof templates === "function" ? await templates(call) : templates;

    const applied = await client
      .apply(template, {
        into: call.tenant,
        ...(isRecord(values) ? { values } : {}),
        key: `${call.runKey}:${call.node}`,
      })
      .orThrow();

    return {
      applicationId: applied.application.id,
      subject: applied.subject,
      runs: applied.runs.map((run) =>
        "runId" in run
          ? { definition: run.definition, runId: run.runId }
          : { definition: run.definition, error: run.error.message },
      ),
    };
  };
}
